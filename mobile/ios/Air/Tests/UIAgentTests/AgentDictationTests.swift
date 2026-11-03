import XCTest
@testable import UIAgent
import WalletContext
import WalletCore
import WalletResources

final class AgentDictationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testLeavingThreadListCancelsLockedRecordingWithoutTranscription() async throws {
        let fixture = Fixture()
        let client = FakeAgentV2Client()
        client.threadListResult = try JSONDecoder().decode(
            ApiAgentV2ThreadListResponse.self, from: Data("{\"protocolVersion\":3,\"threads\":[]}".utf8)
        )
        let list = AgentThreadListVC(
            model: AgentThreadListModel(client: client, newsClient: ThreadListNewsClient()),
            loadConsent: { true },
            acceptConsent: {}
        )
        list.loadViewIfNeeded()
        list.bottomBar.composerView.dictationController = fixture.controller
        let controller = try XCTUnwrap(list.bottomBar.composerView.dictationController)
        controller.startHandsFree()
        await fixture.waitForRecording()
        XCTAssertEqual(controller.state.phase, .locked)

        list.viewWillDisappear(false)
        fixture.scheduler.advance(by: 60)
        await drainTasks()

        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertEqual(fixture.recorder.cancelCount, 1)
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    @MainActor
    func testTapBefore220MillisecondsNeitherOpensMicrophoneNorFails() async {
        let fixture = Fixture()
        fixture.controller.touchBegan()
        fixture.scheduler.advance(by: 0.219)
        fixture.controller.touchEnded()
        XCTAssertEqual(fixture.controller.state.phase, .idle)
        fixture.scheduler.advance(by: 1)
        await drainTasks()

        XCTAssertEqual(fixture.recordingStarts, 0)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
        XCTAssertEqual(fixture.failureFeedbackCount, 0)
    }

    @MainActor
    func testSlidingLeft150PointsDeletesRecordingWithoutTranscription() async {
        let fixture = Fixture()
        fixture.controller.touchBegan()
        fixture.scheduler.advance(by: 0.22)
        await fixture.waitForRecording()
        fixture.scheduler.advance(by: 0.8)

        fixture.controller.touchMoved(x: -149, y: 0)
        XCTAssertEqual(fixture.controller.state.phase, .holding)
        fixture.controller.touchMoved(x: -150, y: 0)
        fixture.controller.touchEnded()

        XCTAssertEqual(fixture.controller.state.phase, .idle)
        XCTAssertEqual(fixture.recorder.cancelCount, 1)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(fixture.failureFeedbackCount, 0)
    }

    @MainActor
    func testReleasingPastTelegramThresholdsCancelsOrLocks() async {
        let cancelling = Fixture()
        cancelling.controller.touchBegan()
        cancelling.scheduler.advance(by: 0.22)
        await cancelling.waitForRecording()
        cancelling.scheduler.advance(by: 0.8)
        cancelling.controller.touchMoved(x: -101, y: -10)
        cancelling.controller.touchEnded(x: -101, y: -10)
        XCTAssertEqual(cancelling.controller.state.phase, .idle)
        XCTAssertEqual(cancelling.recorder.cancelCount, 1)

        let locking = Fixture()
        locking.controller.touchBegan()
        locking.scheduler.advance(by: 0.22)
        await locking.waitForRecording()
        locking.controller.touchMoved(x: 0, y: -20)
        locking.controller.touchEnded(x: 0, y: -20, velocityY: -500)
        XCTAssertEqual(locking.controller.state.phase, .locked)
        locking.controller.cancel()
    }

    @MainActor
    func testRecordingShorterThan700MillisecondsNeverLeavesDevice() async {
        let fixture = Fixture()
        fixture.controller.startHandsFree()
        await fixture.waitForRecording()
        fixture.scheduler.advance(by: 0.699)

        fixture.controller.finish()

        XCTAssertEqual(fixture.controller.state, AgentDictationState(phase: .failed, failure: .tooShort))
        XCTAssertEqual(fixture.recorder.cancelCount, 1)
        XCTAssertTrue(fixture.requests.isEmpty)
        fixture.scheduler.advance(by: AgentDictationController.failureDuration)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
    }

