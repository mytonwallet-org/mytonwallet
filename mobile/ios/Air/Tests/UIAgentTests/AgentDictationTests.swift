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
    func testLeavingThreadListCancelsHandsFreeRecordingWithoutTranscription() async throws {
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
        XCTAssertEqual(controller.state.phase, .handsFree)

        list.viewWillDisappear(false)
        fixture.scheduler.advance(by: 60)
        await drainTasks()

        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertEqual(fixture.recorder.cancelCount, 1)
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    /// Recording starts at touch-down. A touch released within 0.2 s is a tap, which records on hands-free until the
    /// next tap puts the transcript into the field; one held longer is push-to-talk, whose release sends it. The
    /// recording's haptic waits for the touch to be one or the other.
    @MainActor
    func testTapRecordsHandsFreeAndAHoldIsPushToTalk() async {
        XCTAssertEqual(AgentDictationController.tapDuration, 0.2)
        let tapping = Fixture()
        tapping.controller.touchBegan()
        XCTAssertEqual(tapping.controller.state.phase, .holding, "Recording from touch-down")
        await tapping.waitForRecorder()
        XCTAssertEqual(tapping.recordingReadyCount, 0, "No haptic before the touch is a tap or a hold")
        tapping.scheduler.advance(by: 0.19)
        XCTAssertFalse(tapping.controller.state.isHeld)
        tapping.controller.touchEnded()
        XCTAssertEqual(tapping.controller.state.phase, .handsFree)
        XCTAssertEqual(tapping.recordingReadyCount, 1, "The tap's haptic")
        tapping.scheduler.advance(by: 5)
        XCTAssertEqual(tapping.controller.state.phase, .handsFree, "It records until the next tap")
        tapping.controller.finish()
        await tapping.waitForRequest()
        tapping.resumeTranscription(text: "Tapped")
        await drainTasks()
        XCTAssertEqual(tapping.transcripts, ["Tapped"])
        XCTAssertTrue(tapping.sentTranscripts.isEmpty)
        XCTAssertEqual(tapping.controller.state.phase, .idle)
        XCTAssertTrue(tapping.controller.state.canDictateMore)

        let holding = Fixture()
        holding.controller.touchBegan()
        await holding.waitForRecorder()
        XCTAssertEqual(holding.recordingReadyCount, 0)
        holding.scheduler.advance(by: 0.2)
        XCTAssertTrue(holding.controller.state.isHeld)
        XCTAssertEqual(holding.recordingReadyCount, 1, "The hold's haptic")
        holding.scheduler.advance(by: 1)
        holding.controller.touchEnded()
        XCTAssertEqual(holding.controller.state.phase, .recognizing)
        XCTAssertFalse(holding.controller.state.canDictateMore, "A transcript to send brings no floating microphone")
        await holding.waitForRequest()
        holding.resumeTranscription(text: "Held")
        await drainTasks()
        XCTAssertEqual(holding.sentTranscripts, ["Held"], "Releasing a hold sends the question at once")
        XCTAssertTrue(holding.transcripts.isEmpty)
        XCTAssertEqual(holding.controller.state, AgentDictationState())
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
    func testReleasingPastTelegramThresholdsCancelsOrPauses() async {
        let cancelling = Fixture()
        cancelling.controller.touchBegan()
        cancelling.scheduler.advance(by: 0.22)
        await cancelling.waitForRecording()
        cancelling.scheduler.advance(by: 0.8)
        cancelling.controller.touchMoved(x: -101, y: -10)
        cancelling.controller.touchEnded(x: -101, y: -10)
        XCTAssertEqual(cancelling.controller.state.phase, .idle)
        XCTAssertEqual(cancelling.recorder.cancelCount, 1)

        let pausing = Fixture()
        pausing.controller.touchBegan()
        pausing.scheduler.advance(by: 0.22)
        await pausing.waitForRecording()
        pausing.scheduler.advance(by: 0.8)
        pausing.controller.touchMoved(x: 0, y: -20)
        pausing.controller.touchEnded(x: 0, y: -20, velocityY: -500)
        XCTAssertEqual(pausing.controller.state.phase, .recognizing)
        await pausing.waitForRequest()
        pausing.resumeTranscription(text: "Kept")
        await drainTasks()
        XCTAssertEqual(pausing.transcripts, ["Kept"], "A swipe up keeps the question in the field")
        XCTAssertTrue(pausing.sentTranscripts.isEmpty)
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
                fixture.scheduler.advance(by: Self.holdDuration)
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
            fixture.scheduler.advance(by: Self.holdDuration)
            await fixture.waitForRecorderFactory()
            XCTAssertEqual(fixture.controller.state.phase, .holding)

            if releaseTouch {
                fixture.controller.touchEnded()
            } else {
                fixture.controller.cancel()
            }

            XCTAssertNotNil(fixture.recorderContinuation)
            // Releasing a hold before the recorder is ready is too short to dictate
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

    /// Swiping a held microphone up 110 pt stops the recording at once and recognizes it into the field instead of
    /// sending it, and the floating microphone then dictates more
    @MainActor
    func testSwipingUpKeepsTheTranscriptInTheField() async {
        let fixture = Fixture()
        fixture.controller.touchBegan()
        await fixture.waitForRecorder()
        fixture.scheduler.advance(by: 1)
        XCTAssertTrue(fixture.controller.state.isHeld)
        XCTAssertEqual(fixture.recordingReadyCount, 1)

        fixture.controller.touchMoved(x: 0, y: -109)
        XCTAssertEqual(fixture.controller.state.phase, .holding)
        XCTAssertEqual(fixture.gestureFeedbackCount, 0)
        fixture.controller.touchMoved(x: 0, y: -110)
        XCTAssertEqual(fixture.controller.state.phase, .recognizing)
        XCTAssertEqual(fixture.gestureFeedbackCount, 1, "A light tap marks the pause")
        await fixture.waitForRequest()
        XCTAssertEqual(fixture.recorder.stopCount, 1)
        // The finger that is still down neither records nor sends anything
        fixture.controller.touchMoved(x: 0, y: -200)
        fixture.controller.touchEnded(x: 0, y: -200)
        XCTAssertEqual(fixture.recordingStarts, 1)

        fixture.resumeTranscription(text: "Recognized phrase")
        await drainTasks()
        XCTAssertEqual(fixture.transcripts, ["Recognized phrase"])
        XCTAssertTrue(fixture.sentTranscripts.isEmpty)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
        XCTAssertTrue(fixture.controller.state.canDictateMore)

        fixture.controller.endDictatingMore()
        XCTAssertEqual(fixture.controller.state, AgentDictationState(), "A sent or cleared question ends it")
    }

    /// A hands-free recording stops by itself at one minute, and its transcript goes into the field
    @MainActor
    func testRecordingStopsAtOneMinuteIntoTheField() async {
        let fixture = Fixture()
        fixture.recorder.averagePowerValue = -40
        fixture.controller.touchBegan()
        await fixture.waitForRecorder()
        fixture.scheduler.advance(by: 0.1)
        fixture.controller.touchEnded()
        XCTAssertEqual(fixture.controller.state.phase, .handsFree)
        fixture.scheduler.advance(by: 59.8)
        XCTAssertEqual(fixture.controller.state.phase, .handsFree)
        fixture.scheduler.advance(by: 0.1)
        XCTAssertEqual(fixture.controller.state.phase, .recognizing)
        XCTAssertTrue(fixture.controller.state.canDictateMore, "The floating microphone comes up as recognition starts")
        await fixture.waitForRequest()
        XCTAssertEqual(fixture.requests.first?.format, .m4a)
        XCTAssertEqual(fixture.requests.first?.audio, Data([1, 2, 3]).base64EncodedString())
        XCTAssertEqual(fixture.requests.first?.lang, "ru")

        fixture.resumeTranscription(text: "Recognized phrase")
        await drainTasks()
        XCTAssertEqual(fixture.transcripts, ["Recognized phrase"])
        XCTAssertEqual(fixture.recorder.stopCount, 1)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
        XCTAssertTrue(fixture.controller.state.canDictateMore)
    }

    /// The floating microphone records hands-free after a transcript in the field, and its transcript goes into the
    /// field too. While the field holds dictated text, it comes back after a further dictation that is cancelled or
    /// fails; a sent or cleared field ends it.
    @MainActor
    func testDictatingMoreRecordsHandsFreeIntoTheField() async {
        let fixture = Fixture()
        fixture.controller.startHandsFree()
        await fixture.waitForRecording()
        fixture.scheduler.advance(by: 1)
        fixture.controller.finish()
        await fixture.waitForRequest()
        fixture.resumeTranscription(text: "First")
        await drainTasks()
        XCTAssertTrue(fixture.controller.state.canDictateMore)

        fixture.controller.startHandsFree()
        XCTAssertEqual(fixture.controller.state.phase, .handsFree)
        XCTAssertFalse(fixture.controller.state.canDictateMore)
        await fixture.waitForRecording(count: 2)
        fixture.scheduler.advance(by: 1)
        fixture.controller.finish()
        await fixture.waitForRequest(count: 2)
        fixture.resumeTranscription(text: "Second")
        await drainTasks()
        XCTAssertEqual(fixture.transcripts, ["First", "Second"])
        XCTAssertTrue(fixture.controller.state.canDictateMore)

        fixture.controller.startHandsFree()
        await fixture.waitForRecording(count: 3)
        fixture.controller.cancel()
        XCTAssertEqual(fixture.controller.state.phase, .idle)
        XCTAssertTrue(fixture.controller.state.canDictateMore, "The field still holds its dictated text")

        fixture.controller.startHandsFree()
        await fixture.waitForRecording(count: 4)
        fixture.controller.finish()
        XCTAssertEqual(fixture.controller.state.phase, .failed, "Too short")
        fixture.scheduler.advance(by: AgentDictationController.failureDuration)
        XCTAssertEqual(fixture.controller.state.phase, .idle)
        XCTAssertTrue(fixture.controller.state.canDictateMore)

        fixture.controller.endDictatingMore()
        XCTAssertEqual(fixture.controller.state, AgentDictationState())
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
        XCTAssertEqual(retrying.controller.state.phase, .holding, "A new touch records at once")
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
            lang("$agent_dictation_microphone_denied_device")
        )
        XCTAssertEqual(AgentDictationState.Failure.error(.networkError).accessibilityAnnouncement, AgentV2Copy.error(.networkError))
    }

    /// A touch held past a tap's time
    @MainActor
    private static var holdDuration: TimeInterval { AgentDictationController.tapDuration }

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
    var sentTranscripts: [String] = []
    var failureFeedbackCount = 0
    var gestureFeedbackCount = 0
    var blocksPermission = false
    var isPermissionDenied = false
    var permissionContinuation: CheckedContinuation<Bool, Never>?
    var blocksRecorderCreation = false
    var recorderContinuation: CheckedContinuation<any AgentDictationRecording, Error>?
    private var transcriptionContinuations: [CheckedContinuation<ApiAgentV2TranscriptionResponse, Error>?] = []

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
                return try await withCheckedThrowingContinuation { transcriptionContinuations.append($0) }
            },
            language: { "ru" },
            haptic: { [unowned self] in recordingReadyCount += 1 },
            gestureFeedback: { [unowned self] in gestureFeedbackCount += 1 },
            failureFeedback: { [unowned self] in failureFeedbackCount += 1 },
            observeLifecycle: false
        )
        controller.onTranscript = { [unowned self] in
            transcripts.append($0)
        }
        controller.onSendTranscript = { [unowned self] in
            sentTranscripts.append($0)
        }
        return controller
    }()

    func waitForRecording(count: Int = 1) async {
        for _ in 0..<100 where recordingReadyCount < count { await Task.yield() }
        XCTAssertEqual(recordingStarts, count)
        XCTAssertEqual(recordingReadyCount, count)
    }

    /// The recorder of a touch not yet a tap or a hold is recording, without its haptic yet
    func waitForRecorder(count: Int = 1) async {
        for _ in 0..<100 where recordingStarts < count { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(recordingStarts, count)
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

    func waitForRequest(count: Int = 1) async {
        for _ in 0..<100 where transcriptionContinuations.count < count { await Task.yield() }
        XCTAssertEqual(requests.count, count)
        XCTAssertEqual(transcriptionContinuations.count, count)
    }

    /// Answers the request at `index`, the latest one by default
    func resumeTranscription(text: String, at index: Int? = nil) {
        resumeTranscription(.init(outcome: .transcribed, text: text), at: index)
    }

    func resumeTranscription(_ response: ApiAgentV2TranscriptionResponse, at index: Int? = nil) {
        let index = index ?? transcriptionContinuations.count - 1
        guard transcriptionContinuations.indices.contains(index) else { return }
        transcriptionContinuations[index]?.resume(returning: response)
        transcriptionContinuations[index] = nil
    }

    func failTranscription(_ error: Error) {
        guard let index = transcriptionContinuations.indices.last else { return }
        transcriptionContinuations[index]?.resume(throwing: error)
        transcriptionContinuations[index] = nil
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
