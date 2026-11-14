import XCTest
import UIKit
import Kingfisher
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class AgentPinnedReplyScrollTests: XCTestCase {
    func testOlderTablesKeepTheirWidthAfterScrollingAndRotation() async throws {
        let chat = try await makeChat(historyCount: 40, tableHistory: true)
        let context = try XCTUnwrap(chat.backend.context)
        let tableIDs = context.itemIDs.filter { context.message(for: $0)?.role == .assistant }
        for width: CGFloat in [402, 874, 402] {
            chat.window.frame.size = CGSize(width: width, height: width == 402 ? 874 : 402)
            try await chat.waitForStableLayout()
            for tableIndex in [0, 10, 18, 0] {
                let item = try XCTUnwrap(context.itemIDs.firstIndex(of: tableIDs[tableIndex]))
                let indexPath = IndexPath(item: item, section: 0)
                chat.collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
                try await chat.waitForStableLayout()
                let cell = try XCTUnwrap(chat.collectionView.cellForItem(at: indexPath) as? AgentMessageCell)
                let table = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentRichMessageView }.first)
                XCTAssertFalse(table.isHidden)
                XCTAssertGreaterThan(table.bounds.width, 200)
                XCTAssertLessThanOrEqual(table.bounds.width, 512)
                XCTAssertEqual(cell.bounds.width, chat.collectionView.bounds.width, accuracy: 1)
            }
        }
    }

    func testScrollToLatestSettlesOffscreenTableHeight() async throws {
        let chat = try await makeChat(tableHistory: true)
        var reply = try await chat.sendAndStartReply()
        chat.collectionView.contentOffset.y -= 1_500
        try await chat.waitForStableLayout()
        reply.text = Self.longTable
        reply.answerBlocks = AgentMessageBlockParser.parse(reply.text)
        reply.isStreaming = false
        reply.controls = [AgentMessageControl(id: "followup:table", title: "Explain these assets", isEnabled: true, kind: .followup)]
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        chat.controller.scrollToTop(animated: true)
        try await Task.sleep(for: .milliseconds(700))
        try await chat.waitForStableLayout()
        let replyIndex = try XCTUnwrap(chat.backend.context?.itemIDs.firstIndex(of: reply.id))
        let frame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: IndexPath(item: replyIndex, section: 0))).frame
        let visibleBottom = chat.collectionView.contentOffset.y + chat.collectionView.bounds.height - chat.controller.occlusionBottomInset
        XCTAssertEqual(frame.maxY, visibleBottom, accuracy: 1)
    }

    func testStructuredTableCompletionShowsFollowupsWithoutMovingQuestion() async throws {
        let chat = try await makeChat()
        var reply = try await chat.sendAndStartReply()
        let questionY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1))
        reply.text = "Here are the assets.\n\n| Token | Balance |\n| --- | --- |\n| TON | 10 |"
        reply.answerBlocks = AgentMessageBlockParser.parse(reply.text)
        reply.isStreaming = false
        reply.controls = [AgentMessageControl(id: "followup:table", title: "Explain these assets", isEnabled: true, kind: .followup)]
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
        let suggestions = descendants(of: chat.collectionView).compactMap { $0 as? AgentSuggestionButton }
        let suggestion = try XCTUnwrap(suggestions.first { $0.accessibilityLabel == "Explain these assets" })
        var ancestor: UIView? = suggestion
        while let view = ancestor, view !== chat.collectionView {
            XCTAssertFalse(view.isHidden)
            ancestor = view.superview
        }
        let replyCell = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.max { $0.frame.minY < $1.frame.minY })
        XCTAssertFalse(replyCell.isRevealingStreamedText)
    }

    /// A suggestion under an answer streamed in the chat turns into its question's bubble when tapped, as one in a
    /// loaded chat does, and so does one under the answer to that question: the cell the finished answer updates keeps
    /// the tap that starts the morph
    func testSuggestionsOfStreamedAnswersMorphIntoTheirQuestions() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the bubble at once")
        let chat = try await makeChat()
        var reply = try await chat.sendAndStartReply()
        for (index, title) in ["What happens next?", "And after that?"].enumerated() {
            reply.text = "Here is the news \(index)"
            reply.isStreaming = false
            reply.controls = [AgentMessageControl(id: "followup:\(index)", title: title, isEnabled: true, kind: .followup)]
            chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
            let replyID = reply.id
            let replyCell = try XCTUnwrap(
                chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first { $0.messageID == replyID }
            )
            try await chat.waitUntil { _ in replyCell.getFollowupButton(controlID: "followup:\(index)") != nil }
            try await chat.waitForStableLayout()
            let button = try XCTUnwrap(replyCell.getFollowupButton(controlID: "followup:\(index)"))
            let sentCount = chat.backend.sentTexts.count

            XCTAssertFalse(replyCell.bubbleBackgroundView.showsTail, "\(title): the suggestions hang in place of the tail")
            button.sendActions(for: .touchUpInside)
            // The suggestions go, and the answer's tail grows back out of its corner rather than being set at once
            let answerBubble = replyCell.bubbleBackgroundView
            try await chat.waitUntil { _ in answerBubble.showsTail }
            XCTAssertTrue(answerBubble.isTailMorphing, "\(title): the answer's tail grows back")
            XCTAssertEqual(chat.backend.sentTexts.count, sentCount + 1)
            XCTAssertEqual(chat.backend.sentTexts.last, title)
            let morph = try XCTUnwrap(chat.controller.suggestionMorph, "\(title): the suggestion turns into its question")
            XCTAssertFalse(morph.isFinished)
            XCTAssertTrue(morph.morphView.superview === chat.controller.view)
            try await chat.waitUntil { _ in morph.isFinished }
            let question = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first {
                guard let id = $0.messageID, case .message(let message)? = chat.model.item(for: id) else { return false }
                return message.role == .user && message.text == title
            })
            XCTAssertEqual(question.sentAppearanceView.alpha, 1, "\(title): the bubble shows once the morph ends")
            reply = try await chat.startReply()
        }
    }

    /// The Agent finishing while the app is in the background takes its thinking visuals with it: back in the
    /// foreground, no glow and no typing row remain, and the answer shows as it is
    func testThinkingVisualsGoWhenTheAnswerEndsInTheBackground() async throws {
        let chat = try await makeChat()
        let center = NotificationCenter.default
        defer { center.post(name: UIApplication.didBecomeActiveNotification, object: nil) }
        try await chat.sendAndWaitForTypingIndicator()
        let glow = chat.controller.thinkingGlowView
        XCTAssertTrue(glow.isGlowing)

        // Kingfisher's image cache, which other tests set up, cleans its disk in a background task on this notification,
        // which can crash the test runner
        center.removeObserver(ImageCache.default, name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        // The answer comes and ends while the app is away, which stays away longer than any fade
        let typingID = try XCTUnwrap(chat.backend.typingIndicatorID)
        let answer = AgentMessage(role: .assistant, text: "The answer, complete", isStreaming: false)
        chat.backend.context?.replaceItem(id: typingID, with: .message(answer), animated: true)
        try await Task.sleep(for: .milliseconds(600))
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertFalse(glow.isGlowing)
        XCTAssertFalse(glow.isShown, "No glow stays on the screen's edge")
        chat.layout()
        XCTAssertFalse(chat.hasTypingIndicator, "Nor the typing row")
        try await chat.waitUntil { chat in
            chat.collectionView.visibleCells.contains { ($0 as? AgentMessageCell)?.messageID == answer.id }
        }
    }

    /// A Stop while the Agent thinks, before any of its answer has come, takes the typing row's status away at once,
    /// grows the row's top as a press does, over the content around it, and knocks it and the chat's large top as a
    /// failure does; the row stays a moment with its top grown, the top then shrinks back and the row goes as the run's
    /// end has it go. With Reduce Motion nothing grows or is knocked: the status and the row fade. A Stop once the
    /// answer is being written knocks neither top.
    func testStopWhileThinkingKnocksTheTopsAndAStopWhileWritingDoesNot() async throws {
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        func findTops(in view: UIView) -> [AgentSpinningTopView] {
            view.subviews.flatMap { ([$0 as? AgentSpinningTopView].compactMap { $0 }) + findTops(in: $0) }
        }

        let thinking = try await makeChat()
        try await thinking.sendAndWaitForTypingIndicator()
        let typingID = try XCTUnwrap(thinking.backend.typingIndicatorID)
        let typingRow = try XCTUnwrap(thinking.collectionView.visibleCells.compactMap { $0 as? AgentTypingIndicatorCell }.first)
        let rowTop = typingRow.topView
        let status = try XCTUnwrap(descendants(of: typingRow).compactMap { $0 as? AgentGradientLabel }.first)
        let largeTop = try XCTUnwrap(findTops(in: thinking.controller.view).first { $0.showsGround })
        XCTAssertFalse(rowTop.isRecoveringFromKnock)
        XCTAssertFalse(largeTop.isRecoveringFromKnock)
        XCTAssertEqual(status.alpha, 1)
        thinking.controller.composerView.onStop?()
        // The run's end takes the row out
        thinking.backend.context?.removeItem(id: typingID, animated: true)
        XCTAssertEqual(rowTop.isRecoveringFromKnock, !isMotionReduced, "The typing row's top")
        XCTAssertEqual(largeTop.isRecoveringFromKnock, !isMotionReduced, "The large top")
        XCTAssertFalse(thinking.controller.thinkingGlowView.isGlowing, "The rest of the chat ends at once")
        XCTAssertEqual(status.alpha, 0, "The status goes at once")
        XCTAssertEqual(rowTop.isOverContent, !isMotionReduced, "The grown top is drawn over the content around it")

        // Frame by frame from the Stop: the top grows from its size without a frame at the grown size first, reaches the
        // held size, eases back to its own size, never under it, and fades away with the row over a visible moment
        var scales: [CGFloat] = []
        var staleFrames = 0
        var scaleWhenTheRowStartedLeaving: CGFloat?
        var wasOverContentWhenTheRowStartedLeaving = false
        var exitOpacities: [(time: CFTimeInterval, opacity: Float)] = []
        var didBlurAway = false
        let stopTime = CACurrentMediaTime()
        var statusOpacityAfterItsFade: Float?
        // The top stays where it shows from the Stop until it has faded, lifted over the content or back in its row
        var largestDrift: CGFloat = 0
        for _ in 0..<400 where thinking.hasTypingIndicatorItem {
            scales.append(rowTop.shownScale)
            if let shown = rowTop.shownRestingCenterInWindow, rowTop.window != nil {
                let place = rowTop.convert(CGPoint(x: rowTop.bounds.midX, y: rowTop.bounds.midY), to: nil)
                largestDrift = max(largestDrift, hypot(shown.x - place.x, shown.y - place.y))
            }
            if statusOpacityAfterItsFade == nil,
               // With room for the fade's start waiting on a busy main thread
               CACurrentMediaTime() - stopTime > AgentTypingIndicatorCell.stoppedStatusFadeDuration + 0.25 {
                statusOpacityAfterItsFade = status.layer.presentation()?.opacity ?? 0
            }
            if !rowTop.isShowingImageAtItsSize { staleFrames += 1 }
            let rowLayer = typingRow.contentView.layer
            // The exit leaves the row transparent, unlike its entrance, which can still be playing at the Stop
            if rowLayer.animation(forKey: "agentBlurTransition") != nil, rowLayer.opacity == 0 {
                if !didBlurAway {
                    didBlurAway = true
                    scaleWhenTheRowStartedLeaving = rowTop.shownScale
                    wasOverContentWhenTheRowStartedLeaving = rowTop.isOverContent
                }
                exitOpacities.append((CACurrentMediaTime(), rowLayer.presentation()?.opacity ?? 0))
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        XCTAssertFalse(thinking.hasTypingIndicatorItem, "The row leaves")
        XCTAssertTrue(didBlurAway, isMotionReduced ? "The row fades" : "The row blurs away")
        XCTAssertLessThan(try XCTUnwrap(statusOpacityAfterItsFade), 0.01, "The status is gone after a quick fade")
        XCTAssertEqual(staleFrames, 0, "No frame shows the top's previous image stretched to a new canvas")
        XCTAssertLessThan(largestDrift, 2, "The top stays where it shows until it has faded")
        if isMotionReduced {
            XCTAssertTrue(scales.allSatisfy { abs($0 - 1) < 0.01 }, "Nothing grows with Reduce Motion")
        } else {
            let holdScale = try XCTUnwrap(scales.max())
            XCTAssertGreaterThan(holdScale, 2.9, "The top grows to a held top's size")
            XCTAssertLessThanOrEqual(try XCTUnwrap(scales.first), 1.01, "No first frame above its starting size")
            let rise = scales.prefix { $0 < holdScale * 0.98 }
            XCTAssertTrue(zip(rise, rise.dropFirst()).allSatisfy { $1 >= $0 - 0.001 }, "A steady rise to the held size")
            let afterPeak = scales.drop { $0 < holdScale }
            XCTAssertGreaterThan(try XCTUnwrap(afterPeak.min()), 0.99, "Back to its size, never under it")
            XCTAssertEqual(try XCTUnwrap(scaleWhenTheRowStartedLeaving), 1, accuracy: 0.05, "Back to its size before the row goes")
            XCTAssertFalse(wasOverContentWhenTheRowStartedLeaving, "Back in its place in the row")
        }
        let fading = exitOpacities.filter { $0.opacity < 0.99 }
        // The ease-in fade drops fastest at its end, often from above 0.01 to gone between two samples; it passes 0.2
        // about 0.26 s in
        if let first = fading.first, let gone = fading.first(where: { $0.opacity < 0.2 }) {
            XCTAssertGreaterThanOrEqual(gone.time - first.time, 0.2, "The row and its top fade over a visible moment")
        } else {
            XCTFail("The fade wasn't sampled")
        }
        thinking.close()

        let writing = try await makeChat()
        _ = try await writing.sendAndStartReply()
        let writingLargeTop = try XCTUnwrap(findTops(in: writing.controller.view).first { $0.showsGround })
        writing.controller.composerView.onStop?()
        XCTAssertFalse(writingLargeTop.isRecoveringFromKnock, "A Stop while the answer is written only eases the top back")
        let rowTops = writing.collectionView.visibleCells.compactMap { $0 as? AgentTypingIndicatorCell }.flatMap(findTops(in:))
        XCTAssertFalse(rowTops.contains { $0.isRecoveringFromKnock })
        writing.close()
    }

    /// A new question during the moment the stopped typing row stays takes the row away at once
    func testNewQuestionTakesTheStoppedTypingRowAwayAtOnce() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "With Reduce Motion the row goes at once anyway")
        let chat = try await makeChat()
        try await chat.sendAndWaitForTypingIndicator()
        let typingID = try XCTUnwrap(chat.backend.typingIndicatorID)
        chat.controller.composerView.onStop?()
        chat.backend.context?.removeItem(id: typingID, animated: true)
        XCTAssertTrue(chat.controller.model.itemIDs.contains(typingID), "Held for the knock")
        chat.backend.context?.sendMessage("And now?", source: .composer)
        XCTAssertFalse(chat.controller.model.itemIDs.contains(typingID), "Gone with the new question")
        chat.close()
    }

    /// The typing row a Stop keeps for its top leaves without moving anything above it: frame by frame, through its
    /// moment on screen, its blur-away and its removal, the bubbles stay exactly where they show, in a short chat whose
    /// question stands under the header with room reserved under it as in a long one
    func testStoppedTypingRowLeavesWithoutMovingTheBubblesAbove() async throws {
        for historyCount in [1, 12] {
            let chat = try await makeChat(historyCount: historyCount)
            try await chat.sendAndWaitForTypingIndicator()
            let typingID = try XCTUnwrap(chat.backend.typingIndicatorID)
            func getBubbleTops() -> [AgentItemID: CGFloat] {
                var tops: [AgentItemID: CGFloat] = [:]
                for cell in chat.collectionView.visibleCells.compactMap({ $0 as? AgentMessageCell }) {
                    guard let id = cell.messageID else { continue }
                    tops[id] = chat.presentedScreenMinY(of: cell)
                }
                return tops
            }
            let before = getBubbleTops()
            XCTAssertGreaterThanOrEqual(before.count, 1)
            chat.controller.composerView.onStop?()
            chat.backend.context?.removeItem(id: typingID, animated: true)

            var worstShift: CGFloat = 0
            var samplesAfterRemoval = 0
            var sampleCount = 0
            // Through the removal's animation and a little after it
            while samplesAfterRemoval < 30, sampleCount < 400 {
                try await Task.sleep(for: .milliseconds(8))
                sampleCount += 1
                if !chat.hasTypingIndicatorItem { samplesAfterRemoval += 1 }
                for (id, top) in getBubbleTops() {
                    guard let original = before[id] else { continue }
                    worstShift = max(worstShift, abs(top - original))
                }
            }
            XCTAssertFalse(chat.hasTypingIndicatorItem, "\(historyCount) messages: the row leaves")
            XCTAssertLessThan(worstShift, 0.5, "\(historyCount) messages: the bubbles above stay where they show")
            chat.close()
        }
    }

    /// The answer that takes the typing row's place shows only through the row's morph: the pass that puts the answer
    /// in the list hands it to the morph, so the first frame after it shows the answer's bubble still faded out within
    /// the row's frame, never the answer whole before the morph. The morph starts where the row showed on screen, also
    /// as a row above grows in that pass and the list scrolls to keep the question in place.
    func testAnswerTakingTheTypingRowsPlaceShowsOnlyThroughItsMorph() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion cross-fades the answer in")
        let chat = try await makeChat()
        chat.controller.additionalSafeAreaInsets.bottom = 300
        try await chat.waitForStableLayout()
        try await chat.sendAndWaitForTypingIndicator()
        // The row's picture needs it drawn once
        try await Task.sleep(for: .milliseconds(100))
        let typingID = try XCTUnwrap(chat.backend.typingIndicatorID)
        let typingRow = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentTypingIndicatorCell }.first)
        // The row's last frame on screen
        let lastFrame = try XCTUnwrap(typingRow.makeAnswerMorphSource(in: chat.window))
        // The message above the question grows in the answer's pass, which moves the rows under it in the list
        let context = try XCTUnwrap(chat.backend.context)
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        let previousIndex = IndexPath(item: questionIndex - 1, section: 0)
        if let previous = chat.collectionView.cellForItem(at: previousIndex) as? AgentMessageCell {
            let grownHeight = previous.bounds.height + 120
            previous.minimumHeightProvider = { grownHeight }
            let invalidation = UICollectionViewLayoutInvalidationContext()
            invalidation.invalidateItems(at: [previousIndex])
            chat.collectionView.collectionViewLayout.invalidateLayout(with: invalidation)
        }
        let answer = AgentMessage(role: .assistant, text: "Here is", isStreaming: true)
        chat.backend.context?.replaceItem(id: typingID, with: .message(answer), animated: true)

        // Still in the pass that put the answer in the list
        let morph = try XCTUnwrap(chat.controller.typingAnswerMorph, "The morph takes the answer over in the same pass")
        XCTAssertEqual(morph.pictures.count, 2)
        for (picture, frame) in zip(morph.pictures, [lastFrame.topFrame, lastFrame.statusFrame]) {
            // Where the picture stands, before the transform it animates by
            let placed = CGRect(
                x: picture.center.x - picture.bounds.width / 2,
                y: picture.center.y - picture.bounds.height / 2,
                width: picture.bounds.width,
                height: picture.bounds.height
            )
            let shown = try XCTUnwrap(picture.superview).convert(placed, to: chat.window)
            XCTAssertEqual(shown.minX, frame.minX, accuracy: 1, "The morph starts where the row showed")
            XCTAssertEqual(shown.minY, frame.minY, accuracy: 1)
        }
        let indexPath = try XCTUnwrap(chat.controller.messageIndexPath(for: answer.id))
        let cell = try XCTUnwrap(chat.collectionView.cellForItem(at: indexPath) as? AgentMessageCell)
        let bubble = cell.bubbleBackgroundView
        XCTAssertNotNil(bubble.layer.mask, "Within the row's frame")
        XCTAssertNotNil(bubble.layer.animation(forKey: AgentTypingAnswerMorph.bubbleFadeKey))
        // The first frame after it
        CATransaction.flush()
        XCTAssertEqual(bubble.layer.presentation()?.opacity ?? 1, 0, accuracy: 0.1, "Not shown before the morph")
        XCTAssertNotNil(chat.controller.typingAnswerMorph)
    }

    func testShrinkingHistoryDoesNotLeaveAnAnimatedScrollCorrection() async throws {
        let chat = try await makeChat()
        chat.controller.additionalSafeAreaInsets.bottom = 300
        try await chat.waitForStableLayout()
        try await chat.sendAndWaitForTypingIndicator()
        let context = try XCTUnwrap(chat.backend.context)
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        let previousIndex = IndexPath(item: questionIndex - 1, section: 0)
        let cell = try XCTUnwrap(chat.collectionView.cellForItem(at: previousIndex) as? AgentMessageCell)
        let originalHeight = cell.bounds.height
        let questionIndexPath = IndexPath(item: questionIndex, section: 0)
        func questionY() throws -> CGFloat {
            try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: questionIndexPath)).frame.maxY
                - chat.collectionView.contentOffset.y
        }
        let expectedY = try questionY()
        for height in [originalHeight + 500, originalHeight] {
            cell.minimumHeightProvider = { height }
            let invalidation = UICollectionViewLayoutInvalidationContext()
            invalidation.invalidateItems(at: [previousIndex])
            chat.collectionView.collectionViewLayout.invalidateLayout(with: invalidation)
            try await chat.waitForStableLayout()
            XCTAssertEqual(try questionY(), expectedY, accuracy: 1)
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(try questionY(), expectedY, accuracy: 1)
        }
    }

    func testRepeatedSendsAfterWideTableKeepQuestionVisible() async throws {
        let table = "Here are the assets in your wallet.\n\n"
            + "| Asset | Network | Amount | Value |\n| --- | --- | --- | --- |\n"
            + (0..<100).map { "| Token \($0) | ethereum | 123456789.012345678 | $1234.56 |" }.joined(separator: "\n")
            + "\n\nSome assets do not have a price."
        let chat = try await makeChat(historyCount: 4, historyTexts: ["Show my assets", Self.longTable, "Show all accounts", table])
        let context = try XCTUnwrap(chat.backend.context)

        for _ in 0..<3 {
            try await chat.sendAndWaitForTypingIndicator()
            let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
            let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
            func questionY() throws -> CGFloat {
                try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: IndexPath(item: questionIndex, section: 0)))
                    .frame.maxY - chat.collectionView.contentOffset.y
            }
            let expectedY = chat.collectionView.adjustedContentInset.top + 100
            XCTAssertEqual(try questionY(), expectedY, accuracy: 1)
            for status in ["Checking wallet…", "Reading assets…", "Preparing answer…"] {
                chat.backend.typingIndicatorStatusText = status
                context.notifyStateChanged()
                try await chat.waitForStableLayout()
                XCTAssertEqual(try questionY(), expectedY, accuracy: 1)
            }
            var reply = try await chat.startReply()
            reply.text = "The wallet contains several assets without a price."
            reply.isStreaming = false
            reply.controls = [AgentMessageControl(id: "followup:0", title: "Tell me more about these assets", isEnabled: true, kind: .followup)]
            context.updateMessage(reply, animated: false, scrollToBottom: false)
            try await chat.waitForStableLayout()
            XCTAssertEqual(try questionY(), expectedY, accuracy: 1)
        }
    }

    func testLayoutDoesNotClampUnchangedBottomOverscroll() async throws {
        let chat = try await makeChat()
        _ = try await chat.sendAndStartReply()
        let offset = chat.maxContentOffsetY + 40
        chat.collectionView.contentOffset.y = offset
        chat.collectionView.setNeedsLayout()
        chat.collectionView.layoutIfNeeded()
        XCTAssertEqual(chat.collectionView.contentOffset.y, offset, accuracy: 1)
    }

    func testUnchangedTypingStatusDoesNotRemeasureMessages() async throws {
        let chat = try await makeChat(tableHistory: true)
        try await chat.sendAndWaitForTypingIndicator()
        var fittingCount = 0
        for cell in chat.collectionView.visibleCells.compactMap({ $0 as? AgentMessageCell }) {
            cell.minimumHeightProvider = { fittingCount += 1; return 0 }
        }
        for _ in 0..<10 {
            chat.backend.context?.notifyStateChanged()
        }
        XCTAssertEqual(fittingCount, 0)
    }

    func testScrollingSettledConversationDoesNotScanHistory() async throws {
        let chat = try await makeChat(historyCount: 200)
        var reply = try await chat.sendAndStartReply()
        reply.isStreaming = false
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        chat.model.itemReadCount = 0
        for _ in 0..<10 {
            chat.collectionView.contentOffset.y -= 1
            chat.collectionView.layoutIfNeeded()
        }

        XCTAssertLessThan(chat.model.itemReadCount, 100, "Scrolling should only inspect visible rows, not the full conversation")
    }

    func testStreamingChunksWaitForVisibleHeightChangesBeforeResizingRows() async throws {
        let chat = try await makeChat()
        var reply = try await chat.sendAndStartReply()
        reply.text = String(repeating: "Gram and TON network news for the last two days. ", count: 8)
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        let replyCell = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }
            .max { $0.frame.minY < $1.frame.minY })
        let heightBefore = replyCell.bounds.height
        var fittingCount = 0
        replyCell.minimumHeightProvider = { fittingCount += 1; return 0 }

        // Receive several chunks before the next reveal tick. Their text is not visible yet.
        for _ in 0..<10 {
            reply.text += " More news."
            chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        }
        XCTAssertEqual(fittingCount, 0)

        try await chat.waitUntil { _ in replyCell.bounds.height > heightBefore + 20 }
        XCTAssertGreaterThan(fittingCount, 0, "The row must still resize as the new lines become visible")
    }

    func testScrollingWhileReplyRetainsReserveSlackDoesNotScanHistory() async throws {
        let chat = try await makeChat(historyCount: 200)
        let reply = try await chat.sendAndStartReply()
        let reserveBefore = chat.reserveSpaceHeight
        chat.stream(reply, repeating: 2)
        try await chat.waitForStableLayout()
        XCTAssertEqual(chat.reserveSpaceHeight, reserveBefore, accuracy: 1)

        chat.model.itemReadCount = 0
        for _ in 0..<10 {
            chat.collectionView.contentOffset.y -= 1
            chat.collectionView.layoutIfNeeded()
        }
        XCTAssertLessThan(chat.model.itemReadCount, 100)
    }

    func testOffscreenStreamingChunksAppearWhenReturningToReply() async throws {
        let chat = try await makeChat(historyCount: 200)
        var reply = try await chat.sendAndStartReply()
        let replyIndex = try XCTUnwrap(chat.backend.context?.itemIDs.firstIndex(of: reply.id))
        let replyIndexPath = IndexPath(item: replyIndex, section: 0)
        chat.collectionView.contentOffset.y -= 1_500
        try await chat.waitForStableLayout()
        XCTAssertFalse(chat.collectionView.indexPathsForVisibleItems.contains(replyIndexPath))
        let offsetBefore = chat.collectionView.contentOffset.y
        chat.model.itemReadCount = 0

        for _ in 0..<10 {
            reply.text += " More news from the TON network."
            chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        }
        try await chat.waitForStableLayout()
        XCTAssertLessThan(chat.model.itemReadCount, 100)
        XCTAssertEqual(chat.collectionView.contentOffset.y, offsetBefore, accuracy: 1)

        chat.collectionView.scrollToItem(at: replyIndexPath, at: .top, animated: false)
        try await chat.waitForStableLayout()
        let replyCell = try XCTUnwrap(chat.collectionView.cellForItem(at: replyIndexPath))
        let textView = try XCTUnwrap(descendants(of: replyCell).compactMap { $0 as? AgentStreamingTextView }.first)
        XCTAssertEqual(textView.displayText, reply.text)
    }

    func testReplyCompletionWithCoveredBottomAreaPreservesQuestion() async throws {
        try await checkReplyCompletionPreservesQuestion(coveredHeight: 300, dismissesCoveredArea: false)
    }

    func testReplyCompletionAfterCoveredBottomAreaShrinksPreservesQuestion() async throws {
        try await checkReplyCompletionPreservesQuestion(coveredHeight: 300, dismissesCoveredArea: true)
    }

    private func checkReplyCompletionPreservesQuestion(coveredHeight: CGFloat, dismissesCoveredArea: Bool) async throws {
        let chat = try await makeChat(tableHistory: true)
        chat.controller.additionalSafeAreaInsets.bottom = coveredHeight
        try await chat.waitForStableLayout()
        var reply = try await chat.sendAndStartReply()
        let context = try XCTUnwrap(chat.backend.context)
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let index = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        func questionY() throws -> CGFloat {
            try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
                .frame.maxY - chat.collectionView.contentOffset.y
        }
        let targetY = chat.collectionView.adjustedContentInset.top + 100
        XCTAssertEqual(try questionY(), targetY, accuracy: 1)
        reply.text = Self.longTable
        context.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        if dismissesCoveredArea {
            chat.controller.additionalSafeAreaInsets.bottom = 0
            try await chat.waitForStableLayout()
            XCTAssertEqual(try questionY(), targetY, accuracy: 1)
        }
        reply.isStreaming = false
        reply.controls = (0..<3).map {
            AgentMessageControl(id: "followup:\($0)", title: "Tell me more about token \($0)", isEnabled: true, kind: .followup)
        }
        context.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try questionY(), targetY, accuracy: 1)
    }

    func testDeferredSelfSizingAboveQuestionPreservesPosition() async throws {
        let chat = try await makeChat()
        try await chat.sendAndWaitForTypingIndicator()
        let context = try XCTUnwrap(chat.backend.context)
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        let previousIndexPath = IndexPath(item: questionIndex - 1, section: 0)
        let cell = try XCTUnwrap(chat.collectionView.cellForItem(at: previousIndexPath) as? AgentMessageCell)
        let previousHeight = cell.bounds.height
        let before = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: IndexPath(item: questionIndex, section: 0)))
            .frame.maxY - chat.collectionView.contentOffset.y

        cell.minimumHeightProvider = { previousHeight + 500 }
        let invalidation = UICollectionViewLayoutInvalidationContext()
        invalidation.invalidateItems(at: [previousIndexPath])
        chat.collectionView.collectionViewLayout.invalidateLayout(with: invalidation)
        try await chat.waitForStableLayout()

        let after = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: IndexPath(item: questionIndex, section: 0)))
            .frame.maxY - chat.collectionView.contentOffset.y
        XCTAssertEqual(after, before, accuracy: 1)
    }

    func testLongTableHistoryKeepsSentQuestionInPlace() async throws {
        let chat = try await makeChat(tableHistory: true)
        try await chat.sendAndWaitForTypingIndicator()
        let context = try XCTUnwrap(chat.backend.context)
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        func questionY() throws -> CGFloat {
            let index = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
            return try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
                .frame.maxY - chat.collectionView.contentOffset.y
        }
        let targetY = chat.collectionView.adjustedContentInset.top + 100
        XCTAssertEqual(try questionY(), targetY, accuracy: 1)

        var reply = try await chat.startReply()
        XCTAssertEqual(try questionY(), targetY, accuracy: 1)
        reply.text = Self.longTable
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        reply.isStreaming = false
        reply.controls = [AgentMessageControl(id: "followup:0", title: "Tell me more", isEnabled: true, kind: .followup)]
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try questionY(), targetY, accuracy: 1)
    }

    private static var longTable: String {
        "| Asset | Network | Balance |\n| --- | --- | --- |\n"
            + (0..<30).map { "| Token \($0) | TON | 123.45 |" }.joined(separator: "\n")
    }

    func testHistoryRemeasuredAboveTheQuestionDoesNotMoveIt() async throws {
        let chat = try await makeChat()
        let context = try XCTUnwrap(chat.backend.context)
        let previousReplyID = try XCTUnwrap(context.itemIDs.last)
        var previousReply = try XCTUnwrap(context.message(for: previousReplyID))
        try await chat.sendAndWaitForTypingIndicator()
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        func questionY() throws -> CGFloat {
            let frame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: IndexPath(item: questionIndex, section: 0))).frame
            return frame.maxY - chat.collectionView.contentOffset.y
        }
        let initialY = try questionY()

        previousReply.text = String(repeating: "An older answer now has additional content. ", count: 30)
        context.updateMessage(previousReply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        XCTAssertEqual(try questionY(), initialY, accuracy: 1)
    }

    func testTableBubbleKeepsReadableWidthAfterReuse() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 76))
        for _ in 0..<2 {
            cell.configure(with: AgentMessage(role: .assistant, text: "Hi", isStreaming: false), onURLTap: { _ in })
            cell.layoutIfNeeded()
            cell.prepareForReuse()
            let message = AgentMessage(role: .assistant, text: """
            Here are the assets in this wallet, grouped by network and balance.

            | Asset | Network | Balance |
            | --- | --- | --- |
            | TON | TON | 123.45 |
            | USDT | TRON | 50.00 |
            """, isStreaming: false)
            cell.configure(with: message, onURLTap: { _ in })
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            attributes.size = CGSize(width: 402, height: 76)
            cell.frame.size = cell.preferredLayoutAttributesFitting(attributes).size
            cell.layoutIfNeeded()

            let richView = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentRichMessageView }.first)
            XCTAssertGreaterThan(richView.bounds.width, 200)
            XCTAssertLessThan(cell.bounds.height, 400)
            cell.prepareForReuse()
        }
    }

    func testInitialStreamingHistoryShowsTheLatestMessage() async throws {
        let chat = try await makeChat(historyArrivesOnScreen: true, streamingHistory: true, scrollsToBottom: false)
        let lastMessage = IndexPath(item: chat.collectionView.numberOfItems(inSection: 0) - 2, section: 0)
        let frame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: lastMessage)).frame
        let visibleBottom = chat.collectionView.contentOffset.y + chat.collectionView.bounds.height
            - chat.controller.occlusionBottomInset

        XCTAssertTrue(chat.collectionView.indexPathsForVisibleItems.contains(lastMessage))
        // Its text may continue growing below the viewport after the initial scroll.
        XCTAssertGreaterThanOrEqual(frame.minY, chat.collectionView.contentOffset.y + chat.collectionView.adjustedContentInset.top)
        XCTAssertLessThan(frame.minY, visibleBottom)
    }

    /// A tall question under an answer stops with the answer's last line in sight above it, whole with the bubble's
    /// padding under it
    func testComposerSendPinsQuestionAfterClearingMultilineDraft() async throws {
        let chat = try await makeChat()
        chat.composer.setDraftText((1...6).map(String.init).joined(separator: "\n"), focus: false)
        try await chat.waitForStableLayout()

        chat.composer.onSend?()
        try await chat.waitUntil { $0.hasTypingIndicator }
        try await chat.waitForStableLayout()

        XCTAssertEqual(try getPreviousAnswerLastLineTop(in: chat), chat.collectionView.adjustedContentInset.top, accuracy: 1)
        XCTAssertGreaterThan(try questionBubbleFrame(in: chat).minY, chat.collectionView.adjustedContentInset.top + 16)
    }

    func testComposerSendPinsSingleLineQuestionAtTail() async throws {
        let chat = try await makeChat()
        chat.composer.setDraftText("Tell me the news", focus: false)
        try await chat.waitForStableLayout()

        chat.composer.onSend?()
        try await chat.waitUntil { $0.hasTypingIndicator }
        try await chat.waitForStableLayout()

        XCTAssertEqual(
            try questionBubbleFrame(in: chat).maxY,
            chat.collectionView.adjustedContentInset.top + 100,
            accuracy: 1
        )
    }

    func testComposerSendPinsTallQuestionAtTopWhenReplyStartsStreaming() async throws {
        let chat = try await makeChat()
        chat.composer.setDraftText((1...12).map { "Question line \($0)" }.joined(separator: "\n"), focus: false)
        try await chat.waitForStableLayout()

        chat.composer.onSend?()
        try await chat.waitUntil { $0.hasTypingIndicator }
        try await chat.waitForStableLayout()

        let questionY = try questionBubbleFrame(in: chat).minY
        XCTAssertEqual(try getPreviousAnswerLastLineTop(in: chat), chat.collectionView.adjustedContentInset.top, accuracy: 1)

        let reply = try await chat.startReply()
        XCTAssertEqual(try questionBubbleFrame(in: chat).minY, questionY, accuracy: 1)
        chat.stream(reply, repeating: 4)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try questionBubbleFrame(in: chat).minY, questionY, accuracy: 1)
    }

    func testNavigationBarBackgroundFadesMessagesUnderTheHeader() async throws {
        let chat = try await makeChat()
        let view = try XCTUnwrap(chat.controller.view)
        let background = try XCTUnwrap(view.subviews.first { $0.frame.minY < view.bounds.minY })
        let backgroundIndex = try XCTUnwrap(view.subviews.firstIndex { $0 === background })
        let collectionIndex = try XCTUnwrap(view.subviews.firstIndex { $0 === chat.collectionView })
        XCTAssertGreaterThan(backgroundIndex, collectionIndex)

        for style: UIUserInterfaceStyle in [.light, .dark] {
            chat.window.overrideUserInterfaceStyle = style
            try await chat.waitForStableLayout()
            let headerBottom = view.safeAreaLayoutGuide.layoutFrame.minY
            XCTAssertFalse(background.isHidden)
            XCTAssertFalse(background.isUserInteractionEnabled)
            XCTAssertEqual(background.frame.minY, view.bounds.minY - 20, accuracy: 1)
            XCTAssertEqual(background.frame.minX, view.bounds.minX, accuracy: 1)
            XCTAssertEqual(background.frame.maxX, view.bounds.maxX, accuracy: 1)
            // The edge effect reaches a little below the header, so messages fade out instead of being cut off
            XCTAssertEqual(background.frame.maxY, headerBottom + 18, accuracy: 1)
            XCTAssertTrue(descendants(of: background).contains { $0 is EdgeEffectView })
            let appearance = try XCTUnwrap(chat.controller.navigationItem.standardAppearance)
            XCTAssertNil(appearance.backgroundEffect)
            XCTAssertEqual(appearance.backgroundColor?.cgColor.alpha ?? 0, 0)
            if #available(iOS 26.0, *) {
                XCTAssertTrue(chat.collectionView.topEdgeEffect.isHidden)
                XCTAssertTrue(chat.collectionView.bottomEdgeEffect.isHidden)
            }
        }
    }

    func testRootChatHasNoThreadsButton() async throws {
        let chat = try await makeChat()
        XCTAssertNil(chat.controller.navigationItem.leftBarButtonItem)
        XCTAssertFalse(chat.controller.navigationItem.hidesBackButton)
    }

    /// With the keyboard hidden, the field rests on the Agent list's field line: just inside the home indicator's
    /// safe area, or 16 pt above the bottom edge without one. Before iOS 17 the keyboard layout guide ends at the safe
    /// area, and the field has to rest below it all the same.
    func testFieldRestsOnTheAgentListFieldLineWithTheKeyboardHidden() async throws {
        let chat = try await makeChat(historyCount: 2)
        let navigation = try XCTUnwrap(chat.controller.navigationController)
        for additionalBottom: CGFloat in [0, 34] {
            navigation.additionalSafeAreaInsets.bottom = additionalBottom
            try await chat.waitForStableLayout()
            let safeAreaBottom = chat.controller.view.safeAreaInsets.bottom
            XCTAssertGreaterThanOrEqual(safeAreaBottom, additionalBottom)
            let field = chat.composer.convert(chat.composer.inputBackgroundFrame, to: chat.window)
            let fieldLine = chat.window.bounds.maxY - AgentComposerMetrics.getFieldBottomInset(safeAreaBottom: safeAreaBottom)
            XCTAssertEqual(field.maxY, fieldLine, accuracy: 0.5)
        }
    }

    func testMessagesScrollUnderComposerIntoTheBottomFade() async throws {
        let chat = try await makeChat(historyCount: 40)
        let view = try XCTUnwrap(chat.controller.view)
        let context = try XCTUnwrap(chat.backend.context)
        let questionIDs = context.itemIDs.filter { context.message(for: $0)?.role == .user }
        let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionIDs[questionIDs.count / 2]))
        let indexPath = IndexPath(item: questionIndex, section: 0)
        let collectionIndex = try XCTUnwrap(view.subviews.firstIndex { $0 === chat.collectionView })

        for style: UIUserInterfaceStyle in [.light, .dark] {
            chat.window.overrideUserInterfaceStyle = style
            chat.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            try await chat.waitForStableLayout()
            let cell = try XCTUnwrap(chat.collectionView.cellForItem(at: indexPath))
            let bubble = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentBubbleBackgroundView }.first)
            let inputFrame = chat.composer.convert(chat.composer.inputBackgroundFrame, to: view)
            let bubbleFrame = bubble.convert(bubble.bounds, to: view)
            chat.collectionView.contentOffset.y += bubbleFrame.midY - inputFrame.minY - 10
            try await chat.waitForStableLayout()

            let scrolledCell = try XCTUnwrap(chat.collectionView.cellForItem(at: indexPath))
            let scrolledBubble = try XCTUnwrap(descendants(of: scrolledCell).compactMap { $0 as? AgentBubbleBackgroundView }.first)
            let scrolledFrame = scrolledBubble.convert(scrolledBubble.bounds, to: view)
            XCTAssertLessThan(scrolledFrame.minY, inputFrame.minY)
            XCTAssertGreaterThan(scrolledFrame.maxY, inputFrame.minY)
            XCTAssertTrue(scrolledFrame.intersects(inputFrame))

            // Directly above the messages and below the composer, a blurred fade starts 28 pt above the field
            let fades = view.subviews.compactMap { $0 as? EdgeEffectView }
            XCTAssertEqual(fades.count, 1)
            let fade = try XCTUnwrap(fades.first)
            let fadeIndex = try XCTUnwrap(view.subviews.firstIndex { $0 === fade })
            let composerIndex = try XCTUnwrap(view.subviews.firstIndex { $0 === chat.composer })
            XCTAssertEqual(fadeIndex, collectionIndex + 1)
            XCTAssertLessThan(fadeIndex, composerIndex)
            XCTAssertFalse(fade.isUserInteractionEnabled)
            XCTAssertEqual(fade.frame.minY, inputFrame.minY - 28, accuracy: 1)
            XCTAssertEqual(fade.frame.maxY, view.bounds.maxY, accuracy: 1)
            XCTAssertEqual(fade.frame.minX, view.bounds.minX, accuracy: 1)
            XCTAssertEqual(fade.frame.maxX, view.bounds.maxX, accuracy: 1)

            let scrollToLatest = try XCTUnwrap(view.subviews.compactMap { $0 as? AgentScrollToBottomButton }.first)
            // As large as the composer's microphone circle
            let microphoneSize = AgentComposerMetrics.microphoneSize
            XCTAssertEqual(scrollToLatest.bounds.size, CGSize(width: microphoneSize, height: microphoneSize))
            XCTAssertEqual(scrollToLatest.center.y + scrollToLatest.bounds.height / 2, inputFrame.minY - 12, accuracy: 1)

            let coveredRegion = CGRect(
                x: view.bounds.minX,
                y: inputFrame.minY,
                width: view.bounds.width,
                height: view.bounds.maxY - inputFrame.minY
            )
            func checkLayer(_ layer: CALayer, inheritedOpacity: Float = 1, isMask: Bool = false) {
                let opacity = layer.isHidden ? 0 : inheritedOpacity * layer.opacity
                if layer.convert(layer.bounds, to: view.layer).intersects(coveredRegion) {
                    XCTAssertFalse(layer is CAGradientLayer)
                    if !isMask {
                        XCTAssertLessThan((layer.backgroundColor?.alpha ?? 0) * CGFloat(opacity), 1)
                    }
                }
                for sublayer in layer.sublayers ?? [] {
                    checkLayer(sublayer, inheritedOpacity: opacity, isMask: isMask)
                }
                if let mask = layer.mask {
                    checkLayer(mask, inheritedOpacity: opacity, isMask: true)
                }
            }
            // Apart from the fade, nothing opaque covers the messages under the composer
            for overlay in view.subviews.dropFirst(collectionIndex + 1) where overlay !== chat.composer && overlay !== fade {
                for subview in [overlay] + descendants(of: overlay)
                    where subview.convert(subview.bounds, to: view).intersects(coveredRegion) {
                    XCTAssertFalse(subview is EdgeEffectView || subview is UIVisualEffectView)
                }
                checkLayer(overlay.layer)
            }
        }
    }

    func testLoadedSingleTallQuestionOpensAtItsEnd() async throws {
        let chat = try await makeChat(historyCount: 0)
        let context = try XCTUnwrap(chat.backend.context)
        let question = AgentMessage(
            role: .user,
            text: (1...60).map { "Question line \($0)" }.joined(separator: "\n"),
            isStreaming: false
        )
        context.replaceTimeline(with: [.message(question)], animated: false)
        try await chat.waitForStableLayout()

        let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: question.id))
        let frame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(
            at: IndexPath(item: questionIndex, section: 0)
        )).frame
        let expectedOffsetY = frame.maxY - chat.collectionView.bounds.height + chat.controller.occlusionBottomInset
        XCTAssertGreaterThan(expectedOffsetY, -chat.collectionView.adjustedContentInset.top)
        XCTAssertEqual(chat.collectionView.contentOffset.y, expectedOffsetY, accuracy: 1)
    }

    func testFirstQuestionAndDateStayAtNaturalPositionWhenReplyStarts() async throws {
        for lineCount in [5, 60] {
            let chat = try await makeChat(historyCount: 0)
            let context = try XCTUnwrap(chat.backend.context)
            context.sendMessage((1...lineCount).map { "Question line \($0)" }.joined(separator: "\n"), source: .composer)
            chat.layout()
            let dateIndexPath = IndexPath(item: 0, section: 0)
            let questionIndexPath = IndexPath(item: 1, section: 0)
            let dateFrame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: dateIndexPath)).frame
            let questionFrame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: questionIndexPath)).frame
            let offsetY = chat.collectionView.contentOffset.y
            XCTAssertEqual(offsetY, -chat.collectionView.adjustedContentInset.top, accuracy: 1)
            XCTAssertEqual(dateFrame.minY - offsetY, chat.collectionView.adjustedContentInset.top + 16, accuracy: 1)

            try await chat.waitUntil { $0.hasTypingIndicatorItem }
            try await chat.waitForStableLayout()
            XCTAssertEqual(chat.collectionView.contentOffset.y, offsetY, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: dateIndexPath)).frame.minY
                - chat.collectionView.contentOffset.y, dateFrame.minY - offsetY, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: questionIndexPath)).frame.minY
                - chat.collectionView.contentOffset.y, questionFrame.minY - offsetY, accuracy: 1)

            let reply = try await chat.startReply()
            chat.stream(reply, repeating: 4)
            try await chat.waitForStableLayout()
            XCTAssertEqual(chat.collectionView.contentOffset.y, offsetY, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: dateIndexPath)).frame.minY
                - chat.collectionView.contentOffset.y, dateFrame.minY - offsetY, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: questionIndexPath)).frame.minY
                - chat.collectionView.contentOffset.y, questionFrame.minY - offsetY, accuracy: 1)
        }
    }

    func testQuestionDateStaysVisibleWhenStreamingReloadRegeneratesDateHeaders() async throws {
        let chat = try await makeChat()
        let context = try XCTUnwrap(chat.backend.context)
        let historyTimestamp = Date().addingTimeInterval(-3_600)
        let history: [AgentTimelineItem] = (0..<12).map { index in
            .message(AgentMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: String(repeating: "History message \(index) with enough text to fill the chat. ", count: 4),
                isStreaming: false,
                timestamp: historyTimestamp
            ))
        }
        context.replaceTimeline(with: history, animated: false)
        try await chat.waitForStableLayout()
        context.sendMessage((1...60).map { "Question line \($0)" }.joined(separator: "\n"), source: .composer)
        try await chat.waitUntil { $0.hasTypingIndicatorItem }
        try await chat.waitForStableLayout()
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let questionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        let dateHeaderID = context.itemIDs[questionIndex - 1]
        XCTAssertTrue(try XCTUnwrap(context.message(for: dateHeaderID)).isDateTimeSystemMessage)
        let dateIndexPath = IndexPath(item: questionIndex - 1, section: 0)
        let dateY = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: dateIndexPath)).frame.minY
            - chat.collectionView.contentOffset.y
        XCTAssertEqual(dateY, chat.collectionView.adjustedContentInset.top + 16, accuracy: 1)

        let reply = try await chat.startReply()
        chat.stream(reply, repeating: 4)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: dateIndexPath)).frame.minY
            - chat.collectionView.contentOffset.y, dateY, accuracy: 1)
        let streamingDateHeaderID = context.itemIDs[questionIndex - 1]
        let messages = context.itemIDs.compactMap { context.message(for: $0) }.filter { !$0.isDateTimeSystemMessage }
        context.replaceTimeline(with: messages.map(AgentTimelineItem.message), animated: false,
                                reconfigureItemIDs: messages.map(\.id))
        try await chat.waitForStableLayout()

        let reloadedQuestionIndex = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        XCTAssertNotEqual(context.itemIDs[reloadedQuestionIndex - 1], streamingDateHeaderID)
        let reloadedDateFrame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(
            at: IndexPath(item: reloadedQuestionIndex - 1, section: 0)
        )).frame
        XCTAssertEqual(reloadedDateFrame.minY - chat.collectionView.contentOffset.y, dateY, accuracy: 1)
    }

    func testHintPinsFirstQuestionAfterHintsDisappear() async throws {
        let chat = try await makeChat(historyCount: 0)
        let hints = (0..<3).map {
            AgentHint(id: "hint:\($0)", title: "Suggestion \($0)", subtitle: "Learn", prompt: "Tell me the news \($0)")
        }
        chat.backend.context?.setHints(hints, animated: false)
        try await chat.waitForStableLayout()
        let button = try XCTUnwrap(descendants(of: chat.controller.view)
            .compactMap { $0 as? AgentSuggestionButton }.first { $0.accessibilityLabel == hints[0].title })

        button.sendActions(for: .touchUpInside)
        try await chat.waitUntil { $0.hasTypingIndicator }
        try await chat.waitForStableLayout()
        // With no history above it, the first question can already sit closer to the top than the pin target.
        let questionY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0))
        XCTAssertLessThanOrEqual(questionY, chat.collectionView.adjustedContentInset.top + 100)

        var reply = try await chat.startReply()
        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
        reply.isStreaming = false
        reply.controls = [AgentMessageControl(id: "followup:0", title: "Tell me more", isEnabled: true, kind: .followup)]
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
    }

    func testMessageSentToSupportGoesToTheEndWithoutPinOrReserve() async throws {
        let chat = try await makeChat()
        chat.backend.supportState = .waiting

        try await chat.sendAndWaitForTypingIndicator()

        XCTAssertEqual(chat.reserveSpaceHeight, 0, accuracy: 0.5)
        XCTAssertEqual(try chat.getLatestRowBottomGap(), 0, accuracy: 1)
        XCTAssertNil(chat.controller.pinnedUserMessageID)
    }

    func testSupportFollowsNewMessagesAtTheEndAndKeepsAPositionScrolledUp() async throws {
        let chat = try await makeChat()
        chat.backend.supportState = .operator(nil)

        chat.appendOperatorReply()
        try await chat.waitForStableLayout()
        XCTAssertEqual(try chat.getLatestRowBottomGap(), 0, accuracy: 1)
        XCTAssertFalse(chat.controller.scrollToBottomButton.isButtonVisible)

        chat.collectionView.contentOffset.y -= 200
        try await chat.waitForStableLayout()
        let offsetY = chat.collectionView.contentOffset.y
        chat.appendOperatorReply()
        try await chat.waitForStableLayout()
        XCTAssertEqual(chat.collectionView.contentOffset.y, offsetY, accuracy: 1)
        XCTAssertTrue(chat.controller.scrollToBottomButton.isButtonVisible)
    }

    func testSupportTakingAPinnedQuestionKeepsItsPlaceUntilTheNextSend() async throws {
        let chat = try await makeChat()
        try await chat.sendAndWaitForTypingIndicator()
        let questionY = try questionBubbleFrame(in: chat).minY
        let reserveHeight = chat.reserveSpaceHeight
        XCTAssertGreaterThan(reserveHeight, 0)

        chat.backend.supportState = .waiting
        chat.appendOperatorReply()
        try await chat.waitForStableLayout()
        XCTAssertEqual(try questionBubbleFrame(in: chat).minY, questionY, accuracy: 1)
        XCTAssertGreaterThan(chat.reserveSpaceHeight, 0)

        try await chat.sendAndWaitForTypingIndicator()
        XCTAssertEqual(chat.reserveSpaceHeight, 0, accuracy: 0.5)
        XCTAssertEqual(try chat.getLatestRowBottomGap(), 0, accuracy: 1)
    }

    func testReplyArrivalPreservesPositionAfterUserScrollsUp() async throws {
        let chat = try await makeChat()
        try await chat.sendAndWaitForTypingIndicator()
        chat.collectionView.contentOffset.y -= 100
        try await chat.waitForStableLayout()
        let questionY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0))

        _ = try await chat.startReply()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
    }

    func testStreamingTimelineReloadPreservesPositionAfterUserScrollsUp() async throws {
        let chat = try await makeChat()
        _ = try await chat.sendAndStartReply()
        chat.collectionView.contentOffset.y -= 100
        try await chat.waitForStableLayout()
        let questionY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1))
        let context = try XCTUnwrap(chat.backend.context)
        let messages = context.itemIDs.compactMap { context.message(for: $0) }

        context.replaceTimeline(with: messages.map(AgentTimelineItem.message), animated: false,
                                reconfigureItemIDs: messages.map(\.id))
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
    }

    func testPinnedMessageStaysInPlaceWhenCoveredAreaShrinks() async throws {
        try await checkPinnedMessageStaysInPlaceWhenCoveredAreaShrinks(windowHeight: 874)
    }

    func testPinnedMessageWithoutReserveSpaceStaysInPlaceWhenCoveredAreaShrinks() async throws {
        try await checkPinnedMessageStaysInPlaceWhenCoveredAreaShrinks(windowHeight: 450)
    }

    func testReserveSpaceShrinksWhileReplyStreams() async throws {
        try await checkReserveSpaceShrinksWhileReplyStreams(historyArrivesOnScreen: false)
    }

    func testReserveSpaceShrinksWhileReplyStreamsAfterHistoryArrivesOnScreen() async throws {
        try await checkReserveSpaceShrinksWhileReplyStreams(historyArrivesOnScreen: true)
    }

    private func checkReserveSpaceShrinksWhileReplyStreams(historyArrivesOnScreen: Bool) async throws {
        let chat = try await makeChat(historyArrivesOnScreen: historyArrivesOnScreen)
        let reply = try await chat.sendAndStartReply()
        let questionY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1))
        let initialReplyHeight = try XCTUnwrap(chat.messageFrames.last).height

        chat.stream(reply, repeating: 20)
        try await chat.waitUntil { ($0.messageFrames.last?.height ?? 0) > initialReplyHeight + 120 }

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(chat.maxContentOffsetY, chat.collectionView.contentOffset.y - 1)
        XCTAssertLessThanOrEqual(
            chat.maxContentOffsetY,
            chat.collectionView.contentOffset.y + AgentVC.streamingReserveSpaceSlack + 1
        )
    }

    func testReserveSpaceIsRefitInStepsWhileReplyStreams() async throws {
        let chat = try await makeChat()
        let reply = try await chat.sendAndStartReply()
        var heights: [CGFloat] = []
        for count in 1...16 {
            chat.stream(reply, repeating: count)
            try await chat.waitForStableLayout()
            heights.append(chat.reserveSpaceHeight)
        }

        let decreases = zip(heights, heights.dropFirst()).filter { $0 - $1 > 0.5 }
        XCTAssertFalse(decreases.isEmpty, "\(heights)")
        XCTAssertLessThan(decreases.count, heights.count / 2, "\(heights)")
    }

    func testReserveSpaceSlackIsTrimmedWhenReplyIsRevealed() async throws {
        try await checkReserveSpaceSlackIsTrimmed(scrollsAwayFromReply: false)
    }

    func testReserveSpaceSlackIsTrimmedWhenReplyFinishesOffScreen() async throws {
        try await checkReserveSpaceSlackIsTrimmed(scrollsAwayFromReply: true)
    }

    func testReserveSpaceFollowsFollowupsAddedAfterReplyIsRevealed() async throws {
        let chat = try await makeChat()
        var reply = try await chat.sendAndStartReply()
        reply.text = String(repeating: "Gram and TON network news for the last two days. ", count: 2)
        reply.isStreaming = false
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        let replyCell = try XCTUnwrap(chat.collectionView.visibleCells
            .compactMap { $0 as? AgentMessageCell }
            .max { $0.frame.minY < $1.frame.minY })
        let revealCompletion = RevealCompletion()
        let onRevealCompleted = replyCell.onStreamingRevealCompleted
        replyCell.onStreamingRevealCompleted = {
            onRevealCompleted?()
            revealCompletion.didComplete = true
        }
        try await chat.waitUntil(timeout: .seconds(30)) { _ in revealCompletion.didComplete }
        try await chat.waitForStableLayout()
        let reserveSpaceHeight = chat.reserveSpaceHeight
        let replyHeight = try XCTUnwrap(chat.messageFrames.last).height
        XCTAssertGreaterThan(reserveSpaceHeight, 120)

        reply.controls = [AgentMessageControl(id: "followup:0", title: "Show staking", isEnabled: true, kind: .followup)]
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        let growth = try XCTUnwrap(chat.messageFrames.last).height - replyHeight
        XCTAssertGreaterThan(growth, 0)
        XCTAssertEqual(chat.reserveSpaceHeight, reserveSpaceHeight - growth, accuracy: 1)
    }

    private func checkReserveSpaceSlackIsTrimmed(scrollsAwayFromReply: Bool) async throws {
        let chat = try await makeChat()
        var reply = try await chat.sendAndStartReply()
        var count = 1
        func spaceBelowReply() throws -> CGFloat {
            chat.collectionView.bounds.height - chat.controller.occlusionBottomInset
                - (try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0)))
        }
        while try spaceBelowReply() > 0 {
            count += 1
            chat.stream(reply, repeating: count)
            try await chat.waitForStableLayout()
        }
        XCTAssertGreaterThan(chat.reserveSpaceHeight, 1)
        if scrollsAwayFromReply {
            chat.collectionView.setContentOffset(
                CGPoint(x: 0, y: -chat.collectionView.adjustedContentInset.top),
                animated: false
            )
            try await chat.waitForStableLayout()
            let replyIndexPath = IndexPath(item: chat.collectionView.numberOfItems(inSection: 0) - 2, section: 0)
            XCTAssertFalse(chat.collectionView.indexPathsForVisibleItems.contains(replyIndexPath))
        }

        reply.text = String(repeating: "Gram and TON network news for the last two days. ", count: count + 2)
        reply.isStreaming = false
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        if !scrollsAwayFromReply {
            let replyCell = try XCTUnwrap(chat.collectionView.visibleCells
                .compactMap { $0 as? AgentMessageCell }
                .max { $0.frame.minY < $1.frame.minY })
            let revealCompletion = RevealCompletion()
            let onRevealCompleted = replyCell.onStreamingRevealCompleted
            replyCell.onStreamingRevealCompleted = {
                onRevealCompleted?()
                revealCompletion.didComplete = true
            }
            try await chat.waitUntil(timeout: .seconds(30)) { _ in revealCompletion.didComplete }
        }
        try await chat.waitForStableLayout()

        XCTAssertLessThanOrEqual(chat.reserveSpaceHeight, 1)
    }

    func testPinnedMessageStaysInPlaceWhenStreamingReplyShrinks() async throws {
        let chat = try await makeChat()
        let reply = try await chat.sendAndStartReply()
        let initialReplyHeight = try XCTUnwrap(chat.messageFrames.last).height

        chat.stream(reply, repeating: 8)
        try await chat.waitUntil { ($0.messageFrames.last?.height ?? 0) > initialReplyHeight + 120 }
        try await chat.waitForStableLayout()
        let grownReplyHeight = try XCTUnwrap(chat.messageFrames.last).height
        let pinnedMessageY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1))

        chat.stream(reply, repeating: 4)
        try await chat.waitUntil { ($0.messageFrames.last?.height ?? .infinity) < grownReplyHeight - 40 }
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), pinnedMessageY, accuracy: 1)
    }

    func testPositionBelowPinnedMessageIsKeptWhileReplyStreams() async throws {
        let chat = try await makeChat()
        try await chat.sendAndWaitForTypingIndicator()
        chat.composer.setDraftText((1...6).map(String.init).joined(separator: "\n"), focus: false)
        try await chat.waitForStableLayout()
        chat.collectionView.setContentOffset(CGPoint(x: 0, y: chat.maxContentOffsetY), animated: false)
        try await chat.waitForStableLayout()
        let scrolledMessageY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0))

        let reply = try await chat.startReply()
        let initialReplyHeight = try XCTUnwrap(chat.messageFrames.last).height
        chat.stream(reply, repeating: 8)
        try await chat.waitUntil { ($0.messageFrames.last?.height ?? 0) > initialReplyHeight + 120 }
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), scrolledMessageY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(chat.maxContentOffsetY, chat.collectionView.contentOffset.y - 1)
        XCTAssertLessThanOrEqual(
            chat.maxContentOffsetY,
            chat.collectionView.contentOffset.y + AgentVC.streamingReserveSpaceSlack + 1
        )
    }

    func testPinnedMessageStaysInPlaceWhenViewGrowsTaller() async throws {
        try await checkPinnedMessageStaysInPlaceWhenViewResizes(
            from: CGSize(width: 402, height: 700),
            to: CGSize(width: 402, height: 874)
        )
    }

    func testPinnedMessageStaysInPlaceWhenViewRotates() async throws {
        try await checkPinnedMessageStaysInPlaceWhenViewResizes(
            from: CGSize(width: 874, height: 402),
            to: CGSize(width: 402, height: 874)
        )
    }

    func testScrolledPositionStaysInPlaceWhenViewRotates() async throws {
        try await checkPinnedMessageStaysInPlaceWhenViewResizes(
            from: CGSize(width: 874, height: 402),
            to: CGSize(width: 402, height: 874),
            scrollOffset: -80
        )
    }

    func testHeightChangeRequestedDuringPinnedRowResizeIsApplied() async throws {
        let chat = try await makeChat()
        _ = try await chat.sendAndStartReply()
        try checkHeightChangeRequestedDuringRowResizeIsApplied(in: chat)
    }

    func testHeightChangeRequestedDuringUnpinnedRowResizeIsApplied() async throws {
        let chat = try await makeChat(includesUserMessages: false)
        let reply = AgentMessage(role: .assistant, text: "Here is", isStreaming: true)
        chat.backend.context?.append(.message(reply), animated: true)
        try await chat.waitForStableLayout()
        try checkHeightChangeRequestedDuringRowResizeIsApplied(in: chat)
    }

    func testCompletedReplyStaysInPlaceWhenCoveredAreaShrinks() async throws {
        let chat = try await makeChat()
        chat.composer.setDraftText((1...6).map(String.init).joined(separator: "\n"), focus: false)
        try await chat.waitForStableLayout()
        var reply = try await chat.sendAndStartReply()
        for count in stride(from: 4, through: 60, by: 4) {
            if count > 4 {
                try await Task.sleep(for: .milliseconds(60))
            }
            chat.stream(reply, repeating: count)
        }
        reply.text = String(repeating: "Gram and TON network news for the last two days. ", count: 60)
        reply.isStreaming = false
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        let replyCell = try XCTUnwrap(chat.collectionView.visibleCells
            .compactMap { $0 as? AgentMessageCell }
            .max { $0.frame.minY < $1.frame.minY })
        let revealCompletion = RevealCompletion()
        let onRevealCompleted = replyCell.onStreamingRevealCompleted
        replyCell.onStreamingRevealCompleted = {
            onRevealCompleted?()
            revealCompletion.didComplete = true
        }
        try await chat.waitUntil(timeout: .seconds(30)) { _ in revealCompletion.didComplete }
        try await chat.waitForStableLayout()
        let questionY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1))

        chat.composer.clearDraft()
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
    }

    func testFinishedReplyControlsDoNotMoveTheQuestion() async throws {
        let chat = try await makeChat()
        var reply = try await chat.sendAndStartReply()
        var count = 1
        func spaceBelowReply() throws -> CGFloat {
            chat.collectionView.bounds.height - chat.controller.occlusionBottomInset
                - (try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0)))
        }
        while try spaceBelowReply() >= 40 {
            count += 1
            chat.stream(reply, repeating: count)
            try await chat.waitForStableLayout()
        }
        XCTAssertGreaterThan(try spaceBelowReply(), 0)
        let questionY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1))

        reply.text = String(repeating: "Gram and TON network news for the last two days. ", count: count)
        reply.isStreaming = false
        reply.controls = [AgentMessageControl(id: "action:receive", title: "Open Receive", isEnabled: true)]
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)

        reply.controls += (0..<3).map {
            AgentMessageControl(id: "followup:\($0)", title: "Follow-up suggestion \($0)", isEnabled: true, kind: .followup)
        }
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), questionY, accuracy: 1)
    }

    func testLongFollowupWrapsOntoTwoLines() async throws {
        let chat = try await makeChat()
        let replyID = try XCTUnwrap(chat.backend.context?.itemIDs.last)
        var reply = try XCTUnwrap(chat.backend.context?.message(for: replyID))
        let longTitle = "Which of these news stories matters most for the price of Gram this week?"
        reply.controls = [
            AgentMessageControl(id: "followup:long", title: longTitle, isEnabled: true, kind: .followup),
            AgentMessageControl(id: "followup:short", title: "Show staking", isEnabled: true, kind: .followup),
        ]
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()

        let buttons = descendants(of: chat.collectionView).compactMap { $0 as? AgentSuggestionButton }
        let longButton = try XCTUnwrap(buttons.first { $0.accessibilityLabel == longTitle })
        let shortButton = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Show staking" })
        XCTAssertGreaterThan(AgentSuggestionButton.width(for: longTitle, showsArrow: true), longButton.bounds.width)
        XCTAssertEqual(shortButton.bounds.height, AgentSuggestionButton.height, accuracy: 0.5)
        XCTAssertGreaterThan(longButton.bounds.height, AgentSuggestionButton.height + 10)
        let replyCell = try XCTUnwrap(chat.collectionView.visibleCells.first { longButton.isDescendant(of: $0) })
        XCTAssertLessThanOrEqual(longButton.convert(longButton.bounds, to: replyCell).maxY, replyCell.bounds.maxY)
    }

    func testTypingStatusStaysReadableBeforeTheNextOne() async throws {
        let chat = try await makeChat()
        chat.backend.typingIndicatorStatusText = "Searching the web…"
        try await chat.sendAndWaitForTypingIndicator()
        XCTAssertEqual(chat.typingStatusText, "Searching the web…")

        chat.backend.typingIndicatorStatusText = "Found 4 sources"
        chat.backend.context?.notifyStateChanged()
        chat.layout()
        XCTAssertEqual(chat.typingStatusText, "Searching the web…")

        try await chat.waitUntil(timeout: .seconds(3)) { $0.typingStatusText == "Found 4 sources" }
    }

    func testContentAboveStaysWhenSendHidesFollowups() async throws {
        let chat = try await makeChat()
        let replyID = try XCTUnwrap(chat.backend.context?.itemIDs.last)
        var reply = try XCTUnwrap(chat.backend.context?.message(for: replyID))
        reply.controls = (0..<3).map {
            AgentMessageControl(id: "followup:\($0)", title: "Follow-up suggestion \($0)", isEnabled: true, kind: .followup)
        }
        chat.backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        chat.collectionView.setContentOffset(CGPoint(x: 0, y: chat.maxContentOffsetY), animated: false)
        try await chat.waitForStableLayout()
        let replyCell = try XCTUnwrap(chat.collectionView.visibleCells
            .compactMap { $0 as? AgentMessageCell }
            .max { $0.frame.minY < $1.frame.minY })
        let replyY = chat.presentedScreenMinY(of: replyCell)

        chat.backend.context?.sendMessage("Tell me the news", source: .composer)
        var maxDrop: CGFloat = 0
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(8))
            maxDrop = max(maxDrop, chat.presentedScreenMinY(of: replyCell) - replyY)
        }

        XCTAssertLessThan(maxDrop, 4)
    }

    /// A suggestion tapped under an answer brings its question in where the suggestions were, and the chat brings the
    /// question up only once it has appeared there and a moment has passed, as on Android
    func testFollowupQuestionAppearsInPlaceBeforeTheChatBringsItUp() async throws {
        let chat = try await makeChat()
        let context = try XCTUnwrap(chat.backend.context)
        let replyID = try XCTUnwrap(context.itemIDs.last)
        var reply = try XCTUnwrap(context.message(for: replyID))
        reply.controls = (0..<3).map {
            AgentMessageControl(id: "followup:\($0)", title: "Follow-up suggestion \($0)", isEnabled: true, kind: .followup)
        }
        context.updateMessage(reply, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        chat.collectionView.setContentOffset(CGPoint(x: 0, y: chat.maxContentOffsetY), animated: false)
        try await chat.waitForStableLayout()

        let sentAt = ContinuousClock.now
        context.sendMessage("Follow-up suggestion 1", source: .followup(messageID: "reply", followupID: "followup:1"))
        let offsetY = chat.collectionView.contentOffset.y
        let visibleBottom = chat.collectionView.bounds.height - chat.controller.occlusionBottomInset
        XCTAssertLessThanOrEqual(try questionBubbleFrame(in: chat).maxY, visibleBottom, "The question shows under the answer")
        // The pin waits for the appearance and the delay after it, timed from the send, so it cannot start sooner
        var maxShift: CGFloat = 0
        while ContinuousClock.now < sentAt + .milliseconds(450) {
            let drawnOffsetY = chat.collectionView.layer.presentation()?.bounds.minY ?? chat.collectionView.contentOffset.y
            maxShift = max(maxShift, abs(drawnOffsetY - offsetY))
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertLessThan(maxShift, 1, "The chat stays as the question appears and a moment after")

        try await chat.waitUntil { $0.hasTypingIndicator }
        try await chat.waitForStableLayout()
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let pinnedOffsetY = try XCTUnwrap(chat.controller.pinnedOffsetY(for: questionID))
        XCTAssertEqual(chat.collectionView.contentOffset.y, chat.controller.clampedContentOffsetY(pinnedOffsetY), accuracy: 1)
        XCTAssertGreaterThan(chat.collectionView.contentOffset.y, offsetY + 1, "Then the chat brings the question up")
    }

    func testQuestionFromEntryPointIsPinnedWhenChatOpens() async throws {
        try await checkQuestionOpeningStaysPinned(inTabBar: false)
    }

    func testQuestionFromEntryPointStaysPinnedWhenTabReopens() async throws {
        try await checkQuestionOpeningStaysPinned(inTabBar: true)
    }

    private func checkQuestionOpeningStaysPinned(inTabBar: Bool) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = FakeAgentV2Client(shouldCompleteRun: true, blockedHydrationAttempt: 1)
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        let controller = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(
            query: "Receive tokens", preloader: preloader
        ) as? AgentVC)
        let model = try XCTUnwrap(Mirror(reflecting: controller).children.first { $0.label == "model" }?.value as? AgentV2Model)
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        if inTabBar {
            let tabs = UITabBarController()
            tabs.viewControllers = [UIViewController(), navigation]
            tabs.selectedIndex = 1
            window.rootViewController = tabs
        } else {
            window.rootViewController = navigation
        }
        defer {
            client.resumeThreadCreation()
            client.resumeBlockedHydration()
            window.rootViewController = nil
            window.isHidden = true
            preloader.setWalletReady(false)
        }
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        let collection = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        let questionID = try XCTUnwrap(model.itemIDs.first {
            guard case .message(let message)? = model.item(for: $0) else { return false }
            return message.role == .user
        })
        func frames() throws -> (date: CGRect, question: CGRect) {
            let questionIndex = try XCTUnwrap(model.itemIDs.firstIndex(of: questionID))
            guard questionIndex > 0,
                  case .message(let date)? = model.item(for: model.itemIDs[questionIndex - 1]) else {
                XCTFail("Opening question must have a date header")
                throw PinnedReplyTimeout()
            }
            XCTAssertTrue(date.isDateTimeSystemMessage)
            let dateFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: questionIndex - 1, section: 0))).frame
            let questionFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: questionIndex, section: 0))).frame
            return (
                dateFrame.offsetBy(dx: 0, dy: -collection.contentOffset.y),
                questionFrame.offsetBy(dx: 0, dy: -collection.contentOffset.y)
            )
        }
        let initialFrames = try frames()
        XCTAssertEqual(initialFrames.date.minY, collection.adjustedContentInset.top + 16, accuracy: 1)
        XCTAssertGreaterThan(initialFrames.question.minY, initialFrames.date.minY)
        XCTAssertTrue(collection.visibleCells.contains { $0 is AgentMessageCell })
        let typingCell = try XCTUnwrap(collection.visibleCells.first { $0 is AgentTypingIndicatorCell })
        XCTAssertTrue(descendants(of: typingCell).compactMap { $0 as? UILabel }.contains {
            $0.text == lang("$agent_activity_analyzing_request")
        })
        XCTAssertEqual(controller.title, "Receive tokens")
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertNil(model.threadId)
        func checkPosition() throws {
            let currentFrames = try frames()
            XCTAssertEqual(currentFrames.date.minY, initialFrames.date.minY, accuracy: 1)
            XCTAssertEqual(currentFrames.question.minY, initialFrames.question.minY, accuracy: 1)
            XCTAssertEqual(currentFrames.question.maxY, initialFrames.question.maxY, accuracy: 1)
            XCTAssertTrue(navigation.topViewController === controller)
        }
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            try checkPosition()
        }
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertTrue(client.startedCommands.isEmpty)
        if let tabs = window.rootViewController as? UITabBarController {
            tabs.selectedIndex = 0
            try await Task.sleep(for: .milliseconds(100))
            tabs.selectedIndex = 1
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            try checkPosition()
        }

        let answerStarted = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: Data("""
        {"type":"agentV2","update":{"kind":"messageStarted","threadId":"thread-a","clientRunId":"client-thread-a",
        "runId":"run-thread-a","messageId":"answer","contentKind":"markdown"}}
        """.utf8)).update
        let answerText = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: Data("""
        {"type":"agentV2","update":{"kind":"textDelta","threadId":"thread-a","clientRunId":"client-thread-a",
        "runId":"run-thread-a","messageId":"answer","delta":"Here is the answer."}}
        """.utf8)).update
        client.startRunObserver = {
            WalletCoreData.notify(event: .agentV2(answerStarted))
            WalletCoreData.notify(event: .agentV2(answerText))
        }
        client.resumeThreadCreation()
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            try checkPosition()
        }
        XCTAssertEqual(client.startedCommands.count, 1)
        XCTAssertTrue(model.itemIDs.contains {
            guard case .message(let message)? = model.item(for: $0) else { return false }
            return message.role == .assistant && message.text == "Here is the answer."
        })
    }

    private func checkHeightChangeRequestedDuringRowResizeIsApplied(in chat: PinnedReplyChat) throws {
        let cell = try XCTUnwrap(chat.collectionView.visibleCells
            .compactMap { $0 as? AgentMessageCell }
            .max { $0.frame.minY < $1.frame.minY })
        let indexPath = try XCTUnwrap(chat.collectionView.indexPath(for: cell))
        let initialHeight = cell.frame.height
        let nestedRequest = NestedResizeRequest()
        let observation = chat.collectionView.observe(\.contentSize) { _, _ in
            MainActor.assumeIsolated {
                guard !nestedRequest.didRequest else { return }
                nestedRequest.didRequest = true
                cell.minimumHeightProvider = { initialHeight + 120 }
                cell.onPreferredHeightChanged?(false)
            }
        }
        defer { observation.invalidate() }

        cell.minimumHeightProvider = { initialHeight + 40 }
        cell.onPreferredHeightChanged?(false)

        XCTAssertTrue(nestedRequest.didRequest)
        let height = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: indexPath)).frame.height
        XCTAssertEqual(height, initialHeight + 120, accuracy: 1)
    }

    private func checkPinnedMessageStaysInPlaceWhenViewResizes(
        from initialSize: CGSize,
        to size: CGSize,
        scrollOffset: CGFloat = 0
    ) async throws {
        let chat = try await makeChat(windowSize: initialSize)
        try await chat.sendAndWaitForTypingIndicator()
        chat.collectionView.contentOffset.y += scrollOffset
        try await chat.waitForStableLayout()
        let pinnedMessageY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0))

        chat.window.frame.size = size
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0)), pinnedMessageY, accuracy: 1)
    }

    private func checkPinnedMessageStaysInPlaceWhenCoveredAreaShrinks(windowHeight: CGFloat) async throws {
        let chat = try await makeChat(windowSize: CGSize(width: 402, height: windowHeight))
        chat.composer.setDraftText((1...6).map(String.init).joined(separator: "\n"), focus: false)
        try await chat.waitForStableLayout()

        try await chat.sendAndWaitForTypingIndicator()
        let pinnedMessageY = try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0))

        chat.composer.clearDraft()
        try await chat.waitForStableLayout()

        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0)), pinnedMessageY, accuracy: 1)
    }

    private func makeChat(
        windowSize: CGSize = CGSize(width: 402, height: 874),
        historyCount: Int = 12,
        tableHistory: Bool = false,
        historyTexts: [String]? = nil,
        includesUserMessages: Bool = true,
        historyArrivesOnScreen: Bool = false,
        streamingHistory: Bool = false,
        scrollsToBottom: Bool = true
    ) async throws -> PinnedReplyChat {
        _ = WalletResourcesBundle.bundle.load()
        let backend = PinnedReplyTestBackend()
        let model = CountingAgentModel(backend: backend)
        let history: [AgentTimelineItem] = (0..<historyCount).map { index in
            .message(AgentMessage(
                role: includesUserMessages && index.isMultiple(of: 2) ? .user : .assistant,
                text: historyTexts?[index] ?? (tableHistory && !index.isMultiple(of: 2) ? Self.longTable
                    : "History message \(index) with enough text to take a couple of lines in the chat"),
                isStreaming: streamingHistory && index == historyCount - 1
            ))
        }
        if !historyArrivesOnScreen {
            backend.context?.replaceTimeline(with: history, animated: false)
        }

        let controller = AgentVC(model: model)
        let window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
        let navigationController = UINavigationController(rootViewController: controller)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        if historyArrivesOnScreen {
            backend.context?.replaceTimeline(with: history, animated: false)
        }

        let chat = PinnedReplyChat(
            window: window,
            controller: controller,
            model: model,
            backend: backend,
            collectionView: try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first),
            composer: try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? AgentComposerView }.first)
        )
        addTeardownBlock { chat.close() }
        try await chat.waitForStableLayout()
        if scrollsToBottom {
            chat.collectionView.setContentOffset(CGPoint(x: 0, y: chat.maxContentOffsetY), animated: false)
            try await chat.waitForStableLayout()
        }
        return chat
    }

    /// Where the last line of the answer right above the question starts on screen: a line of the answer's text and the
    /// bubble's padding above the bubble's bottom
    private func getPreviousAnswerLastLineTop(in chat: PinnedReplyChat) throws -> CGFloat {
        let context = try XCTUnwrap(chat.backend.context)
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let index = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        XCTAssertEqual(context.message(for: context.itemIDs[index - 1])?.role, .assistant, "An answer stands right above")
        let cell = try XCTUnwrap(chat.collectionView.cellForItem(at: IndexPath(item: index - 1, section: 0)))
        let bubble = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentBubbleBackgroundView }.first)
        let bubbleFrame = bubble.convert(bubble.bounds, to: chat.collectionView)
            .offsetBy(dx: 0, dy: -chat.collectionView.contentOffset.y)
        return bubbleFrame.maxY - AgentMessageCellMetrics.bodyVerticalPadding - AgentMessageTextRenderer.answerLineHeight
    }

    private func questionBubbleFrame(in chat: PinnedReplyChat) throws -> CGRect {
        let context = try XCTUnwrap(chat.backend.context)
        let questionID = try XCTUnwrap(context.itemIDs.last { context.message(for: $0)?.role == .user })
        let index = try XCTUnwrap(context.itemIDs.firstIndex(of: questionID))
        let cell = try XCTUnwrap(chat.collectionView.cellForItem(at: IndexPath(item: index, section: 0)))
        let bubble = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentBubbleBackgroundView }.first)
        return bubble.convert(bubble.bounds, to: chat.collectionView)
            .offsetBy(dx: 0, dy: -chat.collectionView.contentOffset.y)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private struct PinnedReplyTimeout: Error {}