    @MainActor
    func testRecordingBelowSpeechThresholdNeverLeavesDevice() async {
        let fixture = Fixture()
        fixture.recorder.averagePowerValue = -40.1
        fixture.controller.startHandsFree()
        await fixture.waitForRecording()
        fixture.scheduler.advance(by: 1)

        fixture.controller.finish()

        XCTAssertEqual(fixture.controller.state, AgentDictationState(phase: .failed, failure: .noSpeech))
        XCTAssertEqual(fixture.recorder.cancelCount, 1)
        XCTAssertTrue(fixture.requests.isEmpty)
        fixture.scheduler.advance(by: AgentDictationController.failureDuration)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
    }

    @MainActor
    func testMeterUsesDecibelScaleForQuietAndLoudSpeech() async {
        let fixture = Fixture()
        fixture.controller.startHandsFree()
        await fixture.waitForRecording()
        defer { fixture.controller.cancel() }

        let samples: [(Float, Float)] = [(-80, 0), (-50, 0), (-30, 0.5), (-10, 1), (0, 1)]
        for (power, level) in samples {
            fixture.recorder.averagePowerValue = power
            fixture.scheduler.advance(by: 0.1)

            XCTAssertEqual(fixture.controller.state.level, level, accuracy: 0.001)
            XCTAssertEqual(fixture.controller.state.levels.last, level)
        }
    }

    @MainActor
    func testWavesSwellWithPeakAmplitudeAsTelegrams() async {
        let fixture = Fixture()
        fixture.controller.startHandsFree()
        await fixture.waitForRecording()
        defer { fixture.controller.cancel() }

        // Linear in amplitude, full at 16000 of 32767: about -6 dBFS
        let samples: [(Float, Float)] = [(-160, 0), (-40, 0.0205), (-20, 0.2048), (-12, 0.5144), (-6, 1), (0, 1)]
        for (peak, level) in samples {
            fixture.recorder.peakPowerValue = peak
            fixture.scheduler.advance(by: 0.1)
            XCTAssertEqual(fixture.controller.state.waveLevel, level, accuracy: 0.001)
        }
        XCTAssertEqual(AgentDictationController.getWaveLevel(peakPower: -.infinity), 0)
    }

    @MainActor
    func testCancelledRecognitionDiscardsLateTranscript() async {
        let fixture = Fixture()
        fixture.controller.startHandsFree()
        await fixture.waitForRecording()
        fixture.scheduler.advance(by: 0.8)
        fixture.controller.finish()
        await fixture.waitForRequest()
        XCTAssertEqual(fixture.controller.state.phase, .recognizing)

        fixture.controller.cancel()
        fixture.resumeTranscription(text: "Late result")
        await drainTasks()

        XCTAssertEqual(fixture.controller.state.phase, .idle)
        XCTAssertTrue(fixture.transcripts.isEmpty)
        XCTAssertEqual(fixture.failureFeedbackCount, 0)
        XCTAssertEqual(fixture.recorder.stopCount, 1)
    }

    @MainActor
    func testPermissionResponseAfterCancellationNeitherOpensMicrophoneNorFails() async {
        for releaseTouch in [false, true] {
            for granted in [false, true] {
                let fixture = Fixture()
                fixture.blocksPermission = true
                fixture.controller.touchBegan()
                fixture.scheduler.advance(by: 0.22)
                for _ in 0..<100 where fixture.permissionContinuation == nil { await Task.yield() }
                XCTAssertNotNil(fixture.permissionContinuation)

                if releaseTouch {
                    fixture.controller.touchEnded()
                } else {
                    fixture.controller.cancel()
                }

                XCTAssertEqual(fixture.controller.state.phase, .idle)
                XCTAssertEqual(fixture.recordingStarts, 0)
                XCTAssertTrue(fixture.requests.isEmpty)

                fixture.permissionContinuation?.resume(returning: granted)
                fixture.permissionContinuation = nil
                await drainTasks()

                XCTAssertEqual(fixture.controller.state.phase, .idle)
                XCTAssertEqual(fixture.recordingStarts, 0)
                XCTAssertEqual(fixture.recorder.stopCount, 0)
                XCTAssertTrue(fixture.requests.isEmpty)
                XCTAssertTrue(fixture.transcripts.isEmpty)
                XCTAssertEqual(fixture.failureFeedbackCount, 0)
            }
        }
    }

