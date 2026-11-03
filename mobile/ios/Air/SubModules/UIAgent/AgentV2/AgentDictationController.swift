import AVFoundation
import Foundation
import UIKit
import UIComponents
import WalletContext
import WalletCore

struct AgentDictationState: Equatable {
    enum Phase {
        case idle, holding, locked, recognizing
        /// A recording that produced no transcript: the recording circle shows it briefly, then the microphone returns
        case failed
    }

    /// Why a recording produced no transcript
    enum Failure: Equatable {
        case tooShort
        case noSpeech
        case microphoneDenied
        case error(ApiAgentV2ErrorCode)
    }

    var phase: Phase = .idle
    var elapsed: TimeInterval = 0
    var level: Float = 0
    var levels: [Float] = []
    /// How far the recording waves swell, from 0 to 1: Telegram's level, the peak amplitude against 16000 of 32767
    var waveLevel: Float = 0
    var dragX: Double = 0
    var dragY: Double = 0
    var failure: Failure?
}

extension AgentDictationState.Failure {
    /// What VoiceOver announces; on screen the recording circle turns red instead
    var accessibilityAnnouncement: String {
        switch self {
        case .tooShort: lang("$agent_dictation_too_short")
        case .noSpeech: lang("$agent_dictation_no_speech")
        case .microphoneDenied: lang("$agent_dictation_microphone_denied")
        case .error(let code): AgentV2Copy.error(code)
        }
    }
}

@MainActor
protocol AgentDictationScheduledTask {
    func cancel()
}

@MainActor
protocol AgentDictationScheduling {
    var now: TimeInterval { get }
    func schedule(
        after delay: TimeInterval,
        repeating interval: TimeInterval?,
        _ action: @escaping @MainActor () -> Void
    ) -> any AgentDictationScheduledTask
}

