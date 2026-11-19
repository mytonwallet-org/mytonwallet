import AVFoundation
import Foundation
import UIKit
import UIComponents
import WalletContext
import WalletCore

struct AgentDictationState: Equatable {
    enum Phase {
        case idle
        /// Recording while the finger is on the microphone, from touch-down
        case holding
        /// Recording after a tap, or with VoiceOver, until its stop is tapped
        case handsFree
        case recognizing
        /// A recording that produced no transcript: the recording circle shows it briefly, then the microphone returns
        case failed
    }

    /// Where releasing a held microphone takes the recording: its transcript into the field where the finger started,
    /// nowhere at the field's cross toward the leading end, and off as the question at Send toward the trailing end
    enum HoldZone: Equatable {
        case stop
        case cancel
        case send
    }

    /// Why a recording produced no transcript
    enum Failure: Equatable {
        case tooShort
        case noSpeech
        case microphoneDenied
        case error(ApiAgentV2ErrorCode)
    }

    var phase: Phase = .idle
    var level: Float = 0
    var levels: [Float] = []
    /// How far the recording waves swell, from 0 to 1: Telegram's level, the peak amplitude against 16000 of 32767
    var waveLevel: Float = 0
    /// The signal's peak since the last reading, from 0 to 1 of full scale
    var peakLevel: Float = 0
    /// How far the held finger has gone along the field from where it came down
    var dragX: Double = 0
    var failure: Failure?
    /// The finger has stayed on the microphone past a tap's time: where it lets go decides, by `holdZone`
    var isHeld = false
    var holdZone: HoldZone = .stop
    /// While recognized, the transcript goes as the question rather than into the field
    var isSending = false
    /// The recording has heard speech, so there is something to recognize and send
    var hasSpeech = false
}

extension AgentDictationState.Failure {
    /// What VoiceOver announces; on screen the recording circle turns red instead
    var accessibilityAnnouncement: String {
        switch self {
        case .tooShort: lang("$agent_dictation_too_short")
        case .noSpeech: lang("$agent_dictation_no_speech")
        case .microphoneDenied: lang("$agent_dictation_microphone_denied_device")
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
    /// A transcript for the field, after its text
    var onTranscript: ((String) -> Void)?
    /// A held recording's transcript, to send as the question at once
    var onSendTranscript: ((String) -> Void)?
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
    /// The recording has started under a touch that isn't yet a tap or a hold: its haptic waits for the touch to be one
    private var isHapticPending = false

    /// A touch on the microphone released sooner than this is a tap, which records on hands-free; one held longer is
    /// push-to-talk, as in the Claude app. The recording's look for either waits for it, so nothing plays and reverses.
    static let tapDuration: TimeInterval = 0.2
    /// A held microphone slid this far toward the field's cross cancels on release, and this far toward Send sends;
    /// let go nearer its place, its transcript goes into the field. Send stands next to the microphone, the cross across
    /// the field.
    static let cancelZoneDistance: Double = 90
    static let sendZoneDistance: Double = 24
    /// The zones as the field lays them out: halfway from the microphone to the cross, and to Send
    var cancelZoneTravel = AgentDictationController.cancelZoneDistance
    var sendZoneTravel = AgentDictationController.sendZoneDistance
    /// A continuous recording stops after this long, and its transcript goes into the field
    static let recordingLimit: TimeInterval = 60
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

    /// Recording starts at touch-down, so the first words aren't lost; the release decides between a tap and a hold
    func touchBegan(isRightToLeft: Bool = false) {
        guard state.phase == .idle || state.phase == .failed, !isTouchDown else { return }
        endFailure()
        self.isRightToLeft = isRightToLeft
        isTouchDown = true
        start(phase: .holding)
        holdTimer = scheduler.schedule(after: Self.tapDuration, repeating: nil) { [weak self] in
            guard let self else { return }
            self.holdTimer = nil
            guard self.isTouchDown, self.state.phase == .holding else { return }
            self.state.isHeld = true
            self.playPendingHaptic()
        }
    }

    /// The recording circle follows the finger along the field, and the zone it is in decides what releasing does
    func touchMoved(x: Double) {
        guard isTouchDown, state.phase == .holding else { return }
        let zone = getHoldZone(x: x)
        var nextState = state
        nextState.dragX = x
        nextState.holdZone = zone
        // A light tap marks each change of what releasing would do, once the touch is a hold
        if zone != state.holdZone, state.isHeld { gestureFeedback() }
        state = nextState
    }

    private func getHoldZone(x: Double) -> AgentDictationState.HoldZone {
        let towardLeadingEnd = isRightToLeft ? x : -x
        if towardLeadingEnd >= cancelZoneTravel { return .cancel }
        if -towardLeadingEnd >= sendZoneTravel { return .send }
        return .stop
    }

    func touchEnded(x: Double = 0) {
        guard isTouchDown else { return }
        isTouchDown = false
        holdTimer?.cancel()
        holdTimer = nil
        guard state.phase == .holding else { return }
        guard state.isHeld else {
            // A tap records on hands-free until the stop is tapped
            var nextState = state
            nextState.phase = .handsFree
            nextState.dragX = 0
            state = nextState
            playPendingHaptic()
            return
        }
        switch getHoldZone(x: x) {
        case .cancel:
            cancel()
        case .send:
            endRecording(isSending: true)
        case .stop:
            endRecording(isSending: false)
        }
    }

    /// Records hands-free until `finish`: for VoiceOver, and after the consent sheet a recording asked for
    func startHandsFree() {
        guard state.phase == .idle || state.phase == .failed else { return }
        endFailure()
        holdTimer?.cancel()
        holdTimer = nil
        isTouchDown = false
        start(phase: .handsFree)
    }

    func cancel() {
        stopEverything()
        finishWithoutTranscript()
    }

    /// Stops a hands-free recording, whose transcript goes into the field
    func finish() {
        guard state.phase == .holding || state.phase == .handsFree else { return }
        endRecording(isSending: false)
    }

    /// Send during a hands-free recording: it stops, and its transcript goes as the question
    func finishAndSend() {
        guard state.phase == .handsFree else { return }
        endRecording(isSending: true)
    }

    private func playPendingHaptic() {
        guard isHapticPending else { return }
        isHapticPending = false
        haptic()
    }

    private func start(phase: AgentDictationState.Phase) {
        attempt += 1
        isHapticPending = false
        let currentAttempt = attempt
        pendingPermissionAttempt = currentAttempt
        hasSpeech = false
        state = AgentDictationState(phase: phase)
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
                // The recording starts at the touch, and its haptic once the touch is a tap or a hold
                if self.state.phase == .holding, !self.state.isHeld {
                    self.isHapticPending = true
                } else {
                    self.haptic()
                }
                self.scheduleRecordingTimers()
            } catch {
                guard let self, self.attempt == currentAttempt, !Task.isCancelled else { return }
                self.fail(.error(.internalError))
            }
        }
    }