@MainActor
private final class NestedResizeRequest {
    var didRequest = false
}

@MainActor
private final class RevealCompletion {
    var didComplete = false
}

@MainActor
private struct PinnedReplyChat {
    let window: UIWindow
    let controller: AgentVC
    let model: CountingAgentModel
    let backend: PinnedReplyTestBackend
    let collectionView: UICollectionView
    let composer: AgentComposerView

    var maxContentOffsetY: CGFloat {
        collectionView.collectionViewLayout.collectionViewContentSize.height
            - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom
    }

    var messageFrames: [CGRect] {
        collectionView.visibleCells
            .compactMap { $0 as? AgentMessageCell }
            .map(\.frame)
            .sorted { $0.minY < $1.minY }
    }

    var reserveSpaceHeight: CGFloat {
        controller.reserveSpacerHeight
    }

    var hasTypingIndicator: Bool {
        collectionView.visibleCells.contains { $0 is AgentTypingIndicatorCell }
    }

    var typingStatusText: String? {
        func labels(in view: UIView) -> [UILabel] {
            view.subviews.flatMap { subview in (subview as? UILabel).map { [$0] } ?? labels(in: subview) }
        }
        return collectionView.visibleCells
            .compactMap { $0 as? AgentTypingIndicatorCell }
            .flatMap { labels(in: $0.contentView) }
            .first { !$0.isHidden && $0.text?.isEmpty == false }?
            .text
    }