    @MainActor
    func testPendingRecorderCreationDoesNotDelayCancellationOrTouchEnd() async {
        for releaseTouch in [false, true] {
            let fixture = Fixture()
            fixture.blocksRecorderCreation = true
            fixture.controller.touchBegan()
            fixture.scheduler.advance(by: 0.22)
            await fixture.waitForRecorderFactory()
            XCTAssertEqual(fixture.controller.state.phase, .holding)

            if releaseTouch {
                fixture.controller.touchEnded()
            } else {
                fixture.controller.cancel()
            }

            XCTAssertNotNil(fixture.recorderContinuation)
            // Releasing before the recorder is ready is too short to dictate
            XCTAssertEqual(fixture.controller.state.phase, releaseTouch ? .failed : .idle)
            XCTAssertEqual(fixture.controller.state.failure, releaseTouch ? .tooShort : nil)
            XCTAssertEqual(fixture.recorder.cancelCount, 0)
            XCTAssertTrue(fixture.requests.isEmpty)

            fixture.resumeRecorderCreation()
            await fixture.waitForRecorderCancellation()
            fixture.scheduler.advance(by: 60)
            await drainTasks()

            XCTAssertEqual(fixture.recorder.cancelCount, 1)
            XCTAssertEqual(fixture.recorder.stopCount, 0)
            XCTAssertEqual(fixture.controller.state.phase, .idle)
            XCTAssertTrue(fixture.requests.isEmpty)
            XCTAssertTrue(fixture.transcripts.isEmpty)
            XCTAssertEqual(fixture.failureFeedbackCount, releaseTouch ? 1 : 0)
        }
    }

    @MainActor
    func testLockedRecordingStopsAtOneMinuteAndFillsTranscript() async {
        let fixture = Fixture()
        fixture.recorder.averagePowerValue = -40
        fixture.controller.touchBegan()
        fixture.scheduler.advance(by: 0.22)
        await fixture.waitForRecording()
        fixture.controller.touchMoved(x: 0, y: -110)
        fixture.controller.touchEnded()
        XCTAssertEqual(fixture.controller.state.phase, .locked)
        fixture.scheduler.advance(by: 60)
        await fixture.waitForRequest()
        XCTAssertEqual(fixture.controller.state.phase, .recognizing)
        XCTAssertEqual(fixture.requests.first?.format, .m4a)
        XCTAssertEqual(fixture.requests.first?.audio, Data([1, 2, 3]).base64EncodedString())
        XCTAssertEqual(fixture.requests.first?.lang, "ru")

        fixture.resumeTranscription(text: "Recognized phrase")
        await drainTasks()

        XCTAssertEqual(fixture.transcripts, ["Recognized phrase"])
        XCTAssertEqual(fixture.recorder.stopCount, 1)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
    }

    @MainActor
    func testUnrecognizedSpeechFailsBrieflyThenReturnsToMicrophone() async {
        let outcomes: [(ApiAgentV2TranscriptionResponse?, AgentDictationState.Failure)] = [
            (.init(outcome: .noSpeech), .noSpeech),
            (.init(outcome: .transcribed, text: " \n "), .noSpeech),
            (nil, .error(.networkError)),
        ]
        for (response, failure) in outcomes {
            let fixture = Fixture()
            var finishedWithoutTranscript = 0
            fixture.controller.onFinishedWithoutTranscript = { finishedWithoutTranscript += 1 }
            fixture.controller.startHandsFree()
            await fixture.waitForRecording()
            fixture.scheduler.advance(by: 0.8)
            fixture.controller.finish()
            await fixture.waitForRequest()
            if let response {
                fixture.resumeTranscription(response)
            } else {
                fixture.failTranscription(NSError(domain: "AgentDictationTests", code: 1))
            }
            await drainTasks()

            XCTAssertEqual(fixture.controller.state, AgentDictationState(phase: .failed, failure: failure))
            XCTAssertEqual(finishedWithoutTranscript, 1)
            XCTAssertEqual(fixture.failureFeedbackCount, 1)
            XCTAssertTrue(fixture.transcripts.isEmpty)
            fixture.scheduler.advance(by: AgentDictationController.failureDuration - 0.05)
            XCTAssertEqual(fixture.controller.state.phase, .failed)
            fixture.scheduler.advance(by: 0.1)
            XCTAssertEqual(fixture.controller.state, AgentDictationState())
            XCTAssertEqual(finishedWithoutTranscript, 1)
        }
    }

