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
        /// Recording after a tap, with VoiceOver or from the floating microphone, until the trailing circle's stop is
        /// tapped
        case handsFree
        case recognizing
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
    var level: Float = 0
    var levels: [Float] = []
    /// How far the recording waves swell, from 0 to 1: Telegram's level, the peak amplitude against 16000 of 32767
    var waveLevel: Float = 0
    var dragX: Double = 0
    var dragY: Double = 0
    var failure: Failure?
    /// The finger has stayed on the microphone past a tap's time: releasing it sends the question, and a hint shows
    /// that a swipe up keeps it in the field instead
    var isHeld = false
    /// The field has text, typed, pasted or dictated, or a transcript is on its way there while recognized: the
    /// floating microphone dictates more after it. Sending or clearing the field ends it.
    var canDictateMore = false
    /// The recording is on the floating microphone, which stays where it rests: held, or hands-free after a tap on it,
    /// as the recording's stop. It has no hints, pause or swipe-to-cancel, its transcript goes into the field, and the
    /// composer's trailing microphone gives way to it meanwhile.
    var isFloating = false

    /// Recording on the floating microphone, held or hands-free
    var isRecordingFloating: Bool {
        isFloating && (phase == .holding || phase == .handsFree)
    }

    /// The floating microphone shows while the field holds a dictated transcript or one is on its way there, also
    /// while a further dictation's failure shows, after which it is at rest again
    var showsFloatingMicrophone: Bool {
        canDictateMore && (phase == .idle || phase == .recognizing || phase == .failed)
    }
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
    private var hasPassedCancelFeedback = false
    private var isFloatingTouch = false
    /// The recording has started under a touch that isn't yet a tap or a hold: its haptic waits for the touch to be one
    private var isHapticPending = false
    /// The field holds text, typed or dictated, so the floating microphone returns after a further dictation that
    /// fails or is cancelled
    private var isFieldHoldingText = false

    /// A touch on the microphone released sooner than this is a tap, which records on hands-free; one held longer is
    /// push-to-talk, as in the Claude app. The recording's look for either waits for it, so nothing plays and reverses.
    static let tapDuration: TimeInterval = 0.2
    /// Telegram's voice recording gestures: a slide this far toward the leading edge cancels, this far up keeps the
    /// question in the field
    static let cancelDistance: Double = 150
    static let pauseDistance: Double = 110
    /// Releasing a held microphone after this much travel, or with this speed, cancels or pauses as well
    static let releaseCancelDistance: Double = 100
    static let releasePauseDistance: Double = 60
    static let releaseVelocity: Double = 400
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

    /// Recording starts at touch-down, so the first words aren't lost; the release decides between a tap and a hold.
    /// `isFloating` is a touch on the floating microphone, whose hold records into the field.
    func touchBegan(isRightToLeft: Bool = false, isFloating: Bool = false) {
        guard state.phase == .idle || state.phase == .failed, !isTouchDown else { return }
        endFailure()
        self.isRightToLeft = isRightToLeft
        isTouchDown = true
        isFloatingTouch = isFloating
        hasPassedCancelFeedback = false
        start(phase: .holding, isFloating: isFloating)
        holdTimer = scheduler.schedule(after: Self.tapDuration, repeating: nil) { [weak self] in
            guard let self else { return }
            self.holdTimer = nil
            guard self.isTouchDown, self.state.phase == .holding else { return }
            self.state.isHeld = true
            self.playPendingHaptic()
        }
    }

    func touchMoved(x: Double, y: Double) {
        // The floating microphone follows the finger instead
        guard isTouchDown, state.phase == .holding, !isFloatingTouch else { return }
        let cancelTravel = isRightToLeft ? x : -x
        if cancelTravel >= Self.cancelDistance {
            cancel()
        } else if y <= -Self.pauseDistance {
            isTouchDown = false
            pause()
        } else {
            state.dragX = x
            state.dragY = min(0, y)
            // A light tap marks the point where releasing would cancel
            let isPastCancel = cancelTravel >= Self.releaseCancelDistance
            if isPastCancel && !hasPassedCancelFeedback { gestureFeedback() }
            hasPassedCancelFeedback = isPastCancel
        }
    }

    func touchEnded(x: Double = 0, y: Double = 0, velocityX: Double = 0, velocityY: Double = 0) {
        guard isTouchDown else { return }
        isTouchDown = false
        holdTimer?.cancel()
        holdTimer = nil
        guard state.phase == .holding else { return }
        guard state.isHeld else {
            // A tap records on hands-free until the next tap, on the floating microphone where it stands after a tap on it
            var nextState = state
            nextState.phase = .handsFree
            nextState.isFloating = isFloatingTouch
            nextState.dragX = 0
            nextState.dragY = 0
            isFloatingTouch = false
            state = nextState
            playPendingHaptic()
            return
        }
        // A hold of the floating microphone dictates more into the field
        guard !isFloatingTouch else {
            endRecording(isSending: false)
            return
        }
        // Only the dominant direction of the release counts, as in Telegram
        let isHorizontal = abs(x) > abs(y)
        let cancelTravel = isRightToLeft ? x : -x
        let cancelVelocity = isRightToLeft ? velocityX : -velocityX
        if isHorizontal && (cancelVelocity > Self.releaseVelocity || cancelTravel > Self.releaseCancelDistance) {
            cancel()
        } else if !isHorizontal && (velocityY < -Self.releaseVelocity || y < -Self.releasePauseDistance) {
            pause()
        } else {
            endRecording(isSending: true)
        }
    }

    /// Records hands-free until `finish`: for VoiceOver, on the microphone, or `isFloating` on the floating one, where
    /// it stays as the recording's stop, and after the consent sheet a recording asked for
    func startHandsFree(isFloating: Bool = false) {
        guard state.phase == .idle || state.phase == .failed else { return }
        endFailure()
        holdTimer?.cancel()
        holdTimer = nil
        isTouchDown = false
        start(phase: .handsFree, isFloating: isFloating)
    }

    func cancel() {
        stopEverything()
        finishWithoutTranscript()
    }

    /// The swipe up of a held microphone: the recording stops, and its transcript goes into the field instead of being
    /// sent
    func pause() {
        guard state.phase == .holding || state.phase == .handsFree else { return }
        gestureFeedback()
        endRecording(isSending: false)
    }

    /// Stops a hands-free recording, whose transcript goes into the field
    func finish() {
        guard state.phase == .holding || state.phase == .handsFree else { return }
        endRecording(isSending: false)
    }

    /// The field is empty, its question sent or cleared, so the floating microphone goes
    func endDictatingMore() {
        isFieldHoldingText = false
        guard state.canDictateMore, state.phase == .idle else { return }
        state.canDictateMore = false
    }

    /// The field has text: typed, pasted, dictated, or a transcript meant to be sent that stayed there, as the question
    /// couldn't be sent yet. The floating microphone dictates more after it.
    func offerDictatingMore() {
        isFieldHoldingText = true
        guard state.phase == .idle else { return }
        state.canDictateMore = true
    }

    private func playPendingHaptic() {
        guard isHapticPending else { return }
        isHapticPending = false
        haptic()
    }

    private func start(phase: AgentDictationState.Phase, isFloating: Bool = false) {
        attempt += 1
        isHapticPending = false
        let currentAttempt = attempt
        pendingPermissionAttempt = currentAttempt
        hasSpeech = false
        var startingState = AgentDictationState(phase: phase)
        startingState.isFloating = isFloating
        state = startingState
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
        nextState.levels = Array(state.levels.suffix(47)) + [level]
        nextState.waveLevel = Self.getWaveLevel(peakPower: recorder.getPeakPower())
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
        isFloatingTouch = false
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
        // A transcript bound for the field brings the floating microphone up as its recognition starts
        var recognizingState = AgentDictationState(phase: .recognizing)
        recognizingState.canDictateMore = !isSending
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
                if !isSending {
                    self.isFieldHoldingText = true
                }
                self.state = self.makeIdleState()
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
        // The field keeps what was dictated into it before, and the floating microphone for more
        var failedState = AgentDictationState(phase: .failed, failure: failure)
        failedState.canDictateMore = isFieldHoldingText
        state = failedState
        onFinishedWithoutTranscript?()
        failureFeedback()
        failureTimer = scheduler.schedule(after: Self.failureDuration, repeating: nil) { [weak self] in
            guard let self else { return }
            self.failureTimer = nil
            if self.state.phase == .failed { self.state = self.makeIdleState() }
        }
    }

    private func endFailure() {
        failureTimer?.cancel()
        failureTimer = nil
        if state.phase == .failed { state = makeIdleState() }
    }

    /// At rest, with the floating microphone while the field holds a dictated transcript
    private func makeIdleState() -> AgentDictationState {
        var idleState = AgentDictationState()
        idleState.canDictateMore = isFieldHoldingText
        return idleState
    }

    private func stopEverything() {
        attempt += 1
        pendingPermissionAttempt = nil
        isTouchDown = false
        isFloatingTouch = false
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
        state = makeIdleState()
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
