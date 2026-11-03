import XCTest
import UIKit
@testable import UIAgent
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
        XCTAssertEqual(controller.state.phase, .locked)
        XCTAssertEqual(microphone.accessibilityLabel, lang("$agent_dictation_finish"))
        let cancelButton = descendants(of: composer).compactMap { $0 as? UIButton }.first {
            $0.title(for: .normal) == lang("Cancel")
        }
        XCTAssertFalse(try XCTUnwrap(cancelButton).isHidden)
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
    func testShrinkingWhitespaceDraftDoesNotLockRecordingUnderStationaryFinger() async throws {
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
    func testCountdownShowsFormattedSecondsFromGeneratedLocalization() throws {
        let strip = AgentDictationStripView()
        strip.update(AgentDictationState(phase: .holding, elapsed: 50))
        let labels = descendants(of: strip).compactMap { $0 as? UILabel }
        let hint = try XCTUnwrap(labels.first {
            $0.text != AgentVoiceRecordingMetrics.formatTimer(50) && !$0.isDescendant(of: strip.cancelAccessibilityElement)
        })
        let tenSeconds = try XCTUnwrap(hint.text)
        XCTAssertFalse(tenSeconds.contains("%"))
        XCTAssertEqual(tenSeconds.compactMap(\.wholeNumberValue), [1, 0])

        strip.update(AgentDictationState(phase: .holding, elapsed: 51))

        let nineSeconds = try XCTUnwrap(hint.text)
        XCTAssertFalse(nineSeconds.contains("%"))
        XCTAssertEqual(nineSeconds.compactMap(\.wholeNumberValue), [9])
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
    func testRightToLeftRecordingKeepsTimerAndCancelClearOfFinishButton() async throws {
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
        XCTAssertEqual(controller.state.phase, .locked)
        window.layoutIfNeeded()
        let strip = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
        XCTAssertEqual(strip.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        XCTAssertEqual(finish.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        let timer = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first {
            $0.text == AgentVoiceRecordingMetrics.formatTimer(0)
        })
        let dot = try XCTUnwrap(strip.subviews.first {
            $0.layer.cornerRadius == AgentVoiceRecordingMetrics.recordingDotDiameter / 2
        })
        let cancel = try XCTUnwrap(strip.cancelAccessibilityElement as? UIButton)
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first { $0 !== timer })

        for elapsed in [0.0, 51.0] {
            scheduler.advance(by: elapsed)
            window.layoutIfNeeded()
            let finishFrame = finish.convert(finish.bounds, to: strip)
            XCTAssertFalse(timer.frame.intersects(finishFrame))
            XCTAssertFalse(dot.frame.intersects(finishFrame))
            XCTAssertFalse(cancel.frame.intersects(finishFrame))
            XCTAssertLessThanOrEqual(finishFrame.maxX, cancel.frame.minX)
            XCTAssertLessThan(cancel.frame.maxX, timer.frame.minX)
            XCTAssertLessThanOrEqual(timer.frame.maxX, dot.frame.minX)
            if elapsed > 0 {
                XCTAssertFalse(hint.isHidden)
                XCTAssertLessThan(cancel.frame.maxX, hint.frame.minX)
                XCTAssertLessThanOrEqual(hint.frame.maxX, timer.frame.minX)
            }
        }

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
