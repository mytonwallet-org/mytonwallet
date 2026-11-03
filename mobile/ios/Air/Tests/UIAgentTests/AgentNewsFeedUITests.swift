import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources
import Kingfisher

@MainActor
final class AgentNewsFeedUITests: XCTestCase {
    func testCardCollapsesMissingImageAndReadsHeadlineBodySourceAndTime() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 370, height: 400))
        let item = ApiAgentV2NewsFeedItem(
            eventId: 1,
            deliveredAt: "2026-10-20T10:30:00Z",
            headline: "Market news",
            body: "Bitcoin is **rising**.",
            sources: [.init(url: "https://example.com/first"), .init(name: "Market Source", url: "https://example.com/second")]
        )
        cell.configure(with: item)
        let image = try XCTUnwrap(descendants(cell).compactMap { $0 as? WImageView }.first)
        XCTAssertTrue(image.isHidden)
        XCTAssertFalse(image.isAccessibilityElement)
        let element = cell.newsView.accessibilityContentElement
        XCTAssertEqual(element.accessibilityCustomActions?.count, 2)
        XCTAssertTrue(element.accessibilityLabel?.hasPrefix("Market news, Bitcoin is rising., ") == true)
        XCTAssertFalse(element.accessibilityLabel?.contains("Market Source") == true)
        let body = try XCTUnwrap(descendants(cell).compactMap { $0 as? UILabel }.first {
            $0.attributedText?.string == "Bitcoin is rising."
        })
        let boldRange = (body.attributedText!.string as NSString).range(of: "rising")
        let font = try XCTUnwrap(body.attributedText?.attribute(.font, at: boldRange.location, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        cell.prepareForReuse()
        cell.configure(with: makeItem(2))
        XCTAssertTrue(image.isHidden)
        XCTAssertEqual(element.accessibilityCustomActions?.count, 1)
    }

    func testCopyAndShareTextIncludesPlainBodyAndFirstSource() {
        let item = ApiAgentV2NewsFeedItem(
            eventId: 1,
            deliveredAt: "2026-10-20T10:30:00Z",
            headline: "Headline",
            body: "A **bold** word.\nSecond paragraph.",
            sources: [.init(url: "https://example.com/first"), .init(url: "https://example.com/second")]
        )
        XCTAssertEqual(AgentNewsFeedVC.copyText(for: item), "Headline\n\nA bold word.\nSecond paragraph.\n\nhttps://example.com/first")
        XCTAssertEqual(AgentNewsFeedVC.copyText(for: makeItem(2)), "Headline 2\n\nNews body 2.")
    }

    func testNewsButtonPushesWithPageLocaleIgnoresRepeatedTapsAndUpdatesOlderCard() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = NewsFeedUIClient(first: .success(.init(locale: "pt", items: [makeItem(3)], nextCursor: "older")))
        client.older = .init(locale: "pt", items: [makeItem(1)])
        var threads: [String: ApiAgentV2ThreadSummary] = [:]
        let model = AgentNewsFeedModel(
            client: client,
            readState: AgentNewsReadState(userDefaults: makeDefaults()),
            language: { "pt-BR" },
            findThread: { threads[$0] }
        )
        await model.refresh()
        await model.loadMore()
        var requests: [(eventId: Int, locale: String)] = []
        var completions: [(ApiAgentV2ThreadSummary) -> Void] = []
        var chats: [UIViewController] = []
        let preloader = AgentPreloader(client: FakeAgentV2Client())
        defer { preloader.setWalletReady(false) }
        let controller = AgentNewsFeedVC(model: model, preloader: preloader, makeNewsChatViewController: { item, locale, completion in
            requests.append((item.eventId, locale))
            XCTAssertEqual(item, model.items.first { $0.eventId == item.eventId })
            completions.append(completion)
            let chat = UIViewController()
            chats.append(chat)
            return chat
        })
        let window = present(controller)
        defer { window.isHidden = true }
        let navigationController = try XCTUnwrap(controller.navigationController)
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil { !model.isLoading && collection.visibleCells.contains { $0 is AgentNewsFeedCardCell } }
        collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: false)
        collection.layoutIfNeeded()
        let cell = try XCTUnwrap(collection.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsCard-1" })
        let button = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIButton }.first)

        let action = try XCTUnwrap(button.actions(forTarget: cell, forControlEvent: .touchUpInside)?.first)
        cell.perform(NSSelectorFromString(action), with: button)
        cell.perform(NSSelectorFromString(action), with: button)

        let request = try XCTUnwrap(requests.first)
        let completion = try XCTUnwrap(completions.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.eventId, 1)
        XCTAssertEqual(request.locale, "pt")
        XCTAssertEqual(navigationController.viewControllers.count, 2)
        XCTAssertTrue(navigationController.topViewController === chats.first)
        // The user has written in the discussion after its post, so the card offers to continue it
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data("""
        {"id":"news-thread","revision":1,"createdAt":"2026-10-20T12:00:00Z","updatedAt":"2026-10-20T12:00:00Z",
         "lastActivityAt":"2026-10-20T12:00:00Z","messageCount":2,"icon":"📰"}
        """.utf8))
        threads[thread.id] = thread
        completion(thread)
        XCTAssertEqual(model.items.first?.discussion, .init(threadId: "news-thread", icon: "📰"))
        try await waitUntil { navigationController.transitionCoordinator == nil }
        navigationController.popViewController(animated: false)
        try await waitUntil {
            window.layoutIfNeeded()
            return navigationController.topViewController === controller && !model.isLoading
                && collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-1" }
        }
        let updatedCell = try XCTUnwrap(collection.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsCard-1" })
        let updatedButton = try XCTUnwrap(descendants(updatedCell).compactMap { $0 as? UIButton }.first)
        try await waitUntil {
            updatedButton.accessibilityLabel == L10n.agentNewsContinueDiscussionAccessibility(headline: "Headline 1")
        }
        XCTAssertTrue(descendants(updatedButton).compactMap { $0 as? UILabel }.contains { $0.text == lang("$agent_news_continue_discussion") })
        XCTAssertEqual(model.items.first?.discussion?.threadId, "news-thread")

        WalletCoreData.notify(event: .agentThreadDeleted(threadId: "news-thread"))
        try await waitUntil { model.items.first?.discussion == nil }
        try await waitUntil {
            window.layoutIfNeeded()
            return navigationController.topViewController === controller && !model.isLoading
                && collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-1" }
        }
        let resetCell = try XCTUnwrap(collection.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsCard-1" })
        let resetButton = try XCTUnwrap(descendants(resetCell).compactMap { $0 as? UIButton }.first)
        try await waitUntil {
            resetButton.accessibilityLabel == "\(lang("$agent_news_discuss")), Headline 1"
        }
        XCTAssertTrue(descendants(resetButton).compactMap { $0 as? UILabel }.contains { $0.text == lang("$agent_news_discuss") })
        // The thread avatar with the discussion's emoji gives way to the Agent's mark
        let avatar = try XCTUnwrap(descendants(resetButton).compactMap { $0 as? AgentThreadAvatarView }.first)
        XCTAssertTrue(avatar.isHidden)
    }

    func testNewsDiscussionPushKeepsTheNeighborVisibleWhileTheScreensMove() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("The news transition requires an application host with a window scene")
        }
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "The card stays in place with Reduce Motion")
        _ = WalletResourcesBundle.bundle.load()
        let imageKey = "https://example.invalid/news-neighbor-\(UUID().uuidString).png"
        let orangeImage = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
        try await ImageCache.default.store(orangeImage, forKey: imageKey, toDisk: false)
        defer { ImageCache.default.removeImage(forKey: imageKey, fromDisk: false, completionHandler: nil) }
        let discussed = ApiAgentV2NewsFeedItem(
            eventId: 1, deliveredAt: "2026-10-20T10:00:00Z", headline: "The discussed news",
            body: String(repeating: "The news remains in place while its discussion opens. ", count: 14)
        )
        let neighbor = ApiAgentV2NewsFeedItem(
            eventId: 2, deliveredAt: "2026-10-20T10:01:00Z", headline: "The orange neighboring news",
            body: String(repeating: "The next post remains visible until the discussion covers it. ", count: 12),
            imageUrl: imageKey
        )
        let model = AgentNewsFeedModel(
            client: NewsFeedUIClient(first: .success(.init(locale: "en", items: [neighbor, discussed]))),
            readState: AgentNewsReadState(userDefaults: makeDefaults())
        )
        await model.refresh()
        let preloader = AgentPreloader(client: FakeAgentV2Client())
        var clients: [FakeAgentV2Client] = []
        var chats: [AgentVC] = []
        let feed = AgentNewsFeedVC(model: model, preloader: preloader, makeNewsChatViewController: { item, locale, _ in
            let client = FakeAgentV2Client()
            client.blocksThreadCreation = true
            clients.append(client)
            let chat = AgentVC(model: AgentV2Model(client: client, news: item, locale: locale) { _ in })
            chats.append(chat)
            return chat
        })
        let navigation = WNavigationController(rootViewController: feed)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            chats.forEach { ($0.model as? AgentV2Model)?.stop() }
            clients.forEach { $0.resumeThreadCreation() }
            preloader.setWalletReady(false)
            previousKeyWindow?.makeKey()
        }
        let collection = try XCTUnwrap(descendants(feed.view).compactMap { $0 as? UICollectionView }.first)
        for attempt in 0..<3 {
            try await waitUntil {
                window.layoutIfNeeded()
                return !model.isLoading && navigation.transitionCoordinator == nil
                    && collection.numberOfItems(inSection: 0) >= 2
            }
            collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: false)
            collection.layoutIfNeeded()
            let card = try XCTUnwrap(collection.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }.first {
                $0.accessibilityIdentifier == "AgentNewsCard-1"
            })
            let cardBottom = card.convert(card.bounds, to: window).maxY
            collection.setContentOffset(CGPoint(x: 0, y: collection.contentOffset.y + cardBottom - 340), animated: false)
            collection.layoutIfNeeded()
            let nextCard = try XCTUnwrap(collection.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }.first {
                $0.accessibilityIdentifier == "AgentNewsCard-2"
            })
            try await waitUntil { nextCard.newsView.imageView.image != nil }
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertTrue(nextCard.convert(nextCard.bounds, to: window).intersects(window.bounds))

            let button = try XCTUnwrap(descendants(card).compactMap { $0 as? UIButton }.first)
            let action = try XCTUnwrap(button.actions(forTarget: card, forControlEvent: .touchUpInside)?.first)
            card.perform(NSSelectorFromString(action), with: button)
            let chat = try XCTUnwrap(chats.last)
            XCTAssertTrue(navigation.topViewController === chat)
            XCTAssertNotNil(chat.newsPostArrival)
            var movingSamples = 0
            // No synchronous hierarchy capture here: simctl records the actual committed frames, including
            // any intermediate composition before UIKit installs the push animation.
            for _ in 0..<50 {
                if let layer = chat.view.layer.presentation(), let windowLayer = window.layer.presentation() {
                    let x = layer.convert(layer.bounds, to: windowLayer).minX
                    if x > 1 && x < window.bounds.width - 1 {
                        movingSamples += 1
                        XCTAssertEqual(nextCard.newsView.alpha, 1, "Neighbor hidden during push \(attempt)")
                        XCTAssertFalse(nextCard.isHidden)
                        XCTAssertTrue(nextCard.window === window)
                    }
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertGreaterThan(movingSamples, 2, "Observe the actual sliding screens, not just the settled chat")
            try await waitUntil { navigation.transitionCoordinator == nil && chat.newsPostArrival == nil }
            navigation.popViewController(animated: true)
            try await waitUntil { navigation.transitionCoordinator == nil && navigation.topViewController === feed }
            XCTAssertEqual(card.newsView.alpha, 1)
            clients.last?.resumeThreadCreation()
        }
    }

    func testSourceLinksOnlyDispatchAllowedAppScreensToDeeplinkHandler() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let oldDelegate = WalletContextManager.delegate
        let delegate = NewsFeedLinkDelegate()
        WalletContextManager.delegate = delegate
        defer { WalletContextManager.delegate = oldDelegate }
        let cases: [(String, String)] = [
            ("\(SELF_PROTOCOL)transfer?amount=1", "unsupported"),
            (SELF_PROTOCOL, "unsupported"),
            ("ton://transfer/EQaddress?amount=1", "unsupported"),
            ("tc://connect", "unsupported"),
            ("https://user:password@example.com/article", "unsupported"),
            ("https://example.com/article", "browser"),
            ("http://example.com/article", "browser"),
            ("\(SHORT_UNIVERSAL_URL)transfer?amount=1", "browser"),
            ("https://t.me/news/123", "telegram"),
            ("tg://resolve?domain=news", "telegram"),
            ("\(SELF_PROTOCOL)settings/appearance", "screen")
        ]
        for (rawURL, expected) in cases {
            let url = try XCTUnwrap(URL(string: rawURL))
            let item = ApiAgentV2NewsFeedItem(
                eventId: 1,
                deliveredAt: "2026-10-20T10:30:00Z",
                headline: "News",
                body: "Body",
                sources: [.init(url: rawURL)]
            )
            let client = NewsFeedUIClient(first: .success(.init(locale: "en", items: [item])))
            let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()))
            var browserURLs: [URL] = []
            var telegramURLs: [URL] = []
            var errors: [DisplayError] = []
            let controller = AgentNewsFeedVC(
                model: model,
                openInBrowser: { browserURLs.append($0) },
                openTelegramURL: { telegramURLs.append($0) },
                showLinkError: { errors.append($0) }
            )
            let window = present(controller)
            defer { window.isHidden = true }
            let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
            try await waitUntil {
                window.layoutIfNeeded()
                return collection.visibleCells.contains { $0 is AgentNewsFeedCardCell }
            }
            let cell = try XCTUnwrap(collection.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }.first)
            delegate.openedURLs = []
            cell.openSourceAction?()

            XCTAssertEqual(delegate.openedURLs, expected == "screen" ? [url] : [], rawURL)
            XCTAssertEqual(browserURLs, expected == "browser" ? [url] : [], rawURL)
            XCTAssertEqual(telegramURLs, expected == "telegram" ? [url] : [], rawURL)
            XCTAssertEqual(errors.map(\.text), expected == "unsupported" ? [lang("Unsupported link")] : [], rawURL)
        }
    }

    func testVisibleFeedRefreshesOnForegroundAndHiddenFeedDoesNot() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = NewsFeedUIClient(first: .success(.init(locale: "en", items: [makeItem(1)])))
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()))
        let controller = AgentNewsFeedVC(model: model)
        controller.loadViewIfNeeded()
        controller.walletCore(event: .applicationWillEnterForeground)
        await Task.yield()
        XCTAssertTrue(client.cursors.isEmpty)

        controller.viewWillAppear(false)
        try await waitUntil { client.cursors.count == 1 && !model.isLoading }
        client.first = .success(.init(locale: "en", items: [makeItem(2), makeItem(1)]))
        WalletCoreData.notify(event: .applicationWillEnterForeground)
        try await waitUntil { client.cursors.count == 2 && model.items.count == 2 && !model.isLoading }
        XCTAssertEqual(client.cursors, [nil, nil])
        XCTAssertEqual(model.items.map(\.eventId), [1, 2])

        controller.viewWillDisappear(false)
        controller.walletCore(event: .applicationWillEnterForeground)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(client.cursors.count, 2)
    }

    func testInitialScrollShowsUnreadDividerAndHeaderHasNoMenuOrComposer() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let defaults = makeDefaults()
        let readState = AgentNewsReadState(userDefaults: defaults)
        readState.markRead(items: [makeItem(6)])
        let items = (1...9).map { makeItem($0, longBody: true) }
        let client = NewsFeedUIClient(first: .success(.init(locale: "en", items: Array(items.reversed()))))
        let model = AgentNewsFeedModel(client: client, readState: readState)
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil {
            window.layoutIfNeeded()
            return collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsUnreadDivider" }
        }
        let divider = try XCTUnwrap(collection.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsUnreadDivider" })
        XCTAssertEqual(divider.frame.minY - collection.contentOffset.y, collection.adjustedContentInset.top, accuracy: 3)
        XCTAssertEqual(model.unreadEventId, 7)
        XCTAssertTrue(collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-7" })
        XCTAssertNil(controller.navigationItem.rightBarButtonItem)
        XCTAssertFalse(descendants(controller.view).contains { $0 is AgentComposerView })
        XCTAssertEqual(controller.title, lang("News"))
        let titleView = try XCTUnwrap(controller.navigationItem.titleView)
        let title = try XCTUnwrap(descendants(titleView).compactMap { $0 as? AgentChatTitleView }.first)
        XCTAssertEqual(title.accessibilityLabel, lang("News"))
        XCTAssertTrue(title.accessibilityTraits.contains(.header))
    }

    func testPushedFeedSharesTheChatHeaderAndThreadsButton() throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentNewsFeedModel(
            client: NewsFeedUIClient(first: .success(.init(locale: "en", items: [makeItem(1)]))),
            readState: AgentNewsReadState(userDefaults: makeDefaults())
        )
        let controller = AgentNewsFeedVC(model: model)
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = makeKeyWindow(showing: navigation)
        defer { window.isHidden = true }
        navigation.pushViewController(controller, animated: false)
        controller.loadViewIfNeeded()
        controller.viewIsAppearing(false)

        let threadsCircle = try XCTUnwrap(controller.navigationHandoffLeadingView as? AgentGlassCircleButton)
        XCTAssertEqual(threadsCircle.button.accessibilityIdentifier, "agent_threads_button")
        XCTAssertEqual(threadsCircle.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertTrue(controller.navigationItem.hidesBackButton)
        XCTAssertNil(controller.navigationHandoffTrailingView)
        for appearance in [controller.navigationItem.standardAppearance, controller.navigationItem.scrollEdgeAppearance] {
            let appearance = try XCTUnwrap(appearance)
            XCTAssertNil(appearance.backgroundEffect)
            XCTAssertEqual(appearance.backgroundColor?.cgColor.alpha ?? 0, 0)
        }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(collection.topEdgeEffect.isHidden)
        }
        XCTAssertTrue(descendants(controller.view).contains { $0 is EdgeEffectView })
        controller.setNavigationHandoffHidden(true)
        XCTAssertEqual(threadsCircle.alpha, 0)
        controller.setNavigationHandoffHidden(false)
        XCTAssertEqual(threadsCircle.alpha, 1)
    }

    func testCachedPageShowsAtOnceAndAnEmptyFeedLoadsBehindTheSkeleton() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let page = ApiAgentV2NewsFeedPage(locale: "en", items: [makeItem(2), makeItem(1)])
        let cached = AgentNewsFeedModel(
            client: NewsFeedUIClient(first: .success(page)),
            readState: AgentNewsReadState(userDefaults: makeDefaults()),
            cachedPage: (page, "en")
        )
        XCTAssertEqual(cached.items.map(\.eventId), [1, 2])
        XCTAssertEqual(cached.locale, "en")
        let cachedController = AgentNewsFeedVC(model: cached)
        let cachedWindow = present(cachedController)
        defer { cachedWindow.isHidden = true }
        let cachedCollection = try XCTUnwrap(descendants(cachedController.view).compactMap { $0 as? UICollectionView }.first)
        cachedCollection.layoutIfNeeded()
        XCTAssertTrue(cachedCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-2" })
        XCTAssertTrue(try XCTUnwrap(descendants(cachedController.view).compactMap { $0 as? AgentMessagesSkeletonView }.first).isHidden)

        let model = AgentNewsFeedModel(
            client: NewsFeedUIClient(first: .success(page)),
            readState: AgentNewsReadState(userDefaults: makeDefaults())
        )
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let skeleton = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentMessagesSkeletonView }.first)
        XCTAssertFalse(skeleton.isHidden)
        XCTAssertFalse(descendants(controller.view).contains { ($0 as? UIActivityIndicatorView)?.isAnimating == true })
        try await waitUntil { model.items.count == 2 && skeleton.isHidden }
    }

    func testNoUnreadStartsAtBottomAndOlderPagePreservesVisibleCard() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = NewsFeedUIClient(first: .success(.init(
            locale: "en", items: Array((3...10).map { makeItem($0, longBody: true) }.reversed()), nextCursor: "older"
        )))
        client.older = .init(locale: "en", items: [makeItem(2, longBody: true), makeItem(1, longBody: true)])
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()))
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil {
            window.layoutIfNeeded()
            return collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-10" }
        }
        XCTAssertEqual(collection.contentOffset.y, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom, accuracy: 3)
        let scrollToLatest = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentScrollToBottomButton }.first {
            $0.accessibilityIdentifier == "AgentNewsScrollToBottom"
        })
        XCTAssertFalse(scrollToLatest.isButtonVisible)
        collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: false)
        collection.layoutIfNeeded()
        controller.scrollViewDidScroll(collection)
        XCTAssertTrue(scrollToLatest.isButtonVisible)
        XCTAssertEqual(scrollToLatest.bounds.size, CGSize(width: AgentScrollToBottomButton.size, height: AgentScrollToBottomButton.size))
        let original = try XCTUnwrap(collection.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsCard-3" })
        let originalY = original.frame.minY - collection.contentOffset.y
        await model.loadMore()
        try await waitUntil {
            collection.layoutIfNeeded()
            guard collection.numberOfItems(inSection: 0) == 11,
                  let retained = collection.visibleCells.first(where: { $0.accessibilityIdentifier == "AgentNewsCard-3" }) else { return false }
            return abs(retained.frame.minY - collection.contentOffset.y - originalY) < 3
        }
        let retained = try XCTUnwrap(collection.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsCard-3" })
        XCTAssertEqual(retained.frame.minY - collection.contentOffset.y, originalY, accuracy: 3)
        XCTAssertEqual(client.cursors, [nil, "older"])
    }

    func testInitialNewsUnavailableOffersRetryAndRecovers() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = NewsFeedUIClient(first: .failure(SdkError.apiReturnedError(error: "news_unavailable", data: nil)))
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()))
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        try await waitUntil { model.error != nil }
        let errorView = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentLoadErrorView }.first)
        XCTAssertEqual(errorView.label.text, lang("$agent_news_unavailable"))
        let retry = errorView.retryButton
        XCTAssertFalse(retry.superview?.isHidden == true)
        client.first = .success(.init(locale: "en", items: [makeItem(1)]))
        let action = try XCTUnwrap(retry.actions(forTarget: errorView, forControlEvent: .touchUpInside)?.first)
        errorView.perform(NSSelectorFromString(action), with: retry)
        try await waitUntil { model.items.count == 1 && !model.isLoading }
        XCTAssertNil(model.error)
        XCTAssertTrue(retry.superview?.isHidden == true)
        XCTAssertEqual(client.cursors.count, 2)
        XCTAssertEqual(AgentNewsFeedVC.errorText(SdkError.unexpected(message: "Failure")), lang("$agent_error_generic"))
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AgentNewsFeedUITests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeItem(_ id: Int, longBody: Bool = false) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: id,
            deliveredAt: String(format: "2026-10-20T10:%02d:00Z", id),
            headline: "Headline \(id)",
            body: longBody ? Array(repeating: "News **market** text.", count: 12).joined(separator: "\n") : "News body \(id)."
        )
    }

    private func present(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("News feed UI did not settle within 2 seconds", file: file, line: line)
        throw NewsFeedUIError.timedOut
    }
}

private enum NewsFeedUIError: Error {
    case timedOut
}

@MainActor
private final class NewsFeedLinkDelegate: NSObject, WalletContextDelegate {
    var openedURLs: [URL] = []
    var isWalletReady: Bool { true }
    var isAppUnlocked: Bool { true }

    func bridgeIsReady() {}
    func walletIsReady(isReady: Bool) {}
    func restartApp() {}

    func handleDeeplink(url: URL, source: DeeplinkOpenSource) -> Bool {
        openedURLs.append(url)
        return true
    }
}

@MainActor
private final class NewsFeedUIClient: AgentNewsFeedClient {
    var first: Result<ApiAgentV2NewsFeedPage, Error>
    var older = ApiAgentV2NewsFeedPage(locale: "en", items: [])
    var cursors: [String?] = []

    init(first: Result<ApiAgentV2NewsFeedPage, Error>) {
        self.first = first
    }

    func getNewsFeed(lang: String, cursor: String?) async throws -> ApiAgentV2NewsFeedPage {
        cursors.append(cursor)
        return try cursor == nil ? first.get() : older
    }
}
