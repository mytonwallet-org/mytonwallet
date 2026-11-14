import XCTest
import UIKit
@testable import UIAgent
import UIComponents
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
        // The microphone stands beside the empty field; with text the send button is inside the field
        XCTAssertFalse(send.superview === microphone.superview)
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
        XCTAssertTrue(microphone.isHidden)
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
        // A hands-free recording's Cancel is a cross floating above the field
        XCTAssertFalse(composer.cancelBubble.view.isHidden)
        XCTAssertEqual(composer.cancelBubble.button.accessibilityLabel, lang("Cancel"))
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
        XCTAssertTrue(microphone.isHidden)
        XCTAssertFalse(send.isHidden)
    }

    @MainActor
    func testTrailingCircleStandsApartFromTheFieldAndBecomesSendWhileTyping() throws {
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
        let trailingEdge = composer.bounds.width - AgentComposerMetrics.threadHorizontalInset
        let microphoneFrame = microphone.convert(microphone.bounds, to: composer)
        let field = composer.inputBackgroundFrame
        XCTAssertEqual(microphoneFrame.width, AgentComposerMetrics.microphoneSize, accuracy: 0.5)
        XCTAssertEqual(microphoneFrame.height, AgentComposerMetrics.microphoneSize, accuracy: 0.5)
        XCTAssertEqual(microphoneFrame.maxX, trailingEdge, accuracy: 0.5)
        XCTAssertEqual(microphoneFrame.minX - field.maxX, AgentComposerMetrics.microphoneSpacing, accuracy: 0.5)
        XCTAssertEqual(microphoneFrame.maxY, field.maxY, accuracy: 0.5)
        XCTAssertEqual(field.minX, AgentComposerMetrics.threadHorizontalInset, accuracy: 0.5)

        composer.setDraftText("Hello", focus: false)
        window.layoutIfNeeded()
        let send = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == lang("Send")
        })
        XCTAssertTrue(microphone.isHidden)
        XCTAssertFalse(send.isHidden)
        // The field takes the microphone's place, and the send button sits inside its trailing end
        let filledField = composer.inputBackgroundFrame
        XCTAssertEqual(filledField.minX, AgentComposerMetrics.threadHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(filledField.maxX, trailingEdge, accuracy: 0.5)
        let sendFrame = send.convert(send.bounds, to: composer)
        XCTAssertEqual(sendFrame.maxX, filledField.maxX, accuracy: 0.5)
        XCTAssertEqual(sendFrame.maxY, filledField.maxY, accuracy: 0.5)
        XCTAssertTrue(filledField.contains(sendFrame))
    }

    /// A swipe up's transcript lands in the field with Send, and a microphone floats above the field: it takes its
    /// touches there, outside the composer, and records hands-free at touch-down, as a tap does even when held. The
    /// stop puts the next transcript after the first, and the microphone floats again. A cleared field sends it away.
    @MainActor
    func testTranscriptInTheFieldFloatsAMicrophoneThatDictatesMore() async throws {
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
        XCTAssertNil(findButton(labelled: lang("$agent_voice_resume"), in: composer))

        controller.touchBegan()
        for _ in 0..<100 where recordings == 0 { await Task.yield() }
        scheduler.advance(by: 1)
        controller.touchMoved(x: 0, y: -AgentDictationController.pauseDistance)
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertTrue(controller.state.canDictateMore)
        XCTAssertEqual(composer.draftText, "Раз, два")
        let send = try XCTUnwrap(findButton(labelled: lang("Send"), in: composer), "Send shows as for typed text")
        XCTAssertTrue(microphone.isHidden)

        window.layoutIfNeeded()
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        let center = resume.convert(CGPoint(x: resume.bounds.midX, y: resume.bounds.midY), to: composer)
        XCTAssertLessThan(center.y, composer.inputBackgroundFrame.minY, "The microphone floats above the field")
        XCTAssertEqual(
            resume.convert(resume.bounds, to: composer).maxY,
            composer.inputBackgroundFrame.minY - AgentVCLayout.scrollToBottomButtonSpacing,
            accuracy: 0.5,
            "Where the scroll-to-bottom button rests"
        )
        XCTAssertEqual(resume.bounds.width, AgentScrollToBottomButton.size)
        XCTAssertTrue(
            descendants(of: resume).compactMap { ($0 as? UIImageView)?.image }.contains { $0 === AgentComposerView.microphoneImage },
            "The composer's own microphone, not a filled one"
        )
        XCTAssertGreaterThan(center.x, send.convert(send.bounds, to: composer).minX, "Above the trailing circle's place")
        XCTAssertTrue(composer.hitTest(center, with: nil)?.isDescendant(of: resume) == true)

        // Tapped, it records hands-free; held, it would record while held
        let touchView = try XCTUnwrap(resume.superview)
        for state in [UIGestureRecognizer.State.began, .ended] {
            touchView.perform(
                NSSelectorFromString("handleFloatingPress:"),
                with: FloatingMicrophoneTestPress(state: state)
            )
        }
        XCTAssertEqual(controller.state.phase, .handsFree, "A tap records hands-free")
        XCTAssertFalse(controller.state.canDictateMore)
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        window.layoutIfNeeded()
        XCTAssertNil(findButton(labelled: lang("$agent_voice_resume"), in: composer), "The recording circle takes its place")
        let floating = try XCTUnwrap(touchView as? AgentDictationTouchView)
        XCTAssertTrue(floating.isShowingFloatingStop, "Its circle stays there as the stop")
        XCTAssertTrue(microphone.isHidden, "One microphone at a time")
        scheduler.advance(by: 1)
        touchView.perform(NSSelectorFromString("handleFloatingStopTap"))
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertEqual(composer.draftText, "Раз, два три", "The next transcript goes after the first, a space apart")
        XCTAssertTrue(controller.state.canDictateMore)
        window.layoutIfNeeded()
        XCTAssertNotNil(findButton(labelled: lang("$agent_voice_resume"), in: composer), "After a tap's stop as well")

        composer.clearDraft()
        XCTAssertFalse(controller.state.canDictateMore, "A cleared field sends the floating microphone away")
        window.layoutIfNeeded()
        XCTAssertNil(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        XCTAssertNil(composer.hitTest(center, with: nil), "Touches there go to the chat again")
    }

    /// Releasing a held microphone sends its transcript as the question at once, as in the Claude app; one that can't be
    /// sent yet stays in the field, with the floating microphone to dictate more
    @MainActor
    func testReleasingAHeldMicrophoneSendsTheTranscript() async throws {
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
            controller.touchEnded()
            for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        }
        XCTAssertEqual(sent, ["Раз, два"], "The held recording went as the question, without a stop in the field")
        XCTAssertEqual(composer.draftText, "Раз, два", "The second couldn't be sent and stays in the field")
        XCTAssertTrue(controller.state.canDictateMore)
    }

    /// A held recording released while an answer is written still sends its transcript as the question, which the chat
    /// keeps waiting for the answer, as it accepts questions then; it doesn't stay in the field
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
        controller.touchEnded()
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertEqual(sent, ["Раз, два"], "Sent, for the chat to keep waiting")
        XCTAssertEqual(composer.draftText ?? "", "")
    }

    /// The pause hint rises only for a hold, once the touch is one, out from behind the recording circle as Telegram's
    /// lock panel does; a tap never shows it
    @MainActor
    func testPauseHintRisesOnlyForAHold() async throws {
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
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        let hint = try XCTUnwrap(descendants(of: touchView).compactMap { $0 as? AgentVoicePauseHintView }.first)
        XCTAssertEqual(hint.alpha, 0)

        controller.touchBegan()
        for _ in 0..<100 where controller.state.phase != .holding { await Task.yield() }
        XCTAssertFalse(controller.state.isHeld, "Before the touch is a tap or a hold")
        XCTAssertEqual(hint.alpha, 0, "Nothing yet")
        controller.touchEnded()
        for _ in 0..<100 where controller.state.phase != .handsFree { await Task.yield() }
        XCTAssertEqual(controller.state.phase, .handsFree, "A tap")
        XCTAssertEqual(hint.alpha, 0, "A tap has no pause hint")
        XCTAssertFalse(touchView.isPauseHintNudging, "Nor its arrow's nudge")

        controller.cancel()
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        controller.touchBegan()
        for _ in 0..<100 where controller.state.phase != .holding { await Task.yield() }
        XCTAssertEqual(hint.alpha, 0)
        scheduler.advance(by: AgentDictationController.tapDuration)
        XCTAssertTrue(controller.state.isHeld, "A hold")
        XCTAssertEqual(hint.alpha, 1, "The hint comes in")
        XCTAssertFalse(hint.layer.animationKeys()?.isEmpty ?? true, "It rises, or fades in with Reduce Motion")
        // Its arrow's nudge starts with the hold and begins to play once the hint has settled
        XCTAssertTrue(touchView.isPauseHintNudging, "The arrow nudges for a hold")
    }

    /// Recording starts at the touch, but none of its look but the pause hint shows until the touch is a tap or a hold,
    /// 0.2 s on, so nothing plays and then reverses. A tap then brings the hands-free look: the dot in from the field's
    /// leading end beside the placeholder, the circle as Stop, the cross and the haptic. A hold brings "Slide to cancel"
    /// with the dot from the trailing end in the placeholder's place, the circle and the haptic.
    @MainActor
    func testRecordingLookWaitsForTheTouchToBeATapOrAHold() async throws {
        XCTAssertEqual(AgentDictationController.tapDuration, 0.2)
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
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
        let cancelHint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
        let dot = try XCTUnwrap(strip.subviews.first { $0.backgroundColor == AgentVoiceRecordingMetrics.recordingDotColor })
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)

        func beginTouch() async {
            let starts = recordingStarts
            controller.touchBegan()
            for _ in 0..<100 where recordingStarts == starts { await Task.yield() }
            for _ in 0..<20 { await Task.yield() }
            window.layoutIfNeeded()
            XCTAssertEqual(controller.state.phase, .holding, "Recording from the touch")
            XCTAssertFalse(controller.state.isHeld)
            XCTAssertTrue(strip.isHidden || dot.isHidden && cancelHint.isHidden, "No dot or hint yet")
            XCTAssertNotNil(composer.placeholderFrame, "The placeholder stays")
            XCTAssertEqual(touchView.recordingCircleAlpha, 0, "No circle yet")
            XCTAssertTrue(composer.cancelBubble.view.isHidden, "No cross yet")
        }

        await beginTouch()
        XCTAssertEqual(haptics, 0, "No haptic yet")
        controller.touchEnded()
        window.layoutIfNeeded()
        XCTAssertEqual(controller.state.phase, .handsFree, "A tap")
        XCTAssertEqual(haptics, 1)
        XCTAssertFalse(dot.isHidden)
        XCTAssertTrue(cancelHint.isHidden, "A tap has no hint")
        XCTAssertNotNil(composer.placeholderFrame, "Beside the placeholder")
        XCTAssertFalse(composer.cancelBubble.view.isHidden)
        XCTAssertGreaterThan(touchView.recordingCircleAlpha, 0, "The circle as Stop")
        if !isMotionReduced {
            let slide = try XCTUnwrap(dot.layer.animation(forKey: "slideIn") as? CABasicAnimation)
            let start = dot.layer.position.x + CGFloat((slide.fromValue as? NSNumber)?.doubleValue ?? 0)
            XCTAssertLessThan(start, 0, "From past the field's leading end")
        }

        controller.cancel()
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        // The cross merges back into the field
        for _ in 0..<90 where !composer.cancelBubble.view.isHidden { try await Task.sleep(for: .milliseconds(16)) }
        await beginTouch()
        XCTAssertEqual(haptics, 1)
        scheduler.advance(by: AgentDictationController.tapDuration)
        window.layoutIfNeeded()
        XCTAssertTrue(controller.state.isHeld, "A hold")
        XCTAssertEqual(haptics, 2)
        XCTAssertFalse(dot.isHidden)
        XCTAssertFalse(cancelHint.isHidden)
        XCTAssertNil(composer.placeholderFrame, "In the placeholder's place")
        XCTAssertGreaterThan(touchView.recordingCircleAlpha, 0)
        if !isMotionReduced {
            let slide = try XCTUnwrap(dot.layer.animation(forKey: "slideIn") as? CABasicAnimation)
            XCTAssertGreaterThan((slide.fromValue as? NSNumber)?.doubleValue ?? 0, 0, "From the trailing end")
        }
    }

    /// The hands-free cross is clear Liquid Glass, untinted, with the header's glass buttons' size and glyph, in the
    /// field's glass container. Its glass takes the touches, so it stretches toward the finger, and so does the floating
    /// microphone's, which VoiceOver still activates.
    @MainActor
    func testCancelCrossAndFloatingMicrophoneAreClearGlassThatTakesTheTouches() throws {
        guard #available(iOS 26, *), IOS_26_MODE_ENABLED else { throw XCTSkip("Liquid Glass") }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        UIView.performWithoutAnimation { composer.setCancelBubbleShown(true) }
        window.layoutIfNeeded()
        let bubble = composer.cancelBubble
        let glass = try XCTUnwrap(bubble.glassView)
        XCTAssertTrue(bubble.view === glass)
        XCTAssertFalse(glass.isHidden)
        let container = try XCTUnwrap(glass.superview?.superview as? UIVisualEffectView)
        XCTAssertTrue(container.effect is UIGlassContainerEffect, "In the field's glass container")
        let effect = try XCTUnwrap(glass.effect as? UIGlassEffect)
        XCTAssertNil(effect.tintColor, "Clear glass, without a tint")
        XCTAssertTrue(effect.isInteractive)
        XCTAssertEqual(glass.bounds.width, WGlassButtonMetrics.size, accuracy: 0.5)
        XCTAssertEqual(bubble.button.configuration?.baseForegroundColor, .label, "The header buttons' glyph colour")
        let center = glass.convert(CGPoint(x: glass.bounds.midX, y: glass.bounds.midY), to: composer)
        let hit = try XCTUnwrap(composer.hitTest(center, with: nil))
        XCTAssertTrue(hit === bubble.button)
        XCTAssertTrue(hit.isDescendant(of: glass), "The glass sees the touch")

        let microphone = AgentVoiceResumeButton()
        microphone.frame = CGRect(x: 0, y: 0, width: AgentVoiceResumeButton.diameter, height: AgentVoiceResumeButton.diameter)
        microphone.layoutIfNeeded()
        let microphoneGlass = try XCTUnwrap(descendants(of: microphone).compactMap { $0 as? WGlassView }.first)
        let microphoneHit = try XCTUnwrap(microphone.hitTest(CGPoint(x: microphone.bounds.midX, y: microphone.bounds.midY), with: nil))
        XCTAssertTrue(microphoneHit.isDescendant(of: microphoneGlass), "The floating microphone's glass sees the touch")
        var activations = 0
        microphone.addAction(UIAction { _ in activations += 1 }, for: .touchUpInside)
        XCTAssertTrue(microphone.accessibilityActivate())
        XCTAssertEqual(activations, 1)
    }

    /// The cross splits off the field's glass: it starts in the field's leading end and rises above the field. With
    /// Reduce Motion it fades in and out where it rests instead.
    @MainActor
    func testCancelCrossSplitsOffTheFieldOrFadesInPlaceWithReduceMotion() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let view = composer.cancelBubble.view
        let button = composer.cancelBubble.button
        func isMoving() -> Bool {
            view.layer.animationKeys()?.contains { $0.hasPrefix("position") } ?? false
        }
        func isFading() -> Bool {
            button.layer.animationKeys()?.contains { $0.hasPrefix("opacity") } ?? false
        }

        composer.setCancelBubbleShown(true, isReduceMotionEnabled: true)
        let field = composer.inputBackgroundFrame
        let rest = view.convert(view.bounds, to: composer)
        XCTAssertEqual(rest.maxY, field.minY - AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5, "Above the field")
        XCTAssertFalse(isMoving(), "It doesn't move")
        XCTAssertTrue(isFading(), "It fades in")
        XCTAssertEqual(button.alpha, 1)
        view.layer.removeAllAnimations()
        button.layer.removeAllAnimations()

        composer.setCancelBubbleShown(false, isReduceMotionEnabled: true)
        XCTAssertFalse(isMoving(), "It doesn't move")
        XCTAssertTrue(isFading(), "It fades out")
        XCTAssertEqual(button.alpha, 0)
        XCTAssertEqual(view.convert(view.bounds, to: composer), rest, "Where it rests")
        view.layer.removeAllAnimations()
        button.layer.removeAllAnimations()

        guard #available(iOS 26, *), IOS_26_MODE_ENABLED, !UIAccessibility.isReduceMotionEnabled else { return }
        composer.setCancelBubbleShown(true, isReduceMotionEnabled: false)
        XCTAssertTrue(isMoving(), "It rises out of the field")
        let key = try XCTUnwrap(view.layer.animationKeys()?.first { $0.hasPrefix("position") })
        let start = try XCTUnwrap(view.layer.animation(forKey: key) as? CABasicAnimation)
        let offset = try XCTUnwrap((start.fromValue as? NSValue)?.cgPointValue)
        // Additive: from the field's leading end, below and toward the leading edge of where it rests
        XCTAssertGreaterThan(offset.y, rest.height, "From inside the field")
        XCTAssertEqual(view.convert(view.bounds, to: composer), rest, "Toward its place above the field")
    }

    /// While the microphone is held, the pause hint's arrow nudges up, showing that the microphone goes up to pause,
    /// until the finger starts moving up and the hint's rise takes over, and with the hold
    @MainActor
    func testPauseHintsArrowNudgesUpWhileHeldUntilTheFingerMovesUp() async throws {
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
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        let hint = try XCTUnwrap(descendants(of: touchView).compactMap { $0 as? AgentVoicePauseHintView }.first)

        for isMovingUp in [true, false] {
            controller.touchBegan()
            for _ in 0..<100 where controller.state.phase != .holding || recordings == 0 { await Task.yield() }
            XCTAssertFalse(touchView.isPauseHintNudging, "Not before the touch is a hold")
            scheduler.advance(by: AgentDictationController.tapDuration)
            XCTAssertTrue(controller.state.isHeld)
            XCTAssertTrue(touchView.isPauseHintNudging, "Held, the arrow nudges up")
            if !UIAccessibility.isReduceMotionEnabled {
                let arrow = try XCTUnwrap(hint.subviews.compactMap { $0 as? UIImageView }.first)
                XCTAssertNotNil(arrow.layer.animation(forKey: AgentVoicePauseHintView.nudgeKey))
            }
            if isMovingUp {
                controller.touchMoved(x: 0, y: -20)
                XCTAssertFalse(touchView.isPauseHintNudging, "The finger moving up takes over")
                controller.cancel()
            } else {
                controller.cancel()
                XCTAssertFalse(touchView.isPauseHintNudging, "It stops with the recording")
            }
            for _ in 0..<20 { await Task.yield() }
        }
    }

    /// The Agent list's field holds a question, which keeps the search circle away, while it records or recognizes,
    /// offers to dictate more, or has text. A recording that turns into its transcript reports no moment without one
    /// between.
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
        XCTAssertFalse(controller.state.canDictateMore)
        XCTAssertFalse(bar.hasQuestion, "Once sent or cleared")
        XCTAssertEqual(reports, [true, false])

        bar.composerView.setDraftText("Typed", focus: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(bar.hasQuestion, "With typed text")
        XCTAssertEqual(reports, [true, false, true])
    }

    /// In a chat, a touch on the floating microphone over a dictated question reaches it through the window, and
    /// records on
    @MainActor
    func testChatFloatingMicrophoneTakesTapsThroughTheWindow() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        let dictation = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .transcribed, text: "Раз, два, три") },
            haptic: { recordings += 1 },
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { dictation.cancel() }
        let controller = AgentVC(model: AgentModel(backend: AgentTestChat.Backend()), dictationController: dictation)
        let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        dictation.startHandsFree()
        for _ in 0..<100 where recordings == 0 { await Task.yield() }
        scheduler.advance(by: 1)
        dictation.finish()
        for _ in 0..<100 where dictation.state.phase != .idle { await Task.yield() }
        XCTAssertTrue(dictation.state.canDictateMore)
        window.layoutIfNeeded()
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: controller.view))
        // The scroll-to-bottom button stands above the floating microphone, as far apart as each is from the field
        controller.view.layoutIfNeeded()
        let down = controller.scrollToBottomButton.convert(controller.scrollToBottomButton.bounds, to: window)
        let microphone = resume.convert(resume.bounds, to: window)
        XCTAssertEqual(down.maxY, microphone.minY - AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5)
        XCTAssertEqual(down.midX, microphone.midX, accuracy: 0.5)
        XCTAssertEqual(down.size, microphone.size)
        let frame = resume.convert(resume.bounds, to: window)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        // The microphone takes the tap, on its glass where it has Liquid Glass
        for point in [center, CGPoint(x: frame.midX, y: frame.maxY - 2), CGPoint(x: frame.maxX - 2, y: frame.midY)] {
            XCTAssertTrue(window.hitTest(point, with: nil)?.isDescendant(of: resume) == true, "A tap at \(point)")
        }

        let touchView = try XCTUnwrap(resume.superview)
        for state in [UIGestureRecognizer.State.began, .ended] {
            touchView.perform(
                NSSelectorFromString("handleFloatingPress:"),
                with: FloatingMicrophoneTestPress(state: state)
            )
        }
        XCTAssertEqual(dictation.state.phase, .handsFree, "A tap records hands-free")
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        XCTAssertEqual(recordings, 2)
    }

    /// A transcript's characters come 6 ms apart, closer for a long one so the last starts within 0.8 s, and each
    /// sharpens out of its blur in 0.15 s
    @MainActor
    func testTranscriptCharactersComeFastAndWithinTheCap() {
        XCTAssertEqual(AgentDictationTextReveal.getCharacterStep(characterCount: 1), 0.006, accuracy: 0.00001)
        XCTAssertEqual(AgentDictationTextReveal.getCharacterStep(characterCount: 100), 0.006, accuracy: 0.00001)
        XCTAssertEqual(AgentDictationTextReveal.getCharacterStep(characterCount: 201), 0.004, accuracy: 0.00001)
        XCTAssertEqual(AgentDictationTextReveal.getCharacterStep(characterCount: 1000) * 999, 0.8, accuracy: 0.00001)
        XCTAssertEqual(AgentDictationTextReveal.sharpenDuration, 0.15)
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

    /// Once the finger holds the microphone, a hint above the circle, where Telegram's lock sits, shows that a swipe up
    /// keeps the question in the field: it fades a little toward that point. A touch not yet a hold and a hands-free
    /// recording show none.
    @MainActor
    func testPauseHintShowsOnceTheFingerHoldsTheMicrophone() throws {
        let distance = CGFloat(AgentDictationController.pauseDistance)
        XCTAssertEqual(distance, 110)
        XCTAssertEqual(AgentVoiceRecordingMetrics.getPauseProgress(dragY: 0), 0)
        XCTAssertEqual(AgentVoiceRecordingMetrics.getPauseProgress(dragY: 12), 0, "A finger below where it started")
        XCTAssertEqual(AgentVoiceRecordingMetrics.getPauseProgress(dragY: -distance / 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AgentVoiceRecordingMetrics.getPauseProgress(dragY: -distance - 40), 1, "Past the pause point")

        struct HintCase {
            let phase: AgentDictationState.Phase
            let isHeld: Bool
            let alpha: CGFloat
        }
        let cases = [
            HintCase(phase: .holding, isHeld: false, alpha: 0),
            HintCase(phase: .holding, isHeld: true, alpha: 1),
            HintCase(phase: .handsFree, isHeld: false, alpha: 0),
        ]
        for hintCase in cases {
            let touchView = AgentDictationTouchView()
            touchView.setAnchor(CGPoint(x: 300, y: 800), fieldTop: 776)
            let hint = try XCTUnwrap(descendants(of: touchView).compactMap { $0 as? AgentVoicePauseHintView }.first)
            var state = AgentDictationState()
            state.phase = hintCase.phase
            touchView.update(state, isRightToLeft: false)
            state.isHeld = hintCase.isHeld
            touchView.update(state, isRightToLeft: false)
            touchView.layoutIfNeeded()
            XCTAssertFalse(touchView.isHidden)
            XCTAssertEqual(hint.alpha, hintCase.alpha, "The hint while \(hintCase.phase), held: \(hintCase.isHeld)")
            XCTAssertLessThan(
                hint.frame.maxY,
                touchView.bounds.midY - AgentVoiceRecordingMetrics.circleDiameter / 2,
                "Above the recording circle"
            )
        }
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
        touchView.setAnchor(CGPoint(x: 340, y: 800), fieldTop: 776)
        touchView.update(AgentDictationState(phase: .handsFree), isRightToLeft: false)
        let glyph = try XCTUnwrap(
            descendants(of: touchView).compactMap { $0 as? UIImageView }.first { $0.superview is AgentVoiceBlobView }
        )
        XCTAssertEqual(glyph.tintColor.resolvedColor(with: touchView.traitCollection), .black, "On the white circle")

        // The failure plays only in motion
        UIView.setAnimationsEnabled(true)
        touchView.update(AgentDictationState(phase: .failed), isRightToLeft: false)
        XCTAssertNotNil(touchView.failureCenter, "The failure shows")
        XCTAssertEqual(glyph.tintColor.resolvedColor(with: touchView.traitCollection), .white, "On the red circle")
    }

    /// The floating microphone comes up out of the trailing circle as a stop's transcript is recognized, and out of
    /// the pause hint after a swipe up, settling at the same place above the field; it waits for the transcript, and
    /// sinks back into the trailing circle once the field is sent or cleared
    @MainActor
    func testFloatingMicrophoneRisesOutOfTheFieldOrThePauseHint() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades it in place")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        var restFrames: [CGRect] = []
        for isPausedBySwipe in [false, true] {
            let touchView = AgentDictationTouchView()
            window.addSubview(touchView)
            touchView.setAnchor(CGPoint(x: 340, y: 800), fieldTop: 776)
            touchView.layoutIfNeeded()
            var recording = AgentDictationState(phase: isPausedBySwipe ? .holding : .handsFree)
            touchView.update(recording, isRightToLeft: false)
            if isPausedBySwipe {
                recording.isHeld = true
                touchView.update(recording, isRightToLeft: false)
            }
            touchView.layoutIfNeeded()
            let hint = try XCTUnwrap(descendants(of: touchView).compactMap { $0 as? AgentVoicePauseHintView }.first)
            let start = isPausedBySwipe ? hint.center : CGPoint(x: touchView.bounds.midX, y: touchView.bounds.midY)

            var recognizing = AgentDictationState(phase: .recognizing)
            recognizing.canDictateMore = true
            touchView.update(recognizing, isRightToLeft: false)
            let resume = try XCTUnwrap(descendants(of: touchView).compactMap { $0 as? AgentVoiceResumeButton }.first)
            XCTAssertFalse(resume.isHidden, "It comes as recognition starts")
            XCTAssertFalse(resume.isEnabled, "It waits for the transcript")
            let rest = resume.frame
            let fieldTop = 776 - 800 + touchView.bounds.midY
            XCTAssertEqual(rest.width, AgentScrollToBottomButton.size, "As large as the scroll-to-bottom button")
            XCTAssertEqual(rest.maxY, fieldTop - AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5, "As far above the field")
            XCTAssertEqual(rest.midX, touchView.bounds.midX, accuracy: 0.5, "Over the trailing circle")
            restFrames.append(rest)
            try await Task.sleep(for: .milliseconds(40))
            let shownY = try XCTUnwrap(resume.layer.presentation()).position.y
            if isPausedBySwipe {
                XCTAssertLessThan(start.y, rest.midY)
                XCTAssertLessThan(shownY, rest.midY - 1, "Coming down from the pause hint")
            } else {
                XCTAssertGreaterThan(shownY, rest.midY + 1, "Coming up out of the trailing circle")
            }

            var transcribed = AgentDictationState()
            transcribed.canDictateMore = true
            touchView.update(transcribed, isRightToLeft: false)
            XCTAssertTrue(resume.isEnabled)
            touchView.update(AgentDictationState(), isRightToLeft: false)
            XCTAssertFalse(resume.isHidden, "It sinks back first")
            for _ in 0..<100 where !resume.isHidden { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(resume.isHidden)
            XCTAssertTrue(touchView.isHidden)
            touchView.removeFromSuperview()
        }
        XCTAssertEqual(restFrames.first, restFrames.last, "Both ways end at one place")
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

    /// Recording hands-free from an empty field keeps its placeholder in sight, moved toward the middle, where "Slide to
    /// cancel" stands for a held recording, past the dot at the leading end, and back as the recording ends. No caret
    /// blinks in the field meanwhile. The cancelling cross is a glass circle of its own above the field's leading end,
    /// opposite where the floating microphone rests, which cancels when tapped and goes as the recording ends.
    @MainActor
    func testTapModeCentresThePlaceholderAndFloatsTheCrossAboveTheField() async throws {
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
        let idle = try XCTUnwrap(composer.placeholderFrame)
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
        func findCross() -> UIView? {
            composer.cancelBubble.view.isHidden ? nil : composer.cancelBubble.view
        }
        XCTAssertNil(findCross())

        controller.startHandsFree()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        window.layoutIfNeeded()
        let field = composer.inputBackgroundFrame
        let recording = try XCTUnwrap(composer.placeholderFrame, "The placeholder stays in sight")
        XCTAssertLessThan(abs(recording.midX - field.midX), abs(idle.midX - field.midX), "Toward the middle")
        XCTAssertGreaterThan(recording.minX - idle.minX, AgentDictationStripView.contentStart - 0.5, "Past the dot")
        XCTAssertEqual(recording.minY, idle.minY, accuracy: 0.5)
        XCTAssertEqual(textView.tintColor, .clear, "No caret while recording")

        let cross = try XCTUnwrap(findCross(), "The cross floats above the field")
        let crossFrame = cross.convert(cross.bounds, to: composer)
        XCTAssertFalse(crossFrame.intersects(field), "Outside the field")
        XCTAssertEqual(crossFrame.maxY, field.minY - AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5)
        XCTAssertLessThan(crossFrame.midX, field.midX, "At the leading end")
        XCTAssertEqual(crossFrame.width, WGlassButtonMetrics.size, accuracy: 0.5, "As large as the header's glass buttons")
        XCTAssertTrue(composer.hitTest(CGPoint(x: crossFrame.midX, y: crossFrame.midY), with: nil) === composer.cancelBubble.button)

        scheduler.advance(by: 1)
        controller.finish()
        for _ in 0..<200 where controller.state.phase != .idle { await Task.yield() }
        window.layoutIfNeeded()
        XCTAssertEqual(composer.recordingTextInset, 0, "Back as the recording ends")
        XCTAssertEqual(composer.textLeadingInset, AgentComposerMetrics.contentHorizontalInset)
        XCTAssertNotEqual(textView.tintColor, .clear, "The caret is back")
        XCTAssertNil(findCross(), "The cross goes with the recording")

        // The cross cancels
        composer.clearDraft()
        controller.startHandsFree()
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        window.layoutIfNeeded()
        XCTAssertNotNil(findCross())
        dispatch(.touchUpInside, from: composer.cancelBubble.button)
        XCTAssertEqual(controller.state.phase, .idle, "Cancelled")
        XCTAssertEqual(composer.draftText ?? "", "")
    }

    /// A hands-free recording's dot comes in from past the field's leading end, where it stands, never crossing the
    /// placeholder; a held one's comes in with "Slide to cancel" from the trailing end
    @MainActor
    func testTapModesDotComesInFromTheLeadingEnd() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "With Reduce Motion the dot fades in")
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
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)

        controller.startHandsFree()
        for _ in 0..<100 where recordings < 1 { await Task.yield() }
        let dot = try XCTUnwrap(strip.subviews.first { $0.backgroundColor == AgentVoiceRecordingMetrics.recordingDotColor })
        let slide = try XCTUnwrap(dot.layer.animation(forKey: "slideIn") as? CABasicAnimation, "The dot comes in")
        let start = dot.layer.position.x + CGFloat((slide.fromValue as? NSNumber)?.doubleValue ?? 0)
        XCTAssertLessThan(start, 0, "From past the leading end")
        XCTAssertLessThanOrEqual(dot.frame.maxX, AgentDictationStripView.contentStart, "Standing at the leading end")
    }

    /// A held recording cancelled by a slide toward the leading end brings the placeholder back the way "Slide to
    /// cancel" took its place, sliding in as it fades in, rather than in one frame
    @MainActor
    func testPlaceholderComesBackInMotionAfterASlideToCancel() async throws {
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
        XCTAssertTrue(placeholder.isHidden, "\"Slide to cancel\" takes its place")
        controller.cancel()
        XCTAssertFalse(placeholder.isHidden)
        XCTAssertFalse(placeholder.layer.animationKeys()?.isEmpty ?? true, "It comes back in motion")
    }

    /// Dictating more into a field with text leaves the field as it is: its text stays in sight, unchanged, as tall as
    /// it is and where it is, without the dot or the cross before it while the floating microphone records, held or
    /// hands-free, and without the recognition's status while the transcript is recognized, when the field glows
    @MainActor
    func testFurtherDictationLeavesTheFieldsTextAsItIs() async throws {
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
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        let touchView = try XCTUnwrap(resume.superview as? AgentDictationTouchView)
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
        let rim = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentFieldGlowView }.first { $0.part == .rim })
        func press(_ state: UIGestureRecognizer.State) {
            touchView.perform(NSSelectorFromString("handleFloatingPress:"), with: FloatingMicrophoneTestPress(state: state))
        }
        let padding = AgentComposerMetrics.contentHorizontalInset
        func assertFieldAsItIs(_ text: String?, height: CGFloat, _ moment: String) {
            window.layoutIfNeeded()
            XCTAssertTrue(composer.isDraftTextShown, "\(moment): the text stays in sight")
            XCTAssertEqual(composer.draftText, text, "\(moment): unchanged")
            XCTAssertEqual(composer.inputHeight, height, "\(moment): as tall as it is")
            XCTAssertEqual(composer.textLeadingInset, padding, "\(moment): where it is")
            XCTAssertEqual(composer.recordingTextInset, 0, "\(moment): no room made for a dot or a cross")
            XCTAssertTrue(strip.isHidden, "\(moment): no dot, cross or status before it")
        }

        // Held: the floating microphone records, the field as it is
        let text = composer.draftText
        let height = composer.inputHeight
        press(.began)
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        assertFieldAsItIs(text, height: height, "Touched")
        scheduler.advance(by: AgentDictationController.tapDuration)
        XCTAssertTrue(controller.state.isHeld)
        assertFieldAsItIs(text, height: height, "Held")
        XCTAssertEqual(touchView.recordingCircleAlpha, 1, "The floating microphone shows the recording")
        XCTAssertNotNil(touchView.floatingRecordingCenter)
        scheduler.advance(by: 1)
        press(.ended)
        XCTAssertEqual(controller.state.phase, .recognizing)
        assertFieldAsItIs(text, height: height, "Recognizing")
        XCTAssertTrue(rim.isGlowing, "The field glows as it is recognized")
        await waitUntilIdle()
        XCTAssertEqual(composer.draftText, "Раз, два три", "The transcript goes after it")
        XCTAssertEqual(composer.textLeadingInset, padding)

        // Tapped: the floating microphone is the stop, the field as it is
        let longerText = composer.draftText
        let longerHeight = composer.inputHeight
        press(.began)
        press(.ended)
        XCTAssertEqual(controller.state.phase, .handsFree)
        for _ in 0..<100 where recordings < 3 { await Task.yield() }
        assertFieldAsItIs(longerText, height: longerHeight, "Hands-free")
        XCTAssertTrue(touchView.isShowingFloatingStop, "The floating microphone shows the recording as its stop")
        scheduler.advance(by: 1)
        touchView.perform(NSSelectorFromString("handleFloatingStopTap"))
        XCTAssertEqual(controller.state.phase, .recognizing)
        assertFieldAsItIs(longerText, height: longerHeight, "Recognizing after the stop")
        XCTAssertTrue(rim.isGlowing)
        await waitUntilIdle()
        XCTAssertEqual(composer.draftText, "Раз, два три четыре")
        XCTAssertEqual(composer.textLeadingInset, padding)
    }

    /// A further dictation from the floating microphone that hears nothing plays its failure on the floating microphone,
    /// where it rests, which stays there rather than going down into the trailing circle, and leaves the field's text
    /// as it was and the microphone at rest there, in its idle glass: nothing records again, and no recording circle
    /// stays over the trailing circle
    @MainActor
    func testFloatingDictationThatHearsNothingLeavesTheMicrophoneIdleAndTheFieldAsItWas() async throws {
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
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        let touchView = try XCTUnwrap(resume.superview as? AgentDictationTouchView)
        let resting = resume.center
        let restingFrame = resume.frame

        // Held, it records more, which comes back with no speech
        func press(_ state: UIGestureRecognizer.State) {
            touchView.perform(NSSelectorFromString("handleFloatingPress:"), with: FloatingMicrophoneTestPress(state: state))
        }
        press(.began)
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        scheduler.advance(by: AgentDictationController.tapDuration)
        scheduler.advance(by: 1)
        // The failure plays only in motion
        UIView.setAnimationsEnabled(true)
        press(.ended)
        for _ in 0..<200 where controller.state.phase != .failed { await Task.yield() }
        guard case .noSpeech? = controller.state.failure else {
            return XCTFail("Nothing was heard: \(String(describing: controller.state.failure))")
        }
        XCTAssertEqual(composer.draftText, "Раз, два", "The field keeps its text")
        window.layoutIfNeeded()
        XCTAssertFalse(resume.isHidden, "The floating microphone stays")
        XCTAssertEqual(resume.frame, restingFrame, "Where it rests, not down in the trailing circle")
        let failure = try XCTUnwrap(touchView.failureCenter, "The failure shows")
        XCTAssertEqual(failure.x, resting.x, accuracy: 0.5, "On the floating microphone")
        XCTAssertEqual(failure.y, resting.y, accuracy: 0.5)
        XCTAssertEqual(failures, 1, "Its haptic plays")

        scheduler.advance(by: AgentDictationController.failureDuration)
        window.layoutIfNeeded()
        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertTrue(controller.state.canDictateMore)
        XCTAssertEqual(composer.draftText, "Раз, два")
        XCTAssertFalse(resume.isHidden)
        XCTAssertTrue(resume.isEnabled, "At rest, ready for more")
        XCTAssertEqual(resume.center.x, resting.x, accuracy: 0.5, "Where it was")
        XCTAssertEqual(resume.center.y, resting.y, accuracy: 0.5)
        XCTAssertEqual(touchView.recordingCircleAlpha, 0, "No recording circle stays over the trailing circle")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(recordings, 2, "Nothing records again by itself")
    }

    /// The floating microphone stays where it rests. Held, it records into the field there, sending nothing, and held
    /// again it records again; tapped, it records hands-free there, its circle the stop, and stays for more. While it
    /// records, held or hands-free, the composer's trailing microphone doesn't come out beside it: the field stays over
    /// its place, as with the transcript in it.
    @MainActor
    func testFloatingMicrophoneDictatesIntoTheFieldWhereItRests() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let scheduler = AgentDictationTestScheduler()
        var recordings = 0
        var transcripts = ["Раз", "два", "три", "четыре"]
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
        var sends = 0
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        composer.onSend = { sends += 1 }
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
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        let touchView = try XCTUnwrap(resume.superview as? AgentDictationTouchView)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let resting = resume.center
        // With the transcript in it, the field has taken in the trailing circle, and shows Send at its end
        let mergedFieldWidth = composer.inputBackgroundFrame.width
        XCTAssertTrue(microphone.isHidden)
        func press(_ state: UIGestureRecognizer.State) {
            touchView.perform(NSSelectorFromString("handleFloatingPress:"), with: FloatingMicrophoneTestPress(state: state))
        }
        func assertOneMicrophone(_ message: String) {
            window.layoutIfNeeded()
            XCTAssertTrue(microphone.isHidden, "\(message): the trailing microphone doesn't come out beside the floating one")
            XCTAssertEqual(
                composer.inputBackgroundFrame.width, mergedFieldWidth, accuracy: 0.5,
                "\(message): the field stays over the trailing circle's place"
            )
        }
        func assertRecordingWhereItRests(_ message: String) throws {
            let center = try XCTUnwrap(touchView.floatingRecordingCenter, message)
            XCTAssertEqual(center.x, resting.x, accuracy: 0.5, "\(message): where the microphone rests")
            XCTAssertEqual(center.y, resting.y, accuracy: 0.5, "\(message): where the microphone rests")
        }
        func assertAtRest(_ message: String) throws {
            let microphone = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer), message)
            XCTAssertEqual(microphone.center.x, resting.x, accuracy: 0.5, "\(message): where it rests")
            XCTAssertEqual(microphone.center.y, resting.y, accuracy: 0.5, "\(message): where it rests")
        }

        // Held, it records into the field where it rests
        press(.began)
        XCTAssertEqual(controller.state.phase, .holding)
        XCTAssertTrue(controller.state.isFloating)
        try assertRecordingWhereItRests("Touched")
        assertOneMicrophone("Held")
        for _ in 0..<100 where recordings < 2 { await Task.yield() }
        scheduler.advance(by: AgentDictationController.tapDuration)
        XCTAssertTrue(controller.state.isHeld)
        try assertRecordingWhereItRests("Held")
        scheduler.advance(by: 1)
        press(.ended)
        await waitUntilIdle()
        XCTAssertEqual(composer.draftText, "Раз два", "The transcript goes after the field's text")
        XCTAssertEqual(sends, 0, "Nothing is sent")
        try assertAtRest("After the hold")

        // Held again, it records again
        press(.began)
        XCTAssertEqual(controller.state.phase, .holding)
        for _ in 0..<100 where recordings < 3 { await Task.yield() }
        scheduler.advance(by: AgentDictationController.tapDuration)
        try assertRecordingWhereItRests("Held again")
        scheduler.advance(by: 1)
        press(.ended)
        await waitUntilIdle()
        XCTAssertEqual(composer.draftText, "Раз два три")
        try assertAtRest("After the second hold")
        XCTAssertNotNil(findButton(labelled: lang("Send"), in: composer), "Send at the field's end again")
        XCTAssertEqual(composer.inputBackgroundFrame.width, mergedFieldWidth, accuracy: 0.5)

        // Tapped, it records hands-free where it rests, its circle the stop there
        press(.began)
        press(.ended)
        XCTAssertEqual(controller.state.phase, .handsFree, "A tap records hands-free")
        XCTAssertTrue(controller.state.isFloating)
        window.layoutIfNeeded()
        XCTAssertNil(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        XCTAssertTrue(touchView.isShowingFloatingStop, "The stop")
        try assertRecordingWhereItRests("Hands-free")
        let stop = try XCTUnwrap(touchView.floatingRecordingCenter)
        XCTAssertTrue(touchView.isTakingTouches)
        XCTAssertTrue(touchView.point(inside: stop, with: nil), "It takes the next tap")
        assertOneMicrophone("Hands-free")
        for _ in 0..<100 where recordings < 4 { await Task.yield() }
        scheduler.advance(by: 1)
        // The next tap stops it, and the transcript goes into the field
        touchView.perform(NSSelectorFromString("handleFloatingStopTap"))
        await waitUntilIdle()
        XCTAssertEqual(composer.draftText, "Раз два три четыре")
        try assertAtRest("After the stop")
        XCTAssertNotNil(findButton(labelled: lang("Send"), in: composer))
        XCTAssertEqual(composer.inputBackgroundFrame.width, mergedFieldWidth, accuracy: 0.5)
    }

    /// With text in the field, Send keeps its place through a dictation into the text from the floating microphone,
    /// held or tapped, heard or not: it stays in sight with the same frame, the text keeps its layout width, so it never
    /// reflows but for the transcript it takes, and no microphone comes out in the trailing circle, also while a
    /// failure plays on the floating microphone
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
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        let touchView = try XCTUnwrap(resume.superview as? AgentDictationTouchView)
        let send = try XCTUnwrap(findButton(labelled: lang("Send"), in: composer))
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
        let sendFrame = send.convert(send.bounds, to: composer)
        let textWidth = textView.textContainer.size.width
        func assertSendInPlace(_ moment: String) {
            window.layoutIfNeeded()
            XCTAssertFalse(send.isHidden, "\(moment): Send stays")
            XCTAssertEqual(send.alpha, 1, "\(moment): Send stays")
            XCTAssertEqual(send.convert(send.bounds, to: composer), sendFrame, "\(moment): where it was")
            XCTAssertEqual(textView.textContainer.size.width, textWidth, "\(moment): the text keeps its width")
            XCTAssertTrue(microphone.isHidden, "\(moment): no microphone in the trailing circle")
        }
        func press(_ state: UIGestureRecognizer.State) {
            touchView.perform(NSSelectorFromString("handleFloatingPress:"), with: FloatingMicrophoneTestPress(state: state))
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
        touchView.perform(NSSelectorFromString("handleFloatingStopTap"))
        assertSendInPlace("Recognizing after the stop")
        await waitUntil(.idle)
        assertSendInPlace("Heard after the stop")

        // Tapped, nothing heard
        press(.began)
        press(.ended)
        for _ in 0..<100 where recordings < 5 { await Task.yield() }
        scheduler.advance(by: 1)
        touchView.perform(NSSelectorFromString("handleFloatingStopTap"))
        await waitUntil(.failed)
        assertSendInPlace("Failing after a stop")
        scheduler.advance(by: AgentDictationController.failureDuration)
        await waitUntil(.idle)
        assertSendInPlace("At rest again")
        XCTAssertEqual(composer.draftText, "Раз, два три четыре")
    }

    /// As the field grows with its text, the floating microphone keeps its distance from the field's top, moving with
    /// the field in the same pass rather than after it in a motion of its own
    @MainActor
    func testFloatingMicrophoneKeepsItsDistanceFromTheGrowingField() async throws {
        // Set up at rest, then grown with animations on, as the app grows the field
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
        composer.setDraftText("Раз", focus: false)
        controller.offerDictatingMore()
        window.layoutIfNeeded()
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        UIView.setAnimationsEnabled(true)
        func gap() -> CGFloat {
            composer.inputBackgroundFrame.minY - resume.convert(resume.bounds, to: composer).maxY
        }
        let restingGap = gap()
        XCTAssertEqual(restingGap, AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5)

        // Line by line, as a transcript's reveal grows the field
        var text = "Раз"
        for line in 2...5 {
            text += "\nСтрока \(line)"
            composer.setDraftText(text, focus: false)
            window.layoutIfNeeded()
            XCTAssertEqual(gap(), restingGap, accuracy: 0.5, "Line \(line): the same distance")
            XCTAssertTrue(
                resume.layer.animationKeys()?.isEmpty ?? true,
                "Line \(line): the microphone has no motion of its own after the field's"
            )
        }
        XCTAssertGreaterThan(composer.inputHeight, AgentComposerMetrics.minInputHeight)
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

    /// The first character typed into a fresh composer brings Send into the circle and the small floating microphone
    /// above the field, and no recording circle at any moment, over the circle or anywhere, nor as the field empties.
    /// With an answer to stop, Send takes the circle too, as a question sent during the answer waits for it, and Stop
    /// comes back as the field empties.
    @MainActor
    func testFirstTypedCharacterShowsSendInTheCircleAndNoRecordingCircleOverIt() async throws {
        let controller = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        composer.setSendEnabled(true)
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        let slot = microphone.convert(microphone.bounds, to: composer)

        /// How much of `view` shows now, frame by frame: its opacity and its ancestors' as they show
        func shownOpacity(of view: UIView) -> Float {
            var opacity: Float = 1
            var current: UIView? = view
            while let layerView = current, layerView !== window {
                // Hiding and opacity both as last committed: the screen shows them together
                let shown = layerView.layer.presentation() ?? layerView.layer
                if shown.isHidden { return 0 }
                opacity *= shown.opacity
                current = layerView.superview
            }
            return opacity
        }
        /// The views of the recording's overlay that show over the trailing circle and are clearly larger than it, as the
        /// recording circle is
        func largerViewsOverTheSlot() -> [String] {
            touchView.subviews.compactMap { view in
                guard shownOpacity(of: view) > 0.05 else { return nil }
                let frame = (view.layer.presentation() ?? view.layer).frame
                let shown = touchView.convert(frame, to: composer)
                guard shown.intersects(slot), shown.width > slot.width * 1.25 || shown.height > slot.height * 1.25 else {
                    return nil
                }
                return "\(type(of: view)) \(shown)"
            }
        }

        for isStopAvailable in [false, true] {
            composer.setStopAvailable(isStopAvailable)
            window.layoutIfNeeded()
            let moment = isStopAvailable ? "With an answer to stop" : "Typed"
            textView.insertText("J")
            textView.delegate?.textViewDidChange?(textView)
            XCTAssertTrue(controller.state.canDictateMore, "\(moment): the floating microphone comes")
            for step in 0..<10 {
                XCTAssertEqual(touchView.recordingCircleAlpha, 0, "\(moment), \(step * 50) ms in: no recording circle")
                XCTAssertEqual(largerViewsOverTheSlot(), [], "\(moment), \(step * 50) ms in: nothing larger over the circle")
                try await Task.sleep(for: .milliseconds(50))
                window.layoutIfNeeded()
            }
            let send = try XCTUnwrap(findButton(labelled: lang("Send"), in: composer), "\(moment): Send shows")
            XCTAssertGreaterThan(shownOpacity(of: send), 0.95)
            XCTAssertEqual(shownOpacity(of: microphone), 0, "\(moment): neither the microphone nor Stop over Send")
            let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
            XCTAssertEqual(resume.bounds.width, AgentVoiceResumeButton.diameter, "The floating microphone is the small one")

            // Emptied, the floating microphone goes, and still no recording circle shows
            textView.deleteBackward()
            textView.delegate?.textViewDidChange?(textView)
            XCTAssertFalse(controller.state.canDictateMore)
            if isStopAvailable {
                XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_stop_answer"), "Emptied, Stop comes back")
            }
            for step in 0..<10 {
                XCTAssertEqual(touchView.recordingCircleAlpha, 0, "\(moment), emptied, \(step * 50) ms in")
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Clearing a field of several lines sinks the floating microphone into the trailing circle where it stands once
    /// the field has shrunk, not where it stood beside the taller field, and some microphone shows at every moment of
    /// the sink: the sinking one until it lands, then the circle's own
    @MainActor
    func testClearingATallFieldSinksTheMicrophoneIntoTheCirclesNewPlace() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "With Reduce Motion it fades in place")
        let controller = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        composer.setSendEnabled(true)
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)

        func shownOpacity(of view: UIView) -> Float {
            var opacity: Float = 1
            var current: UIView? = view
            while let layerView = current, layerView !== window {
                // Hiding and opacity both as last committed: the screen shows them together
                let shown = layerView.layer.presentation() ?? layerView.layer
                if shown.isHidden { return 0 }
                opacity *= shown.opacity
                current = layerView.superview
            }
            return opacity
        }
        func shownMicrophones() -> Int {
            descendants(of: composer)
                .compactMap { $0 as? UIImageView }
                .filter { $0.image === AgentComposerView.microphoneImage && shownOpacity(of: $0) > 0.05 }
                .count
        }

        textView.text = "Шагала\nАлл"
        textView.delegate?.textViewDidChange?(textView)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        window.layoutIfNeeded()
        let tallField = composer.inputBackgroundFrame
        XCTAssertNotNil(findButton(labelled: lang("$agent_voice_resume"), in: composer), "The floating microphone is up")

        textView.text = ""
        textView.delegate?.textViewDidChange?(textView)
        window.layoutIfNeeded()
        XCTAssertLessThan(composer.inputBackgroundFrame.height, tallField.height - 1, "The field shrinks")
        let resume = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentVoiceResumeButton }.first {
            $0.accessibilityLabel == lang("$agent_voice_resume") && !$0.isHidden
        })
        let slot = microphone.convert(microphone.bounds, to: composer)
        let landing = resume.convert(resume.bounds, to: composer)
        XCTAssertEqual(landing.midX, slot.midX, accuracy: 0.5, "Into the circle where it stands now")
        XCTAssertEqual(landing.midY, slot.midY, accuracy: 0.5)
        XCTAssertEqual(landing.width, slot.width, accuracy: 0.5)
        for step in 0..<14 {
            XCTAssertEqual(shownMicrophones(), 1, "\(step * 50) ms into the sink: one microphone, never an empty circle")
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        XCTAssertNil(findButton(labelled: lang("$agent_voice_resume"), in: composer), "Landed")
        XCTAssertGreaterThan(shownOpacity(of: microphone), 0.95, "The circle's own microphone")
        XCTAssertEqual(microphone.convert(microphone.bounds, to: composer).midY, slot.midY, accuracy: 0.5)
    }

    /// Text typed into the empty field raises the trailing microphone out of its circle to where the floating one
    /// rests, as a dictation's does, with Send coming in the circle; deleting it all sinks the floating microphone back
    /// into the circle, where it becomes the circle's microphone. Only one microphone shows at any moment of either.
    @MainActor
    func testTypingRaisesTheMicrophoneAndEmptyingTheFieldSinksItBack() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "With Reduce Motion it fades in place")
        let controller = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        defer { controller.cancel() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let composer = AgentComposerView()
        composer.dictationController = controller
        composer.setSendEnabled(true)
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentComposerTextView }.first)
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let trailingCircle = microphone.convert(microphone.bounds, to: composer)

        /// How much of `view` shows now, frame by frame: its opacity and its ancestors' as they show
        func shownOpacity(of view: UIView) -> Float {
            var opacity: Float = 1
            var current: UIView? = view
            while let layerView = current, layerView !== window {
                // Hiding and opacity both as last committed: the screen shows them together
                let shown = layerView.layer.presentation() ?? layerView.layer
                if shown.isHidden { return 0 }
                opacity *= shown.opacity
                current = layerView.superview
            }
            return opacity
        }
        func shownMicrophones() -> Int {
            descendants(of: composer)
                .compactMap { $0 as? UIImageView }
                .filter { $0.image === AgentComposerView.microphoneImage && shownOpacity(of: $0) > 0.05 }
                .count
        }
        func sample(_ moment: String) async throws {
            for step in 0..<8 {
                XCTAssertLessThanOrEqual(shownMicrophones(), 1, "\(moment), \(step * 60) ms in: one microphone")
                try await Task.sleep(for: .milliseconds(60))
            }
            window.layoutIfNeeded()
        }
        XCTAssertEqual(shownMicrophones(), 1)

        // Typed: the microphone rises to where the floating one rests, and Send takes the circle
        textView.insertText("А")
        textView.delegate?.textViewDidChange?(textView)
        XCTAssertTrue(controller.state.canDictateMore, "Any text brings the floating microphone")
        try await sample("Rising")
        let resume = try XCTUnwrap(findButton(labelled: lang("$agent_voice_resume"), in: composer))
        let resting = resume.convert(resume.bounds, to: composer)
        XCTAssertEqual(
            resting.maxY, composer.inputBackgroundFrame.minY - AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5,
            "Where the floating microphone rests"
        )
        XCTAssertEqual(resting.midX, trailingCircle.midX, accuracy: 0.5)
        let send = try XCTUnwrap(findButton(labelled: lang("Send"), in: composer), "Send in the circle")
        XCTAssertGreaterThan(shownOpacity(of: send), 0.95)
        XCTAssertEqual(shownMicrophones(), 1)

        // Emptied: it sinks back into the circle, whose microphone it becomes
        textView.deleteBackward()
        textView.delegate?.textViewDidChange?(textView)
        XCTAssertEqual(composer.draftText ?? "", "")
        XCTAssertFalse(controller.state.canDictateMore)
        try await sample("Sinking")
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        XCTAssertNil(findButton(labelled: lang("$agent_voice_resume"), in: composer), "Back in the circle")
        XCTAssertEqual(shownMicrophones(), 1)
        XCTAssertGreaterThan(shownOpacity(of: microphone), 0.95, "The circle's own microphone")
        XCTAssertEqual(microphone.convert(microphone.bounds, to: composer).midX, trailingCircle.midX, accuracy: 0.5)
    }

    /// The recording panel shows no time: the dot and "Slide to cancel", or Cancel for a hands-free recording
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

    /// While an answer that can be stopped is being written, Stop takes the microphone's place and stops the answer
    /// instead of recording. Text in the field keeps the send button, and the microphone comes back once the answer
    /// can't be stopped.
    @MainActor
    func testStopTakesTheMicrophonesPlaceWhileAnAnswerCanBeStopped() throws {
        let controller = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        let composer = AgentComposerView()
        composer.dictationController = controller
        var stops = 0
        composer.onStop = { stops += 1 }
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let send = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == lang("Send")
        })
        let recognizer = try XCTUnwrap(microphone.gestureRecognizers?.first { $0 is UILongPressGestureRecognizer })

        composer.setStopAvailable(true)
        XCTAssertFalse(microphone.isHidden)
        XCTAssertTrue(microphone.isEnabled)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_stop_answer"))
        XCTAssertFalse(recognizer.isEnabled, "A press on Stop doesn't start a recording")
        XCTAssertTrue(microphone.accessibilityActivate())
        dispatch(.touchUpInside, from: microphone)
        XCTAssertEqual(stops, 2)
        XCTAssertEqual(controller.state.phase, .idle)

        composer.setDraftText("Hello", focus: false)
        XCTAssertTrue(microphone.isHidden, "Text in the field keeps the send button")
        XCTAssertFalse(send.isHidden)
        composer.setDraftText("", focus: false)
        XCTAssertFalse(microphone.isHidden, "Stop comes back to the emptied field")
        XCTAssertTrue(send.isHidden)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_stop_answer"))
        XCTAssertFalse(recognizer.isEnabled)

        composer.setStopAvailable(false)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_start"))
        XCTAssertTrue(recognizer.isEnabled)
        dispatch(.touchUpInside, from: microphone)
        XCTAssertEqual(stops, 2)
    }

    /// While an answer can be stopped, typing turns Stop into Send and clearing the field turns Send back into Stop:
    /// the circle keeps Stop's glyph as it goes into the field and comes back out of it, so the microphone never shows
    /// in between. Without an answer to stop, the circle comes back as the microphone.
    @MainActor
    func testTypingAndClearingWhileAnAnswerCanBeStoppedTurnsStopAndSendIntoEachOther() throws {
        let composer = AgentComposerView()
        composer.dictationController = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        let microphone = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let send = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == lang("Send")
        })
        let imageViews = descendants(of: composer).compactMap { $0 as? UIImageView }
        let imagesBefore = imageViews.map(\.image)
        composer.setStopAvailable(true)
        // The circle's glyph is the one image that Stop changes
        let glyphIndex = try XCTUnwrap(imageViews.indices.first { imageViews[$0].image !== imagesBefore[$0] })
        let glyph = imageViews[glyphIndex]
        let microphoneImage = try XCTUnwrap(imagesBefore[glyphIndex])
        let stopImage = try XCTUnwrap(glyph.image)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_stop_answer"))

        for text in ["H", "Hello"] {
            composer.setDraftText(text, focus: false)
            XCTAssertFalse(send.isHidden, "Send shows with \"\(text)\"")
            XCTAssertTrue(microphone.isHidden)
            XCTAssertTrue(glyph.image === stopImage, "The circle in the field keeps Stop's glyph with \"\(text)\"")
        }
        for text in ["H", ""] {
            composer.setDraftText(text, focus: false)
            XCTAssertTrue(glyph.image === stopImage, "The circle keeps Stop's glyph with \"\(text)\"")
        }
        XCTAssertTrue(send.isHidden)
        XCTAssertFalse(microphone.isHidden)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_stop_answer"))

        composer.setDraftText("Hello", focus: false)
        composer.setStopAvailable(false)
        XCTAssertFalse(send.isHidden, "An answer that ends while the field has text leaves Send")
        composer.setDraftText("", focus: false)
        XCTAssertTrue(glyph.image === microphoneImage, "Without an answer to stop, the microphone comes back")
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_start"))

        composer.setStopAvailable(true)
        XCTAssertTrue(glyph.image === stopImage)
        composer.setStopAvailable(false)
        XCTAssertTrue(
            glyph.image === microphoneImage,
            "An answer that ends with an empty field turns Stop into the microphone"
        )
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
    func testShrinkingWhitespaceDraftDoesNotPauseRecordingUnderStationaryFinger() async throws {
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
        gesture.pointInWindow = microphone.convert(CGPoint(x: microphone.bounds.midX, y: microphone.bounds.midY), to: window)
        gesture.simulatedState = .began
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
        scheduler.advance(by: 0.22)
        let touchView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationTouchView }.first)
        func getMicrophoneCenterInWindow() -> CGPoint {
            microphone.convert(CGPoint(x: microphone.bounds.midX, y: microphone.bounds.midY), to: window)
        }
        var touchCenterInWindow = composer.convert(touchView.center, to: window)
        XCTAssertEqual(touchCenterInWindow.x, getMicrophoneCenterInWindow().x, accuracy: 0.01)
        XCTAssertEqual(touchCenterInWindow.y, getMicrophoneCenterInWindow().y, accuracy: 0.01)
        XCTAssertEqual(touchView.bounds.width, AgentVoiceRecordingMetrics.circleDiameter)
        for _ in 0..<100 where recordingStarts == 0 { await Task.yield() }
        XCTAssertEqual(recordingStarts, 1)
        window.layoutIfNeeded()
        XCTAssertEqual(composer.inputBackgroundFrame.height, AgentComposerMetrics.minInputHeight)
        XCTAssertEqual(composer.frame.minY - initialComposerY, initialFieldHeight - AgentComposerMetrics.minInputHeight)
        touchCenterInWindow = composer.convert(touchView.center, to: window)
        XCTAssertEqual(touchCenterInWindow.x, getMicrophoneCenterInWindow().x, accuracy: 0.01)
        XCTAssertEqual(touchCenterInWindow.y, getMicrophoneCenterInWindow().y, accuracy: 0.01)

        gesture.pointInWindow.y -= 2
        gesture.simulatedState = .changed
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)

        XCTAssertEqual(controller.state.phase, .holding)
        XCTAssertEqual(controller.state.dragY, -2, accuracy: 0.01)
        touchCenterInWindow = composer.convert(touchView.center, to: window)
        XCTAssertEqual(touchCenterInWindow.x, getMicrophoneCenterInWindow().x, accuracy: 0.01)
        XCTAssertEqual(touchCenterInWindow.y, getMicrophoneCenterInWindow().y, accuracy: 0.01)
        scheduler.advance(by: 0.8)
        gesture.simulatedState = .ended
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
        XCTAssertEqual(controller.state.phase, .recognizing)
        for _ in 0..<100 where controller.state.phase != .idle { await Task.yield() }
        XCTAssertEqual(recorder.stopCount, 1)
    }

    @MainActor
    func testRightToLeftGestureCancelsToTheRightAndHintFollowsTheCancelDirection() async throws {
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
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first { $0.text?.contains("›") == true })

        for dragX in [-149.0, 22.0] {
            gesture.pointInWindow.x = origin.x + dragX
            gesture.simulatedState = .changed
            composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
            window.layoutIfNeeded()
            XCTAssertEqual(controller.state.phase, .holding)
            // The circle grows out of the microphone and stays anchored there; only its blob slides
            let circleCenter = composer.convert(touchView.center, to: window)
            XCTAssertEqual(circleCenter.x, origin.x, accuracy: 0.01)
            XCTAssertEqual(circleCenter.y, origin.y, accuracy: 0.01)
            XCTAssertEqual(hint.transform.tx, max(0, dragX), accuracy: 0.01)
            XCTAssertEqual(hint.alpha, dragX > 0 ? 0.8 : 1, accuracy: 0.01)
        }

        gesture.pointInWindow.x = origin.x + CGFloat(AgentDictationController.cancelDistance)
        composer.perform(NSSelectorFromString("handleMicrophoneGesture:"), with: gesture)
        XCTAssertEqual(controller.state.phase, .idle)
        XCTAssertEqual(recorder.cancelCount, 1)
        scheduler.advance(by: 60)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(recorder.stopCount, 0)
    }

    @MainActor
    func testRightToLeftRecordingKeepsDotAndCancelClearOfFinishButton() async throws {
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
        let dot = try XCTUnwrap(strip.subviews.first {
            $0.layer.cornerRadius == AgentVoiceRecordingMetrics.recordingDotDiameter / 2
        })
        let cancel = try XCTUnwrap(strip.cancelAccessibilityElement as? UIButton)
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)

        scheduler.advance(by: 1)
        window.layoutIfNeeded()
        let finishFrame = finish.convert(finish.bounds, to: strip)
        XCTAssertFalse(dot.frame.intersects(finishFrame))
        // The dot stands at the leading end, away from the stop, and the cross floats above the field at that end
        XCTAssertLessThanOrEqual(finishFrame.maxX, dot.frame.minX)
        XCTAssertEqual(dot.frame.maxX, strip.bounds.maxX, accuracy: 0.5)
        XCTAssertTrue(cancel.isHidden, "No cross in the panel")
        let cross = composer.cancelBubble.view
        XCTAssertFalse(cross.isHidden)
        let crossFrame = cross.convert(cross.bounds, to: composer)
        XCTAssertGreaterThan(crossFrame.midX, composer.inputBackgroundFrame.midX, "At the leading end, on the right")
        XCTAssertLessThanOrEqual(crossFrame.maxY, composer.inputBackgroundFrame.minY)

        controller.finish()
        XCTAssertEqual(controller.state.phase, .recognizing)
        window.layoutIfNeeded()
        XCTAssertTrue(finish.isHidden)
        XCTAssertFalse(cancel.isHidden)
        XCTAssertLessThan(cancel.frame.maxX, hint.frame.minX)
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

/// A press on the floating microphone in the state the test gives
private final class FloatingMicrophoneTestPress: UILongPressGestureRecognizer {
    private let reportedState: UIGestureRecognizer.State

    init(state: UIGestureRecognizer.State) {
        reportedState = state
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { }
    }
}
