import XCTest
import UIKit
@testable import UIAgent
import UIComponents
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

    func testComposerSendPinsQuestionAfterClearingMultilineDraft() async throws {
        let chat = try await makeChat()
        chat.composer.setDraftText((1...6).map(String.init).joined(separator: "\n"), focus: false)
        try await chat.waitForStableLayout()

        chat.composer.onSend?()
        try await chat.waitUntil { $0.hasTypingIndicator }
        try await chat.waitForStableLayout()

        XCTAssertEqual(
            try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0)),
            chat.collectionView.adjustedContentInset.top + 100,
            accuracy: 1
        )
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

    func testQuestionFromEntryPointIsPinnedWhenChatOpens() async throws {
        let chat = try await makeChat(entryPointQuery: "Receive tokens")
        try await chat.waitUntil { $0.hasTypingIndicatorItem }
        try await chat.waitForStableLayout()
        let pinnedMessageY = chat.collectionView.adjustedContentInset.top + 100
        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0)), pinnedMessageY, accuracy: 1)

        _ = try await chat.startReply()
        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), pinnedMessageY, accuracy: 1)
    }

    func testQuestionFromEntryPointIsPinnedWhenTabReopens() async throws {
        let chat = try await makeChat(inTabBar: true)
        let tabBarController = try XCTUnwrap(chat.window.rootViewController as? UITabBarController)
        tabBarController.selectedIndex = 0
        try await Task.sleep(for: .milliseconds(100))

        AgentEntryPoint.enqueue(query: "Receive tokens", entryPoint: nil)
        tabBarController.selectedIndex = 1
        try await chat.waitUntil { $0.hasTypingIndicatorItem }
        try await chat.waitForStableLayout()

        let pinnedMessageY = chat.collectionView.adjustedContentInset.top + 100
        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 0)), pinnedMessageY, accuracy: 1)

        _ = try await chat.startReply()
        XCTAssertEqual(try XCTUnwrap(chat.screenMaxY(ofMessageFromEnd: 1)), pinnedMessageY, accuracy: 1)
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
        scrollsToBottom: Bool = true,
        entryPointQuery: String? = nil,
        inTabBar: Bool = false
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

        if let entryPointQuery {
            AgentEntryPoint.enqueue(query: entryPointQuery, entryPoint: nil)
        }
        addTeardownBlock { AgentEntryPoint.clearPendingRequest() }
        let controller = AgentVC(model: model)
        let window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
        let navigationController = UINavigationController(rootViewController: controller)
        if inTabBar {
            let tabBarController = UITabBarController()
            tabBarController.viewControllers = [UIViewController(), navigationController]
            tabBarController.selectedIndex = 1
            window.rootViewController = tabBarController
        } else {
            window.rootViewController = navigationController
        }
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
        guard entryPointQuery == nil else { return chat }
        try await chat.waitForStableLayout()
        if scrollsToBottom {
            chat.collectionView.setContentOffset(CGPoint(x: 0, y: chat.maxContentOffsetY), animated: false)
            try await chat.waitForStableLayout()
        }
        return chat
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

    func waitUntil(timeout: Duration = .seconds(10), _ condition: (Self) -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        layout()
        while !condition(self) {
            guard ContinuousClock.now < deadline else { throw PinnedReplyTimeout() }
            try await Task.sleep(for: .milliseconds(16))
            layout()
        }
    }

    func waitForStableLayout(timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + timeout
        var state = layoutState
        var stableSamples = 0
        while stableSamples < 20 {
            guard ContinuousClock.now < deadline else { throw PinnedReplyTimeout() }
            try await Task.sleep(for: .milliseconds(16))
            layout()
            let nextState = layoutState
            stableSamples = nextState == state ? stableSamples + 1 : 0
            state = nextState
        }
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

    func attach(to context: AgentBackendContext) { self.context = context }
    func detach() { context = nil }
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
    func didSendUserMessage(_ text: String, userMessageID: AgentItemID, source: AgentBackendSendSource,
                            editContext: AgentBackendEditContext?) {
        let indicator = AgentTypingIndicator()
        typingIndicatorID = indicator.id
        context?.append(.typingIndicator(indicator), animated: true)
    }
    func clearConversation(completion: @escaping (Bool) -> Void) { completion(true) }
}
