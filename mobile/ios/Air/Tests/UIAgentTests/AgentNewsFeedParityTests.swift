import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

/// The News feed behaves as the Agent's chats do, through the chat's own code
@MainActor
final class AgentNewsFeedParityTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// Scrolled up by less than a screen, the scroll button springs the feed down as it does a chat
    func testScrollToLatestRunsTheChatsSpring() async throws {
        let feed = try await makeFeed(count: 20)
        let collectionView = feed.controller.collectionView
        // Cards above settle their heights as they come into view, so the distance is set again once they have
        for _ in 0..<2 {
            collectionView.contentOffset.y = feed.controller.maxContentOffsetY - collectionView.bounds.height * 0.8
            try await feed.waitForStableLayout()
        }
        feed.controller.scrollViewDidScroll(collectionView)
        XCTAssertTrue(feed.controller.scrollToBottomButton.isButtonVisible)

        let log = FeedOffsetLog()
        let observation = collectionView.observe(\.contentOffset, options: [.new]) { _, change in
            let offsetY = change.newValue?.y ?? 0
            MainActor.assumeIsolated { log.offsets.append(offsetY) }
        }
        defer { observation.invalidate() }
        feed.controller.scrollToBottomButtonPressed()
        XCTAssertTrue(feed.controller.listScrollAnimator.isRunning)
        let start = CACurrentMediaTime()
        while feed.controller.listScrollAnimator.isRunning {
            try await Task.sleep(for: .milliseconds(16))
            guard CACurrentMediaTime() - start < 5 else { return XCTFail("The scroll didn't end") }
        }
        XCTAssertGreaterThan(Set(log.offsets.map { Int($0) }).count, 5, "\(log.offsets)")
        for (offset, next) in zip(log.offsets, log.offsets.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next, offset - 0.5)
        }
        XCTAssertEqual(collectionView.contentOffset.y, feed.controller.maxContentOffsetY, accuracy: 1)
        XCTAssertFalse(feed.controller.scrollToBottomButton.isButtonVisible)
    }

    /// Several screens up, the feed relays the shown cards out and the latest ones in, as a chat does
    func testLongScrollToLatestRelaysTheShownCards() async throws {
        let feed = try await makeFeed(count: 40)
        let collectionView = feed.controller.collectionView
        collectionView.contentOffset.y = feed.controller.maxContentOffsetY - collectionView.bounds.height * 3
        try await feed.waitForStableLayout()

        feed.controller.scrollToBottomButtonPressed()
        XCTAssertTrue(feed.controller.view.subviews.contains {
            $0.accessibilityIdentifier == AgentListScrollAnimator.departingViewIdentifier
        })
        let start = CACurrentMediaTime()
        while feed.controller.listScrollAnimator.isRunning {
            try await Task.sleep(for: .milliseconds(16))
            guard CACurrentMediaTime() - start < 5 else { return XCTFail("The scroll didn't end") }
        }
        XCTAssertEqual(collectionView.contentOffset.y, feed.controller.maxContentOffsetY, accuracy: 1)
    }

    /// A tap on the current tab goes to the latest news, as a chat goes to its latest message
    func testTabTapGoesToTheLatestNews() async throws {
        let feed = try await makeFeed(count: 20)
        let collectionView = feed.controller.collectionView
        collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        try await feed.waitForStableLayout()
        feed.controller.scrollToTop(animated: false)
        XCTAssertEqual(collectionView.contentOffset.y, feed.controller.maxContentOffsetY, accuracy: 1)
        XCTAssertTrue(feed.controller.isNearBottom())
    }

    /// The scroll button follows the rows after they change, as a chat's does after it applies its rows, also where the
    /// feed keeps its place rather than scrolling: cards that grow shorter under the shown ones bring the latest news in
    /// reach, and the button goes
    func testScrollButtonFollowsCardsThatChangeWhileTheFeedKeepsItsPlace() async throws {
        let feed = try await makeFeed(count: 12)
        let collectionView = feed.controller.collectionView
        for _ in 0..<2 {
            collectionView.contentOffset.y = feed.controller.maxContentOffsetY - 150
            try await feed.waitForStableLayout()
        }
        feed.controller.scrollViewDidScroll(collectionView)
        XCTAssertFalse(feed.controller.isNearBottom())
        XCTAssertTrue(feed.controller.scrollToBottomButton.isButtonVisible)

        feed.client.page = .init(locale: "en", items: (1...12).map { makeNewsItem($0) }.reversed())
        await feed.model.refresh()
        try await feed.waitForStableLayout()
        try assertCardsStandAtTheirHeights(in: feed)
        XCTAssertEqual(collectionView.contentOffset.y, feed.controller.maxContentOffsetY, accuracy: 1)
        XCTAssertTrue(feed.controller.isNearBottom())
        XCTAssertFalse(feed.controller.scrollToBottomButton.isButtonVisible)
    }

    /// The card and the discussion's post are one view: the same picture, text, meta and geometry, with "News" over
    /// the post alone and the Discuss strip under the card alone
    func testCardAndDiscussionPostShareOneLook() throws {
        let item = ApiAgentV2NewsFeedItem(
            eventId: 5,
            deliveredAt: "2026-10-20T10:30:00Z",
            headline: "Headline",
            body: "A **bold** report.",
            imageUrl: "invalid-news-image://picture",
            sources: [.init(name: "Source", url: "https://example.com/news")]
        )
        let news = ApiAgentV2ThreadNewsCard(
            eventId: 5,
            headline: "Headline",
            excerpt: nil,
            imageUrl: "invalid-news-image://picture",
            publishedAt: "2026-10-20T10:30:00Z",
            source: nil,
            body: "A **bold** report.",
            sources: [.init(name: "Source", url: "https://example.com/news")]
        )
        let card = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        card.configure(with: item)
        let post = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        post.configure(with: news)
        // Sized as the list sizes its rows: at the row's width, to the height of what they show
        for cell in [card, post] as [UICollectionViewCell] {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            attributes.frame = CGRect(x: 0, y: 0, width: 402, height: 100)
            _ = cell.preferredLayoutAttributesFitting(attributes)
            let height = cell.systemLayoutSizeFitting(
                CGSize(width: 402, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            cell.frame = CGRect(x: 0, y: 0, width: 402, height: height)
            cell.layoutIfNeeded()
        }
        let cardView = card.newsView
        let postView = post.newsView
        XCTAssertFalse(cardView.isHeaderVisible)
        XCTAssertTrue(postView.isHeaderVisible)
        XCTAssertEqual(cardView.bounds.width, postView.bounds.width, accuracy: 0.5)
        XCTAssertEqual(cardView.convert(cardView.bounds, to: card).minX, postView.convert(postView.bounds, to: post).minX, accuracy: 0.5)
        // A 16:9 picture a point inside the bubble's sides
        for view in [cardView, postView] {
            let picture = view.imageView.convert(view.imageView.bounds, to: view)
            XCTAssertEqual(picture.minX, AgentNewsImageMetrics.inset, accuracy: 0.5)
            XCTAssertEqual(picture.height, picture.width * 9 / 16, accuracy: 1)
        }
        XCTAssertEqual(cardView.imageView.layer.cornerRadius, AgentNewsImageMetrics.topCornerRadius)
        XCTAssertEqual(postView.imageView.layer.cornerRadius, 0)
        // The text and the meta stand alike under the picture
        func textFrames(in view: AgentNewsPostView) -> [CGRect] {
            let picture = view.imageView.convert(view.imageView.bounds, to: view)
            let labels = findDescendants(of: view).compactMap { $0 as? UILabel }
            let headline = labels.first { $0.text == "Headline" }
            let body = labels.first { $0.attributedText?.string == "A bold report." }
            return [headline, body, view.metaView.timeLabel].compactMap { label in
                label.map { $0.convert($0.bounds, to: view).offsetBy(dx: 0, dy: -picture.maxY) }
            }
        }
        let cardFrames = textFrames(in: cardView)
        let postFrames = textFrames(in: postView)
        XCTAssertEqual(cardFrames.count, 3)
        XCTAssertEqual(postFrames.count, 3)
        for (cardFrame, postFrame) in zip(cardFrames, postFrames) {
            // The time is shorter in the feed, where the day line above gives the date, and ends where the post's does
            XCTAssertEqual(cardFrame.maxX, postFrame.maxX, accuracy: 0.5)
            XCTAssertEqual(cardFrame.minY, postFrame.minY, accuracy: 0.5)
            XCTAssertEqual(cardFrame.height, postFrame.height, accuracy: 0.5)
        }
        // Open Source stays among the actions in the feed as in the discussion
        for view in [cardView, postView] {
            XCTAssertEqual(
                view.accessibilityContentElement.accessibilityCustomActions?.first?.name,
                lang("$agent_news_open_source")
            )
        }
    }

    /// A drag that starts on a button scrolls a chat as it scrolls the feed: both lists are the same list view
    func testDragFromAButtonScrollsChatsAndTheFeed() async throws {
        let feed = try await makeFeed(count: 3)
        let chat = AgentTestChat(messages: [AgentMessage(role: .assistant, text: "An answer", isStreaming: false)])
        defer { chat.close() }
        chat.layout()
        for list in [feed.controller.collectionView, chat.collectionView] {
            XCTAssertFalse(list.delaysContentTouches)
            XCTAssertTrue(list.touchesShouldCancel(in: UIButton()))
            XCTAssertTrue(list.touchesShouldCancel(in: AgentSuggestionButton()))
        }
    }

    /// On an iPad the feed is a chat's full-width list with the column in its middle, so it scrolls beside the column
    func testFeedOnAnIPadIsAsWideAsAChatWithTheColumnInItsMiddle() async throws {
        let size = CGSize(width: 1180, height: 820)
        let feed = try await makeFeed(count: 6, size: size)
        let chat = AgentTestChat(messages: [AgentMessage(role: .assistant, text: "An answer", isStreaming: false)], size: size)
        defer { chat.close() }
        chat.layout()
        let feedList = feed.controller.collectionView
        XCTAssertEqual(feedList.frame, chat.collectionView.frame)
        XCTAssertTrue(feed.controller.view.hitTest(CGPoint(x: 40, y: 400), with: nil)?.isDescendant(of: feedList) == true)
        let card = try XCTUnwrap(feedList.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }.first)
        let bubble = card.newsView.convert(card.newsView.bounds, to: nil)
        let columnMinX = (size.width - AgentContentLayout.maxContentWidth) / 2
        XCTAssertEqual(bubble.minX, columnMinX + AgentMessageCellMetrics.horizontalInset, accuracy: 0.5)
        XCTAssertEqual(bubble.width, AgentContentLayout.maxContentWidth - 2 * AgentMessageCellMetrics.horizontalInset, accuracy: 0.5)
        let button = feed.controller.scrollToBottomButton.convert(feed.controller.scrollToBottomButton.bounds, to: nil)
        let chatButton = chat.controller.scrollToBottomButton.convert(chat.controller.scrollToBottomButton.bounds, to: nil)
        XCTAssertEqual(button.maxX, chatButton.maxX, accuracy: 0.5)
    }

    /// The feed's rows are a chat's rows: as far under the header and as far apart, each card's tail ending its row
    func testCardsStandAsAChatsRows() async throws {
        let feed = try await makeFeed(count: 4)
        let list = feed.controller.collectionView
        list.contentOffset.y = -list.adjustedContentInset.top
        try await feed.waitForStableLayout()
        let rows = list.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(first.frame.minY, AgentVCLayout.sectionTopInset, accuracy: 0.5)
        for (row, next) in zip(rows, rows.dropFirst()) {
            XCTAssertEqual(next.frame.minY - row.frame.maxY, AgentVCLayout.rowSpacing, accuracy: 0.5)
        }
        for card in rows.compactMap({ $0 as? AgentNewsFeedCardCell }) {
            let bubble = card.newsView.bubbleView.convert(card.newsView.bubbleView.bounds, to: card.contentView)
            XCTAssertEqual(bubble.maxY, card.contentView.bounds.height, accuracy: 0.5)
        }
    }

    /// The latest news ends as far above the bottom edge as a chat's latest message ends above its field, less the
    /// field: 16 pt above the line where the field rests. The scroll button stands over that line as a chat's stands
    /// over its field, and nothing fades the news under it. Checked against a chat laid out the same, with and without
    /// a home indicator.
    func testLatestNewsEndsWhereAChatsLatestMessageWouldWithoutItsField() async throws {
        for safeAreaBottom: CGFloat in [34, 0] {
            let feed = try await makeFeed(count: 8, safeAreaBottom: safeAreaBottom)
            let chat = AgentTestChat(messages: (0..<12).map { index in
                AgentMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "Message \(index) " + String(repeating: "text ", count: 30), isStreaming: false)
            })
            defer { chat.close() }
            chat.window.rootViewController?.additionalSafeAreaInsets.bottom = safeAreaBottom
            try await chat.waitForStableLayout()

            let chatView = chat.controller.view!
            let field = chat.controller.composerView.convert(chat.controller.composerView.inputBackgroundFrame, to: chatView)
            let lastMessage = try XCTUnwrap(chat.collectionView.cellForItem(at: XCTUnwrap(chat.controller.lastItemIndexPath)))
            XCTAssertEqual(field.minY - lastMessage.convert(lastMessage.bounds, to: chatView).maxY, AgentVCLayout.bottomMessageSpacing, accuracy: 1)
            let fieldLine = field.maxY

            let feedView = feed.controller.view!
            XCTAssertEqual(feedView.bounds.height, chatView.bounds.height)
            let list = feed.controller.collectionView
            XCTAssertEqual(list.contentOffset.y, feed.controller.maxContentOffsetY, accuracy: 0.5)
            let lastCard = try XCTUnwrap(list.cellForItem(at: XCTUnwrap(feed.controller.lastItemIndexPath)))
            XCTAssertEqual(lastCard.convert(lastCard.bounds, to: feedView).maxY, fieldLine - AgentVCLayout.bottomMessageSpacing, accuracy: 1)

            let button = feed.controller.scrollToBottomButton
            XCTAssertEqual(button.convert(button.bounds, to: feedView).maxY, fieldLine - AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5)
            let chatButton = chat.controller.scrollToBottomButton
            XCTAssertEqual(chatButton.convert(chatButton.bounds, to: chatView).maxY, field.minY - AgentVCLayout.scrollToBottomButtonSpacing, accuracy: 0.5)
            XCTAssertFalse(findDescendants(of: feedView).contains {
                $0 is EdgeEffectView && $0.convert($0.bounds, to: feedView).maxY == feedView.bounds.maxY
            })
            if #available(iOS 26.0, *) {
                XCTAssertTrue(list.bottomEdgeEffect.isHidden)
            }
            feed.close()
        }
    }

    /// The first cards come in over the fading skeleton as a chat's messages come in over its skeleton
    func testFirstCardsComeInFromTheSkeletonAsAChatsMessages() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the cards at once")
        let feed = TestFeed(page: .init(locale: "en", items: (1...3).map { makeNewsItem($0) }.reversed()))
        defer { feed.close() }
        let view = try XCTUnwrap(feed.controller.view)
        let skeleton = try XCTUnwrap(findDescendants(of: view).compactMap { $0 as? AgentMessagesSkeletonView }.first)
        XCTAssertFalse(skeleton.isHidden)
        XCTAssertLessThan(
            try XCTUnwrap(view.subviews.firstIndex(of: skeleton)),
            try XCTUnwrap(view.subviews.firstIndex(of: feed.controller.collectionView))
        )
        // The cards can be on screen a moment before the snapshot's completion brings them in
        var cardKeys: Set<String> = []
        var lineKeys: Set<String> = []
        try await feed.waitUntil {
            let rows = feed.controller.collectionView.visibleCells
            cardKeys = Set(rows.compactMap { $0 as? AgentNewsFeedCardCell }.flatMap { $0.newsView.bubbleView.layer.animationKeys() ?? [] })
            lineKeys = Set(rows.filter { $0 is AgentSystemMessageCell }.flatMap { $0.layer.animationKeys() ?? [] })
            return cardKeys.contains { $0.hasPrefix("agentSkeletonReveal.") }
        }
        XCTAssertTrue(cardKeys.contains("agentSkeletonReveal.geometry"), "\(cardKeys)")
        XCTAssertTrue(lineKeys.isSuperset(of: ["agentSkeletonReveal.opacity", "agentSkeletonReveal.scale"]), "\(lineKeys)")
        XCTAssertFalse(lineKeys.contains("agentSkeletonReveal.position"))
    }

    /// Older news come in above with no spinner and no placeholders: they just appear, and the card on screen stays where
    /// it is in the very update that brings them, before the list draws them
    func testOlderNewsAppearAboveWithoutASpinnerAndTheCardOnScreenStays() async throws {
        let feed = TestFeed(page: .init(locale: "en", items: (3...12).map { makeNewsItem($0, isLong: true) }.reversed(), nextCursor: "older"))
        var releaseOlderPage: CheckedContinuation<Void, Never>?
        feed.client.beforeOlderPage = { await withCheckedContinuation { releaseOlderPage = $0 } }
        defer {
            releaseOlderPage?.resume()
            feed.close()
        }
        feed.client.older = .init(locale: "en", items: [makeNewsItem(1, isLong: true), makeNewsItem(2, isLong: true)])
        feed.client.olderDelay = .milliseconds(300)
        try await feed.waitUntil { !feed.model.isLoading && !feed.controller.isScrollToBottomButtonHeld }
        let view = try XCTUnwrap(feed.controller.view)
        let list = feed.controller.collectionView
        XCTAssertTrue(findDescendants(of: view).compactMap { $0 as? AgentLoadingOlderIndicator }.isEmpty)
        // Scrolled up near the top by the program rather than the user, which loads no older news itself
        list.contentOffset.y = -list.adjustedContentInset.top + 320
        try await feed.waitForStableLayout()
        func findCard(_ identifier: String?) -> AgentNewsFeedCardCell? {
            list.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }.first {
                $0.newsView.content?.accessibilityIdentifier == identifier
            }
        }
        let topCard = try XCTUnwrap(list.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }.min { $0.frame.minY < $1.frame.minY })
        let identifier = topCard.newsView.content?.accessibilityIdentifier
        let cardY = topCard.convert(topCard.bounds, to: view).minY
        var cardYsAfterUpdates: [CGFloat?] = []
        let updateFeed = feed.model.onChange
        feed.model.onChange = {
            updateFeed?()
            list.layoutIfNeeded()
            cardYsAfterUpdates.append(findCard(identifier).map { $0.convert($0.bounds, to: view).minY })
        }

        let loading = Task { await feed.model.loadMore() }
        try await feed.waitUntil { feed.model.isLoadingMore }
        XCTAssertFalse(findDescendants(of: view).contains { ($0 as? UIActivityIndicatorView)?.isAnimating == true })
        XCTAssertFalse(findDescendants(of: view).contains { ($0 as? AgentMessagesSkeletonView)?.isShowing == true })
        try await feed.waitUntil { releaseOlderPage != nil }
        releaseOlderPage?.resume()
        releaseOlderPage = nil
        await loading.value
        XCTAssertEqual(feed.model.items.map(\.eventId), Array(1...12))
        XCTAssertFalse(cardYsAfterUpdates.isEmpty)
        for y in cardYsAfterUpdates {
            XCTAssertEqual(try XCTUnwrap(y), cardY, accuracy: 1)
        }
        try await feed.waitForStableLayout()
        let card = try XCTUnwrap(findCard(identifier))
        XCTAssertEqual(card.convert(card.bounds, to: view).minY, cardY, accuracy: 1)
        XCTAssertFalse(findDescendants(of: view).contains { ($0 as? UIActivityIndicatorView)?.isAnimating == true })
    }

    /// Older news start loading as the user scrolls up with five rows, day lines among them, left wholly above the header,
    /// as on Android, and the cards on screen stay where they are as they come in
    func testOlderNewsStartLoadingAsTheUserScrollsUpWithFiveRowsLeftAbove() async throws {
        let feed = try await makeFeedOfSeveralDays()
        let list = feed.controller.collectionView
        let view = try XCTUnwrap(feed.controller.view)
        let threshold = AgentNewsFeedVC.loadOlderRowThreshold
        try await scrollByProgram(feed, bottomOfItem: threshold, belowHeaderBy: -30)
        XCTAssertEqual(countRowsAboveHeader(in: list), threshold + 1)

        // The user drags the feed up, and the sixth row stays above the header
        feed.controller.scrollViewWillBeginDragging(list)
        list.contentOffset.y -= 10
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(countRowsAboveHeader(in: list), threshold + 1)
        XCTAssertEqual(feed.client.olderRequestCount, 0)

        // The sixth row comes under the header
        list.contentOffset.y -= 30
        XCTAssertEqual(countRowsAboveHeader(in: list), threshold)
        try await feed.waitUntil { feed.client.olderRequestCount == 1 }
        let card = try XCTUnwrap(list.cellForItem(at: IndexPath(item: threshold + 1, section: 0)) as? AgentNewsFeedCardCell)
        let identifier = try XCTUnwrap(card.newsView.content?.accessibilityIdentifier)
        let cardY = card.convert(card.bounds, to: view).minY
        feed.controller.scrollViewDidEndDragging(list, willDecelerate: false)

        try await feed.waitUntil { feed.model.items.count == 15 && !feed.model.isLoadingMore }
        try await feed.waitForStableLayout()
        let shownCard = try XCTUnwrap(list.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }.first {
            $0.newsView.content?.accessibilityIdentifier == identifier
        })
        XCTAssertEqual(shownCard.convert(shownCard.bounds, to: view).minY, cardY, accuracy: 1)
    }

    /// A drag that starts with five rows or fewer above the header loads older news at once, as on Android, and the
    /// program taking the feed there loads none
    func testDragThatStartsWithFiveRowsOrFewerAboveLoadsOlderNews() async throws {
        let feed = try await makeFeedOfSeveralDays()
        let list = feed.controller.collectionView
        try await scrollByProgram(feed, bottomOfItem: 2, belowHeaderBy: -30)
        XCTAssertEqual(countRowsAboveHeader(in: list), 3)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(feed.client.olderRequestCount, 0)

        feed.controller.scrollViewWillBeginDragging(list)
        try await feed.waitUntil { feed.client.olderRequestCount == 1 }
        feed.controller.scrollViewDidEndDragging(list, willDecelerate: false)
    }

    /// Twelve long news over four days, newest last, at the feed's end, with an older day's three news to come
    private func makeFeedOfSeveralDays() async throws -> TestFeed {
        func makeItem(_ id: Int) -> ApiAgentV2NewsFeedItem {
            let item = makeNewsItem(id, isLong: true)
            return ApiAgentV2NewsFeedItem(
                eventId: id,
                deliveredAt: String(format: "2026-10-%02dT10:%02d:00Z", 10 + (id - 1) / 3, id),
                headline: item.headline,
                body: item.body,
                imageUrl: nil,
                sources: item.sources
            )
        }
        let feed = TestFeed(page: .init(locale: "en", items: (4...15).map(makeItem).reversed(), nextCursor: "older"))
        addTeardownBlock { feed.close() }
        feed.client.older = .init(locale: "en", items: (1...3).map(makeItem).reversed())
        feed.client.olderDelay = .milliseconds(300)
        try await feed.waitUntil { !feed.model.isLoading && !feed.controller.isScrollToBottomButtonHeld }
        try await feed.waitForStableLayout()
        return feed
    }

    /// Scrolls the feed as the program does, not the user, until the bottom of the row at `item` stands `distance` below
    /// the header's bottom. Rows take their heights as they come into view, so the offset is set again until they have.
    private func scrollByProgram(_ feed: TestFeed, bottomOfItem item: Int, belowHeaderBy distance: CGFloat) async throws {
        let list = feed.controller.collectionView
        for _ in 0..<3 {
            let frame = try XCTUnwrap(list.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame)
            list.contentOffset.y = frame.maxY - distance - list.adjustedContentInset.top
            try await feed.waitForStableLayout()
        }
    }

    /// The rows that lie wholly above the part of the list under the header
    private func countRowsAboveHeader(in list: UICollectionView) -> Int {
        let visibleTop = list.contentOffset.y + list.adjustedContentInset.top
        return (0..<list.numberOfItems(inSection: 0)).filter { item in
            (list.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame.maxY ?? .infinity) <= visibleTop
        }.count
    }

    /// A chat keeps its spinner under its header while it loads older messages
    func testChatShowsItsSpinnerWhileLoadingOlderMessages() throws {
        let chat = AgentTestChat(messages: [AgentMessage(role: .assistant, text: "An answer", isStreaming: false)])
        defer { chat.close() }
        chat.layout()
        let chatSpinner = try XCTUnwrap(findDescendants(of: chat.controller.view).compactMap { $0 as? AgentLoadingOlderIndicator }.first)
        XCTAssertFalse(chatSpinner.isAnimating)
        chat.backend.isLoadingOlderMessages = true
        chat.controller.agentModelDidUpdateState()
        XCTAssertTrue(chatSpinner.isAnimating)
        chat.backend.isLoadingOlderMessages = false
        chat.controller.agentModelDidUpdateState()
        XCTAssertFalse(chatSpinner.isAnimating)
    }

    /// A refresh that fails with news shown keeps them and ends the feed with a chat's failure line and Retry, as a
    /// chat that fails to reload ends with it; with nothing to show the failure stands in the middle
    func testFailedRefreshWithNewsShownEndsTheFeedWithAChatsFailureLine() async throws {
        let feed = try await makeFeed(count: 3)
        let errorView = try XCTUnwrap(findDescendants(of: feed.controller.view).compactMap { $0 as? AgentLoadErrorView }.first)
        feed.client.firstPageError = URLError(.notConnectedToInternet)
        await feed.model.refresh()
        try await feed.waitForStableLayout()
        XCTAssertTrue(errorView.isHidden)
        let list = feed.controller.collectionView
        let lastIndexPath = try XCTUnwrap(feed.controller.lastItemIndexPath)
        let line = try XCTUnwrap(list.cellForItem(at: lastIndexPath) as? AgentSystemMessageCell)
        let caption = try XCTUnwrap(findDescendants(of: line).compactMap { $0 as? UITextView }.first { !$0.isHidden })
        XCTAssertTrue(caption.text.hasPrefix(lang("$agent_error_generic")), caption.text)
        XCTAssertTrue(caption.text.hasSuffix(lang("Retry")), caption.text)
        XCTAssertTrue(feed.controller.isNearBottom())
        XCTAssertEqual(list.visibleCells.filter { $0 is AgentNewsFeedCardCell }.count, 3)
        XCTAssertEqual(try XCTUnwrap(line.contextMenuConfigurationProvider?()).style.horizontalAlignment, .center)

        // Retry refreshes, and the line goes with the failure
        let retryURL = try XCTUnwrap(URL(string: "agent-control:retry-load"))
        _ = line.textView(caption, shouldInteractWith: retryURL, in: NSRange(location: 0, length: 1))
        try await feed.waitUntil { !feed.model.isLoading && feed.model.error == nil }
        try await feed.waitForStableLayout()
        XCTAssertFalse(list.visibleCells.contains { $0 is AgentSystemMessageCell && list.indexPath(for: $0) == feed.controller.lastItemIndexPath })
    }

    /// The feed renders a news body once for every card and post that shows it, as a chat lays out each answer once,
    /// and a refresh that changes nothing configures no card again
    func testNewsBodiesRenderOnceAndUnchangedCardsStayAsTheyAre() async throws {
        let item = makeNewsItem(7, isLong: true)
        let first = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        let second = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        first.configure(with: item)
        second.configure(with: item)
        // The second card takes the text the first parsed
        let body = try XCTUnwrap(AgentNewsFeedCardCell.makeContent(for: item).body)
        let key = AgentNewsPostView.getBodyKey(for: body, traitCollection: second.newsView.traitCollection)
        var parses = 0
        let cached = AgentTextLayoutCache.shared.getAttributedText(for: key) {
            parses += 1
            return NSAttributedString()
        }
        XCTAssertEqual(parses, 0)
        func shownBody(of cell: AgentNewsFeedCardCell) -> String? {
            findDescendants(of: cell).compactMap { $0 as? UILabel }.first { $0.attributedText?.string.hasPrefix("News market") == true }?.attributedText?.string
        }
        XCTAssertFalse(cached.string.isEmpty)
        XCTAssertEqual(shownBody(of: first), cached.string)
        XCTAssertEqual(shownBody(of: second), cached.string)

        let feed = try await makeFeed(count: 4)
        let cards = feed.controller.collectionView.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }
        XCTAssertFalse(cards.isEmpty)
        var providers = 0
        for card in cards {
            card.newsView.contextMenuConfigurationProvider = { providers += 1; return nil }
        }
        await feed.model.refresh()
        try await feed.waitForStableLayout()
        // A card configured again would have its menu provider replaced
        for card in cards {
            _ = card.newsView.contextMenuConfigurationProvider?()
        }
        XCTAssertEqual(providers, cards.count)
    }

    /// The feed takes a swipe back by a chat's rule: anywhere, but on content that can still scroll back
    func testFeedFollowsAChatsSwipeBackRule() async throws {
        let feed = try await makeFeed(count: 3)
        let controller = feed.controller
        XCTAssertTrue((controller as UIViewController as? WBackSwipeControlling)?.shouldAllowBackSwipe(at: CGPoint(x: 100, y: 300)) == true)
        let table = UIScrollView(frame: CGRect(x: 0, y: 200, width: 300, height: 100))
        table.contentSize = CGSize(width: 900, height: 100)
        table.contentOffset.x = 200
        controller.view.addSubview(table)
        XCTAssertFalse(controller.shouldAllowBackSwipe(at: CGPoint(x: 100, y: 250)))
        XCTAssertEqual(
            controller.shouldAllowBackSwipe(at: CGPoint(x: 100, y: 250)),
            AgentChatBackSwipe.shouldAllowBackSwipe(in: controller.view, at: CGPoint(x: 100, y: 250))
        )
        table.removeFromSuperview()
    }

    /// A card is as tall as what it shows, whatever height it is measured against: the list's estimate or the height it
    /// had before its news or picture changed
    func testCardIsAsTallAsItsContentWhateverHeightItIsMeasuredAgainst() {
        let card = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        card.configure(with: makeNewsItem(1))
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.frame = CGRect(x: 0, y: 0, width: 402, height: 100)
        _ = card.preferredLayoutAttributesFitting(attributes)
        func measure(against height: CGFloat) -> CGFloat {
            card.systemLayoutSizeFitting(
                CGSize(width: 402, height: height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        }
        let natural = measure(against: UIView.layoutFittingCompressedSize.height)
        for height in [180, 400] as [CGFloat] {
            XCTAssertEqual(measure(against: height), natural, accuracy: 0.5, "\(height)")
        }
    }

    /// A card whose picture doesn't load gives up the picture's place, as the cards around it keep theirs
    func testCardWhosePictureFailsToLoadGivesUpItsPlace() async throws {
        let items = (1...3).map { makeNewsItem($0, imageURL: $0 == 2 ? "invalid-news-image://2" : nil) }
        let feed = TestFeed(page: .init(locale: "en", items: items.reversed()))
        defer { feed.close() }
        func findCard() -> AgentNewsFeedCardCell? {
            feed.controller.collectionView.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsCard-2" } as? AgentNewsFeedCardCell
        }
        try await feed.waitUntil { findCard()?.newsView.imageView.isHidden == true }
        try await feed.waitForStableLayout()
        try assertCardsStandAtTheirHeights(in: feed)
    }

    /// Each card on screen stands as tall as a card that shows its news for the first time
    private func assertCardsStandAtTheirHeights(in feed: TestFeed, file: StaticString = #filePath, line: UInt = #line) throws {
        let cards = feed.controller.collectionView.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }
        XCTAssertFalse(cards.isEmpty, file: file, line: line)
        for card in cards {
            let item = try XCTUnwrap(
                feed.model.items.first { card.accessibilityIdentifier == "AgentNewsCard-\($0.eventId)" },
                file: file,
                line: line
            )
            // A picture that didn't load is left out, as the card on screen leaves it out
            let shown = ApiAgentV2NewsFeedItem(
                eventId: item.eventId,
                deliveredAt: item.deliveredAt,
                headline: item.headline,
                body: item.body,
                imageUrl: card.newsView.imageView.isHidden ? nil : item.imageUrl,
                sources: item.sources,
                discussion: item.discussion
            )
            let width = card.bounds.width
            let fresh = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: width, height: 600))
            fresh.configure(with: shown)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            attributes.frame = CGRect(x: 0, y: 0, width: width, height: 100)
            _ = fresh.preferredLayoutAttributesFitting(attributes)
            let height = fresh.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            XCTAssertEqual(card.frame.height, height, accuracy: 1, "\(card.accessibilityIdentifier ?? "")", file: file, line: line)
        }
    }

    func makeFeed(
        count: Int,
        size: CGSize = CGSize(width: 402, height: 874),
        safeAreaBottom: CGFloat = 0
    ) async throws -> TestFeed {
        let items = (1...count).map { makeNewsItem($0, isLong: true) }
        let feed = TestFeed(page: .init(locale: "en", items: items.reversed()), safeAreaBottom: safeAreaBottom, size: size)
        addTeardownBlock { feed.close() }
        try await feed.waitUntil {
            !feed.model.isLoading && !feed.controller.isScrollToBottomButtonHeld
                && feed.controller.collectionView.visibleCells.contains { $0 is AgentNewsFeedCardCell }
        }
        try await feed.waitForStableLayout()
        return feed
    }
}

