import XCTest
import UIKit
@testable import UIAgent
@testable import UIComponents
import WalletContext
import WalletCore
import WalletResources

final class AgentDictationComposerTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testAccessibleDictationFillsDraftWithoutSendingWhileAgentIsBusy() async throws {
        let recorder = AgentDictationTestRecorder()
        let scheduler = AgentDictationTestScheduler()
        var recordingStarts = 0
        var requests: [ApiAgentV2TranscriptionRequest] = []
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: {
                recordingStarts += 1
                return recorder
            },
            transcribe: { request in
                requests.append(request)
                return ApiAgentV2TranscriptionResponse(outcome: .transcribed, text: "Dictated message")
            },
            haptic: {},
            observeLifecycle: false
        )
        let composer = AgentComposerView()
        composer.dictationController = controller
        controller.onTranscript = { [weak composer] text in
            composer?.setDraftText(text, focus: false)
        }
        var sentMessages = 0
        composer.onSend = { sentMessages += 1 }
        composer.setSendEnabled(false)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let send = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == lang("Send")
        })
        // The microphone stands inside the field, where the send button comes with text
        XCTAssertTrue(microphone.isDescendant(of: try XCTUnwrap(send.superview)))
        XCTAssertEqual(send.accessibilityIdentifier, "agent_send")
        XCTAssertFalse(microphone.isHidden)
        XCTAssertTrue(send.isHidden)
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(microphone.isEnabled)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_start"))

        composer.setDraftText(" \n ", focus: false)
        XCTAssertFalse(microphone.isHidden)
        XCTAssertTrue(send.isHidden)
        composer.setDraftText("Hello", focus: false)
        XCTAssertFalse(microphone.isHidden, "The microphone stays beside Send")
        XCTAssertFalse(send.isHidden)
        XCTAssertFalse(send.isEnabled)
        composer.setSendEnabled(true)
        XCTAssertTrue(send.isEnabled)
        dispatch(.touchUpInside, from: send)
        XCTAssertEqual(sentMessages, 1)
        sentMessages = 0
        composer.setSendEnabled(false)
        composer.clearDraft()
        XCTAssertFalse(microphone.isHidden)
        XCTAssertTrue(send.isHidden)

        XCTAssertTrue(microphone.accessibilityActivate())
        for _ in 0..<100 where recordingStarts == 0 {
            await Task.yield()
        }
        XCTAssertEqual(recordingStarts, 1)
        XCTAssertEqual(controller.state.phase, .handsFree)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_finish"))
        // A hands-free recording's Cancel is a cross in the field's leading end
        let cancel = try XCTUnwrap(findRecordingCancel(in: composer))
        XCTAssertEqual(cancel.accessibilityLabel, lang("Cancel"))
        scheduler.advance(by: 0.8)
        XCTAssertTrue(microphone.accessibilityActivate())
        XCTAssertEqual(controller.state.phase, .recognizing)
        for _ in 0..<100 where composer.draftText != "Dictated message" {
            await Task.yield()
        }
        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertEqual(composer.draftText, "Dictated message")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.format, .m4a)
        XCTAssertEqual(sentMessages, 0)
        XCTAssertFalse(microphone.isHidden)
        XCTAssertFalse(send.isHidden)
    }

    /// The field spans the composer's width with the microphone inside its end, as tall as the send button and as far
    /// from the field's end and bottom; text brings the send button there and the microphone steps aside for it
    @MainActor
    func testMicrophoneStandsInsideTheFieldAndStepsAsideForSend() throws {
        let controller = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let composer = AgentComposerView()
        composer.dictationController = controller
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let circle = try XCTUnwrap(microphone.superview, "The microphone's place")
        let trailingEdge = composer.bounds.width - AgentComposerMetrics.threadHorizontalInset
        let field = composer.inputBackgroundFrame
        XCTAssertEqual(field.minX, AgentComposerMetrics.threadHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(field.maxX, trailingEdge, accuracy: 0.5, "No circle beside the field")
        let inset = AgentComposerMetrics.sendButtonInset
        let size = AgentComposerMetrics.fieldMicrophoneSize
        var circleFrame = circle.convert(circle.bounds, to: composer)
        XCTAssertEqual(circleFrame.size, CGSize(width: size, height: size))
        XCTAssertEqual(circleFrame.maxX, field.maxX - inset, accuracy: 0.5)
        XCTAssertEqual(circleFrame.maxY, field.maxY - inset, accuracy: 0.5)
        XCTAssertTrue(field.contains(microphone.convert(microphone.bounds, to: composer)))

        composer.setDraftText("Hello", focus: false)
        window.layoutIfNeeded()
        let send = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == lang("Send")
        })
        XCTAssertFalse(microphone.isHidden)
        XCTAssertFalse(send.isHidden)
        let filledField = composer.inputBackgroundFrame
        XCTAssertEqual(filledField, field, "The field keeps its frame")
        let sendFrame = send.convert(send.bounds, to: composer)
        XCTAssertEqual(sendFrame.maxX, filledField.maxX, accuracy: 0.5)
        XCTAssertEqual(sendFrame.maxY, filledField.maxY, accuracy: 0.5)
        circleFrame = circle.convert(circle.bounds, to: composer)
        XCTAssertEqual(
            circleFrame.maxX,
            filledField.maxX - inset - AgentComposerMetrics.fieldMicrophoneShift,
            accuracy: 0.5,
            "Before the send button"
        )
        XCTAssertEqual(circleFrame.maxY, filledField.maxY - inset, accuracy: 0.5)

        composer.clearDraft()
        window.layoutIfNeeded()
        XCTAssertTrue(send.isHidden)
        XCTAssertEqual(circle.convert(circle.bounds, to: composer).maxX, field.maxX - inset, accuracy: 0.5, "Back at the end")
    }

    /// Offered, support's headset stands in the glass circle beside the empty field, which gives it its room; a draft
    /// merges the circle into the field, and the field takes its room back
    @MainActor
    func testSupportCircleStandsBesideTheEmptyFieldWhileOffered() throws {
        let controller = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let composer = AgentComposerView()
        composer.dictationController = controller
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        var supportRequests = 0
        composer.onSupport = { supportRequests += 1 }
        let support = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "agent_support"
        })
        let trailingEdge = composer.bounds.width - AgentComposerMetrics.threadHorizontalInset
        XCTAssertEqual(composer.inputBackgroundFrame.maxX, trailingEdge, accuracy: 0.5)
        XCTAssertFalse(support.isEnabled)

        composer.isSupportOffered = true
        window.layoutIfNeeded()
        let field = composer.inputBackgroundFrame
        let size = AgentComposerMetrics.actionCircleSize
        XCTAssertEqual(field.maxX, trailingEdge - size - AgentComposerMetrics.actionCircleSpacing, accuracy: 0.5)
        let supportFrame = support.convert(support.bounds, to: composer)
        XCTAssertEqual(supportFrame.size, CGSize(width: size, height: size))
        XCTAssertEqual(supportFrame.maxX, trailingEdge, accuracy: 0.5)
        XCTAssertEqual(supportFrame.maxY, field.maxY, accuracy: 0.5)
        XCTAssertTrue(support.isEnabled)
        XCTAssertEqual(support.accessibilityLabel, lang("$agent_support_contact"))
        dispatch(.touchUpInside, from: support)
        XCTAssertEqual(supportRequests, 1)

        composer.setDraftText("Hello", focus: false)
        window.layoutIfNeeded()
        XCTAssertEqual(composer.inputBackgroundFrame.maxX, trailingEdge, accuracy: 0.5, "A draft merges the circle into the field")
        composer.clearDraft()
        window.layoutIfNeeded()
        XCTAssertEqual(composer.inputBackgroundFrame.maxX, field.maxX, accuracy: 0.5, "Emptied, the circle comes back out")

        composer.isSupportOffered = false
        window.layoutIfNeeded()
        XCTAssertEqual(composer.inputBackgroundFrame.maxX, trailingEdge, accuracy: 0.5)
        XCTAssertFalse(support.isEnabled)
    }

    /// A held recording let go where it started lands in the field with Send, and the field's own microphone, beside
    /// Send, dictates more. Tapped, it records hands-free, and its stop puts the next transcript after the first.
    @MainActor
    func testTranscriptInTheFieldLeavesTheFieldsMicrophoneToDictateMore() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        var transcripts = ["Раз, два", "три"]
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .transcribed, text: transcripts.removeFirst()) },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let composer = AgentComposerView()
        composer.dictationController = controller
        controller.onTranscript = { [weak composer] in composer?.revealDictatedText($0) }
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)

        controller.touchBegan()
        for _ in 0..<100 where recordings == 0 { await Task.yield() }
        scheduler.advance(by: 1)
        XCTAssertTrue(controller.state.isHeld)
        controller.touchEnded()
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertEqual(composer.draftText, "Раз, два")
        let send = try XCTUnwrap(findButton(labelled: lang("Send"), in: composer), "Send shows as for typed text")
        window.layoutIfNeeded()
        XCTAssertFalse(microphone.isHidden, "The field's microphone stays")
        let circle = try XCTUnwrap(microphone.superview)
        XCTAssertFalse(circle.isHidden)
        XCTAssertLessThan(circle.convert(circle.bounds, to: composer).maxX, send.convert(send.bounds, to: composer).minX)

        controller.touchBegan()
        controller.touchEnded()
        XCTAssertEqual(controller.state.phase, .handsFree, "A tap records hands-free")
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_finish"))
        scheduler.advance(by: 1)
        dispatch(.touchUpInside, from: microphone)
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertEqual(composer.draftText, "Раз, два три", "The next transcript goes after the first, a space apart")
    }

    /// A held microphone let go at Send sends its transcript as the question at once; one that can't be sent yet stays
    /// in the field, whose microphone dictates more
    @MainActor
    func testReleasingAHeldMicrophoneAtSendSendsTheTranscript() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .transcribed, text: "Раз, два") },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        let composer = AgentComposerView()
        composer.dictationController = controller
        var canSend = true
        composer.onDraftTextChanged = { [weak composer] in
            composer?.setSendEnabled(canSend && composer?.draftText?.isEmpty == false)
        }
        var sent: [String] = []
        composer.onSend = { [weak composer] in
            sent.append(composer?.draftText ?? "")
            composer?.clearDraft()
        }

        for attempt in 1...2 {
            canSend = attempt == 1
            controller.touchBegan()
            for _ in 0..<100 where recordings < attempt { await Task.yield() }
            scheduler.advance(by: 1)
            XCTAssertTrue(controller.state.isHeld)
            controller.touchMoved(x: Self.sendDrag)
            XCTAssertEqual(controller.state.holdZone, .send)
            controller.touchEnded(x: Self.sendDrag)
            for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        }
        XCTAssertEqual(sent, ["Раз, два"], "The held recording went as the question, without a stop in the field")
        XCTAssertEqual(composer.draftText, "Раз, два", "The second couldn't be sent and stays in the field")
    }

    /// A held recording let go at Send while an answer is written still sends its transcript as the question, which the
    /// chat keeps waiting for the answer, as it accepts questions then; it doesn't stay in the field
    @MainActor
    func testHeldRecordingReleasedDuringAnAnswerSendsItsTranscript() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .transcribed, text: "Раз, два") },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let composer = AgentComposerView()
        composer.dictationController = controller
        composer.onDraftTextChanged = { [weak composer] in
            composer?.setSendEnabled(composer?.draftText?.isEmpty == false)
        }
        var sent: [String] = []
        composer.onSend = { [weak composer] in
            sent.append(composer?.draftText ?? "")
            composer?.clearDraft()
        }

        controller.touchBegan()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        scheduler.advance(by: 1)
        XCTAssertTrue(controller.state.isHeld)
        // An answer starts meanwhile, and the chat takes questions sent during it
        composer.setStopAvailable(true)
        controller.touchMoved(x: Self.sendDrag)
        controller.touchEnded(x: Self.sendDrag)
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertEqual(sent, ["Раз, два"], "Sent, for the chat to keep waiting")
        XCTAssertEqual(composer.draftText ?? "", "")
    }

    /// Recording starts at the touch, but none of its look shows until the touch is a tap or a hold, 0.2 s on, so
    /// nothing plays and then reverses. A tap then brings the hands-free look: the voice in the placeholder's place, the
    /// circle as Stop, the cross and the haptic. A hold brings what letting go does in the placeholder's place, the
    /// circle, the cross and the haptic.
    @MainActor
    func testRecordingLookWaitsForTheTouchToBeATapOrAHold() async throws {
        XCTAssertEqual(AgentDictationController.tapDuration, 0.2)
        let scheduler = AgentDictationTestScheduler()
        var recordingStarts = 0
        var haptics = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: {
                recordingStarts += 1
                return AgentDictationTestRecorder()
            },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: { haptics += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)

        func beginTouch() async {
            let starts = recordingStarts
            controller.touchBegan()
            for _ in 0..<100 where recordingStarts == starts { await Task.yield() }
            for _ in 0..<20 { await Task.yield() }
            window.layoutIfNeeded()
            XCTAssertEqual(controller.state.phase, .holding, "Recording from the touch")
            XCTAssertFalse(controller.state.isHeld)
            XCTAssertTrue(strip.isHidden || hint.isHidden, "No hint yet")
            XCTAssertNotNil(composer.placeholderFrame, "The placeholder stays")
            XCTAssertEqual(touchView.recordingCircleAlpha, 0, "No circle yet")
            XCTAssertNil(findRecordingCancel(in: composer), "No cross yet")
        }

        await beginTouch()
        XCTAssertEqual(haptics, 0, "No haptic yet")
        controller.touchEnded()
        window.layoutIfNeeded()
        XCTAssertEqual(controller.state.phase, .handsFree, "A tap")
        XCTAssertEqual(haptics, 1)
        XCTAssertTrue(hint.isHidden, "A tap has no hint")
        XCTAssertNil(composer.placeholderFrame, "The voice takes the placeholder's place")
        XCTAssertNotNil(findRecordingCancel(in: composer))
        XCTAssertGreaterThan(touchView.recordingCircleAlpha, 0, "The circle as Stop")
        let send = try XCTUnwrap(descendants(of: composer).first { $0.accessibilityIdentifier == "agent_send" })
        let sendX = send.convert(CGPoint(x: send.bounds.midX, y: 0), to: composer).x
        XCTAssertGreaterThanOrEqual(
            abs(sendX - touchView.center.x),
            AgentComposerMetrics.sendButtonSize.width,
            "Stop rests clear of Send, which took the microphone's place"
        )

        controller.cancel()
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertNil(findRecordingCancel(in: composer), "The cross goes with the recording")
        await beginTouch()
        XCTAssertEqual(haptics, 1)
        scheduler.advance(by: AgentDictationController.tapDuration)
        window.layoutIfNeeded()
        XCTAssertTrue(controller.state.isHeld, "A hold")
        XCTAssertEqual(haptics, 2)
        XCTAssertFalse(hint.isHidden)
        XCTAssertEqual(hint.text, lang("$agent_dictation_release_to_stop"))
        XCTAssertNil(composer.placeholderFrame, "In the placeholder's place")
        XCTAssertNotNil(findRecordingCancel(in: composer))
        XCTAssertGreaterThan(touchView.recordingCircleAlpha, 0)
    }

    /// The Agent list's field holds a question, which keeps the search circle away, while it records or recognizes, or
    /// has text. A recording that turns into its transcript reports no moment without one between.
    @MainActor
    func testListFieldHoldsAQuestionWhileDictatingOrWithText() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .transcribed, text: "Раз, два") },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        let bar = AgentListBottomBar(frame: CGRect(x: 0, y: 0, width: 358, height: AgentListBottomBar.height))
        bar.composerView.dictationController = controller
        controller.onTranscript = { [weak bar] in bar?.composerView.revealDictatedText($0) }
        var reports: [Bool] = []
        bar.onQuestionChange = { [weak bar] in reports.append(bar?.hasQuestion == true) }
        XCTAssertFalse(bar.hasQuestion)

        controller.startHandsFree()
        for _ in 0..<100 where recordings == 0 { await Task.yield() }
        XCTAssertTrue(bar.hasQuestion, "While recording")
        scheduler.advance(by: 1)
        controller.finish()
        XCTAssertTrue(bar.hasQuestion, "While recognizing")
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(bar.composerView.draftText, "Раз, два")
        XCTAssertTrue(bar.hasQuestion, "With the transcript")
        XCTAssertEqual(reports, [true])

        bar.clearDraft()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(bar.hasQuestion, "Once sent or cleared")
        XCTAssertEqual(reports, [true, false])

        bar.composerView.setDraftText("Typed", focus: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(bar.hasQuestion, "With typed text")
        XCTAssertEqual(reports, [true, false, true])
    }

    /// A transcript's characters come 6 ms apart, closer for a long one so the last starts within 0.8 s, and each
    /// sharpens out of its blur in 0.15 s
    @MainActor
    func testTranscriptCharactersComeFastAndWithinTheCap() {
        XCTAssertEqual(TextViewCharacterReveal.getCharacterStep(characterCount: 1), 0.006, accuracy: 0.00001)
        XCTAssertEqual(TextViewCharacterReveal.getCharacterStep(characterCount: 100), 0.006, accuracy: 0.00001)
        XCTAssertEqual(TextViewCharacterReveal.getCharacterStep(characterCount: 201), 0.004, accuracy: 0.00001)
        XCTAssertEqual(TextViewCharacterReveal.getCharacterStep(characterCount: 1000) * 999, 0.8, accuracy: 0.00001)
        XCTAssertEqual(TextViewCharacterReveal.sharpenDuration, 0.15)
    }

    /// The field doesn't glow while the user records: its lights and its rim glow once the recording is finished, while
    /// it is recognized. The transcript then comes in character by character as
    /// the glow stays; the field takes no typing and reports no draft until all of it is in, and the glow goes once it
    /// is.
    @MainActor
    func testTranscriptComesInCharacterByCharacterWhileTheFieldGlows() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades the transcript in")
        let transcript = (1...40).map { "word\($0)" }.joined(separator: " ")
        let scheduler = AgentDictationTestScheduler()
        let recorder = AgentDictationTestRecorder()
        var isRecording = false
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { recorder },
            transcribe: { _ in .init(outcome: .transcribed, text: transcript) },
            haptic: { isRecording = true },
            gestureFeedback: {},
            observeLifecycle: false
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let composer = AgentComposerView()
        composer.dictationController = controller
        controller.onTranscript = { [weak composer] in composer?.revealDictatedText($0) }
        var draftChanges = 0
        composer.onDraftTextChanged = { draftChanges += 1 }
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let glows = descendants(of: composer).compactMap { $0 as? AgentFieldGlowView }
        XCTAssertEqual(Set(glows.map(\.part)), [.lights, .rim])
        /// Whether both parts glow, or nil while they differ
        func getGlowState() -> Bool? {
            let states = Set(glows.map(\.isGlowing))
            return states.count == 1 ? states.first : nil
        }
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UITextView }.first)
        let initialHeight = composer.inputHeight
        XCTAssertEqual(getGlowState(), false)

        controller.startHandsFree()
        for _ in 0..<100 where !isRecording { await Task.yield() }
        XCTAssertEqual(getGlowState(), false, "The field doesn't glow while the user records")
        scheduler.advance(by: 1)
        XCTAssertEqual(getGlowState(), false)
        controller.finish()
        XCTAssertEqual(controller.state.phase, .recognizing)
        XCTAssertEqual(getGlowState(), true, "The field glows once the recording is finished, while it is recognized")

        var partialLengths: Set<Int> = []
        for _ in 0..<300 where composer.draftText != transcript {
            let length = composer.draftText?.count ?? 0
            if length > 0 {
                partialLengths.insert(length)
                XCTAssertEqual(getGlowState(), true)
                XCTAssertFalse(composer.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "x"))
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(composer.draftText, transcript)
        XCTAssertGreaterThanOrEqual(partialLengths.count, 3, "The characters come in one after another")
        let characters = Array(transcript)
        XCTAssertTrue(
            partialLengths.contains { $0 > 1 && $0 < characters.count && characters[$0 - 1] != " " && characters[$0] != " " },
            "A word comes in character by character: \(partialLengths.sorted())"
        )
        XCTAssertGreaterThan(composer.inputHeight, initialHeight, "The field grows as the words come in")

        for _ in 0..<300 where draftChanges == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(draftChanges, 1)
        XCTAssertEqual(composer.draftText, transcript)
        XCTAssertEqual(getGlowState(), false)
        XCTAssertTrue(composer.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "x"))
    }

    /// The recording circle's glyph takes the colour of content on the accent, black on the white accent of the dark
    /// theme, and is white on a failure's red circle
    @MainActor
    func testRecordingGlyphReadsOnTheWhiteAccent() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let touchView = AgentDictationTouchView()
        touchView.tintColor = .white
        window.addSubview(touchView)
        touchView.setAnchor(CGPoint(x: 340, y: 800))
        touchView.update(AgentDictationState(phase: .handsFree))
        let glyph = try XCTUnwrap(
            descendants(of: touchView).compactMap { $0 as? UIImageView }.first { $0.superview is AgentVoiceBlobView }
        )
        XCTAssertEqual(glyph.tintColor.resolvedColor(with: touchView.traitCollection), .black, "On the white circle")

        // The failure plays only in motion
        UIView.setAnimationsEnabled(true)
        touchView.update(AgentDictationState(phase: .failed))
        XCTAssertNotNil(touchView.failureCenter, "The failure shows")
        XCTAssertEqual(glyph.tintColor.resolvedColor(with: touchView.traitCollection), .white, "On the red circle")
    }

    /// The field's recognition glow lies on the field as the recording and the recognition change the field and as the
    /// field changes width, and it fades as recognition ends
    @MainActor
    func testRecognitionGlowLiesOnTheField() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in
                try await Task.sleep(for: .seconds(60))
                throw CancellationError()
            },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let rim = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentFieldGlowView }.first { $0.part == .rim })
        func assertRimOnTheField(_ moment: String) {
            composer.layoutIfNeeded()
            let field = composer.inputBackgroundFrame.insetBy(dx: -AgentFieldGlowView.rimMargin, dy: -AgentFieldGlowView.rimMargin)
            let frame = rim.convert(rim.bounds, to: composer)
            XCTAssertEqual(frame.minX, field.minX, accuracy: 0.5, moment)
            XCTAssertEqual(frame.minY, field.minY, accuracy: 0.5, moment)
            XCTAssertEqual(frame.width, field.width, accuracy: 0.5, moment)
            XCTAssertEqual(frame.height, field.height, accuracy: 0.5, moment)
        }

        controller.startHandsFree()
        for _ in 0..<100 where recordings == 0 { await Task.yield() }
        assertRimOnTheField("Recording")
        scheduler.advance(by: 1)
        controller.finish()
        XCTAssertEqual(controller.state.phase, .recognizing)
        XCTAssertTrue(rim.isGlowing)
        assertRimOnTheField("Recognizing")
        window.frame.size.width = 320
        window.layoutIfNeeded()
        assertRimOnTheField("Narrower")

        controller.cancel()
        XCTAssertFalse(rim.isGlowing, "Recognition over, the glow fades")
        assertRimOnTheField("After")
    }

    /// Recording hands-free puts the cancelling cross in the field's leading end, which cancels when tapped and goes as
    /// the recording ends, and the voice in the placeholder's place. No caret blinks in the field meanwhile.
    @MainActor
    func testHandsFreeRecordingPutsTheCrossInTheField() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .transcribed, text: "Раз") },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        controller.onTranscript = { [weak composer] in composer?.revealDictatedText($0) }
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
        XCTAssertNil(findRecordingCancel(in: composer))

        controller.startHandsFree()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        window.layoutIfNeeded()
        let field = composer.inputBackgroundFrame
        XCTAssertNil(composer.placeholderFrame, "The voice takes the placeholder's place")
        XCTAssertEqual(textView.tintColor, .clear, "No caret while recording")

        let cross = try XCTUnwrap(findRecordingCancel(in: composer), "The cross shows")
        let crossFrame = cross.convert(cross.bounds, to: composer)
        XCTAssertTrue(field.insetBy(dx: -0.5, dy: -0.5).contains(crossFrame), "Inside the field")
        XCTAssertLessThan(crossFrame.midX, field.midX, "At the leading end")
        XCTAssertTrue(composer.hitTest(CGPoint(x: crossFrame.midX, y: crossFrame.midY), with: nil) === cross)

        scheduler.advance(by: 1)
        controller.finish()
        for _ in 0..<200 where controller.state.phase != .idle { await Task.yield() }
        window.layoutIfNeeded()
        XCTAssertEqual(composer.textLeadingInset, AgentComposerMetrics.contentHorizontalInset)
        XCTAssertNotEqual(textView.tintColor, .clear, "The caret is back")
        XCTAssertNil(findRecordingCancel(in: composer), "The cross goes with the recording")

        // The cross cancels
        composer.clearDraft()
        controller.startHandsFree()
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        window.layoutIfNeeded()
        dispatch(.touchUpInside, from: try XCTUnwrap(findRecordingCancel(in: composer)))
        XCTAssertEqual(controller.state.phase, .idle, "Cancelled")
        XCTAssertEqual(composer.draftText ?? "", "")
    }

    /// A held recording cancelled brings the placeholder back the way the hint took its place, sliding in as it fades
    /// in, rather than in one frame
    @MainActor
    func testPlaceholderComesBackInMotionAfterAHeldRecording() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "With Reduce Motion it fades in")
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let placeholder = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UILabel }.first {
            $0.text == composer.placeholder
        })

        controller.touchBegan()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        scheduler.advance(by: AgentDictationController.tapDuration)
        XCTAssertTrue(controller.state.isHeld)
        window.layoutIfNeeded()
        XCTAssertTrue(placeholder.isHidden, "The hint takes its place")
        controller.cancel()
        XCTAssertFalse(placeholder.isHidden)
        XCTAssertFalse(placeholder.layer.animationKeys()?.isEmpty ?? true, "It comes back in motion")
    }

    /// Dictating more into a field with text keeps its text in sight, unchanged and where it is, a line up over the
    /// recording's row, while the field's microphone records, held or hands-free, and while the transcript is
    /// recognized, when the field glows; the transcript then goes after the text
    @MainActor
    func testFurtherDictationKeepsTheFieldsTextOverTheRecordingsRow() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        var transcripts = ["Раз, два", "три", "четыре"]
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .transcribed, text: transcripts.removeFirst()) },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        controller.onTranscript = { [weak composer] in composer?.revealDictatedText($0) }
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        func waitUntilIdle() async {
            for _ in 0..<200 where controller.state.phase != .idle { await Task.yield() }
            window.layoutIfNeeded()
        }
        controller.startHandsFree()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        scheduler.advance(by: 1)
        controller.finish()
        await waitUntilIdle()
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
        let rim = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentFieldGlowView }.first { $0.part == .rim })
        let padding = AgentComposerMetrics.contentHorizontalInset
        func assertTextOverTheRow(_ text: String?, height: CGFloat, _ moment: String) {
            window.layoutIfNeeded()
            XCTAssertTrue(composer.isDraftTextShown, "\(moment): the text stays in sight")
            XCTAssertEqual(composer.draftText, text, "\(moment): unchanged")
            XCTAssertEqual(composer.textLeadingInset, padding, "\(moment): where it is")
            XCTAssertFalse(strip.isHidden, "\(moment): the recording's row")
            XCTAssertGreaterThan(composer.inputHeight, height, "\(moment): the field grows a line for the row")
        }

        // Held: the field's microphone records, and let go where it started, the transcript goes into the field
        let text = composer.draftText
        let height = composer.inputHeight
        controller.touchBegan()
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        XCTAssertEqual(composer.draftText, text, "Touched: unchanged")
        scheduler.advance(by: AgentDictationController.tapDuration)
        XCTAssertTrue(controller.state.isHeld)
        assertTextOverTheRow(text, height: height, "Held")
        XCTAssertEqual(touchView.recordingCircleAlpha, 1, "The recording circle shows over the microphone")
        scheduler.advance(by: 1)
        controller.touchEnded()
        XCTAssertEqual(controller.state.phase, .recognizing)
        assertTextOverTheRow(text, height: height, "Recognizing")
        XCTAssertTrue(rim.isGlowing, "The field glows as it is recognized")
        await waitUntilIdle()
        XCTAssertEqual(composer.draftText, "Раз, два три", "The transcript goes after it")
        XCTAssertEqual(composer.textLeadingInset, padding)

        // Tapped: the field's microphone is the stop, the field as it is
        let longerText = composer.draftText
        let longerHeight = composer.inputHeight
        controller.touchBegan()
        controller.touchEnded()
        XCTAssertEqual(controller.state.phase, .handsFree)
        for _ in 0..<100 where recordings < 3 { await Task.yield() }
        assertTextOverTheRow(longerText, height: longerHeight, "Hands-free")
        scheduler.advance(by: 1)
        dispatch(.touchUpInside, from: microphone)
        XCTAssertEqual(controller.state.phase, .recognizing)
        assertTextOverTheRow(longerText, height: longerHeight, "Recognizing after the stop")
        XCTAssertTrue(rim.isGlowing)
        await waitUntilIdle()
        XCTAssertEqual(composer.draftText, "Раз, два три четыре")
        XCTAssertEqual(composer.textLeadingInset, padding)
    }

    /// A further dictation into a field with text that hears nothing plays its failure on the field's microphone and
    /// leaves the field's text as it was and the microphone at rest: nothing records again, and no recording circle
    /// stays over the microphone
    @MainActor
    func testFurtherDictationThatHearsNothingLeavesTheFieldAsItWas() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        var failures = 0
        var responses: [ApiAgentV2TranscriptionResponse] = [
            .init(outcome: .transcribed, text: "Раз, два"),
            .init(outcome: .noSpeech),
        ]
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in responses.removeFirst() },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            failureFeedback: { failures += 1 },
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        controller.onTranscript = { [weak composer] in composer?.revealDictatedText($0) }
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()

        controller.startHandsFree()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        scheduler.advance(by: 1)
        controller.finish()
        for _ in 0..<200 where controller.state.phase != .idle { await Task.yield() }
        window.layoutIfNeeded()
        XCTAssertEqual(composer.draftText, "Раз, два")
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let circle = try XCTUnwrap(microphone.superview)

        // Held, it records more, which comes back with no speech
        controller.touchBegan()
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        scheduler.advance(by: AgentDictationController.tapDuration)
        scheduler.advance(by: 1)
        // The failure plays only in motion
        UIView.setAnimationsEnabled(true)
        controller.touchEnded()
        for _ in 0..<200 where controller.state.phase != .failed { await Task.yield() }
        guard case .noSpeech? = controller.state.failure else {
            return XCTFail("Nothing was heard: \(String(describing: controller.state.failure))")
        }
        XCTAssertEqual(composer.draftText, "Раз, два", "The field keeps its text")
        window.layoutIfNeeded()
        let failure = try XCTUnwrap(touchView.failureCenter, "The failure shows")
        let microphoneCenter = circle.convert(CGPoint(x: circle.bounds.midX, y: circle.bounds.midY), to: touchView)
        XCTAssertEqual(failure.x, microphoneCenter.x, accuracy: 0.5, "On the field's microphone")
        XCTAssertEqual(failure.y, microphoneCenter.y, accuracy: 0.5)
        XCTAssertEqual(failures, 1, "Its haptic plays")

        scheduler.advance(by: AgentDictationController.failureDuration)
        window.layoutIfNeeded()
        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertEqual(composer.draftText, "Раз, два")
        XCTAssertFalse(circle.isHidden, "At rest, ready for more")
        XCTAssertEqual(touchView.recordingCircleAlpha, 0, "No recording circle stays over the microphone")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(recordings, 2, "Nothing records again by itself")
    }

    /// With text in the field, Send keeps its place through a dictation into the text from the field's microphone,
    /// held or tapped, heard or not: it stays in sight with the same frame, and the text keeps its layout width, so it
    /// never reflows but for the transcript it takes, also while a failure plays on the microphone
    @MainActor
    func testSendKeepsItsPlaceThroughADictationIntoTheText() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        var responses: [ApiAgentV2TranscriptionResponse] = [
            .init(outcome: .transcribed, text: "Раз, два"),
            .init(outcome: .transcribed, text: "три"),
            .init(outcome: .noSpeech),
            .init(outcome: .transcribed, text: "четыре"),
            .init(outcome: .noSpeech),
        ]
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in responses.removeFirst() },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            failureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        composer.setSendEnabled(true)
        controller.onTranscript = { [weak composer] in composer?.revealDictatedText($0) }
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        func waitUntil(_ phase: AgentDictationState.Phase) async {
            for _ in 0..<200 where controller.state.phase != phase { await Task.yield() }
            window.layoutIfNeeded()
        }
        controller.startHandsFree()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        scheduler.advance(by: 1)
        controller.finish()
        await waitUntil(.idle)
        let send = try XCTUnwrap(findButton(labelled: lang("Send"), in: composer))
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
        // On screen: the field grows up for the recording's row, its bottom where it is
        let sendFrame = send.convert(send.bounds, to: window)
        let textWidth = textView.textContainer.size.width
        func assertSendInPlace(_ moment: String) {
            window.layoutIfNeeded()
            XCTAssertFalse(send.isHidden, "\(moment): Send stays")
            XCTAssertEqual(send.alpha, 1, "\(moment): Send stays")
            let frame = send.convert(send.bounds, to: window)
            XCTAssertEqual(frame.minX, sendFrame.minX, accuracy: 0.5, "\(moment): where it was")
            XCTAssertEqual(frame.minY, sendFrame.minY, accuracy: 0.5, "\(moment): where it was")
            XCTAssertEqual(frame.size, sendFrame.size, "\(moment): as large")
            XCTAssertEqual(textView.textContainer.size.width, textWidth, "\(moment): the text keeps its width")
        }
        func press(_ state: UIGestureRecognizer.State) {
            if state == .began {
                controller.touchBegan()
            } else {
                controller.touchEnded()
            }
        }
        assertSendInPlace("At rest")

        // Held, heard
        press(.began)
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        assertSendInPlace("Touched")
        scheduler.advance(by: AgentDictationController.tapDuration)
        assertSendInPlace("Held")
        scheduler.advance(by: 1)
        press(.ended)
        assertSendInPlace("Recognizing")
        await waitUntil(.idle)
        assertSendInPlace("Heard")

        // Held, nothing heard
        press(.began)
        for _ in 0..<100 where recordings < 3 { await Task.yield() }
        scheduler.advance(by: AgentDictationController.tapDuration)
        scheduler.advance(by: 1)
        press(.ended)
        await waitUntil(.failed)
        assertSendInPlace("Failing after a hold")
        scheduler.advance(by: AgentDictationController.failureDuration)
        await waitUntil(.idle)
        assertSendInPlace("After the failure")

        // Tapped, heard
        press(.began)
        press(.ended)
        XCTAssertEqual(controller.state.phase, .handsFree)
        for _ in 0..<100 where recordings < 4 { await Task.yield() }
        assertSendInPlace("Hands-free")
        scheduler.advance(by: 1)
        dispatch(.touchUpInside, from: microphone)
        assertSendInPlace("Recognizing after the stop")
        await waitUntil(.idle)
        assertSendInPlace("Heard after the stop")

        // Tapped, nothing heard
        press(.began)
        press(.ended)
        for _ in 0..<100 where recordings < 5 { await Task.yield() }
        scheduler.advance(by: 1)
        dispatch(.touchUpInside, from: microphone)
        await waitUntil(.failed)
        assertSendInPlace("Failing after a stop")
        scheduler.advance(by: AgentDictationController.failureDuration)
        await waitUntil(.idle)
        assertSendInPlace("At rest again")
        XCTAssertEqual(composer.draftText, "Раз, два три четыре")
    }

    /// A transcript's reveal that something interrupts settles at once, all of it sharp and in the text colour, with
    /// nothing left in the accent or blurred: the field taking focus, or a character typed in the middle of it, which
    /// then goes in after it
    @MainActor
    func testInterruptedRevealSettlesInTheTextColour() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "With Reduce Motion the transcript fades in whole")
        let transcript = "Раз два три четыре пять шесть семь"
        for interruption in ["focus", "typing"] {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let composer = AgentComposerView()
            window.addSubview(composer)
            NSLayoutConstraint.activate([
                composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
            ])
            window.layoutIfNeeded()
            let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
            let textColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? UIColor)

            composer.revealDictatedText(transcript)
            XCTAssertLessThan(textView.text.count, transcript.count, "\(interruption): the reveal is under way")
            switch interruption {
            case "focus":
                textView.delegate?.textViewDidBeginEditing?(textView)
                XCTAssertEqual(textView.text, transcript, "Focus: all of it shows")
            default:
                textView.insertText("!")
                XCTAssertEqual(textView.text, transcript + "!", "Typing: all of it shows, and the character goes after it")
            }
            let storage = textView.textStorage
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
                let color = attributes[.foregroundColor] as? UIColor
                XCTAssertEqual(color, textColor, "\(interruption): \(range) in the text colour")
                XCTAssertNil(attributes[.shadow], "\(interruption): \(range) sharp")
            }
            XCTAssertEqual(textView.typingAttributes[.foregroundColor] as? UIColor, textColor, "\(interruption): typing goes on in it")
            XCTAssertNil(textView.typingAttributes[.shadow])
        }
    }

    /// The recording panel shows no time: what letting go does, a hands-free recording's voice, or the recognition
    @MainActor
    func testRecordingPanelShowsNoTimer() {
        let strip = AgentDictationStripView()
        for phase in [AgentDictationState.Phase.holding, .handsFree, .recognizing] {
            strip.update(AgentDictationState(phase: phase))
            let texts = descendants(of: strip).compactMap { ($0 as? UILabel)?.text }
            XCTAssertFalse(
                texts.contains { $0.range(of: #"\d:\d\d"#, options: .regularExpression) != nil },
                "No time while \(phase): \(texts)"
            )
        }
    }

    @MainActor
    private func findButton(labelled label: String, in view: UIView) -> UIButton? {
        descendants(of: view).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == label && !$0.isHidden }
    }

    /// The recording's cross in the field, while it shows
    @MainActor
    private func findRecordingCancel(in composer: AgentComposerView) -> UIButton? {
        descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "agent_dictation_cancel" && !$0.isHidden
        }
    }

    /// Far enough toward Send, past the trailing end, for a held microphone let go there to send
    private static let sendDrag: Double = 300

    /// While an answer can be stopped, the empty field's send button holds Stop in its accent capsule, and the
    /// microphone steps aside for it and still records. Typing turns Stop into Send in the same capsule, and clearing
    /// the field turns it back; once the answer can't be stopped, the empty field has no capsule.
    @MainActor
    func testStopTakesTheSendButtonsPlaceWhileAnAnswerCanBeStopped() throws {
        let controller = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let composer = AgentComposerView()
        composer.dictationController = controller
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        var stops = 0
        var sends = 0
        composer.onStop = { stops += 1 }
        composer.onSend = { sends += 1 }
        composer.setSendEnabled(true)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let circle = try XCTUnwrap(microphone.superview)
        let send = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "agent_send"
        })
        let recognizer = try XCTUnwrap(microphone.gestureRecognizers?.first { $0 is UILongPressGestureRecognizer })
        let restingCircleX = circle.convert(circle.bounds, to: composer).minX
        XCTAssertTrue(send.isHidden)

        composer.setStopAvailable(true)
        window.layoutIfNeeded()
        XCTAssertFalse(send.isHidden)
        XCTAssertTrue(send.isEnabled)
        XCTAssertEqual(send.accessibilityLabel, lang("$agent_stop_answer"))
        XCTAssertEqual(send.accessibilityIdentifier, "agent_stop")
        XCTAssertEqual(
            circle.convert(circle.bounds, to: composer).minX,
            restingCircleX - AgentComposerMetrics.fieldMicrophoneShift,
            accuracy: 0.5,
            "The microphone steps aside for Stop"
        )
        XCTAssertTrue(recognizer.isEnabled, "The microphone still records")
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_start"))
        dispatch(.touchUpInside, from: send)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(sends, 0)

        composer.setDraftText("Hello", focus: false)
        XCTAssertEqual(send.accessibilityLabel, lang("Send"), "Text in the field turns Stop into Send")
        XCTAssertEqual(send.accessibilityIdentifier, "agent_send")
        dispatch(.touchUpInside, from: send)
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(stops, 1)
        composer.setDraftText("", focus: false)
        XCTAssertFalse(send.isHidden, "Stop comes back to the emptied field")
        XCTAssertEqual(send.accessibilityLabel, lang("$agent_stop_answer"))

        composer.setStopAvailable(false)
        window.layoutIfNeeded()
        XCTAssertTrue(send.isHidden, "Without an answer to stop, the empty field has no capsule")
        XCTAssertEqual(send.accessibilityIdentifier, "agent_send")
        XCTAssertEqual(circle.convert(circle.bounds, to: composer).minX, restingCircleX, accuracy: 0.5)
    }

    @MainActor
    func testHoldingDictationKeepsKeyboardFocusAndBlocksInputThroughRecognition() async throws {
        let scheduler = AgentDictationTestScheduler()
        let recorder = AgentDictationTestRecorder()
        var isRecordingReady = false
        var transcription: CheckedContinuation<ApiAgentV2TranscriptionResponse, Error>?
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { recorder },
            transcribe: { _ in
                try await withCheckedThrowingContinuation { transcription = $0 }
            },
            haptic: { isRecordingReady = true },
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        root.view.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: root.view.keyboardLayoutGuide.topAnchor)
        ])
        window.layoutIfNeeded()
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UITextView }.first)
        composer.setDraftText(" ", focus: true)
        XCTAssertTrue(textView.isFirstResponder)

        controller.touchBegan()
        scheduler.advance(by: 0.22)

        XCTAssertEqual(controller.state.phase, .holding)
        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertTrue(textView.isEditable)
        textView.insertText("Blocked while recording")
        textView.deleteBackward()
        XCTAssertEqual(composer.draftText, " ")
        for _ in 0..<100 where !isRecordingReady { await Task.yield() }
        XCTAssertTrue(isRecordingReady)
        scheduler.advance(by: 0.8)
        controller.touchEnded()

        XCTAssertEqual(controller.state.phase, .recognizing)
        XCTAssertTrue(textView.isFirstResponder)
        textView.insertText("Blocked while recognizing")
        textView.deleteBackward()
        XCTAssertEqual(composer.draftText, " ")
        for _ in 0..<100 where transcription == nil { await Task.yield() }
        let pendingTranscription = try XCTUnwrap(transcription)
        controller.cancel()
        pendingTranscription.resume(returning: .init(outcome: .noSpeech))
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(textView.isFirstResponder)
        textView.insertText("Typing resumes")
        XCTAssertEqual(composer.draftText, " Typing resumes")
    }

    @MainActor
    func testShrinkingWhitespaceDraftKeepsTheCircleUnderAStationaryFinger() async throws {
        let scheduler = AgentDictationTestScheduler()
        let recorder = AgentDictationTestRecorder()
        var recordingStarts = 0
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: {
                recordingStarts += 1
                return recorder
            },
            transcribe: { _ in .init(outcome: .transcribed, text: "Dictated message") },
            haptic: {},
            observeLifecycle: false
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let composer = AgentComposerView()
        composer.dictationController = controller
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        composer.setDraftText(String(repeating: "\n", count: 6), focus: false)
        window.layoutIfNeeded()
        // With room above it, the field grows past its least maximum to fit all seven lines
        let initialFieldHeight = composer.inputBackgroundFrame.height
        XCTAssertGreaterThan(initialFieldHeight, AgentComposerMetrics.maxInputHeight)
        let initialComposerY = composer.frame.minY
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let gesture = DictationTestGestureRecognizer()
        microphone.addGestureRecognizer(gesture)
        let pressPoint = microphone.convert(CGPoint(x: microphone.bounds.midX, y: microphone.bounds.midY), to: window)
        gesture.pointInWindow = pressPoint
        gesture.simulatedState = .began
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
        scheduler.advance(by: 0.22)
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        // The circle stays where the finger pressed, as the microphone steps aside for Send and the field shrinks
        var touchCenterInWindow = composer.convert(touchView.center, to: window)
        XCTAssertEqual(touchCenterInWindow.x, pressPoint.x, accuracy: 0.01)
        XCTAssertEqual(touchCenterInWindow.y, pressPoint.y, accuracy: 0.01)
        XCTAssertEqual(touchView.bounds.width, AgentVoiceRecordingMetrics.circleDiameter)
        for _ in 0..<100 where recordingStarts == 0 { await Task.yield() }
        XCTAssertEqual(recordingStarts, 1)
        window.layoutIfNeeded()
        XCTAssertEqual(composer.inputBackgroundFrame.height, AgentComposerMetrics.minInputHeight)
        XCTAssertEqual(composer.frame.minY - initialComposerY, initialFieldHeight - AgentComposerMetrics.minInputHeight)
        touchCenterInWindow = composer.convert(touchView.center, to: window)
        XCTAssertEqual(touchCenterInWindow.x, pressPoint.x, accuracy: 0.01)
        XCTAssertEqual(touchCenterInWindow.y, pressPoint.y, accuracy: 0.01)

        gesture.pointInWindow.y -= 2
        gesture.pointInWindow.x += 4
        gesture.simulatedState = .changed
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)

        XCTAssertEqual(controller.state.phase, .holding)
        XCTAssertEqual(controller.state.holdZone, .stop)
        touchCenterInWindow = composer.convert(touchView.center, to: window)
        XCTAssertEqual(touchCenterInWindow.x, pressPoint.x, accuracy: 0.01)
        XCTAssertEqual(touchCenterInWindow.y, pressPoint.y, accuracy: 0.01)
        scheduler.advance(by: 0.8)
        gesture.simulatedState = .ended
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
        XCTAssertEqual(controller.state.phase, .recognizing)
        XCTAssertFalse(controller.state.isSending, "A small drift keeps the transcript in the field")
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertEqual(recorder.stopCount, 1)
    }

    /// Right to left, the field's cross stands at the right: a held microphone slid right is let go to cancel, and slid
    /// left to send, the hint telling which, while the circle's place stays over the microphone
    @MainActor
    func testRightToLeftHoldCancelsToTheRightAndSendsToTheLeft() async throws {
        let scheduler = AgentDictationTestScheduler()
        let recorder = AgentDictationTestRecorder()
        var isRecordingReady = false
        var requests: [ApiAgentV2TranscriptionRequest] = []
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { recorder },
            transcribe: { request in
                requests.append(request)
                return .init(outcome: .noSpeech)
            },
            haptic: { isRecordingReady = true },
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        root.view.frame = window.bounds
        let host = UIViewController()
        root.addChild(host)
        root.view.addSubview(host.view)
        host.view.frame = window.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: root)
        if #available(iOS 17, *) {
            root.traitOverrides.layoutDirection = .rightToLeft
        } else {
            root.setOverrideTraitCollection(UITraitCollection(layoutDirection: .rightToLeft), forChild: host)
        }
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        host.view.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        window.layoutIfNeeded()
        XCTAssertEqual(composer.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let gesture = DictationTestGestureRecognizer()
        microphone.addGestureRecognizer(gesture)
        let origin = microphone.convert(CGPoint(x: microphone.bounds.midX, y: microphone.bounds.midY), to: window)
        gesture.pointInWindow = origin
        gesture.simulatedState = .began
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
        scheduler.advance(by: 0.22)
        for _ in 0..<100 where !isRecordingReady { await Task.yield() }
        XCTAssertTrue(isRecordingReady)
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(hint.text, lang("$agent_dictation_release_to_stop"))

        let drags: [(x: CGFloat, zone: AgentDictationState.HoldZone)] = [(-300, .send), (300, .cancel)]
        for drag in drags {
            gesture.pointInWindow.x = origin.x + drag.x
            gesture.simulatedState = .changed
            composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
            window.layoutIfNeeded()
            XCTAssertEqual(controller.state.phase, .holding)
            XCTAssertEqual(controller.state.holdZone, drag.zone)
            XCTAssertEqual(hint.text, lang("$agent_dictation_release_to_\(drag.zone == .send ? "send" : "cancel")"))
            // The circle grows out of the microphone and stays anchored there; only its blob slides
            let circleCenter = composer.convert(touchView.center, to: window)
            XCTAssertEqual(circleCenter.x, origin.x, accuracy: 0.01)
            XCTAssertEqual(circleCenter.y, origin.y, accuracy: 0.01)
        }

        gesture.simulatedState = .ended
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertEqual(recorder.cancelCount, 1)
        scheduler.advance(by: 60)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(recorder.stopCount, 0)
    }

    /// Right to left, a hands-free recording's cross stands in the field's leading end, at the right, and nothing
    /// cancels the recognition
    @MainActor
    func testRightToLeftHandsFreeRecordingPutsTheCrossAtTheRight() async throws {
        let scheduler = AgentDictationTestScheduler()
        let recorder = AgentDictationTestRecorder()
        var isRecordingReady = false
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { recorder },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: { isRecordingReady = true },
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        root.view.frame = window.bounds
        let host = UIViewController()
        root.addChild(host)
        root.view.addSubview(host.view)
        host.view.frame = window.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: root)
        if #available(iOS 17, *) {
            root.traitOverrides.layoutDirection = .rightToLeft
        } else {
            root.setOverrideTraitCollection(UITraitCollection(layoutDirection: .rightToLeft), forChild: host)
        }
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        host.view.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let finish = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        XCTAssertTrue(finish.accessibilityActivate())
        for _ in 0..<100 where !isRecordingReady { await Task.yield() }
        XCTAssertTrue(isRecordingReady)
        XCTAssertEqual(controller.state.phase, .handsFree)
        window.layoutIfNeeded()
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
        XCTAssertEqual(strip.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        XCTAssertEqual(finish.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)

        scheduler.advance(by: 1)
        window.layoutIfNeeded()
        XCTAssertFalse(strip.subviews.contains { $0 is UIButton }, "No cross in the panel")
        let cross = try XCTUnwrap(findRecordingCancel(in: composer))
        let crossFrame = cross.convert(cross.bounds, to: composer)
        let field = composer.inputBackgroundFrame
        XCTAssertGreaterThan(crossFrame.midX, field.midX, "At the leading end, on the right")
        XCTAssertTrue(field.insetBy(dx: -0.5, dy: -0.5).contains(crossFrame), "Inside the field")

        controller.finish()
        XCTAssertEqual(controller.state.phase, .recognizing)
        window.layoutIfNeeded()
        XCTAssertTrue(try XCTUnwrap(finish.superview).isHidden, "The microphone gives way to the recognition")
        XCTAssertFalse(strip.subviews.contains { $0 is UIButton && !$0.isHidden }, "Recognition has no Cancel")
        XCTAssertEqual(hint.textAlignment, .right)
    }

    @MainActor
    func testFailedDictationKeepsTheRecordingCircleUntilTheMicrophoneReturns() async throws {
        let scheduler = AgentDictationTestScheduler()
        let recorder = AgentDictationTestRecorder()
        recorder.averagePowerValue = -80
        var isRecordingReady = false
        let controller = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { recorder },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: { isRecordingReady = true },
            gestureFeedback: {},
            failureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let composer = AgentComposerView()
        composer.dictationController = controller
        var circleVisibilityChanges: [Bool] = []
        composer.onRecordingCircleVisibilityChanged = { [weak composer] in
            circleVisibilityChanges.append(composer?.isRecordingCircleVisible ?? false)
        }
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        let gesture = try XCTUnwrap(microphone.gestureRecognizers?.compactMap { $0 as? UILongPressGestureRecognizer }.first)
        XCTAssertFalse(composer.isRecordingCircleVisible)

        controller.startHandsFree()
        for _ in 0..<100 where !isRecordingReady { await Task.yield() }
        XCTAssertTrue(composer.isRecordingCircleVisible)
        XCTAssertFalse(touchView.isHidden)
        scheduler.advance(by: 1)
        controller.finish()

        // No speech: the circle stays up for its failure animation while the microphone is ready again
        XCTAssertEqual(controller.state.phase, .failed)
        XCTAssertTrue(composer.isRecordingCircleVisible)
        XCTAssertFalse(touchView.isHidden)
        XCTAssertFalse(microphone.isHidden)
        XCTAssertTrue(gesture.isEnabled)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_start"))
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
        XCTAssertTrue(strip.isHidden)

        scheduler.advance(by: AgentDictationController.failureDuration)
        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertFalse(composer.isRecordingCircleVisible)
        XCTAssertEqual(circleVisibilityChanges, [true, false])
    }

    @MainActor
    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    /// UIAgentTests run without a host app, so UIApplication cannot dispatch a control's target actions
    @MainActor
    private func dispatch(_ event: UIControl.Event, from control: UIControl) {
        for target in control.allTargets {
            for action in control.actions(forTarget: target, forControlEvent: event) ?? [] {
                (target as? NSObject)?.perform(NSSelectorFromString(action), with: control)
            }
        }
    }
}

@MainActor
private final class DictationTestGestureRecognizer: UILongPressGestureRecognizer {
    var simulatedState: UIGestureRecognizer.State = .possible
    var pointInWindow = CGPoint.zero

    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint {
        view?.convert(pointInWindow, from: nil) ?? pointInWindow
    }
}
