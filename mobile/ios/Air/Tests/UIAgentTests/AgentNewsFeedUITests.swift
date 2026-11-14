import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
import Kingfisher

@MainActor
final class AgentNewsFeedUITests: XCTestCase {
    func testCardCollapsesMissingImageAndReadsHeadlineBodyAndTime() throws {
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
        // The header's trailing slot holds the bell of the digest and notifications sheet, without a chat's menu
        XCTAssertEqual(
            AgentChatNavigation.findButton(in: controller.navigationItem.rightBarButtonItem)?.accessibilityIdentifier,
            AgentChatNavigation.digestSettingsButtonIdentifier
        )
        XCTAssertFalse(descendants(controller.view).contains { $0 is AgentComposerView })
        XCTAssertEqual(controller.title, lang("News"))
        // The view switch stands in the title's place, and the header's morph takes it for the title's pill
        let titleView = try XCTUnwrap(controller.navigationItem.titleView)
        let viewSwitch = try XCTUnwrap(descendants(titleView).compactMap { $0 as? WSegmentedControl }.first)
        XCTAssertFalse(descendants(titleView).contains { $0 is AgentChatTitleView })
        XCTAssertTrue(controller.navigationHandoffTitlePill === viewSwitch)
        XCTAssertEqual(viewSwitch.model.items.map(\.id), ["all", "digests"])
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
        let bell = try XCTUnwrap(controller.navigationHandoffTrailingView as? AgentGlassCircleButton)
        XCTAssertEqual(bell.button.accessibilityIdentifier, AgentChatNavigation.digestSettingsButtonIdentifier)
        XCTAssertEqual(bell.button.accessibilityLabel, lang("$agent_digest_settings_title"))
        var presenters: [UIViewController] = []
        let bellController = AgentNewsFeedVC(model: model, presentDigestSettings: { presenters.append($0) })
        navigation.pushViewController(bellController, animated: false)
        bellController.loadViewIfNeeded()
        bellController.viewIsAppearing(false)
        let bellButton = try XCTUnwrap(AgentChatNavigation.findButton(in: bellController.navigationItem.rightBarButtonItem))
        bellButton.sendActions(for: .primaryActionTriggered)
        XCTAssertTrue(presenters.first === bellController)
        for appearance in [controller.navigationItem.standardAppearance, controller.navigationItem.scrollEdgeAppearance] {
            let appearance = try XCTUnwrap(appearance)
            XCTAssertNil(appearance.backgroundEffect)
            XCTAssertEqual(appearance.backgroundColor?.cgColor.alpha ?? 0, 0)
        }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(collection.topEdgeEffect.isHidden)
        }
        controller.setNavigationHandoffHidden(true)
        XCTAssertEqual(threadsCircle.alpha, 0)
        controller.setNavigationHandoffHidden(false)
        XCTAssertEqual(threadsCircle.alpha, 1)
    }

    func testCachedPageShowsAtOnceAndAnEmptyFeedLoadsBehindTheSkeleton() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let page = ApiAgentV2NewsFeedPage(locale: "en", items: [makeItem(2), makeItem(1)])
        let cachedClient = NewsFeedUIClient(first: .success(page))
        let cached = AgentNewsFeedModel(
            client: cachedClient,
            readState: AgentNewsReadState(userDefaults: makeDefaults()),
            cachedPage: AgentNewsCachedPage(
                page: .init(locale: "en", items: page.items, nextCursor: "c"), language: "en",
                schedule: AgentNewsFeedModel(readState: AgentNewsReadState(userDefaults: makeDefaults())).currentDigestSchedule
            )
        )
        XCTAssertEqual(cached.items.map(\.eventId), [1, 2])
        XCTAssertEqual(cached.locale, "en")
        await cached.prefetchTask?.value
        let cachedController = AgentNewsFeedVC(model: cached)
        let cachedWindow = present(cachedController)
        defer { cachedWindow.isHidden = true }
        let cachedCollection = try XCTUnwrap(descendants(cachedController.view).compactMap { $0 as? UICollectionView }.first)
        cachedCollection.layoutIfNeeded()
        XCTAssertTrue(cachedCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-2" })
        XCTAssertTrue(try XCTUnwrap(descendants(cachedController.view).compactMap { $0 as? AgentMessagesSkeletonView }.first).isHidden)
        try await waitUntil { cachedClient.cursors.contains(nil) && !cached.isLoading }
        XCTAssertEqual(cachedClient.cursors, [nil])

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
        var releaseOlderPage: CheckedContinuation<Void, Never>?
        client.beforeOlderPage = { await withCheckedContinuation { releaseOlderPage = $0 } }
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()))
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer {
            releaseOlderPage?.resume()
            window.isHidden = true
        }
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
        let loading = Task { await model.loadMore() }
        try await waitUntil { releaseOlderPage != nil }
        releaseOlderPage?.resume()
        releaseOlderPage = nil
        await loading.value
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

    /// A feed that loads without news says so in the middle of its column, without Retry, in place of its placeholder,
    /// and keeps saying so while it reads the news again, until they come
    func testEmptyFeedSaysSoUntilNewsArrive() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = NewsFeedUIClient(first: .success(.init(locale: "en", items: [])))
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()))
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let skeleton = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentMessagesSkeletonView }.first)
        let message = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentLoadErrorView }.first)
        try await waitUntil { model.hasLoaded && !model.isLoading }
        window.layoutIfNeeded()
        XCTAssertFalse(skeleton.isShowing)
        XCTAssertFalse(message.isHidden)
        XCTAssertEqual(message.label.text, lang("$agent_news_empty"))
        XCTAssertTrue(message.retryButton.isHidden)
        XCTAssertEqual(message.frame.midX, controller.collectionView.frame.midX, accuracy: 1)
        XCTAssertEqual(message.frame.midY, controller.collectionView.frame.midY, accuracy: 1)

        var page: CheckedContinuation<Void, Never>?
        client.beforeFirstPage = { await withCheckedContinuation { page = $0 } }
        client.first = .success(.init(locale: "en", items: [makeItem(1)]))
        WalletCoreData.notify(event: .applicationWillEnterForeground)
        try await waitUntil { model.isLoading && page != nil }
        XCTAssertFalse(skeleton.isShowing)
        XCTAssertFalse(message.isHidden)
        client.beforeFirstPage = nil
        page?.resume()
        try await waitUntil {
            window.layoutIfNeeded()
            return message.isHidden && controller.collectionView.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-1" }
        }
        XCTAssertFalse(skeleton.isShowing)
        XCTAssertEqual(client.cursors, [nil, nil])
    }

    /// Two fingers on the latest picture keep the feed where it rests at its end, over a home indicator: the list stops
    /// scrolling for the pinch and keeps that indicator's height in its insets
    func testPinchOnTheLatestPictureKeepsTheFeedAtItsEnd() async throws {
        let imageKey = "https://example.invalid/news-pinch-\(UUID().uuidString).png"
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
        try await ImageCache.default.store(image, forKey: imageKey, toDisk: false)
        defer { ImageCache.default.removeImage(forKey: imageKey, fromDisk: false, completionHandler: nil) }
        let items = (1...6).map { makeNewsItem($0, isLong: true, imageURL: $0 == 6 ? imageKey : nil) }
        let feed = TestFeed(page: .init(locale: "en", items: items.reversed()), safeAreaBottom: 34)
        defer { feed.close() }
        let list = feed.controller.collectionView
        var latestPicture: UIImageView?
        try await feed.waitUntil {
            latestPicture = list.visibleCells.compactMap { $0 as? AgentNewsFeedCardCell }
                .first { $0.accessibilityIdentifier == "AgentNewsCard-6" }?.newsView.imageView
            return latestPicture?.image != nil
        }
        try await feed.waitForStableLayout()
        let restingY = list.contentOffset.y
        let bottomInset = list.adjustedContentInset.bottom
        XCTAssertEqual(restingY, feed.controller.maxContentOffsetY, accuracy: 0.5)
        let touchGuard = try XCTUnwrap(latestPicture?.gestureRecognizers?.compactMap { $0 as? PinchTouchGuard }.first)

        touchGuard.updateTouchCount(2)
        feed.layout()
        XCTAssertFalse(list.panGestureRecognizer.isEnabled)
        XCTAssertEqual(list.adjustedContentInset.bottom, bottomInset, accuracy: 0.5)
        XCTAssertEqual(list.contentOffset.y, restingY, accuracy: 0.5)

        touchGuard.reset()
        feed.layout()
        XCTAssertTrue(list.panGestureRecognizer.isEnabled)
        XCTAssertEqual(list.contentOffset.y, restingY, accuracy: 0.5)
    }

    /// A digest's headline opens its news item's discussion over the feed, as the item's card does, or once it loads
    /// when the feed hasn't loaded the item. Discuss opens the digest's thread once the user has written there,
    /// otherwise a visit that starts it, also over the feed.
    func testDigestCardOpensItsNewsAndItsDiscussionOverTheFeed() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let started = try makeDigest(id: "en:2026-10-20T10:05:00.000Z", headlines: [1], discussion: "digest-thread")
        let fresh = try makeDigest(id: "en:2026-10-20T10:06:00.000Z", headlines: [1, 42])
        let threads = try ["digest-thread", "fresh-digest-thread"].map { id in
            try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data("""
            {"id":"\(id)","revision":1,"createdAt":"2026-10-20T12:00:00Z","updatedAt":"2026-10-20T12:00:00Z",
             "lastActivityAt":"2026-10-20T12:00:00Z","messageCount":2}
            """.utf8))
        }
        let thread = threads[0]
        let model = AgentNewsFeedModel(
            client: NewsFeedUIClient(first: .success(.init(locale: "en", items: [makeItem(1)], digests: [started, fresh]))),
            readState: AgentNewsReadState(userDefaults: makeDefaults()),
            findThread: { id in threads.first { $0.id == id } }
        )
        var newsChats: [Int] = []
        var loadedNewsChats: [Int] = []
        var digestChats: [String] = []
        var onDigestThreadCreated: ((ApiAgentV2ThreadSummary) -> Void)?
        var chats: [UIViewController] = []
        func makeChat() -> UIViewController {
            let chat = UIViewController()
            chats.append(chat)
            return chat
        }
        let preloader = AgentPreloader(client: FakeAgentV2Client())
        defer { preloader.setWalletReady(false) }
        let controller = AgentNewsFeedVC(
            model: model, preloader: preloader,
            makeNewsChatViewController: { item, _, _ in
                newsChats.append(item.eventId)
                return makeChat()
            },
            loadNewsChatViewController: { eventId in
                loadedNewsChats.append(eventId)
                return makeChat()
            },
            makeDigestChatViewController: { digest, onThreadCreated in
                digestChats.append(digest.id)
                onDigestThreadCreated = onThreadCreated
                return makeChat()
            }
        )
        let navigationController = PushRecordingNavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigationController)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil { !model.isLoading && model.digests.count == 2 }

        /// Taps `identifier` on the card of `digest`, waits for the chat to be pushed onto the feed's own stack, and goes
        /// back
        func tap(_ identifier: String, on digest: ApiAgentV2NewsFeedDigest) async throws -> UIViewController {
            // The feed refreshes as it comes back from a chat
            try await waitUntil { !model.isLoading && collection.numberOfItems(inSection: 0) == 4 }
            let cell = try await revealCell("AgentNewsDigest-\(digest.id)", in: collection)
            try button(identifier, in: cell).sendActions(for: .touchUpInside)
            try await waitUntil { navigationController.viewControllers.count == 2 }
            XCTAssertTrue(navigationController.viewControllers.first === controller)
            let chat = try XCTUnwrap(navigationController.topViewController)
            // The screens appear and disappear a turn after the stack changes, which lets the feed open the next chat
            try await waitUntil { chat.viewIfLoaded?.window != nil && controller.viewIfLoaded?.window == nil }
            navigationController.popViewController(animated: false)
            try await waitUntil { controller.viewIfLoaded?.window != nil && chat.viewIfLoaded?.window == nil }
            try await Task.sleep(for: .milliseconds(50))
            return chat
        }

        let loadedItemChat = try await tap("AgentNewsDigestHeadline-1", on: fresh)
        XCTAssertTrue(loadedItemChat === chats.last)
        XCTAssertEqual(newsChats, [1])
        let otherItemChat = try await tap("AgentNewsDigestHeadline-42", on: fresh)
        XCTAssertTrue(otherItemChat === chats.last)
        XCTAssertEqual(loadedNewsChats, [42])
        let digestChat = try await tap("AgentNewsDigestDiscussion-\(fresh.id)", on: fresh)
        XCTAssertTrue(digestChat === chats.last)
        XCTAssertEqual(digestChats, [fresh.id])

        let chat = try await tap("AgentNewsDigestDiscussion-\(started.id)", on: started)
        XCTAssertEqual(digestChats, [fresh.id])
        XCTAssertEqual(((chat as? AgentVC)?.model as? AgentV2Model)?.threadId, thread.id)

        // The thread the digest's first message creates becomes its discussion, which the next visit opens
        try XCTUnwrap(onDigestThreadCreated)(threads[1])
        XCTAssertEqual(model.digests.first { $0.id == fresh.id }?.discussion?.threadId, threads[1].id)
        // The fake client has no history for the thread, so the chat the feed keeps for it fails to load and the next
        // visit opens the chat list's copy of the thread
        try await waitUntil { preloader.model(threadId: threads[1].id) == nil }
        let createdChat = try await tap("AgentNewsDigestDiscussion-\(fresh.id)", on: fresh)
        XCTAssertEqual(digestChats, [fresh.id])
        XCTAssertEqual(((createdChat as? AgentVC)?.model as? AgentV2Model)?.threadId, threads[1].id)
    }

    /// The feed opened for a digest scrolls to its card once older pages bring it, and stops asking for pages once
    /// they reach back past the digest without it
    func testRequestedDigestScrollsIntoViewAfterOlderPagesAndTheSearchStops() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let digest = try makeDigest(id: "en:2026-10-20T10:01:30.000Z", headlines: [1])
        let client = NewsFeedUIClient(first: .success(.init(
            locale: "en", items: (5...9).reversed().map { makeItem($0, longBody: true) }, nextCursor: "older1"
        )))
        client.pagesByCursor = [
            "older1": .init(locale: "en", items: [makeItem(4, longBody: true), makeItem(3, longBody: true)], nextCursor: "older2"),
            "older2": .init(locale: "en", items: [makeItem(2, longBody: true), makeItem(1, longBody: true, day: 18)], nextCursor: "older3", digests: [digest]),
        ]
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()), requestedDigestId: digest.id)
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil {
            window.layoutIfNeeded()
            return collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsDigest-\(digest.id)" }
        }
        let card = try XCTUnwrap(collection.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsDigest-\(digest.id)" })
        XCTAssertEqual(card.frame.minY - collection.contentOffset.y, collection.adjustedContentInset.top, accuracy: 3)
        XCTAssertEqual(client.cursors, [nil, "older1", "older2"])

        // A digest the pages reach back past without bringing it leaves the feed at its latest news
        let missingDigest = try makeDigest(id: "en:2026-10-20T10:05:30.000Z", headlines: [5])
        let missingPage = ApiAgentV2NewsFeedPage(
            locale: "en", items: (1...9).reversed().map { makeItem($0, longBody: true, day: $0 == 1 ? 18 : 20) }, nextCursor: "older"
        )
        let missingClient = NewsFeedUIClient(first: .success(missingPage))
        let missing = AgentNewsFeedModel(
            client: missingClient,
            readState: AgentNewsReadState(userDefaults: makeDefaults()),
            requestedDigestId: missingDigest.id
        )
        let missingController = AgentNewsFeedVC(model: missing)
        let missingWindow = present(missingController)
        defer { missingWindow.isHidden = true }
        let missingCollection = try XCTUnwrap(descendants(missingController.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil {
            missingWindow.layoutIfNeeded()
            return !missing.isLoading && missingCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-9" }
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(missing.isLoadingMore)
        XCTAssertEqual(missing.items.count, 9)
        XCTAssertEqual(missing.nextCursor, "older")
        XCTAssertEqual(
            missingCollection.contentOffset.y,
            missingCollection.contentSize.height - missingCollection.bounds.height + missingCollection.adjustedContentInset.bottom,
            accuracy: 3
        )

        let previousRowCount = missingCollection.numberOfItems(inSection: 0)
        missingClient.first = .success(.init(locale: "en", items: missingPage.items, digests: [missingDigest]))
        await missing.refresh()
        try await waitUntil {
            missingWindow.layoutIfNeeded()
            return missingCollection.numberOfItems(inSection: 0) == previousRowCount + 1
        }
        try await Task.sleep(for: .milliseconds(100))
        missingWindow.layoutIfNeeded()
        XCTAssertTrue(missingCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-9" })
        XCTAssertFalse(missingCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsDigest-\(missingDigest.id)" })

        let failedClient = NewsFeedUIClient(first: .success(.init(
            locale: "en", items: (5...9).reversed().map { makeItem($0, longBody: true) }, nextCursor: "older1"
        )))
        failedClient.beforeOlderPage = { throw NewsFeedUIError.unavailable }
        let failed = AgentNewsFeedModel(
            client: failedClient, readState: AgentNewsReadState(userDefaults: makeDefaults()), requestedDigestId: digest.id
        )
        let failedController = AgentNewsFeedVC(model: failed)
        let failedWindow = present(failedController)
        defer { failedWindow.isHidden = true }
        let failedCollection = try XCTUnwrap(descendants(failedController.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil { failedClient.cursors.contains("older1") && !failed.isLoadingMore }
        await failed.prefetchTask?.value
        XCTAssertFalse(failed.canLoadRequestedDigest)
        let previousFailedRowCount = failedCollection.numberOfItems(inSection: 0)

        failedClient.beforeOlderPage = nil
        failedClient.pagesByCursor["older1"] = .init(
            locale: "en", items: (1...4).reversed().map { makeItem($0, longBody: true, day: $0 == 1 ? 18 : 20) }, digests: [digest]
        )
        await failed.refresh()
        await failed.prefetchTask?.value
        try await waitUntil {
            failedWindow.layoutIfNeeded()
            return failedCollection.numberOfItems(inSection: 0) > previousFailedRowCount
        }
        try await Task.sleep(for: .milliseconds(100))
        failedWindow.layoutIfNeeded()
        XCTAssertEqual(failedClient.cursors, [nil, "older1", nil, "older1"])
        XCTAssertTrue(failedCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-9" })
        XCTAssertFalse(failedCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsDigest-\(digest.id)" })
    }

    /// The scroll button the user taps while older pages load leaves the feed at its latest news when the digest comes
    func testScrollToLatestWhileOlderPagesLoadCancelsTheScrollToTheRequestedDigest() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let digest = try makeDigest(id: "en:2026-10-20T10:01:30.000Z", headlines: [1])
        let client = NewsFeedUIClient(first: .success(.init(
            locale: "en", items: (2...9).reversed().map { makeItem($0, longBody: true) }, nextCursor: "older"
        )))
        client.older = .init(locale: "en", items: [makeItem(1, longBody: true)], digests: [digest])
        var release: CheckedContinuation<Void, Never>?
        client.beforeOlderPage = { await withCheckedContinuation { release = $0 } }
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()), requestedDigestId: digest.id)
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil { release != nil }
        controller.scrollToBottomButtonPressed()
        release?.resume()
        try await waitUntil { model.digests.count == 1 && !model.isLoadingMore }
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        XCTAssertFalse(collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsDigest-\(digest.id)" })
        XCTAssertTrue(collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-9" })

        let draggingClient = NewsFeedUIClient(first: .success(.init(
            locale: "en", items: (5...9).reversed().map { makeItem($0, longBody: true, day: 26) }, nextCursor: "older1",
            digests: try [makeDigest(id: "en:2026-10-26T10:00:00.000Z", headlines: [5]), makeDigest(id: "en:2026-10-25T10:00:00.000Z", headlines: [5])]
        )))
        draggingClient.pagesByCursor = [
            "older1": .init(locale: "en", items: [makeItem(4, longBody: true, day: 24)], nextCursor: "older2"),
            "older2": .init(locale: "en", items: [makeItem(3, longBody: true, day: 23)], nextCursor: "older3"),
            "older3": .init(locale: "en", items: [makeItem(2, longBody: true, day: 19)], nextCursor: "unneeded"),
        ]
        var releaseDraggingPage: CheckedContinuation<Void, Never>?
        draggingClient.beforeOlderPage = {
            await withCheckedContinuation { releaseDraggingPage = $0 }
        }
        let dragging = AgentNewsFeedModel(
            client: draggingClient, readState: AgentNewsReadState(userDefaults: makeDefaults()), requestedDigestId: digest.id
        )
        let draggingController = AgentNewsFeedVC(model: dragging)
        let draggingWindow = present(draggingController)
        defer { draggingWindow.isHidden = true }
        let draggingCollection = try XCTUnwrap(descendants(draggingController.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil {
            draggingWindow.layoutIfNeeded()
            return releaseDraggingPage != nil
                && draggingCollection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsCard-9" }
        }
        let prefetch = try XCTUnwrap(dragging.prefetchTask)
        draggingController.scrollViewWillBeginDragging(draggingCollection)
        draggingClient.beforeOlderPage = nil
        releaseDraggingPage?.resume()
        await prefetch.value

        XCTAssertFalse(dragging.canLoadRequestedDigest)
        XCTAssertEqual(draggingClient.cursors, [nil, "older1"])
        XCTAssertEqual(dragging.items.first?.eventId, 4)
        XCTAssertEqual(dragging.nextCursor, "older2")
    }

    /// A feed that opens at its top takes its first older page by its own pagination; the search for the requested
    /// digest goes on from there
    func testRequestedDigestSearchGoesOnAfterTheFeedsOwnPagination() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let digest = try makeDigest(id: "en:2026-10-20T10:01:30.000Z", headlines: [1])
        let client = NewsFeedUIClient(first: .success(.init(
            locale: "en", items: (5...9).reversed().map { makeItem($0, longBody: true) }, nextCursor: "older1"
        )))
        client.pagesByCursor = [
            // Tall enough that the feed, kept at its card, is no longer near its top after this page
            "older1": .init(locale: "en", items: [makeItem(4, longBody: true), makeItem(3, longBody: true)], nextCursor: "older2"),
            "older2": .init(locale: "en", items: [makeItem(2), makeItem(1)], digests: [digest]),
        ]
        // Everything on the first page is unread, so the feed opens at its top, at the unread line
        let readState = AgentNewsReadState(userDefaults: makeDefaults())
        readState.markRead(items: [makeItem(4)])
        let model = AgentNewsFeedModel(client: client, readState: readState, requestedDigestId: digest.id)
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil {
            window.layoutIfNeeded()
            return collection.visibleCells.contains { $0.accessibilityIdentifier == "AgentNewsDigest-\(digest.id)" }
        }
        XCTAssertEqual(client.cursors, [nil, "older1", "older2"])
    }

    /// A new digest hour or minute reloads the feed: the old time's digest goes, the new one's comes and the news stay
    func testNewDigestTimeReplacesTheDigestsAndKeepsTheNews() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        let evening = try makeDigest(id: "en:2026-10-20T10:05:00.000Z", headlines: [1])
        let morning = try makeDigest(id: "en:2026-10-20T10:06:00.000Z", headlines: [1])
        let client = NewsFeedUIClient(first: .success(.init(locale: "en", items: [makeItem(1)], digests: [evening])))
        let model = AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: makeDefaults()), digestSettings: settings)
        let controller = AgentNewsFeedVC(model: model)
        let window = present(controller)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        func shows(_ identifier: String) -> Bool {
            window.layoutIfNeeded()
            return collection.visibleCells.contains { $0.accessibilityIdentifier == identifier }
        }
        try await waitUntil { shows("AgentNewsDigest-\(evening.id)") && shows("AgentNewsCard-1") }

        client.first = .success(.init(locale: "en", items: [makeItem(1)], digests: [morning]))
        let outcome = await settings.setDigestTime(hour: 9, minute: 0)
        XCTAssertEqual(outcome, .ok)
        try await waitUntil { shows("AgentNewsDigest-\(morning.id)") && !shows("AgentNewsDigest-\(evening.id)") && shows("AgentNewsCard-1") }
        XCTAssertEqual(model.digests, [morning])
        XCTAssertEqual(model.items.map(\.eventId), [1])
        XCTAssertEqual(client.digestHours.last, 9)

        let quarter = try makeDigest(id: "en:2026-10-20T10:07:00.000Z", headlines: [1])
        client.first = .success(.init(locale: "en", items: [makeItem(1)], digests: [quarter]))
        let quarterOutcome = await settings.setDigestTime(hour: 9, minute: 45)
        XCTAssertEqual(quarterOutcome, .ok)
        try await waitUntil { shows("AgentNewsDigest-\(quarter.id)") && !shows("AgentNewsDigest-\(morning.id)") }
        XCTAssertEqual(model.digests, [quarter])
        XCTAssertEqual(client.digestMinutes.last, 45)
    }

    /// Quick repeated taps open one chat; a failed opening releases the tap, which opens the chat when repeated
    func testRepeatedTapsOpenOneChatAndAFailedOpeningCanBeRetried() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let digest = try makeDigest(id: "en:2026-10-20T10:06:00.000Z", headlines: [42])
        let model = AgentNewsFeedModel(
            client: NewsFeedUIClient(first: .success(.init(locale: "en", items: [makeItem(1)], digests: [digest]))),
            readState: AgentNewsReadState(userDefaults: makeDefaults())
        )
        var loads = 0
        var pendingLoad: CheckedContinuation<Void, Error>?
        var digestChats = 0
        let controller = AgentNewsFeedVC(
            model: model,
            loadNewsChatViewController: { _ in
                loads += 1
                try await withCheckedThrowingContinuation { pendingLoad = $0 }
                return UIViewController()
            },
            makeDigestChatViewController: { _, _ in
                digestChats += 1
                return UIViewController()
            }
        )
        let navigationController = PushRecordingNavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigationController)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil { !model.isLoading && model.digests.count == 1 }
        let cell = try await revealCell("AgentNewsDigest-\(digest.id)", in: collection)
        let headline = try button("AgentNewsDigestHeadline-42", in: cell)
        let discuss = try button("AgentNewsDigestDiscussion-\(digest.id)", in: cell)

        headline.sendActions(for: .touchUpInside)
        headline.sendActions(for: .touchUpInside)
        discuss.sendActions(for: .touchUpInside)
        try await waitUntil { pendingLoad != nil }
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(digestChats, 0)
        pendingLoad?.resume(throwing: CancellationError())
        pendingLoad = nil
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(navigationController.viewControllers.count, 1)

        discuss.sendActions(for: .touchUpInside)
        discuss.sendActions(for: .touchUpInside)
        headline.sendActions(for: .touchUpInside)
        XCTAssertEqual(digestChats, 1)
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(navigationController.viewControllers.count, 2)
    }

    private func makeDigest(id: String, headlines: [Int], discussion: String? = nil) throws -> ApiAgentV2NewsFeedDigest {
        var digest: [String: Any] = [
            "id": id, "deliveredAt": String(id.drop { $0 != ":" }.dropFirst()), "total": 12,
            "top": headlines.map { ["eventId": $0, "headline": "Headline \($0)"] },
        ]
        digest["discussion"] = discussion.map { ["threadId": $0] }
        return try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: JSONSerialization.data(withJSONObject: digest))
    }

    /// Scrolls the row with `identifier` into view and returns its cell
    private func revealCell(_ identifier: String, in collection: UICollectionView) async throws -> UICollectionViewCell {
        for _ in 0..<20 {
            for item in 0..<collection.numberOfItems(inSection: 0) {
                let indexPath = IndexPath(item: item, section: 0)
                collection.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
                collection.layoutIfNeeded()
                if let cell = collection.cellForItem(at: indexPath), cell.accessibilityIdentifier == identifier { return cell }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("No row \(identifier)")
        throw NewsFeedUIError.timedOut
    }

    private func button(_ identifier: String, in cell: UIView) throws -> UIButton {
        try XCTUnwrap(descendants(cell).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == identifier })
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AgentNewsFeedUITests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeItem(_ id: Int, longBody: Bool = false, day: Int = 20) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: id,
            deliveredAt: String(format: "2026-10-%02dT10:%02d:00Z", day, id),
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

/// Pushes without the animation, which a test window can't finish between taps
private final class PushRecordingNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: false)
    }
}

private enum NewsFeedUIError: Error {
    case timedOut
    case unavailable
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
    var pagesByCursor: [String: ApiAgentV2NewsFeedPage] = [:]
    var cursors: [String?] = []
    var digestHours: [Int] = []
    var digestMinutes: [Int] = []
    /// Holds the first page back until it returns
    var beforeFirstPage: (() async -> Void)?
    /// Holds an older page back until it returns
    var beforeOlderPage: (() async throws -> Void)?

    init(first: Result<ApiAgentV2NewsFeedPage, Error>) {
        self.first = first
    }

    func getNewsFeed(lang: String, cursor: String?, schedule: AgentNewsDigestSchedule, view: ApiAgentV2NewsFeedView = .all) async throws -> ApiAgentV2NewsFeedPage {
        cursors.append(cursor)
        digestHours.append(schedule.hour)
        digestMinutes.append(schedule.minute)
        if cursor == nil, let beforeFirstPage {
            await beforeFirstPage()
        }
        guard let cursor else { return try first.get() }
        try await beforeOlderPage?()
        return pagesByCursor[cursor] ?? older
    }
}