@MainActor
final class AgentDictationController {
    var onStateChanged: ((AgentDictationState) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onFinishedWithoutTranscript: (() -> Void)?

    private(set) var state = AgentDictationState() {
        didSet { onStateChanged?(state) }
    }

    private let scheduler: any AgentDictationScheduling
    private let requestPermission: @MainActor () async -> Bool
    private let makeRecorder: @MainActor () async throws -> any AgentDictationRecording
    private let transcribe: @MainActor (ApiAgentV2TranscriptionRequest) async throws -> ApiAgentV2TranscriptionResponse
    private let language: () -> String?
    private let haptic: () -> Void
    private let gestureFeedback: () -> Void
    private let failureFeedback: () -> Void
    private var recorder: (any AgentDictationRecording)?
    private var holdTimer: (any AgentDictationScheduledTask)?
    private var meterTimer: (any AgentDictationScheduledTask)?
    private var limitTimer: (any AgentDictationScheduledTask)?
    private var failureTimer: (any AgentDictationScheduledTask)?
    private var startTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var attempt = 0
    private var pendingPermissionAttempt: Int?
    private var startedAt: TimeInterval = 0
    private var hasSpeech = false
    private var isTouchDown = false
    private var isRightToLeft = false
    private var pendingDragX: Double = 0
    private var pendingDragY: Double = 0
    private var hasPassedCancelFeedback = false
    private var hasPassedLockFeedback = false

    /// Telegram's voice recording gestures: a slide this far toward the leading edge cancels, this far up locks
    static let cancelDistance: Double = 150
    static let lockDistance: Double = 110
    /// Releasing after this much travel, or with this speed, cancels or locks as well
    static let releaseCancelDistance: Double = 100
    static let releaseLockDistance: Double = 60
    static let releaseVelocity: Double = 400
    /// How long a failed recording stays in the `failed` phase, which the recording circle's failure animation spans
    static let failureDuration: TimeInterval = 0.75

    convenience init(client: any AgentV2Client = LiveAgentV2Client()) {
        self.init(
            scheduler: AgentDictationScheduler(),
            requestPermission: { await AgentDictationRecorder.requestPermission() },
            makeRecorder: { try await AgentDictationRecorder.start() },
            transcribe: { try await client.transcribeAgentV2Audio($0) }
        )
    }

    init(
        scheduler: any AgentDictationScheduling,
        requestPermission: @escaping @MainActor () async -> Bool,
        makeRecorder: @escaping @MainActor () async throws -> any AgentDictationRecording,
        transcribe: @escaping @MainActor (ApiAgentV2TranscriptionRequest) async throws -> ApiAgentV2TranscriptionResponse,
        language: @escaping () -> String? = { LocalizationSupport.shared.langCode },
        haptic: @escaping () -> Void = { Haptics.play(.lightTap) },
        gestureFeedback: @escaping () -> Void = { Haptics.play(.lightTap) },
        failureFeedback: @escaping () -> Void = { Haptics.play(.error) },
        observeLifecycle: Bool = true
    ) {
        self.scheduler = scheduler
        self.requestPermission = requestPermission
        self.makeRecorder = makeRecorder
        self.transcribe = transcribe
        self.language = language
        self.haptic = haptic
        self.gestureFeedback = gestureFeedback
        self.failureFeedback = failureFeedback
        if observeLifecycle {
            observers.append(NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    MainActor.assumeIsolated { self?.cancel() }
                }
            })
        }
    }

    // Older iOS concurrency runtimes can crash in isolated deinit (Swift #85663). Cleanup only cancels the work in
    // flight and removes the observers: the timers stop as their tasks are released, and a recording as its recorder is.
    deinit {
        startTask?.cancel()
        recognitionTask?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func touchBegan(isRightToLeft: Bool = false) {
        guard state.phase == .idle || state.phase == .failed, holdTimer == nil else { return }
        endFailure()
        self.isRightToLeft = isRightToLeft
        isTouchDown = true
        pendingDragX = 0
        pendingDragY = 0
        hasPassedCancelFeedback = false
        hasPassedLockFeedback = false
        holdTimer = scheduler.schedule(after: 0.22, repeating: nil) { [weak self] in
            guard let self, self.isTouchDown else { return }
            self.holdTimer = nil
            self.start(locked: false)
            self.touchMoved(x: self.pendingDragX, y: self.pendingDragY)
        }
    }

    func touchMoved(x: Double, y: Double) {
        guard isTouchDown else { return }
        pendingDragX = x
        pendingDragY = y
        guard state.phase == .holding else { return }
        let cancelTravel = isRightToLeft ? x : -x
        if cancelTravel >= Self.cancelDistance {
            cancel()
        } else if y <= -Self.lockDistance {
            lock()
        } else {
            state.dragX = x
            state.dragY = min(0, y)
            // A light tap marks the point where releasing would cancel or lock
            let isPastCancel = cancelTravel >= Self.releaseCancelDistance
            if isPastCancel && !hasPassedCancelFeedback { gestureFeedback() }
            hasPassedCancelFeedback = isPastCancel
            let isPastLock = y <= -Self.releaseLockDistance
            if isPastLock && !hasPassedLockFeedback { gestureFeedback() }
            hasPassedLockFeedback = isPastLock
        }
    }

    func touchEnded(x: Double = 0, y: Double = 0, velocityX: Double = 0, velocityY: Double = 0) {
        guard isTouchDown else { return }
        isTouchDown = false
        if holdTimer != nil {
            holdTimer?.cancel()
            holdTimer = nil
        } else if state.phase == .holding {
            // Only the dominant direction of the release counts, as in Telegram
            let isHorizontal = abs(x) > abs(y)
            let cancelTravel = isRightToLeft ? x : -x
            let cancelVelocity = isRightToLeft ? velocityX : -velocityX
            if isHorizontal && (cancelVelocity > Self.releaseVelocity || cancelTravel > Self.releaseCancelDistance) {
                cancel()
            } else if !isHorizontal && (velocityY < -Self.releaseVelocity || y < -Self.releaseLockDistance) {
                lock()
            } else {
                finish()
            }
        }
    }

    private func lock() {
        state.phase = .locked
        state.dragX = 0
        state.dragY = 0
        hasPassedCancelFeedback = false
        hasPassedLockFeedback = false
        gestureFeedback()
    }

    func startHandsFree() {
        guard state.phase == .idle || state.phase == .failed else { return }
        endFailure()
        holdTimer?.cancel()
        holdTimer = nil
        isTouchDown = false
        start(locked: true)
    }

    func cancel() {
        stopEverything()
        finishWithoutTranscript()
    }

    private func start(locked: Bool) {
        attempt += 1
        let currentAttempt = attempt
        pendingPermissionAttempt = currentAttempt
        hasSpeech = false
        state = AgentDictationState(phase: locked ? .locked : .holding)
        let permission = requestPermission
        let makeRecorder = makeRecorder
        startTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let granted = await permission()
            if self?.pendingPermissionAttempt == currentAttempt {
                self?.pendingPermissionAttempt = nil
            }
            guard self?.attempt == currentAttempt, !Task.isCancelled else { return }
            guard granted else {
                self?.fail(.microphoneDenied)
                return
            }
            do {
                let recorder = try await makeRecorder()
                guard let self, self.attempt == currentAttempt, !Task.isCancelled else {
                    recorder.cancel()
                    return
                }
                self.startTask = nil
                self.recorder = recorder
                recorder.onFailure = { [weak self] in
                    guard let self, self.attempt == currentAttempt else { return }
                    self.recordingFailed()
                }
                self.startedAt = self.scheduler.now
                self.haptic()
                self.meterTimer = self.scheduler.schedule(after: 0.08, repeating: 0.08) { [weak self] in
                    self?.updateMeter()
                }
                self.limitTimer = self.scheduler.schedule(after: 60, repeating: nil) { [weak self] in
                    self?.finish()
                }
            } catch {
                guard let self, self.attempt == currentAttempt, !Task.isCancelled else { return }
                self.fail(.error(.internalError))
            }
        }
    }

    private func updateMeter() {
        guard let recorder else { return }
        let power = recorder.averagePower()
        // Native input gain differs from getUserMedia; RMS 0.01 (-40 dBFS) keeps quiet speech for server recognition.
        if power >= -40 { hasSpeech = true }
        let level = min(1, max(0, (power + 50) / 40))
        var nextState = state
        nextState.elapsed = min(60, max(0, scheduler.now - startedAt))
        nextState.level = level
        nextState.levels = Array(state.levels.suffix(47)) + [level]
        nextState.waveLevel = Self.getWaveLevel(peakPower: recorder.getPeakPower())
        state = nextState
    }

    /// Telegram's recording waves swell linearly with the peak amplitude, full at 16000 of 32767
    static func getWaveLevel(peakPower: Float) -> Float {
        guard peakPower.isFinite else { return 0 }
        return min(1, max(0, pow(10, peakPower / 20) * 32767 / 16000))
    }

    func finish() {
        guard state.phase == .holding || state.phase == .locked else { return }
        guard let recorder else {
            if pendingPermissionAttempt == attempt {
                cancel()
            } else {
                fail(.tooShort)
            }
            return
        }
        updateMeter()
        let duration = scheduler.now - startedAt
        stopTimers()
        self.recorder = nil
        guard duration >= 0.7 else {
            recorder.cancel()
            fail(.tooShort)
            return
        }
        guard hasSpeech else {
            recorder.cancel()
            fail(.noSpeech)
            return
        }
        attempt += 1
        let currentAttempt = attempt
        state.phase = .recognizing
        let language = language()
        let transcribe = transcribe
        recognitionTask = Task { [weak self] in
            let audio: Data
            do {
                audio = try await recorder.stop()
            } catch {
                guard let self, self.attempt == currentAttempt, !Task.isCancelled else { return }
                self.recognitionTask = nil
                self.fail(.error(.audioUnreadable))
                return
            }
            guard self?.attempt == currentAttempt, !Task.isCancelled else { return }
            guard !audio.isEmpty else {
                guard let self else { return }
                self.recognitionTask = nil
                self.fail(.noSpeech)
                return
            }
            let request = ApiAgentV2TranscriptionRequest(audio: audio.base64EncodedString(), format: .m4a, lang: language)
            do {
                let response = try await transcribe(request)
                guard let self, self.attempt == currentAttempt else { return }
                self.recognitionTask = nil
                if response.outcome == .transcribed, let text = response.text,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.state = AgentDictationState()
                    self.onTranscript?(text)
                } else {
                    self.fail(.noSpeech)
                }
            } catch {
                guard let self, self.attempt == currentAttempt else { return }
                self.recognitionTask = nil
                self.fail(.error((error as? ApiAgentV2MutationError)?.code ?? .networkError))
            }
        }
    }

    private func recordingFailed() {
        guard recorder != nil else { return }
        fail(.error(.audioUnreadable))
    }

    /// Ends the attempt in the `failed` phase, which returns to `idle` after `failureDuration` unless a new touch
    /// or a cancellation ends it sooner
    private func fail(_ failure: AgentDictationState.Failure) {
        stopEverything()
        state = AgentDictationState(phase: .failed, failure: failure)
        onFinishedWithoutTranscript?()
        failureFeedback()
        failureTimer = scheduler.schedule(after: Self.failureDuration, repeating: nil) { [weak self] in
            guard let self else { return }
            self.failureTimer = nil
            if self.state.phase == .failed { self.state = AgentDictationState() }
        }
    }

    private func endFailure() {
        failureTimer?.cancel()
        failureTimer = nil
        if state.phase == .failed { state = AgentDictationState() }
    }

    private func stopEverything() {
        attempt += 1
        pendingPermissionAttempt = nil
        isTouchDown = false
        startTask?.cancel()
        startTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        holdTimer?.cancel()
        holdTimer = nil
        failureTimer?.cancel()
        failureTimer = nil
        stopTimers()
        recorder?.cancel()
        recorder = nil
    }

    private func finishWithoutTranscript() {
        state = AgentDictationState()
        onFinishedWithoutTranscript?()
    }

    private func stopTimers() {
        meterTimer?.cancel()
        meterTimer = nil
        limitTimer?.cancel()
        limitTimer = nil
    }
}

@MainActor
private final class AgentDictationScheduler: AgentDictationScheduling {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(
        after delay: TimeInterval,
        repeating interval: TimeInterval?,
        _ action: @escaping @MainActor () -> Void
    ) -> any AgentDictationScheduledTask {
        let timer = Timer(timeInterval: interval ?? delay, repeats: interval != nil) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.fireDate = Date(timeIntervalSinceNow: delay)
        RunLoop.main.add(timer, forMode: .common)
        return ScheduledTimer(timer: timer)
    }

    private final class ScheduledTimer: AgentDictationScheduledTask {
        let timer: Timer

        init(timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }

        // A task no one holds can't be cancelled any more, so its timer stops with it
        deinit { timer.invalidate() }
    }
}