    var hasTypingIndicatorItem: Bool {
        guard let typingIndicatorID = backend.typingIndicatorID else { return false }
        return backend.context?.itemIDs.contains(typingIndicatorID) == true
    }

    func presentedScreenMinY(of cell: UICollectionViewCell) -> CGFloat {
        let cellMinY = cell.layer.presentation()?.frame.minY ?? cell.frame.minY
        let offsetY = collectionView.layer.presentation()?.bounds.minY ?? collectionView.contentOffset.y
        return cellMinY - offsetY
    }

    func screenMaxY(ofMessageFromEnd index: Int) -> CGFloat? {
        let frames = messageFrames
        guard frames.count > index else { return nil }
        return frames[frames.count - 1 - index].maxY - collectionView.contentOffset.y
    }

    func sendAndWaitForTypingIndicator() async throws {
        backend.context?.sendMessage("Tell me the news", source: .composer)
        try await waitUntil { $0.hasTypingIndicator }
        try await waitForStableLayout()
    }

    func sendAndStartReply() async throws -> AgentMessage {
        try await sendAndWaitForTypingIndicator()
        return try await startReply()
    }

    func startReply() async throws -> AgentMessage {
        let typingID = try XCTUnwrap(backend.typingIndicatorID)
        let reply = AgentMessage(role: .assistant, text: "Here is", isStreaming: true)
        backend.context?.replaceItem(id: typingID, with: .message(reply), animated: true)
        try await waitUntil { !$0.hasTypingIndicator }
        try await waitForStableLayout()
        return reply
    }

