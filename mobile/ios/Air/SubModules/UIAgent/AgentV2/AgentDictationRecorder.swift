import AVFoundation
import Foundation
import WalletContext

@MainActor
protocol AgentDictationRecording: AnyObject {
    var onFailure: (() -> Void)? { get set }
    func averagePower() -> Float
    /// The loudest moment of the latest metering window, in dBFS
    func getPeakPower() -> Float
    func stop() async throws -> Data
    func cancel()
}

@MainActor
final class AgentDictationRecorder: AgentDictationRecording {
    var onFailure: (() -> Void)?

    private let worker: AgentDictationAudioWorker
    private var resumeSounds: (@MainActor @Sendable () -> Void)?
    private var power: Float = -160
    private var peak: Float = -160
    private var isFinished = false

    static func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .denied: return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
                }
            @unknown default: return false
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted: return true
            case .denied: return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    session.requestRecordPermission { @Sendable granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default: return false
            }
        }
    }

    static func start(directory: URL = FileManager.default.temporaryDirectory) async throws -> AgentDictationRecorder {
        // Block chimes before the audio queue takes ownership of the shared session.
        let resumeSounds = AudioHelpers.suspendSounds()
        do {
            let worker = try await AgentDictationAudioQueue.shared.start(directory: directory)
            return AgentDictationRecorder(worker: worker, resumeSounds: resumeSounds)
        } catch {
            resumeSounds()
            throw error
        }
    }

    private init(worker: AgentDictationAudioWorker, resumeSounds: @escaping @MainActor @Sendable () -> Void) {
        self.worker = worker
        self.resumeSounds = resumeSounds
        worker.setCallbacks(
            onPower: { [weak self] power, peak in
                guard let self, !self.isFinished else { return }
                self.power = power
                self.peak = peak
            },
            onFailure: { [weak self] in
                guard let self, !self.isFinished else { return }
                self.onFailure?()
            }
        )
    }

    // Older iOS concurrency runtimes can crash in isolated deinit (Swift #85663). Cleanup only hands an unfinished
    // recording to its queue to stop, which brings the sounds back on the main actor once it's released.
    deinit {
        guard !isFinished else { return }
        let resumeSounds = self.resumeSounds
        worker.cancel { resumeSounds?() }
    }

    func averagePower() -> Float {
        power
    }

    func getPeakPower() -> Float {
        peak
    }

    func stop() async throws -> Data {
        guard !isFinished else { throw AgentDictationRecordingError.couldNotRecord }
        isFinished = true
        defer {
            resumeSounds?()
            resumeSounds = nil
        }
        return try await worker.stop()
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        let resumeSounds = self.resumeSounds
        self.resumeSounds = nil
        worker.cancel { resumeSounds?() }
    }
}

// Session changes and recorder work share one queue so a cancelled start cannot release a newer session.
private final class AgentDictationAudioQueue: @unchecked Sendable {
    static let shared = AgentDictationAudioQueue()

    let queue = DispatchQueue(label: "org.mytonwallet.agent-dictation-audio", qos: .userInitiated)
    var activeWorker: AgentDictationAudioWorker?

    func start(directory: URL) async throws -> AgentDictationAudioWorker {
        let cancellation = AgentDictationStartCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.check()
                        self.activeWorker?.finishWithoutAudio()
                        try cancellation.check()
                        let worker = try AgentDictationAudioWorker(owner: self, directory: directory)
                        if cancellation.isCancelled {
                            worker.finishWithoutAudio()
                            throw CancellationError()
                        }
                        self.activeWorker = worker
                        continuation.resume(returning: worker)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class AgentDictationStartCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func check() throws {
        if isCancelled { throw CancellationError() }
    }
}

private final class AgentDictationAudioWorker: NSObject, @unchecked Sendable, AVAudioRecorderDelegate {
    private let owner: AgentDictationAudioQueue
    private let url: URL
    private var recorder: AVAudioRecorder?
    private let previousCategory: AVAudioSession.Category
    private let previousMode: AVAudioSession.Mode
    private let previousCategoryOptions: AVAudioSession.CategoryOptions
    private let previousAllowsHapticsDuringRecording: Bool
    private var isFinished = false
    private var meterTimer: DispatchSourceTimer?
    private var onPower: (@MainActor @Sendable (_ average: Float, _ peak: Float) -> Void)?
    private var onFailure: (@MainActor @Sendable () -> Void)?