    @MainActor
    func testDeniedMicrophoneFailsWithoutRecording() async {
        let fixture = Fixture()
        fixture.isPermissionDenied = true
        fixture.controller.touchBegan()
        fixture.scheduler.advance(by: 0.22)
        XCTAssertEqual(fixture.controller.state.phase, .holding)
        await drainTasks()

        XCTAssertEqual(fixture.controller.state, AgentDictationState(phase: .failed, failure: .microphoneDenied))
        XCTAssertEqual(fixture.recordingStarts, 0)
        // The finger that is still down neither records nor ends the failure early
        fixture.controller.touchEnded()
        XCTAssertEqual(fixture.controller.state.phase, .failed)
        fixture.scheduler.advance(by: AgentDictationController.failureDuration)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
    }

    @MainActor
    func testNewTouchOrCancellationEndsFailureAtOnce() async {
        let retrying = Fixture()
        retrying.recorder.averagePowerValue = -80
        retrying.controller.startHandsFree()
        await retrying.waitForRecording()
        retrying.scheduler.advance(by: 1)
        retrying.controller.finish()
        XCTAssertEqual(retrying.controller.state.phase, .failed)
        retrying.controller.touchBegan()
        XCTAssertEqual(retrying.controller.state.phase, .idle)
        retrying.scheduler.advance(by: 0.22)
        XCTAssertEqual(retrying.controller.state.phase, .holding)
        retrying.scheduler.advance(by: AgentDictationController.failureDuration)
        XCTAssertEqual(retrying.controller.state.phase, .holding)
        retrying.controller.cancel()

        let cancelling = Fixture()
        cancelling.recorder.averagePowerValue = -80
        cancelling.controller.startHandsFree()
        await cancelling.waitForRecording()
        cancelling.scheduler.advance(by: 1)
        cancelling.controller.finish()
        XCTAssertEqual(cancelling.controller.state.phase, .failed)
        cancelling.controller.cancel()
        XCTAssertEqual(cancelling.controller.state, AgentDictationState())
    }

    @MainActor
    func testFailureAnnouncementsUseDictationCopy() {
        XCTAssertEqual(AgentDictationState.Failure.noSpeech.accessibilityAnnouncement, lang("$agent_dictation_no_speech"))
        XCTAssertEqual(AgentDictationState.Failure.tooShort.accessibilityAnnouncement, lang("$agent_dictation_too_short"))
        XCTAssertEqual(
            AgentDictationState.Failure.microphoneDenied.accessibilityAnnouncement,
            lang("$agent_dictation_microphone_denied")
        )
        XCTAssertEqual(AgentDictationState.Failure.error(.networkError).accessibilityAnnouncement, AgentV2Copy.error(.networkError))
    }

    @MainActor
    private func drainTasks() async {
        for _ in 0..<50 { await Task.yield() }
    }
}

@MainActor
private final class Fixture {
    let scheduler = AgentDictationTestScheduler()
    let recorder = AgentDictationTestRecorder()
    var recordingStarts = 0
    var recordingReadyCount = 0
    var requests: [ApiAgentV2TranscriptionRequest] = []
    var transcripts: [String] = []
    var failureFeedbackCount = 0
    var blocksPermission = false
    var isPermissionDenied = false
    var permissionContinuation: CheckedContinuation<Bool, Never>?
    var blocksRecorderCreation = false
    var recorderContinuation: CheckedContinuation<any AgentDictationRecording, Error>?
    private var transcriptionContinuation: CheckedContinuation<ApiAgentV2TranscriptionResponse, Error>?