    /// How far above the area the composer covers the latest row ends
    func getLatestRowBottomGap() throws -> CGFloat {
        let indexPath = try XCTUnwrap(controller.lastItemIndexPath)
        let frame = try XCTUnwrap(collectionView.layoutAttributesForItem(at: indexPath)?.frame)
        return collectionView.contentOffset.y + collectionView.bounds.height - controller.occlusionBottomInset - frame.maxY
    }

    /// A reply of support's at the chat's end, long enough to take a few lines
    /// A reply an operator writes, as the chat shows it: plain text under the operator's name
    func appendOperatorReply() {
        let text = String(repeating: "The operator checks the transfer and answers here. ", count: 4)
        var reply = AgentMessage(role: .assistant, text: text, isStreaming: false)
        reply.author = .operator(ApiAgentV2OperatorAuthor(operatorId: "alex", name: "Alex"))
        reply.shouldShowAuthor = true
        reply.isPlainText = true
        backend.context?.append(.message(reply), animated: true)
    }

    func stream(_ reply: AgentMessage, repeating count: Int) {
        var reply = reply
        reply.text = String(repeating: "Gram and TON network news for the last two days. ", count: count)
        backend.context?.updateMessage(reply, animated: false, scrollToBottom: false)
    }

    func close() {
        window.rootViewController = nil
        window.isHidden = true
    }