    private func scheduleRecordingTimers() {
        meterTimer = scheduler.schedule(after: 0.08, repeating: 0.08) { [weak self] in
            self?.updateMeter()
        }
        // At the limit the recording stops by itself, and its transcript goes into the field, so nothing is lost
        limitTimer = scheduler.schedule(after: Self.recordingLimit, repeating: nil) { [weak self] in
            self?.finish()
        }
    }

    private func updateMeter() {
        guard let recorder else { return }
        let power = recorder.averagePower()
        // Native input gain differs from getUserMedia; RMS 0.01 (-40 dBFS) keeps quiet speech for server recognition.
        if power >= -40 { hasSpeech = true }
        let level = min(1, max(0, (power + 50) / 40))
        var nextState = state
        nextState.level = level
        nextState.hasSpeech = hasSpeech
        nextState.levels = Array(state.levels.suffix(47)) + [level]
        let peakPower = recorder.getPeakPower()
        nextState.waveLevel = Self.getWaveLevel(peakPower: peakPower)
        nextState.peakLevel = peakPower.isFinite ? min(1, max(0, pow(10, peakPower / 20))) : 0
        state = nextState
    }

    /// Telegram's recording waves swell linearly with the peak amplitude, full at 16000 of 32767
    static func getWaveLevel(peakPower: Float) -> Float {
        guard peakPower.isFinite else { return 0 }
        return min(1, max(0, pow(10, peakPower / 20) * 32767 / 16000))
    }

    /// Stops the recording and recognizes it, to send it or to put it into the field
    private func endRecording(isSending: Bool) {
        holdTimer?.cancel()
        holdTimer = nil
        isTouchDown = false
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
        var recognizingState = AgentDictationState(phase: .recognizing)
        recognizingState.isSending = isSending
        state = recognizingState
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
                guard response.outcome == .transcribed, let text = response.text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.fail(.noSpeech)
                    return
                }
                self.state = AgentDictationState()
                if isSending {
                    self.onSendTranscript?(text)
                } else {
                    self.onTranscript?(text)
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
