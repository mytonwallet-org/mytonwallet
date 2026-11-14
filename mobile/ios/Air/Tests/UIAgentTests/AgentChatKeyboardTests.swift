import XCTest
import UIKit
@testable import UIAgent
import WalletResources

/// The area the composer and the keyboard cover changes here as the keyboard changes it: the composer moves inside an
/// animation, and the list's insets follow from its frame. A draft of several lines grows the composer the way the
/// keyboard raises it; the simulator's software keyboard, when it shows, raises it for real.
@MainActor
final class AgentChatKeyboardTests: XCTestCase {
    private static let tallDraft = (1...6).map { "Line \($0)" }.joined(separator: "\n")

    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    func testContentAtTheEndRidesUpWithTheCoveredAreaAndComesBackDown() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        let shortComposerY = composer.frame.minY
        try await changeCoveredArea(in: chat) { composer.setDraftText(Self.tallDraft, focus: false) }
        XCTAssertLessThan(composer.frame.minY, shortComposerY - 60)
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.clearDraft() }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        XCTAssertEqual(chat.controller.reserveSpacerHeight, 0)
    }

    /// The chat of Artem's recording: a question sent in it, answered at length and read to the end, keeps its end at
    /// the composer, with no space left under it when the covered area shrinks
    func testAnsweredQuestionDoesNotHoldTheListAgainstTheCoveredArea() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        composer.setDraftText("What should I check before paying with crypto?", focus: false)
        composer.onSend?()
        try await chat.waitForStableLayout()
        XCTAssertNotNil(chat.controller.pinnedUserMessageID)
        let reply = AgentMessage(
            role: .assistant,
            text: String(repeating: "Check the address, the network and the amount before you confirm. ", count: 30),
            isStreaming: false
        )
        chat.backend.context?.append(.message(reply), animated: false)
        try await chat.waitForStableLayout()
        chat.collectionView.contentOffset.y = try XCTUnwrap(chat.latestOffsetY)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.setDraftText(Self.tallDraft, focus: false) }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.clearDraft() }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        XCTAssertEqual(chat.controller.reserveSpacerHeight, 0, accuracy: 0.5)
    }

    /// Scrolled up, the rows stay where they are as the covered area grows and shrinks
    func testScrolledUpRowsKeepTheirPlace() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        chat.collectionView.contentOffset.y -= 1_000
        try await chat.waitForStableLayout()
        let offsetY = chat.collectionView.contentOffset.y

        try await changeCoveredArea(in: chat) { composer.setDraftText(Self.tallDraft, focus: false) }
        XCTAssertEqual(chat.collectionView.contentOffset.y, offsetY, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.clearDraft() }
        XCTAssertEqual(chat.collectionView.contentOffset.y, offsetY, accuracy: 1)
    }

    /// The software keyboard, where the simulator shows it
    func testContentAtTheEndRidesTheKeyboard() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let controller = chat.controller
        let textView = try XCTUnwrap(findDescendants(of: controller.composerView).compactMap { $0 as? UITextView }.first)

        let opening = try await followCoveredArea(in: chat) { _ = textView.becomeFirstResponder() }
        guard controller.view.keyboardLayoutGuide.layoutFrame.height > 100 else {
            textView.resignFirstResponder()
            throw XCTSkip("The simulator shows no software keyboard")
        }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        // The keyboard's own animation is one the list can follow at the time its frames show
        XCTAssertGreaterThan(opening.count, 0, opening.unfollowed)

        let closing = try await followCoveredArea(in: chat) { _ = textView.resignFirstResponder() }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        XCTAssertGreaterThan(closing.count, 0, closing.unfollowed)
        XCTAssertEqual(controller.reserveSpacerHeight, 0)
    }

    /// A question the chat takes closes the keyboard as it goes, as on Android, and the field gives its text up
    func testSentQuestionClosesTheKeyboard() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        let text = "What should I check before paying with crypto?"
        composer.setDraftText(text, focus: true)
        XCTAssertTrue(composer.isTextInputActive)

        composer.onSend?()
        XCTAssertFalse(composer.isTextInputActive, "The keyboard goes with the question")
        XCTAssertEqual(composer.draftText ?? "", "")
        let questionID = try XCTUnwrap(chat.model.itemIDs.last)
        XCTAssertEqual(chat.model.message(for: questionID)?.text, text)
        try await chat.waitForStableLayout()
        XCTAssertFalse(composer.isTextInputActive)
    }

    /// A question sent while an answer is written waits for it at the chat's end, and closes the keyboard as one that
    /// goes at once does
    func testQuestionThatWaitsForTheAnswerClosesTheKeyboard() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        chat.backend.canSendMessages = false
        chat.backend.context?.append(.typingIndicator(AgentTypingIndicator()), animated: false)
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        let text = "And what about the fees?"
        composer.setDraftText(text, focus: true)
        XCTAssertTrue(composer.isTextInputActive)

        composer.onSend?()
        XCTAssertFalse(composer.isTextInputActive, "The keyboard goes with the question that waits")
        XCTAssertEqual(composer.draftText ?? "", "")
        let questionID = try XCTUnwrap(chat.model.itemIDs.last)
        XCTAssertEqual(chat.model.message(for: questionID)?.text, text, "It waits after the answer being written")
        try await chat.waitForStableLayout()
        XCTAssertFalse(composer.isTextInputActive)
    }

    /// The field's text flies into the bubble of a question that waits wherever the list takes the bubble meanwhile, as
    /// the list goes down with the keyboard the question closes
    func testWaitingQuestionsTextFliesWithItsBubbleAsTheListMoves() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the bubble without a flight")
        let chat = makeChat()
        try await chat.waitForStableLayout()
        chat.backend.canSendMessages = false
        chat.backend.context?.append(.typingIndicator(AgentTypingIndicator()), animated: false)
        try await chat.waitForStableLayout()
        let controller = chat.controller
        controller.composerView.setDraftText("And what about the fees?", focus: false)
        chat.layout()
        let shownViews = Set(controller.view.subviews.map { ObjectIdentifier($0) })

        controller.composerView.onSend?()
        let picture = try XCTUnwrap(
            controller.view.subviews.last { !shownViews.contains(ObjectIdentifier($0)) },
            "The field's text flies"
        )
        let questionID = try XCTUnwrap(chat.model.itemIDs.last)
        let indexPath = try XCTUnwrap(controller.messageIndexPath(for: questionID))
        let text = try XCTUnwrap(chat.collectionView.cellForItem(at: indexPath) as? AgentMessageCell).sentTextView
        try await Task.sleep(for: .milliseconds(30))
        let pictureY = picture.center.y
        let textY = text.convert(text.bounds, to: controller.view).midY

        chat.collectionView.contentOffset.y -= 40
        try await Task.sleep(for: .milliseconds(60))
        let textShift = text.convert(text.bounds, to: controller.view).midY - textY
        XCTAssertGreaterThan(textShift, 30, "The list moved the bubble")
        XCTAssertEqual(picture.center.y - pictureY, textShift, accuracy: 1, "The text flies with it")
    }

    /// The first question typed in a chat opened at its end, sent without scrolling, lands under what shows: the list
    /// scrolls up over several frames, on its spring, until the question shows above the field as it stood, while the
    /// field's text flies into the bubble and lands on its text wherever the list takes it, and the chat then brings
    /// the question up
    func testFirstQuestionInAChatOpenedAtItsEndFliesOutOfTheField() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the bubble without a flight")
        let chat = makeChat()
        try await chat.waitForStableLayout()
        chat.backend.isThinkingOnSend = true
        let controller = chat.controller
        let collectionView = chat.collectionView
        let composer = controller.composerView
        composer.setDraftText("Тест", focus: true)
        try await chat.waitForStableLayout()
        XCTAssertTrue(controller.isNearBottom(), "The chat is at its end")
        let offsetY = collectionView.contentOffset.y
        let occlusion = controller.occlusionBottomInset
        let shownViews = Set(controller.view.subviews.map { ObjectIdentifier($0) })
        // Every offset the list takes, however seldom the test gets to look
        let log = ContentOffsetLog()
        let observation = collectionView.observe(\.contentOffset, options: [.new]) { _, change in
            let newOffsetY = change.newValue?.y ?? 0
            MainActor.assumeIsolated { log.offsets.append(newOffsetY) }
        }
        defer { observation.invalidate() }

        composer.onSend?()
        let picture = try XCTUnwrap(
            controller.view.subviews.last {
                !shownViews.contains(ObjectIdentifier($0))
                    && $0.accessibilityIdentifier != AgentListScrollAnimator.departingViewIdentifier
            },
            "The field's text flies into the bubble"
        )
        let questionID = try XCTUnwrap(chat.model.itemIDs.last { chat.model.message(for: $0)?.role == .user })
        XCTAssertEqual(chat.model.message(for: questionID)?.text, "Тест")
        let indexPath = try XCTUnwrap(controller.messageIndexPath(for: questionID))
        let text = try XCTUnwrap((collectionView.cellForItem(at: indexPath) as? AgentMessageCell)?.sentTextView)
        XCTAssertEqual(collectionView.contentOffset.y, offsetY, accuracy: 0.5, "The list sets out from where it stood")

        // Frame by frame through the flight, the picture's landing point, its place moved by the transform it flies
        // by, is the bubble's text, within what the list moves between two looks
        var previousOffsetY = collectionView.contentOffset.y
        let deadline = ContinuousClock.now + .seconds(2)
        while picture.superview != nil {
            guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(16))
            let currentOffsetY = collectionView.contentOffset.y
            let textMidY = text.convert(text.bounds, to: controller.view).midY
            XCTAssertEqual(
                picture.center.y + picture.transform.ty,
                textMidY,
                accuracy: abs(currentOffsetY - previousOffsetY) + 1,
                "The text flies onto the bubble's text"
            )
            previousOffsetY = currentOffsetY
        }
        observation.invalidate()
        // Where the question shows whole above the field as it stood, which the list reaches before it brings the
        // question up
        let questionFrame = try XCTUnwrap(collectionView.layoutAttributesForItem(at: indexPath)).frame
        let roomOffsetY = questionFrame.maxY - collectionView.bounds.height + occlusion
        let distance = roomOffsetY - offsetY
        XCTAssertGreaterThan(distance, 1, "The question landed under what showed")
        let offsets = [offsetY] + log.offsets
        let roomIndex = try XCTUnwrap(
            offsets.firstIndex { abs($0 - roomOffsetY) < 1 },
            "The list stops where the question shows whole above the field: \(offsets)"
        )
        let makingRoom = offsets[...roomIndex]
        let largestStep = zip(makingRoom, makingRoom.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(largestStep, distance * 0.75, "The list moves over several frames: \(makingRoom)")
        XCTAssertGreaterThan(Set(makingRoom.map { Int($0.rounded()) }).count, 3, "\(makingRoom)")

        let typingDeadline = ContinuousClock.now + .seconds(5)
        while controller.lastTypingIndicatorID == nil {
            guard ContinuousClock.now < typingDeadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(16))
            chat.layout()
        }
        try await chat.waitForStableLayout()
        let pinnedOffsetY = try XCTUnwrap(controller.pinnedOffsetY(for: questionID))
        XCTAssertEqual(
            collectionView.contentOffset.y,
            controller.clampedContentOffsetY(pinnedOffsetY),
            accuracy: 1,
            "Then the chat brings it up"
        )
    }

    /// A question the chat turns down, as the hardware keyboard's Return sends it while nothing can go, keeps the
    /// keyboard and the draft
    func testTurnedDownQuestionKeepsTheKeyboard() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        chat.backend.canSendMessages = false
        chat.backend.canAcceptMessages = false
        let composer = chat.controller.composerView
        let text = "What should I check before paying with crypto?"
        composer.setDraftText(text, focus: true)
        XCTAssertTrue(composer.isTextInputActive)
        let itemIDs = chat.model.itemIDs

        composer.onSend?()
        try await chat.waitForStableLayout()
        XCTAssertTrue(composer.isTextInputActive, "The keyboard stays")
        XCTAssertEqual(composer.draftText, text)
        XCTAssertEqual(chat.model.itemIDs, itemIDs, "Nothing went")
    }

    /// A question sent with the keyboard up, as a tapped suggestion, turns the trailing circle's microphone into Stop
    /// while the keyboard it closes takes the composer down in the same pass: the leaving glyph shrinks away and the
    /// arriving one grows in inside the circle, frame by frame, wherever the composer is
    func testMicrophoneTurnsIntoStopInsideTheCircleAsTheKeyboardCloses() async throws {
        let chat = makeChat()
        let controller = chat.controller
        // The composer stands where a keyboard holds it
        controller.additionalSafeAreaInsets.bottom = 300
        try await chat.waitForStableLayout()
        let composer = controller.composerView
        let microphone = try XCTUnwrap(findDescendants(of: composer).compactMap { $0 as? AgentDictationButton }.first)
        let circle = try XCTUnwrap(microphone.superview, "The circle's content")
        let raisedComposerY = composer.frame.minY

        composer.setStopAvailable(true)
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) {
            controller.additionalSafeAreaInsets.bottom = 0
            chat.window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
        }
        XCTAssertGreaterThan(composer.frame.minY, raisedComposerY + 100, "The composer goes down")
        XCTAssertFalse((composer.layer.animationKeys() ?? []).isEmpty, "In the keyboard's animation")
        let leaving = try XCTUnwrap(composer.leavingActionGlyphView, "The microphone leaves")
        XCTAssertTrue(leaving.isDescendant(of: circle), "As a view of the circle")
        let arriving = try XCTUnwrap(
            circle.subviews.compactMap { $0 as? UIImageView }.first { $0 !== leaving && !$0.isHidden },
            "Stop comes"
        )
        XCTAssertFalse(arriving.image === leaving.image)
        let start = CACurrentMediaTime()
        var sampleCount = 0
        while leaving.superview != nil, CACurrentMediaTime() - start < 1 {
            for (glyph, name) in [(leaving, "The microphone"), (arriving, "Stop")] {
                let frame = glyph.layer.presentation()?.frame ?? glyph.frame
                XCTAssertTrue(
                    circle.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                    "\(name) stays in the circle, at \(frame) in \(circle.bounds)"
                )
            }
            sampleCount += 1
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertGreaterThan(sampleCount, 1, "The swap takes several frames")
        XCTAssertNil(leaving.superview, "The microphone is gone once it has shrunk away")
        XCTAssertNil(composer.leavingActionGlyphView)
        try await chat.waitForStableLayout()
    }

    /// Applies `change` in the keyboard's animation time, then follows the list
    private func changeCoveredArea(in chat: AgentTestChat, _ change: @escaping () -> Void) async throws {
        let sampling = try await followCoveredArea(in: chat) {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) {
                change()
                chat.controller.view.layoutIfNeeded()
            }
        }
        XCTAssertGreaterThan(sampling.count, 0, sampling.unfollowed)
    }

    /// Runs `change` and checks every frame until the list settles that the rows on screen are all drawn and, for
    /// content that ends at the composer, that its end moves with the composer. The list is set on display link ticks
    /// for the time their frame shows, while the composer's presentation here is of the moment of the check, and the
    /// last tick may come before the previous check, so the two may stand as far apart as the composer moves over the
    /// last two checks. Returns how many of the composer's animated frames `AgentLayerAnimationSampler` followed, each
    /// matching its presentation, and the animations of those it didn't. A busy simulator draws few of them.
    @discardableResult
    private func followCoveredArea(in chat: AgentTestChat, _ change: () -> Void) async throws -> (count: Int, unfollowed: String) {
        let controller = chat.controller
        let composer = controller.composerView
        let isAtEnd = abs(try getSpaceUnderContent(in: chat)) < 1
        // Where the list's visible bottom stands relative to the composer's top, which the change keeps
        let composerToVisibleBottom = chat.collectionView.bounds.height - controller.occlusionBottomInset - composer.frame.minY
        var previousComposerY = composer.frame.minY
        var earlierComposerY = previousComposerY
        var sampledFrameCount = 0
        var unfollowed: Set<String> = []
        change()
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 1 {
            try await Task.sleep(for: .milliseconds(16))
            XCTAssertLessThanOrEqual(chat.getLargestUncoveredGap(), AgentVCLayout.rowSpacing + 1)
            let timeBeforePresentation = CACurrentMediaTime()
            guard let composerY = composer.layer.presentation()?.frame.minY else { continue }
            let timeAfterPresentation = CACurrentMediaTime()
            defer {
                earlierComposerY = previousComposerY
                previousComposerY = composerY
            }
            if let keys = composer.layer.animationKeys(), !keys.isEmpty {
                // The presentation is of a moment between these two
                if let earliestY = AgentLayerAnimationSampler.getMinY(of: composer.layer, at: timeBeforePresentation),
                   let latestY = AgentLayerAnimationSampler.getMinY(of: composer.layer, at: timeAfterPresentation) {
                    XCTAssertGreaterThanOrEqual(composerY, min(earliestY, latestY) - 0.5)
                    XCTAssertLessThanOrEqual(composerY, max(earliestY, latestY) + 0.5)
                    sampledFrameCount += 1
                } else {
                    unfollowed.formUnion(keys.compactMap { key in
                        composer.layer.animation(forKey: key).map { "\(key): \(type(of: $0)) \(($0 as? CAPropertyAnimation)?.keyPath ?? "")" }
                    })
                }
            }
            guard isAtEnd, controller.occlusionFollow != nil,
                  let indexPath = controller.lastItemIndexPath,
                  let lastFrame = chat.collectionView.layoutAttributesForItem(at: indexPath)?.frame else { continue }
            let contentEndY = lastFrame.maxY - chat.collectionView.contentOffset.y
            XCTAssertEqual(contentEndY, composerY + composerToVisibleBottom, accuracy: abs(composerY - earlierComposerY) + 2)
        }
        try await chat.waitForStableLayout()
        XCTAssertNil(controller.occlusionFollow)
        return (sampledFrameCount, unfollowed.sorted().joined(separator: "; "))
    }

    /// The space between the end of the content and the composer
    private func getSpaceUnderContent(in chat: AgentTestChat) throws -> CGFloat {
        let indexPath = try XCTUnwrap(chat.controller.lastItemIndexPath)
        let lastFrame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: indexPath)).frame
        let visibleBottom = chat.collectionView.contentOffset.y + chat.collectionView.bounds.height
            - chat.controller.occlusionBottomInset
        return visibleBottom - lastFrame.maxY
    }

    private func makeChat() -> AgentTestChat {
        let messages = (0..<30).map { index in
            AgentMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: index.isMultiple(of: 2)
                    ? "Question \(index) about the wallet"
                    : "Answer \(index). " + String(repeating: "Gram and TON network news for the last two days. ", count: 4),
                isStreaming: false
            )
        }
        let chat = AgentTestChat(messages: messages)
        addTeardownBlock { chat.close() }
        return chat
    }
}

@MainActor
private final class ContentOffsetLog {
    var offsets: [CGFloat] = []
}