    func layout() {
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    /// Waits count their timeout in 16 ms samples rather than wall time. Rendering long tables can hold the main
    /// thread for seconds between two samples on a loaded machine, and that time is not the condition's to spend.
    /// Ten times the timeout in wall time still ends a wait whose samples keep stalling.
    func waitUntil(timeout: Duration = .seconds(10), _ condition: (Self) -> Bool) async throws {
        var remainingSamples = Self.samples(in: timeout)
        let deadline = ContinuousClock.now + timeout * Self.wallClockFactor
        layout()
        while !condition(self) {
            guard remainingSamples > 0, ContinuousClock.now < deadline else { throw PinnedReplyTimeout() }
            remainingSamples -= 1
            try await Task.sleep(for: Self.sampleInterval)
            layout()
        }
    }

    func waitForStableLayout(timeout: Duration = .seconds(10)) async throws {
        var remainingSamples = Self.samples(in: timeout)
        let deadline = ContinuousClock.now + timeout * Self.wallClockFactor
        var state = layoutState
        var stableSamples = 0
        while stableSamples < 20 {
            guard remainingSamples > 0, ContinuousClock.now < deadline else { throw PinnedReplyTimeout() }
            remainingSamples -= 1
            try await Task.sleep(for: Self.sampleInterval)
            layout()
            let nextState = layoutState
            stableSamples = nextState == state ? stableSamples + 1 : 0
            state = nextState
        }
    }

    private static let sampleInterval = Duration.milliseconds(16)
    private static let wallClockFactor = 10

    private static func samples(in timeout: Duration) -> Int {
        Int((timeout / sampleInterval).rounded(.up))
    }

    private var layoutState: [CGFloat] {
        [
            collectionView.contentOffset.y,
            collectionView.collectionViewLayout.collectionViewContentSize.height,
            collectionView.adjustedContentInset.bottom,
        ]
    }
}

@MainActor
private final class CountingAgentModel: AgentModel {
    var itemReadCount = 0

    override func item(for id: AgentItemID) -> AgentTimelineItem? {
        itemReadCount += 1
        return super.item(for: id)
    }
}

@MainActor
private final class PinnedReplyTestBackend: AgentBackend {
    var context: AgentBackendContext?
    var typingIndicatorID: AgentItemID?
    var typingIndicatorStatusText: String?
    var supportState: AgentSupportState = .none
    var sentTexts: [String] = []

    func attach(to context: AgentBackendContext) { self.context = context }
    func detach() { context = nil }
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
    func performControl(messageID: AgentItemID, controlID: String) {
        guard let control = context?.message(for: messageID)?.controls.first(where: { $0.id == controlID }) else { return }
        context?.sendMessage(control.title, source: .followup(messageID: "reply", followupID: controlID))
    }
    func didSendUserMessage(_ text: String, userMessageID: AgentItemID, source: AgentBackendSendSource,
                            editContext: AgentBackendEditContext?) {
        sentTexts.append(text)
        let indicator = AgentTypingIndicator()
        typingIndicatorID = indicator.id
        context?.append(.typingIndicator(indicator), animated: true)
    }
    func clearConversation() {}
}