/// The News feed in a key window, over a client that serves `page`
@MainActor
final class TestFeed {
    final class Client: AgentNewsFeedClient {
        var page: ApiAgentV2NewsFeedPage
        var older: ApiAgentV2NewsFeedPage?
        /// Fails the next first-page request
        var firstPageError: Error?
        /// How long an older page takes to come
        var olderDelay: Duration?
        var beforeOlderPage: (() async -> Void)?
        /// How many times the feed asked for an older page
        var olderRequestCount = 0

        init(page: ApiAgentV2NewsFeedPage) {
            self.page = page
        }

        func getNewsFeed(lang: String, cursor: String?, schedule: AgentNewsDigestSchedule, view: ApiAgentV2NewsFeedView = .all) async throws -> ApiAgentV2NewsFeedPage {
            guard cursor != nil else {
                if let firstPageError {
                    self.firstPageError = nil
                    throw firstPageError
                }
                return page
            }
            olderRequestCount += 1
            await beforeOlderPage?()
            if let olderDelay {
                try await Task.sleep(for: olderDelay)
            }
            return older ?? .init(locale: page.locale, items: [])
        }
    }

    let client: Client
    let model: AgentNewsFeedModel
    let controller: AgentNewsFeedVC
    let window: UIWindow
    private let defaultsName = "TestFeed-\(UUID().uuidString)"