    init(owner: AgentDictationAudioQueue, directory: URL) throws {
        self.owner = owner
        let url = directory.appendingPathComponent("agent-dictation-\(UUID().uuidString).m4a")
        let session = AVAudioSession.sharedInstance()
        let previousCategory = session.category
        let previousMode = session.mode
        let previousCategoryOptions = session.categoryOptions
        let previousAllowsHapticsDuringRecording = session.allowHapticsAndSystemSoundsDuringRecording
        var createdRecorder: AVAudioRecorder?
        do {
            try session.setCategory(.record, mode: .default)
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            createdRecorder = recorder
            self.recorder = recorder
            self.url = url
            self.previousCategory = previousCategory
            self.previousMode = previousMode
            self.previousCategoryOptions = previousCategoryOptions
            self.previousAllowsHapticsDuringRecording = previousAllowsHapticsDuringRecording
            super.init()
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: 60) else { throw AgentDictationRecordingError.couldNotRecord }
            let meterTimer = DispatchSource.makeTimerSource(queue: owner.queue)
            meterTimer.schedule(deadline: .now(), repeating: .milliseconds(40))
            meterTimer.setEventHandler { [weak self] in self?.updatePower() }
            self.meterTimer = meterTimer
            meterTimer.resume()
        } catch {
            createdRecorder?.delegate = nil
            createdRecorder?.stop()
            try? FileManager.default.removeItem(at: url)
            try? session.setCategory(previousCategory, mode: previousMode, options: previousCategoryOptions)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(previousAllowsHapticsDuringRecording)
            throw error
        }
    }

    func setCallbacks(
        onPower: @escaping @MainActor @Sendable (_ average: Float, _ peak: Float) -> Void,
        onFailure: @escaping @MainActor @Sendable () -> Void
    ) {
        owner.queue.async {
            guard !self.isFinished else { return }
            self.onPower = onPower
            self.onFailure = onFailure
        }
    }

    func stop() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            owner.queue.async {
                do {
                    guard !self.isFinished else { throw AgentDictationRecordingError.couldNotRecord }
                    self.stopRecorder()
                    let audio = Result { try Data(contentsOf: self.url) }
                    self.release()
                    continuation.resume(with: audio)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel(onReleased: @escaping @MainActor @Sendable () -> Void) {
        owner.queue.async {
            self.finishWithoutAudio()
            Task { @MainActor in onReleased() }
        }
    }

    // Only called on the audio queue, including before a newer recorder is created.
    func finishWithoutAudio() {
        guard !isFinished else { return }
        stopRecorder()
        release()
    }

    private func stopRecorder() {
        isFinished = true
        meterTimer?.cancel()
        meterTimer = nil
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        onPower = nil
        onFailure = nil
    }

    private func release() {
        try? FileManager.default.removeItem(at: url)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(previousCategory, mode: previousMode, options: previousCategoryOptions)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(previousAllowsHapticsDuringRecording)
        if owner.activeWorker === self { owner.activeWorker = nil }
    }

    private func updatePower() {
        guard !isFinished, let recorder, let onPower else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let peak = recorder.peakPower(forChannel: 0)
        Task { @MainActor in onPower(power, peak) }
    }

    private func reportFailure() {
        owner.queue.async {
            guard !self.isFinished, let onFailure = self.onFailure else { return }
            Task { @MainActor in onFailure() }
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        reportFailure()
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { reportFailure() }
    }
}

private enum AgentDictationRecordingError: Error {
    case couldNotRecord
}