    lazy var controller: AgentDictationController = {
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { [unowned self] in
                if blocksPermission {
                    return await withCheckedContinuation { permissionContinuation = $0 }
                }
                return !isPermissionDenied
            },
            makeRecorder: { [unowned self] in
                recordingStarts += 1
                if blocksRecorderCreation {
                    return try await withCheckedThrowingContinuation { recorderContinuation = $0 }
                }
                return recorder
            },
            transcribe: { [unowned self] request in
                requests.append(request)
                return try await withCheckedThrowingContinuation { transcriptionContinuation = $0 }
            },
            language: { "ru" },
            haptic: { [unowned self] in recordingReadyCount += 1 },
            gestureFeedback: {},
            failureFeedback: { [unowned self] in failureFeedbackCount += 1 },
            observeLifecycle: false
        )
        controller.onTranscript = { [unowned self] in
            transcripts.append($0)
        }
        return controller
    }()

    func waitForRecording() async {
        for _ in 0..<100 where recordingReadyCount == 0 { await Task.yield() }
        XCTAssertEqual(recordingStarts, 1)
        XCTAssertEqual(recordingReadyCount, 1)
    }

    func waitForRecorderFactory() async {
        for _ in 0..<100 where recorderContinuation == nil { await Task.yield() }
        XCTAssertNotNil(recorderContinuation)
        XCTAssertEqual(recordingStarts, 1)
        XCTAssertEqual(recordingReadyCount, 0)
    }

    func resumeRecorderCreation() {
        recorderContinuation?.resume(returning: recorder)
        recorderContinuation = nil
    }

    func waitForRecorderCancellation() async {
        for _ in 0..<100 where recorder.cancelCount == 0 { await Task.yield() }
        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(recordingReadyCount, 0)
    }

    func waitForRequest() async {
        for _ in 0..<100 where requests.isEmpty { await Task.yield() }
        XCTAssertEqual(requests.count, 1)
        XCTAssertNotNil(transcriptionContinuation)
    }

    func resumeTranscription(text: String) {
        resumeTranscription(.init(outcome: .transcribed, text: text))
    }

    func resumeTranscription(_ response: ApiAgentV2TranscriptionResponse) {
        transcriptionContinuation?.resume(returning: response)
        transcriptionContinuation = nil
    }

    func failTranscription(_ error: Error) {
        transcriptionContinuation?.resume(throwing: error)
        transcriptionContinuation = nil
    }
}

@MainActor
final class AgentDictationTestRecorder: AgentDictationRecording {
    var onFailure: (() -> Void)?
    var averagePowerValue: Float = -20
    var peakPowerValue: Float = -160
    var cancelCount = 0
    var stopCount = 0

    func averagePower() -> Float { averagePowerValue }
    func getPeakPower() -> Float { peakPowerValue }
    func stop() async throws -> Data {
        stopCount += 1
        return Data([1, 2, 3])
    }
    func cancel() { cancelCount += 1 }
}

@MainActor
final class AgentDictationTestScheduler: AgentDictationScheduling {
    private(set) var now: TimeInterval = 0
    private var events: [Event] = []

    func schedule(
        after delay: TimeInterval,
        repeating interval: TimeInterval?,
        _ action: @escaping @MainActor () -> Void
    ) -> any AgentDictationScheduledTask {
        let event = Event(deadline: now + delay, interval: interval, action: action)
        events.append(event)
        return event
    }

    func advance(by duration: TimeInterval) {
        let target = now + duration
        while let event = events.filter({ !$0.isCancelled && $0.deadline <= target })
            .min(by: { $0.deadline < $1.deadline }) {
            now = event.deadline
            if let interval = event.interval {
                event.deadline += interval
            } else {
                events.removeAll { $0 === event }
            }
            event.action()
        }
        now = target
        events.removeAll { $0.isCancelled }
    }

    private final class Event: AgentDictationScheduledTask {
        var deadline: TimeInterval
        let interval: TimeInterval?
        let action: @MainActor () -> Void
        var isCancelled = false

        init(deadline: TimeInterval, interval: TimeInterval?, action: @escaping @MainActor () -> Void) {
            self.deadline = deadline
            self.interval = interval
            self.action = action
        }

        func cancel() { isCancelled = true }
    }
}