    init(
        page: ApiAgentV2NewsFeedPage,
        readThrough: ApiAgentV2NewsFeedItem? = nil,
        safeAreaBottom: CGFloat = 0,
        size: CGSize = CGSize(width: 402, height: 874)
    ) {
        client = Client(page: page)
        let readState = AgentNewsReadState(userDefaults: UserDefaults(suiteName: defaultsName)!)
        if let readThrough {
            readState.markRead(items: [readThrough])
        }
        model = AgentNewsFeedModel(client: client, readState: readState)
        controller = AgentNewsFeedVC(model: model)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.additionalSafeAreaInsets.bottom = safeAreaBottom
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    func close() {
        window.rootViewController = nil
        window.isHidden = true
        UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
    }

    func layout() {
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        controller.collectionView.layoutIfNeeded()
    }

    /// Waits until the list's offset and content stay put for 20 frames, as the cards settle their heights
    func waitForStableLayout() async throws {
        var state: [CGFloat] = []
        var stableSamples = 0
        for _ in 0..<600 {
            try await Task.sleep(for: .milliseconds(16))
            layout()
            let collectionView = controller.collectionView
            let nextState = [
                collectionView.contentOffset.y,
                collectionView.collectionViewLayout.collectionViewContentSize.height,
                collectionView.adjustedContentInset.bottom,
            ]
            stableSamples = nextState == state ? stableSamples + 1 : 0
            state = nextState
            if stableSamples >= 20 { return }
        }
        throw AgentTestTimeout()
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            layout()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AgentTestTimeout()
    }
}

func makeNewsItem(_ id: Int, isLong: Bool = false, imageURL: String? = nil) -> ApiAgentV2NewsFeedItem {
    ApiAgentV2NewsFeedItem(
        eventId: id,
        deliveredAt: String(format: "2026-10-20T10:%02d:00Z", id % 60),
        headline: "Headline \(id)",
        body: isLong ? Array(repeating: "News **market** text.", count: 6).joined(separator: "\n") : "News body \(id).",
        imageUrl: imageURL,
        sources: [.init(name: "Source", url: "https://example.com/\(id)")]
    )
}

@MainActor
private final class FeedOffsetLog {
    var offsets: [CGFloat] = []
}
