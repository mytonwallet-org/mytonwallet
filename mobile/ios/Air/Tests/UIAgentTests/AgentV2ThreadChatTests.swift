import ContextMenuKit
import Dependencies
import XCTest
import UIKit
import Kingfisher
@testable import UIAgent
@testable import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources

final class AgentV2ThreadChatTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testCoordinatorHydratesSuppliedThreadWithoutLoadingDefaultThread() async throws {
        let initialThread = try decodeThread(id: "selected-thread", revision: 1)
        let client = try ThreadChatClient(threadId: initialThread.id)
        let coordinator = AgentV2Coordinator(client: client, thread: initialThread)
        defer { coordinator.stop() }

        XCTAssertEqual(coordinator.thread, initialThread)
        coordinator.start()
        await coordinator.waitForInitialLoad()

        XCTAssertEqual(client.defaultThreadCallCount, 0)
        XCTAssertEqual(client.hydratedThreadIds, [initialThread.id])
        XCTAssertEqual(coordinator.thread, client.hydration.thread)
        XCTAssertEqual(coordinator.messages.map(\.id), ["answer"])
        XCTAssertTrue(coordinator.hasHydratedMessages)
        XCTAssertNil(coordinator.error)

        let updated = try decodeThread(id: initialThread.id, revision: client.hydration.thread.revision + 1)
        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: updated.id, thread: updated)))
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(coordinator.thread, updated)
        XCTAssertEqual(coordinator.messages.map(\.id), ["answer"])
        XCTAssertEqual(client.hydratedThreadIds, [initialThread.id])
    }

    @MainActor
    func testCoordinatorWithoutSuppliedThreadLoadsAndHydratesDefaultThread() async throws {
        let client = try ThreadChatClient(threadId: "default-thread")
        let coordinator = AgentV2Coordinator(client: client)
        defer { coordinator.stop() }

        XCTAssertNil(coordinator.thread)
        coordinator.start()
        await coordinator.waitForInitialLoad()

        XCTAssertEqual(client.defaultThreadCallCount, 1)
        XCTAssertEqual(client.hydratedThreadIds, ["default-thread"])
        XCTAssertEqual(coordinator.thread, client.hydration.thread)
        XCTAssertTrue(coordinator.hasHydratedMessages)
        XCTAssertNil(coordinator.error)
    }

    @MainActor
    func testModelPresentsSuppliedThreadMessages() async throws {
        let client = try ThreadChatClient(threadId: "selected-thread")
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }

        await model.waitForInitialLoad()

        XCTAssertEqual(client.defaultThreadCallCount, 0)
        XCTAssertEqual(client.hydratedThreadIds, ["selected-thread"])
        XCTAssertEqual(model.threadId, "selected-thread")
        XCTAssertTrue(model.isReadyForPresentation)
        XCTAssertTrue(model.itemIDs.contains { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.text == "The selected conversation"
        })
    }

    @MainActor
    func testThreadEntryPresentsTheReadyRegistryModelImmediately() async throws {
        let client = try ThreadChatClient(threadId: "selected-thread")
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let model = try XCTUnwrap(preloader.acquireModel(thread: client.hydration.thread))
        await model.waitForInitialLoad()

        let controller = try XCTUnwrap(
            AgentEntryPoint.makeRootViewController(thread: client.hydration.thread, preloader: preloader) as? AgentVC
        )
        let navigation = UINavigationController(rootViewController: controller)
        defer { navigation.setViewControllers([], animated: false) }
        controller.loadViewIfNeeded()

        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertTrue(model.delegate === controller)
        XCTAssertTrue(preloader.model(threadId: client.hydration.thread.id) === model)
        XCTAssertEqual(model.thread, client.hydration.thread)
        XCTAssertEqual(controller.title, model.chatTitle)
        XCTAssertEqual(client.hydratedThreadIds, ["selected-thread"])
        XCTAssertEqual(client.consentCallCount, 0)
        XCTAssertEqual(client.newsThreadCreateCallCount, 0)
        XCTAssertTrue(model.itemIDs.contains { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.text == "The selected conversation"
        })
    }

    @MainActor
    func testReopeningCachedChatHydratesOnlyANewerIdleRevision() async throws {
        let client = try ThreadChatClient(threadId: "selected-thread")
        let preloader = AgentPreloader(client: client)
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        let model = try XCTUnwrap(preloader.acquireModel(thread: client.hydration.thread))
        await model.waitForInitialLoad()
        let initial = client.hydration.thread

        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: initial, preloader: preloader) is AgentVC)
        XCTAssertEqual(client.hydratedThreadIds.count, 1)

        let updated = try decodeThread(id: initial.id, revision: initial.revision + 1)
        var hydration = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(client.hydration)) as? [String: Any])
        hydration["thread"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(updated))
        client.hydration = try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: JSONSerialization.data(withJSONObject: hydration))
        client.messageFailuresRemaining = 1

        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: updated, preloader: preloader) is AgentVC)
        XCTAssertEqual(model.thread, initial)
        try await waitUntil { client.hydratedThreadIds.count == 2 && !model.isReadyForPresentation }
        XCTAssertEqual(model.thread, initial)

        _ = AgentEntryPoint.makeRootViewController(thread: updated, preloader: preloader)
        try await waitUntil { client.hydratedThreadIds.count == 3 && model.thread == updated }
        XCTAssertEqual(model.thread, updated)

        client.blocksRuns = true
        model.send(text: "Another question")
        try await waitUntil { client.pendingRun != nil }
        let newer = try decodeThread(id: initial.id, revision: updated.revision + 1)
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: newer, preloader: preloader) is AgentVC)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.thread, updated)
        XCTAssertEqual(client.hydratedThreadIds.count, 3)
    }

    @MainActor
    func testRecentlyOpenedChatStaysLoadedAfterItsScreenCloses() async throws {
        let client = try ThreadChatClient(threadId: "selected-thread")
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let thread = client.hydration.thread
        var model: AgentV2Model? = try XCTUnwrap(preloader.acquireModel(thread: thread))
        await model?.waitForInitialLoad()
        weak var weakModel = model
        var chat: UIViewController? = AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader)
        weak var weakChat = chat
        XCTAssertTrue(chat is AgentVC)
        chat = nil
        model = nil
        try await waitUntil { weakChat == nil }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(weakModel?.isReadyForPresentation == true)
        XCTAssertTrue(preloader.model(threadId: thread.id) === weakModel)
        let reopened = AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader)
        XCTAssertTrue(reopened is AgentVC)
        XCTAssertEqual(client.hydratedThreadIds, [thread.id])

        preloader.setWalletReady(false)
        XCTAssertFalse(weakModel?.isReadyForPresentation == true)
    }

    @MainActor
    func testLoadingThreadTitleMatchesTheModelTitle() async throws {
        let cases: [(String?, String?, String)] = [
            ("  Large BTC transfer \n", " 🐳 \n", "🐳 Large BTC transfer"),
            ("Large BTC transfer", " \n", "Large BTC transfer"),
            (" \n", "🐳", "🐳 \(lang("New Chat"))"),
            (nil, nil, lang("New Chat"))
        ]
        for (title, icon, expected) in cases {
            let client = try ThreadChatClient(threadId: "selected-thread", title: title, icon: icon)
            let preloader = AgentPreloader(client: client)
            let model = AgentV2Model(client: client, thread: client.hydration.thread)
            await model.waitForInitialLoad()
            let root = AgentRootVC(thread: client.hydration.thread, preloader: preloader)
            root.loadViewIfNeeded()

            XCTAssertEqual(root.title, expected)
            XCTAssertEqual(root.title, model.chatTitle)

            model.stop()
            preloader.setWalletReady(false)
        }
    }

    @MainActor
    func testUncachedThreadShowsTheMessageSkeletonUnderTheChatChrome() throws {
        let client = try ThreadChatClient(threadId: "selected-thread", title: "Large BTC transfer", icon: "🐳")
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let root = AgentRootVC(thread: client.hydration.thread, preloader: preloader)
        root.loadViewIfNeeded()

        let skeleton = try XCTUnwrap(root.view.subviews.compactMap { $0 as? AgentMessagesSkeletonView }.first)
        let composer = try XCTUnwrap(root.view.subviews.compactMap { $0 as? AgentComposerView }.first)
        XCTAssertFalse(skeleton.isHidden)
        XCTAssertFalse(composer.isHidden)
        XCTAssertFalse(composer.isUserInteractionEnabled)
        XCTAssertTrue(composer.accessibilityElementsHidden)
        XCTAssertFalse(descendants(of: root.view).contains { $0 is UIActivityIndicatorView })
        let titleView = try XCTUnwrap(root.navigationItem.titleView)
        let chatTitle = try XCTUnwrap(descendants(of: titleView).compactMap { $0 as? AgentChatTitleView }.first)
        XCTAssertEqual(chatTitle.accessibilityLabel, "🐳 Large BTC transfer")

        // A new chat has no history to stand in for
        let newChat = AgentRootVC(client: client, preloader: preloader)
        newChat.loadViewIfNeeded()
        XCTAssertTrue(try XCTUnwrap(newChat.view.subviews.compactMap { $0 as? AgentMessagesSkeletonView }.first).isHidden)
        // The loading chat already has the chat's buttons, so the loaded chat replaces it without a change in the header
        let menuCircle = try XCTUnwrap(root.navigationHandoffTrailingView as? AgentGlassCircleButton)
        XCTAssertEqual(menuCircle.button.accessibilityIdentifier, "agent_menu_button")
        XCTAssertFalse(menuCircle.isUserInteractionEnabled)
        XCTAssertFalse(menuCircle.button.isUserInteractionEnabled)
    }

    @MainActor
    func testExistingNewsDiscussionLoadsWithMessageBubbles() throws {
        let messages = [
            newsMessage(text: "News"),
            newsMessage(id: "question", role: "user", text: "What does this mean?", isPost: false),
            newsMessage(id: "answer", text: "Here is the context", isPost: false),
        ]
        for count in [1, 3] {
            let response = try newsResponse(headline: "News", messageCount: count)
            let client = try ThreadChatClient(threadId: "news-thread", messages: Array(messages.prefix(count)), news: response.thread.news)
            let preloader = AgentPreloader(client: client)
            defer { preloader.setWalletReady(false) }
            let root = AgentRootVC(thread: client.hydration.thread, preloader: preloader)
            let window = makeKeyWindow(showing: UINavigationController(rootViewController: root))
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let skeleton = try XCTUnwrap(root.view.subviews.compactMap { $0 as? AgentMessagesSkeletonView }.first)
            let placeholders = skeleton.placeholdersInWindow()
            XCTAssertTrue(placeholders.contains { $0.isOutgoing }, "A news discussion with \(count) messages")
            XCTAssertTrue(placeholders.contains { !$0.isOutgoing }, "A news discussion with \(count) messages")
            let composer = try XCTUnwrap(root.view.subviews.compactMap { $0 as? AgentComposerView }.first)
            let inputTop = composer.convert(composer.inputBackgroundFrame, to: window).minY
            let lowestPlaceholder = try XCTUnwrap(placeholders.map(\.frame.maxY).max())
            XCTAssertEqual(inputTop - lowestPlaceholder, 16, accuracy: 0.5,
                           "Loading bubbles keep the design's gap to the visible input, like loaded messages")
        }
    }

    /// A header transition hides the loading chat's "…" button while it draws over it; the chat keeps that button once
    /// consent is checked, so no second glass circle shows under the drawn one
    @MainActor
    func testLoadingChatKeepsItsMoreButtonOnceConsentIsChecked() async throws {
        let client = try ThreadChatClient(threadId: "selected-thread")
        client.blocksMessages = true
        let preloader = AgentPreloader(client: client)
        defer {
            client.releasePendingRequests()
            preloader.setWalletReady(false)
        }
        let root = AgentRootVC(thread: client.hydration.thread, preloader: preloader)
        root.loadViewIfNeeded()
        let menuItem = try XCTUnwrap(root.navigationItem.rightBarButtonItem)

        try await waitUntil { client.consentCallCount == 1 && client.hydratedThreadIds == ["selected-thread"] }
        XCTAssertTrue(root.navigationItem.rightBarButtonItem === menuItem)
    }

    @MainActor
    func testMessageSkeletonAlternatesTelegramsBubblesWithTheChatSpacing() throws {
        let skeleton = AgentMessagesSkeletonView()
        skeleton.frame = CGRect(x: 0, y: 0, width: 402, height: 700)
        skeleton.layoutIfNeeded()
        let bubbles = skeleton.subviews
            .compactMap { $0 as? AgentBubbleBackgroundView }
            .filter { !$0.isHidden }
            .sorted { $0.frame.maxY > $1.frame.maxY }
        let lowest = try XCTUnwrap(bubbles.first)
        XCTAssertEqual(lowest.frame.maxY, 700)
        XCTAssertEqual(lowest.frame.width, (402 * 0.86).rounded())
        // The Agent's answers run several paragraphs and the user's questions a line or two
        let heights: [CGFloat] = [248, 56, 216, 40, 264, 56, 232, 40]
        let widthFractions: [CGFloat] = [0.86, 0.56, 0.92, 0.44, 0.80, 0.60, 0.86, 0.48]
        XCTAssertGreaterThanOrEqual(bubbles.count, 5)
        // From the bottom, the Agent's bubbles and the user's take turns, each at its side with the chat's insets
        for (index, bubble) in bubbles.enumerated() {
            XCTAssertEqual(bubble.frame.height, heights[index] + AgentBubbleBackgroundView.tailBottomOverflow)
            if index.isMultiple(of: 2) {
                XCTAssertEqual(bubble.frame.minX, AgentMessageCellMetrics.horizontalInset)
                XCTAssertLessThanOrEqual(bubble.frame.maxX, 402 - AgentMessageCellMetrics.incomingTrailingInset)
            } else {
                XCTAssertEqual(bubble.frame.width, (402 * widthFractions[index]).rounded())
                XCTAssertEqual(bubble.frame.maxX, 402 - AgentMessageCellMetrics.horizontalInset)
                XCTAssertGreaterThanOrEqual(bubble.frame.minX, AgentMessageCellMetrics.outgoingOppositeInset)
            }
        }
        // Each tail hangs into the gap below its bubble and stops short of the next one
        for (lower, upper) in zip(bubbles, bubbles.dropFirst()) {
            XCTAssertEqual(lower.frame.minY - upper.frame.maxY, AgentVCLayout.rowSpacing, accuracy: 0.01)
        }
    }

    @MainActor
    func testPushedChatReturnsToTheListWithTheThreadsButton() async throws {
        let client = try ThreadChatClient(threadId: "selected-thread")
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let list = UIViewController()
        let navigation = UINavigationController(rootViewController: list)
        // On screen, so the button's animated pop runs
        let window = makeKeyWindow(showing: navigation)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        let chat = AgentVC(model: model)
        navigation.pushViewController(chat, animated: false)
        chat.loadViewIfNeeded()

        let threadsButton = try XCTUnwrap(AgentChatNavigation.findButton(in: chat.navigationItem.leftBarButtonItem))
        XCTAssertEqual(threadsButton.accessibilityIdentifier, "agent_threads_button")
        XCTAssertEqual(threadsButton.accessibilityLabel, lang("Back"))
        XCTAssertEqual(threadsButton.configuration?.image, AgentChatNavigation.backImage)
        // A fixed square slot keeps the glass a circle like the system back button
        XCTAssertEqual(threadsButton.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(threadsButton.superview?.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertTrue(chat.navigationItem.hidesBackButton)
        let threadsCircle = try XCTUnwrap(AgentChatNavigation.findCircle(in: chat.navigationItem.leftBarButtonItem))
        XCTAssertTrue(chat.navigationHandoffLeadingView === threadsCircle)
        XCTAssertTrue(threadsCircle.button === threadsButton)
        let menuButton = try XCTUnwrap(AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem))
        XCTAssertEqual(menuButton.accessibilityIdentifier, "agent_menu_button")
        XCTAssertEqual(menuButton.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertTrue(menuButton.showsMenuAsPrimaryAction)
        XCTAssertNotNil(menuButton.menu)
        let menuCircle = try XCTUnwrap(AgentChatNavigation.findCircle(in: chat.navigationItem.rightBarButtonItem))
        XCTAssertTrue(chat.navigationHandoffTrailingView === menuCircle)
        chat.setNavigationHandoffHidden(true)
        XCTAssertEqual(threadsCircle.alpha, 0)
        XCTAssertEqual(menuCircle.alpha, 0)
        chat.setNavigationHandoffHidden(false)
        XCTAssertEqual(threadsCircle.alpha, 1)
        XCTAssertEqual(menuCircle.alpha, 1)

        // Once the push has put the chat on screen, the button takes it back to the list
        window.layoutIfNeeded()
        try await waitUntil { chat.viewIfLoaded?.window != nil && navigation.transitionCoordinator == nil }
        threadsButton.sendActions(for: .primaryActionTriggered)
        try await waitUntil { navigation.topViewController === list && navigation.transitionCoordinator == nil }

        // A chat at the root of its stack keeps the system navigation
        navigation.setViewControllers([chat], animated: false)
        chat.viewIsAppearing(false)
        XCTAssertNil(chat.navigationItem.leftBarButtonItem)
        XCTAssertFalse(chat.navigationItem.hidesBackButton)
    }

    @MainActor
    func testPushedChatKeepsTheSwipeBackWhileItsThreadsButtonReplacesTheBackButton() async throws {
        let client = try ThreadChatClient(threadId: "selected-thread")
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let navigation = WNavigationController(rootViewController: UIViewController())
        navigation.loadViewIfNeeded()
        defer { navigation.setViewControllers([], animated: false) }
        let systemDelegate = navigation.interactivePopGestureRecognizer?.delegate
        let chat = AgentVC(model: model)
        navigation.pushViewController(chat, animated: false)
        chat.loadViewIfNeeded()
        chat.viewIsAppearing(false)
        chat.viewDidAppear(false)

        XCTAssertTrue(chat.navigationItem.hidesBackButton)
        XCTAssertTrue(navigation.interactivePopGestureRecognizer?.delegate === navigation)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(navigation.interactiveContentPopGestureRecognizer?.delegate === navigation)
        }
        XCTAssertTrue(chat.shouldAllowBackSwipe(at: CGPoint(x: 8, y: 300)))

        chat.viewWillDisappear(false)
        XCTAssertTrue(navigation.interactivePopGestureRecognizer?.delegate === systemDelegate)
    }

    @MainActor
    func testNewsCardLandsOnThePostAndHandsOverToIt() async throws {
        let client = try ThreadChatClient(threadId: "news-thread", messages: [])
        client.blocksNewsCreation = true
        let preloader = AgentPreloader(client: client)
        let item = newsItem(imageUrl: nil)
        let chat = try XCTUnwrap(
            AgentEntryPoint.makeNewsChatViewController(item: item, locale: "en", preloader: preloader) { _ in } as? AgentVC
        )
        let model = preloader.acquireNewsModel(item: item, locale: "en") { _ in }
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 220))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let isFlying = chat.prepareNewsPostArrival(snapshot: card, from: CGRect(x: 16, y: 320, width: 370, height: 220), contentTop: 100, in: window)
        try XCTSkipUnless(isFlying, "Reduce Motion keeps the post in place")
        // The card waits in the window where the feed showed it, under the headers
        XCTAssertTrue(card.window === window)
        XCTAssertTrue(card.superview === chat.newsPostArrival?.flightView)
        let navigation = UINavigationController(rootViewController: chat)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        let postID = try XCTUnwrap(model.newsPostItemID)
        let collection = try XCTUnwrap(descendants(of: chat.view).compactMap { $0 as? UICollectionView }.first)
        let postIndex = try XCTUnwrap(model.itemIDs.firstIndex(of: postID))
        var post: AgentNewsPostCell?
        try await waitUntil {
            window.layoutIfNeeded()
            post = collection.cellForItem(at: IndexPath(item: postIndex, section: 0)) as? AgentNewsPostCell
            return post != nil
        }
        let cell = try XCTUnwrap(post)
        // The post stays hidden under the card until the card lands on it
        XCTAssertEqual(cell.contentView.alpha, 0)

        for _ in 0..<300 where cell.contentView.alpha < 1 || card.superview != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(cell.contentView.alpha, 1)
        XCTAssertNil(card.superview)
        XCTAssertEqual(descendants(of: chat.view).compactMap { $0 as? AgentNewsPostCell }.count, 1)
    }

    /// The flight stays outside both clipped screens, with its own header and composer limits in window coordinates.
    @MainActor
    func testNewsCardStaysUnderTheHeadersFromTakeoffToLanding() async throws {
        let item = newsItem(imageUrl: nil)
        let response = try newsResponse(headline: item.headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsPostWithSuggestion(for: item)],
            news: response.thread.news
        )
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        await model.waitForInitialLoad()
        let chat = AgentVC(model: model)
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 220))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let feedContentTop: CGFloat = 100
        let isFlying = chat.prepareNewsPostArrival(
            snapshot: card,
            from: CGRect(x: 16, y: 40, width: 370, height: 220),
            contentTop: feedContentTop,
            in: window
        )
        try XCTSkipUnless(isFlying, "Reduce Motion keeps the post in place")
        let arrival = try XCTUnwrap(chat.newsPostArrival)
        let navigation = UINavigationController(rootViewController: chat)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        func assertLayering(_ phase: String) throws {
            XCTAssertTrue(card.isDescendant(of: arrival.flightView), phase)
            XCTAssertTrue(arrival.flightView.superview === window, phase)
            XCTAssertFalse(arrival.flightView.isDescendant(of: chat.view), phase)
            XCTAssertEqual(arrival.flightView.frame, window.bounds, phase)
            let mask = try XCTUnwrap(arrival.flightView.layer.mask as? CAGradientLayer, phase)
            let height = arrival.flightView.bounds.height
            let locations = try XCTUnwrap(mask.locations?.map { CGFloat($0.doubleValue) * height }, phase)
            XCTAssertEqual(mask.frame, arrival.flightView.bounds, phase)
            XCTAssertEqual(locations.count, 6, phase)
            guard locations.count == 6 else { return }
            XCTAssertEqual(locations[1], arrival.contentTop, accuracy: 0.5, phase)
            XCTAssertEqual(locations[2] - locations[1], AgentNewsPostArrival.headerFadeHeight, accuracy: 0.5, phase)
            XCTAssertEqual(mask.colors?.count, 6, phase)
            XCTAssertEqual(locations, locations.sorted(), phase)
            if locations[4] < height {
                let composerTop = chat.composerView.convert(chat.composerView.inputBackgroundFrame, to: window).minY
                XCTAssertEqual(locations[4], composerTop, accuracy: 0.5, phase)
                XCTAssertEqual(locations[4] - locations[3], AgentVCLayout.bottomEdgeFadeHeight, accuracy: 0.5, phase)
            }
        }
        try assertLayering("holding")
        chat.view.clipsToBounds = true
        chat.view.transform = CGAffineTransform(translationX: 120, y: 0)

        var flyingSamples = 0
        _ = try await waitForLandedNewsPost(in: chat, of: model, card: card, window: window) { _ in
            guard card.superview != nil else { return }
            flyingSamples += 1
            try? assertLayering("flying")
        }
        XCTAssertGreaterThan(flyingSamples, 0)
        XCTAssertNil(arrival.flightView.superview)
    }

    @MainActor
    func testNewsFlightSamplesTheCardThroughTheHeaderAndRestoresBackdropsOnCancel() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 880, height: 874))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let feed = WViewController()
        let navigation = UINavigationController(rootViewController: feed)
        root.addChild(navigation)
        root.view.addSubview(navigation.view)
        navigation.view.frame = CGRect(x: 280, y: 0, width: 600, height: 874)
        navigation.didMove(toParent: root)
        let feedHeader = feed.addCustomNavigationBarBackground(color: .white)
        window.layoutIfNeeded()
        let sourceHeaderHeight = feedHeader.bounds.height

        let destination = WViewController()
        destination.loadViewIfNeeded()
        let destinationHeader = destination.addCustomNavigationBarBackground(color: .white)
        let card = UIView()
        card.backgroundColor = .red
        let sourceFrame = CGRect(x: 300, y: 80, width: 500, height: 320)
        let arrival = AgentNewsPostArrival(card: card, frame: sourceFrame, contentTop: 100) {
            guard destination.view.window != nil else { return nil }
            return AgentNewsPostArrival.Destination(
                hostView: destination.view, cell: nil, news: nil,
                contentTop: 100, contentBottom: 780, headerBackground: destinationHeader
            )
        }
        defer { arrival.cancel(); window.isHidden = true }
        arrival.start(in: window, navigationHost: navigation, sourceHeaderBackground: feedHeader)
        XCTAssertTrue(arrival.flightView.superview === navigation.view)
        XCTAssertEqual(card.convert(card.bounds, to: window), sourceFrame)
        XCTAssertTrue(feedHeader.isHidden)
        let mask = try XCTUnwrap(arrival.flightView.layer.mask as? CAGradientLayer)
        let firstColor = try XCTUnwrap(mask.colors?.first) as! CGColor
        XCTAssertEqual(firstColor.alpha, 1, "The flying card remains visible to the translucent header")

        navigation.pushViewController(destination, animated: false)
        destination.view.clipsToBounds = true
        destination.view.transform = CGAffineTransform(translationX: 100, y: 0)
        window.layoutIfNeeded()
        destinationHeader.frame.size.height = 20
        try await waitUntil { destinationHeader.isHidden }
        XCTAssertFalse(arrival.flightView.isDescendant(of: destination.view))
        var chrome: UIView = navigation.navigationBar
        while let parent = chrome.superview, parent !== navigation.view { chrome = parent }
        let flightIndex = try XCTUnwrap(navigation.view.subviews.firstIndex(of: arrival.flightView))
        let chromeIndex = try XCTUnwrap(navigation.view.subviews.firstIndex(of: chrome))
        XCTAssertLessThan(flightIndex, chromeIndex)
        XCTAssertEqual(navigation.view.subviews.filter {
            $0.accessibilityIdentifier == "AgentFlightHeaderBackdrop"
        }.count, 1, "The overlapping screens share one tint, rather than doubling its opacity")
        let backdrop = try XCTUnwrap(navigation.view.subviews.first {
            $0.accessibilityIdentifier == "AgentFlightHeaderBackdrop"
        })
        let backdropIndex = try XCTUnwrap(navigation.view.subviews.firstIndex(of: backdrop))
        XCTAssertLessThan(flightIndex, backdropIndex)
        XCTAssertLessThan(backdropIndex, chromeIndex)
        XCTAssertFalse(backdrop.isDescendant(of: arrival.flightView), "The flight mask must not contain the live blur")
        XCTAssertNil(backdrop.superview?.layer.mask)
        XCTAssertEqual(backdrop.frame.minX, 0)
        XCTAssertEqual(backdrop.frame.width, navigation.view.bounds.width)
        XCTAssertGreaterThanOrEqual(backdrop.frame.height, sourceHeaderHeight,
                                    "An incoming header without its final safe area must not shrink the backdrop")
        arrival.cancel()
        XCTAssertFalse(feedHeader.isHidden)
        XCTAssertFalse(destinationHeader.isHidden)
        XCTAssertNil(arrival.flightView.superview)
        XCTAssertNil(backdrop.superview)
    }

    @MainActor
    func testNewsFlightKeepsTheHeaderBackdropVisibleAtEveryScrollPosition() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("The composed header requires an application host with a window scene")
        }
        let imageKey = "https://example.invalid/news-flight-header-\(UUID().uuidString).png"
        let blackImage = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
        try await ImageCache.default.store(blackImage, forKey: imageKey, toDisk: false)
        defer { ImageCache.default.removeImage(forKey: imageKey, fromDisk: false, completionHandler: nil) }
        let news = ApiAgentV2ThreadNewsCard(
            eventId: 307,
            headline: "A news discussion",
            excerpt: nil,
            imageUrl: imageKey,
            publishedAt: "2026-10-20T10:00:00Z",
            source: "A source",
            body: String(repeating: "A market update remains visible below the picture. ", count: 12),
            sources: nil
        )
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        defer { previousKeyWindow?.makeKey() }

        // Scrolling the source past the destination reverses the card's pitch through the stationary header.
        for sourceOffset in [CGFloat(-140), -50, 70] {
            let controller = WViewController()
            controller.title = "Discussion"
            let navigation = UINavigationController(rootViewController: controller)
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            navigation.navigationBar.standardAppearance = appearance
            navigation.navigationBar.scrollEdgeAppearance = appearance
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            controller.view.backgroundColor = .white
            controller.view.clipsToBounds = true
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            let cell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 700))
            controller.view.addSubview(cell)
            cell.configure(with: news)
            cell.layoutIfNeeded()
            cell.frame.size.height = cell.contentView.systemLayoutSizeFitting(
                CGSize(width: cell.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            let header = controller.addCustomNavigationBarBackground(color: .white)
            window.layoutIfNeeded()
            try await waitUntil { cell.newsView.imageView.image != nil }
            cell.layoutIfNeeded()

            let barFrame = navigation.navigationBar.convert(navigation.navigationBar.bounds, to: window)
            // The trailing part of this header contains no navigation button or title glass.
            let region = CGRect(x: window.bounds.width - 70, y: barFrame.minY + 6, width: 24, height: 12)
            let imageFrame = cell.newsView.imageView.convert(cell.newsView.imageView.bounds, to: window)
            cell.frame.origin.y += region.midY - imageFrame.midY
            window.layoutIfNeeded()
            XCTAssertTrue(cell.newsView.imageView.convert(cell.newsView.imageView.bounds, to: window).contains(region))
            try await Task.sleep(for: .milliseconds(80))

            let baseline = try captureNewsHeader(in: window)
            let baselineBrightness = try newsHeaderBrightness(baseline, in: region)
            header.isHidden = true
            let uncovered = try captureNewsHeader(in: window)
            header.isHidden = false
            let uncoveredBrightness = try newsHeaderBrightness(uncovered, in: region)
            XCTAssertLessThan(uncoveredBrightness, 0.12, "The control must expose the black picture, not native bar glass")
            XCTAssertGreaterThan(baselineBrightness - uncoveredBrightness, 0.35,
                                 "A blank snapshot cannot verify the normal header's tint and blur")
            let baselineAttachment = XCTAttachment(image: baseline)
            baselineAttachment.name = "Normal header over black news, source offset \(Int(sourceOffset))"
            baselineAttachment.lifetime = .keepAlways
            add(baselineAttachment)

            let target = cell.postView.convert(cell.postView.bounds, to: window)
            let sourceFrame = CGRect(
                x: target.minX, y: target.minY + sourceOffset,
                width: target.width, height: target.height - cell.postTailOverflow
            )
            XCTAssertTrue(sourceFrame.contains(region))
            let card = UIImageView(image: blackImage)
            let arrival = AgentNewsPostArrival(card: card, frame: sourceFrame, contentTop: barFrame.maxY) {
                AgentNewsPostArrival.Destination(
                    hostView: controller.view, cell: cell, news: news,
                    contentTop: barFrame.maxY, contentBottom: window.bounds.height - 90,
                    headerBackground: header
                )
            }
            defer { arrival.cancel() }
            arrival.start(in: window, navigationHost: navigation, sourceHeaderBackground: header)
            let flightContainer = try XCTUnwrap(card.superview)
            XCTAssertTrue(flightContainer.superview === arrival.flightView, "The cell must start the actual 3D flight")
            XCTAssertEqual(cell.contentView.alpha, 0)
            let startedAt = CACurrentMediaTime()
            var sampleCount = 0
            var tiltedSampleCount = 0
            var worstBrightness = CGFloat.greatestFiniteMagnitude
            var worstImage: UIImage?
            var worstTime: CFTimeInterval = 0
            for sampleTime in [0.10, 0.16, 0.22, 0.28, 0.34, 0.40] {
                let delay = sampleTime - (CACurrentMediaTime() - startedAt)
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                let elapsed = CACurrentMediaTime() - startedAt
                guard elapsed < 0.48, card.superview === flightContainer else { continue }
                let transform = flightContainer.layer.transform
                if abs(transform.m23) + abs(transform.m13) > 0.001 { tiltedSampleCount += 1 }
                let frame = try captureNewsHeader(in: window)
                let brightness = try newsHeaderBrightness(frame, in: region)
                sampleCount += 1
                if brightness < worstBrightness {
                    worstBrightness = brightness
                    worstImage = frame
                    worstTime = elapsed
                }
            }
            let worstAttachment = XCTAttachment(image: try XCTUnwrap(worstImage))
            worstAttachment.name = "Darkest flying header, offset \(Int(sourceOffset)), \(Int(worstTime * 1000)) ms"
            worstAttachment.lifetime = .keepAlways
            add(worstAttachment)
            XCTAssertGreaterThanOrEqual(sampleCount, 3, "Sample the moving card, not just its landed state")
            XCTAssertGreaterThanOrEqual(tiltedSampleCount, 3, "The samples must include the card's perspective tilt")
            XCTAssertGreaterThanOrEqual(worstBrightness, baselineBrightness - 0.12,
                                        "The header vanished during flight from offset \(sourceOffset): baseline \(baselineBrightness), darkest \(worstBrightness)")
            arrival.cancel()
            XCTAssertFalse(header.isHidden)
            XCTAssertEqual(cell.contentView.alpha, 1)
        }
    }

    @MainActor
    func testNewsSuggestionsThatArriveAfterTheCardLandsRiseIntoPlaceUnderThePost() async throws {
        let item = newsItem(imageUrl: nil)
        let response = try newsResponse(headline: item.headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsPostWithSuggestion(for: item)],
            news: response.thread.news
        )
        client.blocksNewsCreation = true
        let model = AgentV2Model(client: client, news: item, locale: "en") { _ in }
        let chat = AgentVC(model: model)
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 220))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let isFlying = chat.prepareNewsPostArrival(snapshot: card, from: CGRect(x: 16, y: 320, width: 370, height: 220), contentTop: 100, in: window)
        try XCTSkipUnless(isFlying, "Reduce Motion keeps the post in place")
        let navigation = UINavigationController(rootViewController: chat)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
            client.releasePendingRequests()
        }
        let cell = try await waitForLandedNewsPost(in: chat, of: model, card: card, window: window)

        client.resumeNewsCreation(with: .success(response))
        var buttons: [AgentSuggestionButton] = []
        for _ in 0..<200 where buttons.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
            buttons = descendants(of: cell).compactMap { $0 as? AgentSuggestionButton }
        }

        // As under an answer, the suggestions rise into place under the post, which loses its tail, and end enabled at
        // full strength once the discussion can be written in
        XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Why does this matter?"])
        XCTAssertTrue(buttons.allSatisfy { $0.layer.animationKeys()?.isEmpty == false })
        XCTAssertEqual(cell.postTailOverflow, 0)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(model.canSendMessage(draftText: "A question"))
        XCTAssertTrue(buttons.allSatisfy { button in
            button.isEnabled && button.alpha == 1 && abs((button.layer.presentation()?.opacity ?? 1) - 1) < 0.01
        })
    }

    @MainActor
    func testNewsSuggestionsShownBeforeTheCardLandsRiseIntoPlaceAsItLands() async throws {
        let item = newsItem(imageUrl: nil)
        let response = try newsResponse(headline: item.headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsPostWithSuggestion(for: item)],
            news: response.thread.news
        )
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        await model.waitForInitialLoad()
        let chat = AgentVC(model: model)
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 220))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let isFlying = chat.prepareNewsPostArrival(snapshot: card, from: CGRect(x: 16, y: 320, width: 370, height: 220), contentTop: 100, in: window)
        try XCTSkipUnless(isFlying, "Reduce Motion keeps the post in place")
        let navigation = UINavigationController(rootViewController: chat)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        var standInTailOverflows: Set<CGFloat> = []
        let cell = try await waitForLandedNewsPost(in: chat, of: model, card: card, window: window) { post in
            for standIn in self.descendants(of: window).compactMap({ $0 as? AgentNewsPostCell }) where standIn !== post {
                standInTailOverflows.insert(standIn.postTailOverflow)
            }
        }
        let buttons = descendants(of: cell).compactMap { $0 as? AgentSuggestionButton }

        // The copy of the post the card turns into has no tail either, and the suggestions rise into place as it lands
        XCTAssertEqual(standInTailOverflows, [0])
        XCTAssertEqual(cell.postTailOverflow, 0)
        XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Why does this matter?"])
        XCTAssertTrue(buttons.allSatisfy { $0.layer.animationKeys()?.isEmpty == false })
    }

    @MainActor
    func testLateNewsSuggestionsMorphFromPlaceholdersWithoutJumping() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let body = String(repeating: "Market context explaining this update in detail.\n\n", count: 25)
        let item = newsItem(imageUrl: nil, body: body)
        let response = try newsResponse(headline: item.headline, messageCount: 1, body: body)
        var post = newsPostWithSuggestion(for: item)
        post["followups"] = (0..<3).map { index in
            ["id": UUID().uuidString.lowercased(), "kind": "suggested_prompt", "text": "Explain this update \(index)"]
        }
        let client = try ThreadChatClient(threadId: "news-thread", messages: [post], news: response.thread.news)
        XCTAssertEqual(client.hydration.messages.first?.followups?.count, 3)
        client.blocksNewsCreation = true
        let model = AgentV2Model(client: client, news: item, locale: "en") { _ in }
        let chat = AgentVC(model: model)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 390))
        let navigation = UINavigationController(rootViewController: chat)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
            client.releasePendingRequests()
        }
        try await waitUntil {
            window.layoutIfNeeded()
            return client.pendingNewsCreation != nil && chat.hasPerformedInitialScroll
        }
        // The placeholders come once the suggestions have taken a second, and settle as they come in
        var postCell: AgentNewsPostCell?
        for _ in 0..<300 where postCell?.showsFollowupPlaceholders != true {
            try await Task.sleep(for: .milliseconds(10))
            window.layoutIfNeeded()
            postCell = descendants(of: chat.view).compactMap { $0 as? AgentNewsPostCell }.first
        }
        XCTAssertEqual(postCell?.showsFollowupPlaceholders, true)
        try await Task.sleep(for: .milliseconds(700))
        window.layoutIfNeeded()
        let loading = try XCTUnwrap(descendants(of: chat.view).compactMap { $0 as? AgentFollowupView }.first)
        XCTAssertEqual(loading.arrangedSubviews.count, 3)
        let before = loading.convert(loading.bounds, to: window).minY
        client.resumeNewsCreation(with: .success(response))
        var offsets: [CGFloat] = []
        var hasAnimatedButton = false
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            offsets.append(loading.convert(loading.bounds, to: window).minY)
            hasAnimatedButton = hasAnimatedButton || descendants(of: chat.view)
                .compactMap { $0 as? AgentFollowupView }
                .contains { $0.isFillingPlaceholders }
        }
        let end = try XCTUnwrap(offsets.last)
        XCTAssertEqual(model.message(for: try XCTUnwrap(model.newsPostItemID))?.controls.count, 3)
        XCTAssertLessThan(abs(end - before), 1, "Replacing equal-height placeholders keeps the visible suggestions in place")
        XCTAssertTrue(hasAnimatedButton, "The real suggestions fill the placeholders' pills")
    }

    @MainActor
    func testSelectedThreadIgnoresForeignThreadChangesBeforeAndAfterHydration() async throws {
        let initialThread = try decodeThread(id: "selected-thread", revision: 1)
        let foreignThread = try decodeThread(id: "another-thread", revision: 9)
        let client = try ThreadChatClient(threadId: initialThread.id)
        let coordinator = AgentV2Coordinator(client: client, thread: initialThread)
        defer { coordinator.stop() }

        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: foreignThread.id, thread: foreignThread)))
        XCTAssertEqual(coordinator.thread, initialThread)

        coordinator.start()
        await coordinator.waitForInitialLoad()
        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: foreignThread.id, thread: foreignThread)))

        XCTAssertEqual(coordinator.thread, client.hydration.thread)
        XCTAssertEqual(coordinator.messages.map(\.id), ["answer"])
        XCTAssertEqual(client.hydratedThreadIds, [initialThread.id])
        XCTAssertEqual(client.defaultThreadCallCount, 0)
    }

    @MainActor
    func testNewsEntryPresentsThePreviewPostImmediatelyWithoutTypingOrStartingARun() async throws {
        let client = try ThreadChatClient(threadId: "news-thread", messages: [])
        client.blocksNewsCreation = true
        let preloader = AgentPreloader(client: client)
        let item = newsItem(imageUrl: nil)
        let controller = AgentEntryPoint.makeNewsChatViewController(item: item, locale: "en", preloader: preloader) { _ in }
        let model = preloader.acquireNewsModel(item: item, locale: "en") { _ in }
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }

        let postID = try XCTUnwrap(model.newsPostItemID)
        let post = try XCTUnwrap(model.message(for: postID))
        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertTrue(model.delegate === controller)
        XCTAssertEqual(controller.title, item.headline)
        XCTAssertNil(model.threadId)
        XCTAssertEqual(post.role, .assistant)
        XCTAssertTrue(post.newsPost)
        XCTAssertEqual(model.news?.body, item.body)
        XCTAssertEqual(model.news?.sources, item.sources)
        XCTAssertEqual(model.news?.imageUrl, item.imageUrl)
        XCTAssertEqual(model.news?.publishedAt, item.deliveredAt)
        XCTAssertTrue(typingIndicatorIDs(in: model).isEmpty)
        XCTAssertFalse(model.canSendMessage(draftText: "A follow-up question"))
        let composer = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? AgentComposerView }.first)
        XCTAssertEqual(composer.placeholder, lang("Ask anything"))
        XCTAssertFalse(descendants(of: controller.view).contains { ($0 as? UIActivityIndicatorView)?.isAnimating == true })

        try await waitUntil { client.pendingNewsCreation != nil }
        let collection = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        let postIndex = try XCTUnwrap(model.itemIDs.firstIndex(of: postID))
        try await waitUntil {
            window.layoutIfNeeded()
            return collection.cellForItem(at: IndexPath(item: postIndex, section: 0)) is AgentNewsPostCell
        }
        XCTAssertEqual(client.newsThreadRequests, [.init(eventId: item.eventId, locale: "en")])
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(client.hydratedThreadIds.isEmpty)
        XCTAssertTrue(model.canDeleteChat)
        // Untouched, the discussion has no Delete; with consent its menu has Report a Problem from the start
        try await waitUntil { AgentChatNavigation.findButton(in: controller.navigationItem.rightBarButtonItem) != nil }
    }

    /// A news discussion the user hasn't written in has no Delete, after consent as well: its menu has Report a Problem
    /// alone, and its menu button shows for it
    @MainActor
    func testUntouchedNewsDiscussionOffersOnlyAProblemReport() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(threadId: "news-thread", news: response.thread.news)
        client.isProblemReportAvailable = true
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        XCTAssertFalse(model.isStarted)
        let chat = AgentVC(model: model)
        let navigation = UINavigationController(rootViewController: chat)
        let window = makeKeyWindow(showing: navigation)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        try await waitUntil { AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem) != nil }
        let actions = AgentChatActions(model: model, viewController: chat, cancelDictation: {}, refreshNavigationItemMenu: {})
        XCTAssertFalse(actions.canDeleteChat)
        XCTAssertEqual(actions.makeOverflowMenu().children.compactMap { ($0 as? UIAction)?.title }, [lang("Report a Problem")])
    }

    /// With consent, a news discussion offers Report a Problem from the start, while its thread is still being created
    /// and before the server's check has answered; a report sent then goes once the thread is there, and once
    @MainActor
    func testNewsDiscussionOffersAProblemReportBeforeItsThreadAndSendsItOnceItIsThere() async throws {
        let item = newsItem()
        let response = try newsResponse(headline: item.headline, messageCount: 1)
        let client = try ThreadChatClient(threadId: "news-thread", news: response.thread.news)
        client.blocksNewsCreation = true
        client.isProblemReportAvailable = true
        let model = AgentV2Model(client: client, news: item, locale: "en") { _ in }
        let controller = AgentVC(model: model)
        let navigation = UINavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigation)
        defer {
            model.stop()
            client.releasePendingRequests()
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        try await waitUntil { client.pendingNewsCreation != nil }
        try await waitUntil { model.canReportProblem }
        XCTAssertEqual(client.problemReportAvailabilityRequestCount, 0, "Before the server's check")
        try await waitUntil { AgentChatNavigation.findButton(in: controller.navigationItem.rightBarButtonItem) != nil }
        let actions = AgentChatActions(model: model, viewController: controller, cancelDictation: {}, refreshNavigationItemMenu: {})
        XCTAssertEqual(actions.makeOverflowMenu().children.compactMap { ($0 as? UIAction)?.title }, [lang("Report a Problem")])

        let report = Task { await model.reportProblem(messageID: nil, comment: "Wrong summary") }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(client.reports.isEmpty, "Held until the thread is there")
        client.resumeNewsCreation(with: .success(response))
        let isSent = await report.value
        XCTAssertTrue(isSent)
        XCTAssertEqual(client.reports.map(\.threadId), [response.thread.id], "Sent once, to the thread")
        XCTAssertEqual(client.reports.first?.report.comment, "Wrong summary")
    }

    /// With the consent the app already knows, a news discussion's ⋯ is in its header from the start, before the chat
    /// appears, its thread exists or its consent is read again
    @MainActor
    func testNewsDiscussionHasItsMenuButtonBeforeItAppears() throws {
        let item = newsItem()
        let response = try newsResponse(headline: item.headline, messageCount: 1)
        let client = try ThreadChatClient(threadId: "news-thread", news: response.thread.news)
        client.blocksNewsCreation = true
        client.isConsentKnownGiven = true
        let model = AgentV2Model(client: client, news: item, locale: "en") { _ in }
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        let controller = AgentVC(model: model)
        controller.loadViewIfNeeded()
        XCTAssertNotNil(AgentChatNavigation.findButton(in: controller.navigationItem.rightBarButtonItem))
        XCTAssertTrue(model.canReportProblem)
    }

    /// The server's check saying it takes no reports takes Report a Problem away, which shows until then
    @MainActor
    func testServerTakingNoReportsTakesTheProblemReportAway() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(threadId: "news-thread", news: response.thread.news)
        client.isProblemReportAvailable = false
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        try await waitUntil { client.problemReportAvailabilityRequestCount > 0 && !model.canReportProblem }
        let isSent = await model.reportProblem(messageID: nil, comment: nil)
        XCTAssertFalse(isSent)
        XCTAssertTrue(client.reports.isEmpty)
    }

    @MainActor
    func testFeedReopensExistingNewsDiscussionWithTheSavedPostDateHeader() async throws {
        let item = newsItem()
        let response = try newsResponse(headline: item.headline, messageCount: 3)
        let formatter = ISO8601DateFormatter()
        let createdAt = formatter.string(from: Date().addingTimeInterval(-3 * 24 * 60 * 60))
        let savedDate = try XCTUnwrap(formatter.date(from: createdAt))
        let client = try ThreadChatClient(threadId: "news-thread", messages: [
            newsMessage(text: "**\(item.headline)**\n\n\(item.body)", createdAt: createdAt),
            newsMessage(id: "question", role: "user", text: "What does this mean?", isPost: false, createdAt: createdAt),
            newsMessage(id: "answer", text: "The previous analysis", isPost: false, createdAt: createdAt)
        ], news: response.thread.news)
        client.blocksNewsCreation = true
        let model = AgentV2Model(client: client, news: item, locale: "en") { _ in }
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        let postID = try XCTUnwrap(model.newsPostItemID)
        let previewDate = try XCTUnwrap(model.message(for: postID)?.timestamp)
        XCTAssertGreaterThan(previewDate.timeIntervalSince(savedDate), 2 * 24 * 60 * 60)
        try await waitUntil { client.pendingNewsCreation != nil }
        client.resumeNewsCreation(with: .success(response))
        await model.waitForInitialLoad()

        let messages = model.itemIDs.compactMap { model.message(for: $0) }
        let dateHeader = try XCTUnwrap(messages.first { $0.isDateTimeSystemMessage })
        XCTAssertEqual(model.newsPostItemID, postID)
        XCTAssertEqual(model.message(for: postID)?.timestamp, savedDate)
        XCTAssertEqual(dateHeader.timestamp, savedDate)
        XCTAssertEqual(messages.filter(\.newsPost).map(\.id), [postID])
        XCTAssertEqual(messages.filter { !$0.isDateTimeSystemMessage }.count, 3)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testSavedNewsPostReplacesPreviewWithoutDuplicatesOrMovingTheTimeline() async throws {
        let item = newsItem(imageUrl: nil)
        let response = try newsResponse(headline: item.headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsMessage(
                text: "**\(item.headline)**\n\n\(item.body)",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )],
            news: response.thread.news
        )
        client.blocksNewsCreation = true
        let model = AgentV2Model(client: client, news: item, locale: "en") { _ in }
        let controller = AgentVC(model: model)
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
            client.releasePendingRequests()
        }
        let postID = try XCTUnwrap(model.newsPostItemID)
        let collection = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        func postTopY() throws -> CGFloat {
            let index = try XCTUnwrap(model.itemIDs.firstIndex(of: postID))
            let frame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0))).frame
            return collection.convert(frame, to: window).minY
        }
        func settleLayout() async throws {
            var previous: [CGFloat] = []
            var stableSamples = 0
            for _ in 0..<200 {
                try await Task.sleep(for: .milliseconds(16))
                window.layoutIfNeeded()
                controller.view.layoutIfNeeded()
                let state = [collection.contentOffset.y, collection.contentSize.height, try postTopY()]
                stableSamples = state == previous ? stableSamples + 1 : 0
                if stableSamples == 10 { return }
                previous = state
            }
            XCTFail("News chat layout did not settle")
            throw ThreadChatClientError.unavailable
        }
        try await waitUntil { client.pendingNewsCreation != nil }
        try await settleLayout()
        let originalItemIDs = model.itemIDs.filter { model.message(for: $0)?.isDateTimeSystemMessage != true }
        let originalTopY = try postTopY()
        let postIndex = try XCTUnwrap(model.itemIDs.firstIndex(of: postID))
        let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: postIndex, section: 0)) as? AgentNewsPostCell)
        client.resumeNewsCreation(with: .success(response))
        await model.waitForInitialLoad()
        try await settleLayout()

        XCTAssertEqual(model.newsPostItemID, postID)
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.isDateTimeSystemMessage != true }, originalItemIDs)
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }, [postID])
        XCTAssertTrue(model.itemIDs.filter { model.message(for: $0)?.role == .user }.isEmpty)
        XCTAssertTrue(collection.cellForItem(at: IndexPath(item: postIndex, section: 0)) === cell)
        XCTAssertEqual(try postTopY(), originalTopY, accuracy: 0.5)
        XCTAssertEqual(model.news, try makeNewsCard(of: response, source: "First source"))
        XCTAssertTrue(model.canSendMessage(draftText: "A follow-up question"))
        XCTAssertTrue(typingIndicatorIDs(in: model).isEmpty)
        XCTAssertEqual(client.hydratedThreadIds, ["news-thread"])
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testEmptyNewsThreadShowsALocalPostAndNeverSendsTheHeadline() async throws {
        let response = try newsResponse(headline: "Server headline", messageCount: 0)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
        client.blocksNewsCreation = true
        let preloader = AgentPreloader(client: client)
        var createdThreads: [ApiAgentV2ThreadSummary] = []
        let model = preloader.acquireNewsModel(item: newsItem(), locale: "ru") { createdThreads.append($0) }
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        let postID = try XCTUnwrap(model.newsPostItemID)
        try await waitUntil { client.pendingNewsCreation != nil }
        client.resumeNewsCreation(with: .success(response))
        await model.waitForInitialLoad()

        XCTAssertEqual(model.newsPostItemID, postID)
        XCTAssertEqual(model.news, try makeNewsCard(of: response, source: "First source"))
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }, [postID])
        XCTAssertEqual(model.newsPost(for: try XCTUnwrap(model.message(for: postID)))?.headline, "Server headline")
        XCTAssertTrue(model.canSendMessage(draftText: "A follow-up question"))
        XCTAssertFalse(model.isOpening)
        XCTAssertTrue(typingIndicatorIDs(in: model).isEmpty)
        XCTAssertEqual(client.newsThreadRequests, [.init(eventId: newsItem().eventId, locale: "ru")])
        XCTAssertEqual(client.hydratedThreadIds, ["news-thread"])
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(client.retriedClientRunIds.isEmpty)
        XCTAssertEqual(createdThreads, [response.thread])
        XCTAssertTrue(preloader.model(threadId: response.thread.id) === model)
    }

    @MainActor
    func testClearedNewsHistoryKeepsALocalPostWithoutStartingARun() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsMessage(text: "**\(newsItem().headline)**")],
            news: response.thread.news
        )
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let postID = try XCTUnwrap(model.newsPostItemID)

        model.clearChat(animated: false)
        try await waitUntil { client.clearThreadCallCount == 1 && model.newsPostItemID != nil && !model.itemIDs.isEmpty }

        XCTAssertEqual(model.newsPostItemID, postID)
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }, [postID])
        XCTAssertTrue(model.canSendMessage(draftText: "A follow-up question"))
        XCTAssertFalse(model.isOpening)
        XCTAssertFalse(model.hasActiveRun)
        XCTAssertTrue(typingIndicatorIDs(in: model).isEmpty)
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(client.retriedClientRunIds.isEmpty)
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
    }

    @MainActor
    func testNewsThreadClearedBeforeHydrationUsesTheLocalPostWithoutStartingARun() async throws {
        let response = try newsResponse(headline: "Created headline", messageCount: 1)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [])
        client.blocksNewsCreation = true
        let model = AgentV2Model(client: client, news: newsItem(), locale: "en") { _ in }
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        let postID = try XCTUnwrap(model.newsPostItemID)
        try await waitUntil { client.pendingNewsCreation != nil }
        client.resumeNewsCreation(with: .success(response))
        await model.waitForInitialLoad()

        XCTAssertEqual(model.news?.headline, "Created headline")
        XCTAssertEqual(model.newsPostItemID, postID)
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }, [postID])
        XCTAssertTrue(model.canSendMessage(draftText: "A follow-up question"))
        XCTAssertEqual(client.hydratedThreadIds, ["news-thread"])
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(typingIndicatorIDs(in: model).isEmpty)
    }

    @MainActor
    func testNewsOpeningWaitsForHistoryBeforeSendingAndKeepsTheQuestionAfterHistory() async throws {
        let postText = "**\(newsItem().headline)**\n\n\(newsItem().body)"
        let response = try newsResponse(headline: newsItem().headline, messageCount: 3)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [
                newsMessage(text: postText),
                newsMessage(id: "earlier-question", role: "user", text: "Earlier question", isPost: false),
                newsMessage(id: "earlier-answer", text: "Earlier answer", isPost: false)
            ],
            news: response.thread.news
        )
        client.blocksNewsCreation = true
        client.blocksMessages = true
        client.blocksHostContext = true
        client.blocksRuns = true
        let model = AgentV2Model(client: client, news: newsItem(), locale: "en") { _ in }
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        try await waitUntil { client.pendingNewsCreation != nil }
        client.resumeNewsCreation(with: .success(response))
        try await waitUntil { client.pendingMessages != nil && client.pendingHostContext != nil }
        XCTAssertFalse(model.canSendMessage(draftText: "What does this mean?"))
        XCTAssertFalse(model.canClearChat)
        model.send(text: "A question before history loads")
        model.clearChat(animated: false)
        XCTAssertFalse(model.hasActiveRun)
        XCTAssertEqual(client.clearThreadCallCount, 0)
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(typingIndicatorIDs(in: model).isEmpty)

        client.resumeMessages(with: .success(client.hydration))
        try await waitUntil { model.canSendMessage(draftText: "What does this mean?") }
        XCTAssertTrue(model.canClearChat)
        XCTAssertEqual(
            model.itemIDs.compactMap { model.message(for: $0) }.filter { !$0.isDateTimeSystemMessage }.map(\.text),
            [postText, "Earlier question", "Earlier answer"]
        )
        model.send(text: "What does this mean?")
        XCTAssertEqual(client.hostContextPublishedCallCount, 0)
        XCTAssertTrue(client.startedCommands.isEmpty)
        client.resumeHostContext(with: .success(()))
        try await waitUntil { client.pendingRun != nil }
        XCTAssertEqual(client.hostContextPublishedCountsAtRunStart, [1])
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "What does this mean?")])
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [nil])
        XCTAssertFalse(model.isOpening)
        let questionID = try XCTUnwrap(model.itemIDs.first { model.message(for: $0)?.text == "What does this mean?" })

        await model.waitForInitialLoad()

        XCTAssertEqual(model.message(for: questionID)?.text, "What does this mean?")
        XCTAssertEqual(
            model.itemIDs.compactMap { model.message(for: $0) }.filter { !$0.isDateTimeSystemMessage }.map(\.text),
            [postText, "Earlier question", "Earlier answer", "What does this mean?"]
        )
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }.count, 1)
        XCTAssertEqual(client.clearThreadCallCount, 0)
        XCTAssertEqual(client.startedCommands.count, 1)
    }

    @MainActor
    func testHydratedNewsCardKeepsMissingPreviewBodyAndSourcesOnlyForTheSameEvent() async throws {
        let item = newsItem()
        let cases: [(eventID: Int, body: String?, sources: [ApiAgentV2NewsFeedItem.Source]?)] = [
            (item.eventId, nil, nil),
            (item.eventId, "Server body", nil),
            (item.eventId, nil, []),
            (item.eventId + 1, nil, nil)
        ]
        for testCase in cases {
            let expectedBody = testCase.body ?? (testCase.eventID == item.eventId ? item.body : nil)
            let expectedSources = testCase.sources ?? (testCase.eventID == item.eventId ? item.sources : nil)
            let card = ApiAgentV2ThreadNewsCard(
                eventId: testCase.eventID,
                headline: "Server headline",
                excerpt: "Old excerpt",
                imageUrl: nil,
                publishedAt: item.deliveredAt,
                source: nil,
                body: testCase.body,
                sources: testCase.sources
            )
            let client = try ThreadChatClient(
                threadId: "news-thread",
                messages: [newsMessage(text: "**Server headline**")],
                news: card
            )
            let response = try JSONDecoder().decode(
                ApiAgentV2ThreadCreateResponse.self,
                from: JSONSerialization.data(withJSONObject: [
                    "protocolVersion": 3, "created": false,
                    "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(client.hydration.thread))
                ])
            )
            client.blocksNewsCreation = true
            client.blocksMessages = true
            let model = AgentV2Model(client: client, news: item, locale: "en") { _ in }
            defer {
                model.stop()
                client.releasePendingRequests()
            }
            let postID = try XCTUnwrap(model.newsPostItemID)
            XCTAssertEqual(model.news?.body, item.body)
            XCTAssertEqual(model.news?.sources, item.sources)
            try await waitUntil { client.pendingNewsCreation != nil }
            client.resumeNewsCreation(with: .success(response))
            try await waitUntil { client.pendingMessages != nil }
            XCTAssertEqual(model.news?.body, expectedBody)
            XCTAssertEqual(model.news?.sources, expectedSources)

            client.resumeMessages(with: .success(client.hydration))
            await model.waitForInitialLoad()

            let hydratedCard = try XCTUnwrap(model.news)
            XCTAssertEqual(hydratedCard.headline, card.headline)
            XCTAssertEqual(hydratedCard.body, expectedBody)
            XCTAssertEqual(hydratedCard.sources, expectedSources)
            XCTAssertEqual(model.newsPostItemID, postID)
            XCTAssertEqual(model.message(for: postID)?.text, "**Server headline**\n\n\(expectedBody ?? "Old excerpt")")
            XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }, [postID])
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testNewsThreadFromChatListWaitsForHydrationBeforeSendingOrClearing() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsMessage(text: "**\(newsItem().headline)**")],
            news: response.thread.news
        )
        client.blocksMessages = true
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        try await waitUntil { client.pendingMessages != nil }

        XCTAssertFalse(model.canSendMessage(draftText: "What does this mean?"))
        XCTAssertFalse(model.canClearChat)
        XCTAssertTrue(model.itemIDs.isEmpty)
        client.resumeMessages(with: .success(client.hydration))
        await model.waitForInitialLoad()

        XCTAssertTrue(model.canSendMessage(draftText: "What does this mean?"))
        XCTAssertTrue(model.canClearChat)
        XCTAssertNotNil(model.newsPostItemID)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testLegacyHeadlineMessageBecomesThePostWithoutStartingARun() async throws {
        let headline = newsItem().headline
        let response = try newsResponse(headline: headline, messageCount: 3)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [
            newsMessage(id: "legacy-headline", role: "user", text: headline, isPost: false),
            newsMessage(id: "legacy-answer", text: "The previous analysis", isPost: false),
            newsMessage(id: "follow-up", role: "user", text: "A follow-up question", isPost: false)
        ], news: response.thread.news)
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()

        let postID = try XCTUnwrap(model.newsPostItemID)
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }, [postID])
        XCTAssertEqual(model.newsPost(for: try XCTUnwrap(model.message(for: postID))), response.thread.news)
        XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.text == headline })
        XCTAssertTrue(model.itemIDs.contains { model.message(for: $0)?.text == "The previous analysis" })
        XCTAssertTrue(model.itemIDs.contains { model.message(for: $0)?.text == "A follow-up question" })
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testSavedNewsPostTakesPrecedenceOverTheLegacyHeadline() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 2)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [
            newsMessage(id: "legacy-headline", role: "user", text: newsItem().headline, isPost: false),
            newsMessage(id: "saved-post", text: "Saved markdown")
        ], news: response.thread.news)
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()

        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }.count, 1)
        XCTAssertTrue(model.itemIDs.contains { model.message(for: $0)?.text == newsItem().headline })
        XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.text == "Saved markdown" })
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testNewsPostHasNoAnswerControlsRatingOrProblemReport() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsMessage(text: "**\(newsItem().headline)**")],
            news: response.thread.news
        )
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()

        let postID = try XCTUnwrap(model.newsPostItemID)
        let post = try XCTUnwrap(model.message(for: postID))
        XCTAssertFalse(post.canRate)
        XCTAssertTrue(post.controls.isEmpty)
        let didRate = await model.rateMessage(messageID: postID, feedback: .like)
        let didReport = await model.reportProblem(messageID: postID, comment: nil)
        XCTAssertFalse(didRate)
        XCTAssertFalse(didReport)
    }

    @MainActor
    func testSavedNewsPostOffersItsFollowupsAsSuggestions() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        var savedPost = newsMessage(text: "**\(newsItem().headline)**")
        savedPost["followups"] = [[
            "id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "Why does this matter?"
        ]]
        let client = try ThreadChatClient(threadId: "news-thread", messages: [savedPost], news: response.thread.news)
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()

        let postID = try XCTUnwrap(model.newsPostItemID)
        let post = try XCTUnwrap(model.message(for: postID))
        XCTAssertTrue(post.newsPost)
        XCTAssertFalse(post.canRate)
        XCTAssertEqual(post.controls.map(\.title), ["Why does this matter?"])
        XCTAssertEqual(post.controls.map(\.kind), [.followup])
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    /// Before consent a news discussion opens as it does after: its thread is created at once, with the post and its
    /// suggestions, without asking. Its first message asks in the consent sheet: closing it sends nothing and keeps the
    /// message; Allow records consent and sends the message there, and later messages don't ask.
    @MainActor
    func testNewsDiscussionOpensBeforeConsentAndAsksAtTheFirstMessage() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        let response = try newsResponse(headline: newsItem().headline, messageCount: 0)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
        client.hasConsent = false
        client.blocksNewsCreation = true
        client.blocksRuns = true
        let preloader = AgentPreloader(client: client)
        let item = newsItem(imageUrl: nil)
        let controller = try XCTUnwrap(
            AgentEntryPoint.makeNewsChatViewController(item: item, locale: "en", preloader: preloader) { _ in } as? AgentVC
        )
        let model = preloader.acquireNewsModel(item: item, locale: "en") { _ in }
        let navigation = UINavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigation)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        let postID = try XCTUnwrap(model.newsPostItemID)
        try await waitUntil { client.pendingNewsCreation != nil }
        XCTAssertEqual(client.newsThreadRequests.count, 1, "The thread comes at once, before consent")
        client.resumeNewsCreation(with: .success(response))
        await model.waitForInitialLoad()
        try await waitUntil { model.canSendMessage(draftText: "Why does it matter?") }
        XCTAssertTrue(model.needsConsentToSend)
        XCTAssertTrue(presentation.presentedSheets.isEmpty, "The discussion opens without asking")
        XCTAssertNotNil(model.message(for: postID), "With its post")
        let actions = AgentChatActions(model: model, viewController: controller, cancelDictation: {}, refreshNavigationItemMenu: {})
        XCTAssertTrue(actions.makeOverflowMenu().children.isEmpty, "Untouched and before consent, its menu has nothing")
        XCTAssertNil(AgentChatNavigation.findButton(in: controller.navigationItem.rightBarButtonItem), "So it has no menu button")

        let composer = controller.composerView
        composer.setDraftText("Why does it matter?", focus: false)
        composer.onSend?()
        let closed = try await waitForConsentSheet(over: controller, in: self)
        XCTAssertTrue(closed.accessibilityPerformEscape())
        try await waitUntil { presentation.presentedViewController(of: controller) == nil }
        XCTAssertEqual(composer.draftText, "Why does it matter?", "Closing the sheet keeps the message")
        XCTAssertTrue(client.startedCommands.isEmpty)

        composer.onSend?()
        let consent = try await waitForConsentSheet(over: controller, in: self).consentView
        consent.onContinue?()
        consent.onContinue?()
        try await waitUntil { client.startedCommands.count == 1 }
        try await waitUntil { presentation.presentedViewController(of: controller) == nil }
        XCTAssertEqual(client.startedCommands.count, 1, "Allow sends the message once")
        XCTAssertEqual(presentation.presentedSheets.count, 2)
        XCTAssertEqual(client.acceptConsentCallCount, 1)
        XCTAssertFalse(model.needsConsentToSend)
        XCTAssertTrue(composer.draftText?.isEmpty != false, "The message leaves the field")
        XCTAssertEqual(client.newsThreadRequests.count, 1)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Why does it matter?")])
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [nil])
        // Written in, the discussion can be deleted, and its menu button comes without reopening it
        XCTAssertTrue(model.isStarted)
        try await waitUntil { AgentChatNavigation.findButton(in: controller.navigationItem.rightBarButtonItem) != nil }
        XCTAssertTrue(actions.makeOverflowMenu().children.contains { ($0 as? UIAction)?.title == lang("Delete Chat") })
    }

    /// While a news discussion's consent read hasn't answered, under way or failed, the microphone doesn't record: the
    /// prompt reads the consent again, records hands-free at once when it is given, and asks in the sheet otherwise,
    /// where closing records nothing and Allow records. With the consent known, it records at once, as a chat does.
    @MainActor
    func testRecordingWaitsForAnUnansweredConsentReadInANewsDiscussion() async throws {
        enum Read { case pending, failed, knownGiven }
        for (read, hasConsent) in [(Read.pending, true), (.pending, false), (.failed, false), (.knownGiven, true)] {
            let moment = "\(read), consent: \(hasConsent)"
            let presentation = AgentTestConsentSheetPresentation.install(in: self)
            let response = try newsResponse(headline: newsItem().headline, messageCount: 0)
            let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
            client.hasConsent = hasConsent
            client.isConsentKnownGiven = read == .knownGiven
            client.blocksFirstConsent = read == .pending
            client.consentFailuresRemaining = read == .failed ? 1 : 0
            client.blocksNewsCreation = true
            var recordingStarts = 0
            let dictation = AgentDictationController(
                scheduler: AgentDictationTestScheduler(),
                requestPermission: { true },
                makeRecorder: {
                    recordingStarts += 1
                    return AgentDictationTestRecorder()
                },
                transcribe: { _ in ApiAgentV2TranscriptionResponse(outcome: .transcribed, text: "Dictated") },
                haptic: {},
                observeLifecycle: false
            )
            let preloader = AgentPreloader(client: client)
            let item = newsItem(imageUrl: nil)
            let model = preloader.acquireNewsModel(item: item, locale: "en") { _ in }
            let controller = AgentVC(model: model, dictationController: dictation)
            let navigation = UINavigationController(rootViewController: controller)
            let window = makeKeyWindow(showing: navigation)
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
                client.releasePendingRequests()
            }
            controller.loadViewIfNeeded()
            if read == .failed {
                try await waitUntil { client.consentCallCount == 1 }
                for _ in 0..<20 { await Task.yield() }
            }
            let shouldStartDictation = try XCTUnwrap(controller.composerView.shouldStartDictation)

            if read == .knownGiven {
                XCTAssertTrue(shouldStartDictation(), "\(moment): records at once")
                XCTAssertTrue(presentation.presentedSheets.isEmpty, moment)
                continue
            }
            XCTAssertFalse(shouldStartDictation(), "\(moment): doesn't record before the consent is known")
            if hasConsent {
                try await waitUntil { recordingStarts == 1 }
                XCTAssertTrue(presentation.presentedSheets.isEmpty, "\(moment): no sheet")
                continue
            }
            let closed = try await waitForConsentSheet(over: controller, in: self)
            XCTAssertTrue(closed.accessibilityPerformEscape())
            try await waitUntil { presentation.presentedViewController(of: controller) == nil }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(recordingStarts, 0, "\(moment): closing the sheet records nothing")

            XCTAssertFalse(shouldStartDictation(), moment)
            let consent = try await waitForConsentSheet(over: controller, in: self).consentView
            consent.onContinue?()
            try await waitUntil { recordingStarts == 1 }
            XCTAssertEqual(client.acceptConsentCallCount, 1, moment)
        }
    }

    /// A news discussion that goes from the screen while the microphone's consent read is under way doesn't record when
    /// the read finds the consent, whether it is back by then or not, and the discussion still learns of the consent
    @MainActor
    func testRecordingDoesNotStartInANewsDiscussionLeftWhileItsConsentIsRead() async throws {
        for isBack in [false, true] {
            let presentation = AgentTestConsentSheetPresentation.install(in: self)
            let response = try newsResponse(headline: newsItem().headline, messageCount: 0)
            let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
            client.consentFailuresRemaining = 1
            client.blocksNewsCreation = true
            var recordingStarts = 0
            let dictation = AgentDictationController(
                scheduler: AgentDictationTestScheduler(),
                requestPermission: { true },
                makeRecorder: {
                    recordingStarts += 1
                    return AgentDictationTestRecorder()
                },
                transcribe: { _ in ApiAgentV2TranscriptionResponse(outcome: .transcribed, text: "Dictated") },
                haptic: {},
                observeLifecycle: false
            )
            let preloader = AgentPreloader(client: client)
            let item = newsItem(imageUrl: nil)
            let model = preloader.acquireNewsModel(item: item, locale: "en") { _ in }
            let controller = AgentVC(model: model, dictationController: dictation)
            let navigation = UINavigationController(rootViewController: controller)
            let window = makeKeyWindow(showing: navigation)
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
                client.releasePendingRequests()
            }
            controller.loadViewIfNeeded()
            try await waitUntil { client.consentCallCount == 1 }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertTrue(model.isConsentToSendUnknown, "isBack: \(isBack)")

            client.blocksNextConsent = true
            XCTAssertEqual(controller.composerView.shouldStartDictation?(), false)
            try await waitUntil { client.consentCallCount == 2 }
            navigation.pushViewController(UIViewController(), animated: false)
            try await waitUntil {
                window.layoutIfNeeded()
                return controller.view.window == nil
            }
            if isBack {
                navigation.popViewController(animated: false)
                try await waitUntil {
                    window.layoutIfNeeded()
                    return controller.view.window != nil
                }
            }
            client.resumeConsent()
            try await waitUntil { !model.isConsentToSendUnknown }
            for _ in 0..<20 { await Task.yield() }
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(recordingStarts, 0, "isBack: \(isBack)")
            XCTAssertEqual(controller.dictationController.state.phase, .idle, "isBack: \(isBack)")
            XCTAssertTrue(presentation.presentedSheets.isEmpty, "isBack: \(isBack)")
        }
    }

    /// A chat with consent records at once
    @MainActor
    func testRecordingStartsAtOnceInAChatWithConsent() async throws {
        let client = try ThreadChatClient(threadId: "thread")
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let controller = AgentVC(model: model)
        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.composerView.shouldStartDictation?(), true)
    }

    @MainActor
    func testNewsContextPublicationFailureDoesNotBlockOpeningAndFailsTheExplicitQuestionNormally() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 0)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
        client.hostContextFailuresRemaining = 3
        let coordinator = AgentV2Coordinator(
            client: client,
            initialHostContextRetryDelay: .milliseconds(1),
            news: response.thread.news,
            newsRequest: .init(eventId: newsItem().eventId, locale: "en")
        )
        client.blocksNewsCreation = true
        defer {
            coordinator.stop()
            client.releasePendingRequests()
        }
        coordinator.start()
        try await waitUntil { client.pendingNewsCreation != nil }
        client.resumeNewsCreation(with: .success(response))
        await coordinator.waitForInitialLoad()

        XCTAssertTrue(coordinator.hasHydratedMessages)
        XCTAssertFalse(coordinator.isOpening)
        XCTAssertNil(coordinator.error)
        XCTAssertEqual(client.hostContextUpdateCallCount, 3)
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertFalse(coordinator.showsOpeningTypingIndicator)

        client.hostContextFailuresRemaining = 1
        coordinator.send(input: .append(text: "What does this mean?"), entryPoint: nil, visibleText: "What does this mean?")
        try await waitUntil { coordinator.activeRun?.isRunning == false }

        XCTAssertEqual(client.hostContextUpdateCallCount, 4)
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertEqual(coordinator.error, lang("Agent is unavailable"))
    }

    @MainActor
    func testNewsContextPublicationRecoveryLoadsStartupStatusesOnce() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 0)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
        client.hostContextFailuresRemaining = 3
        client.isProblemReportAvailable = true
        client.blocksNewsCreation = true
        client.blocksRuns = true
        let coordinator = AgentV2Coordinator(
            client: client,
            initialHostContextRetryDelay: .milliseconds(1),
            news: response.thread.news,
            newsRequest: .init(eventId: newsItem().eventId, locale: "en")
        )
        defer {
            coordinator.stop()
            client.releasePendingRequests()
        }
        coordinator.start()
        try await waitUntil { client.pendingNewsCreation != nil }
        client.resumeNewsCreation(with: .success(response))
        await coordinator.waitForInitialLoad()

        XCTAssertEqual(client.hostContextUpdateCallCount, 3)
        XCTAssertEqual(client.availabilityRequestCount, 0)
        XCTAssertEqual(client.userQuotaRequestCount, 0)
        XCTAssertEqual(client.problemReportAvailabilityRequestCount, 0)
        XCTAssertNil(coordinator.problemReportAvailability, "Not checked yet")
        XCTAssertTrue(client.startedCommands.isEmpty)

        coordinator.send(input: .append(text: "What does this mean?"), entryPoint: nil, visibleText: "What does this mean?")
        try await waitUntil {
            client.pendingRun != nil
                && client.availabilityRequestCount == 1
                && client.userQuotaRequestCount == 1
                && coordinator.problemReportAvailability == true
        }

        XCTAssertEqual(client.hostContextUpdateCallCount, 4)
        XCTAssertEqual(client.hostContextPublishedCallCount, 1)
        XCTAssertEqual(client.problemReportAvailabilityRequestCount, 1)
        client.resumeRun(with: .success(try JSONDecoder().decode(ApiAgentV2RunResult.self, from: Data("""
        {"clientRunId":"first-run","state":"completed"}
        """.utf8))))
        try await waitUntil { coordinator.activeRun?.isRunning == false }

        coordinator.send(input: .append(text: "Tell me more"), entryPoint: nil, visibleText: "Tell me more")
        try await waitUntil { client.pendingRun != nil }

        XCTAssertEqual(client.availabilityRequestCount, 1)
        XCTAssertEqual(client.userQuotaRequestCount, 1)
        XCTAssertEqual(client.problemReportAvailabilityRequestCount, 1)
        XCTAssertEqual(coordinator.problemReportAvailability, true)
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [nil, nil])
    }

    @MainActor
    func testNewsCreationFailureKeepsThePostAndRetryOnlyCreatesAndLoadsTheThread() async throws {
        let errors: [(Error, String)] = [
            (ThreadChatClientError.unavailable, lang("Agent is unavailable")),
            (try JSONDecoder().decode(ApiAgentV2MutationError.self, from: Data("""
            {"code":"news_unavailable","retryable":true}
            """.utf8)), lang("$agent_news_unavailable"))
        ]
        for (error, expectedText) in errors {
            let response = try newsResponse(headline: "Server headline", messageCount: 0)
            let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
            client.blocksNewsCreation = true
            let model = AgentV2Model(client: client, news: newsItem(), locale: "fr") { _ in }
            defer {
                model.stop()
                client.releasePendingRequests()
            }
            let postID = try XCTUnwrap(model.newsPostItemID)
            try await waitUntil { client.pendingNewsCreation != nil }
            client.resumeNewsCreation(with: .failure(error))
            await model.waitForInitialLoad()
            let status = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == expectedText })
            let retry = try XCTUnwrap(status.controls.first { $0.id == "retry-opening" && $0.isEnabled })
            XCTAssertEqual(model.newsPostItemID, postID)
            XCTAssertTrue(typingIndicatorIDs(in: model).isEmpty)

            model.performControl(messageID: status.id, controlID: retry.id)
            model.performControl(messageID: status.id, controlID: retry.id)
            try await waitUntil { client.pendingNewsCreation != nil }
            client.resumeNewsCreation(with: .success(response))
            await model.waitForInitialLoad()

            XCTAssertEqual(client.newsThreadRequests, Array(repeating: .init(eventId: newsItem().eventId, locale: "fr"), count: 2))
            XCTAssertEqual(model.newsPostItemID, postID)
            XCTAssertTrue(client.startedCommands.isEmpty)
            XCTAssertTrue(client.retriedClientRunIds.isEmpty)
            XCTAssertEqual(client.hydratedThreadIds, ["news-thread"])
            XCTAssertTrue(model.canSendMessage(draftText: "A follow-up question"))
        }
    }

    @MainActor
    func testNewsHydrationRetriesWhenInitialHostContextChangesDuringTheRequest() async throws {
        for opensFromFeed in [false, true] {
            let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
            let client = try ThreadChatClient(
                threadId: "news-thread",
                messages: [newsMessage(text: "Saved news post")],
                news: response.thread.news
            )
            client.blocksMessages = true
            client.blocksHostContext = true
            client.blocksNewsCreation = opensFromFeed
            let coordinator = opensFromFeed
                ? AgentV2Coordinator(
                    client: client, news: response.thread.news,
                    newsRequest: .init(eventId: newsItem().eventId, locale: "en")
                )
                : AgentV2Coordinator(client: client, thread: client.hydration.thread)
            defer {
                coordinator.stop()
                client.releasePendingRequests()
            }
            coordinator.start()
            if opensFromFeed {
                try await waitUntil { client.pendingNewsCreation != nil }
                client.resumeNewsCreation(with: .success(response))
            }
            try await waitUntil { client.pendingMessages != nil && client.pendingHostContext != nil }
            XCTAssertEqual(coordinator.isOpening, opensFromFeed)
            XCTAssertFalse(coordinator.hasHydratedMessages)
            client.blocksMessages = false
            client.resumeMessages(with: .failure(ApiAgentV2MutationError(code: .walletContextChanged, retryable: true)))
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(client.hydratedThreadIds.count, 1)
            XCTAssertFalse(coordinator.hasHydratedMessages)
            XCTAssertNil(coordinator.error)
            client.resumeHostContext(with: .success(()))
            try await waitUntil { client.hostContextPublishedCallCount == 1 }
            await coordinator.waitForInitialLoad()

            XCTAssertNil(coordinator.error)
            XCTAssertTrue(coordinator.hasHydratedMessages)
            XCTAssertEqual(coordinator.messages.map(\.text), ["Saved news post"])
            XCTAssertFalse(coordinator.isOpening)
            XCTAssertEqual(client.hydratedThreadIds, ["news-thread", "news-thread"])
            XCTAssertEqual(client.newsThreadCreateCallCount, opensFromFeed ? 1 : 0)
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testNewsHydrationStopsAfterThreeWalletContextRejections() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(threadId: "news-thread", news: response.thread.news)
        client.messageError = ApiAgentV2MutationError(code: .walletContextChanged, retryable: true)
        let coordinator = AgentV2Coordinator(client: client, thread: client.hydration.thread)
        defer {
            coordinator.stop()
            client.releasePendingRequests()
        }
        coordinator.start()
        await coordinator.waitForInitialLoad()

        XCTAssertEqual(client.hydratedThreadIds, Array(repeating: "news-thread", count: 3))
        XCTAssertEqual(coordinator.error, lang("Failed to load chat"))
        XCTAssertFalse(coordinator.hasHydratedMessages)
        XCTAssertTrue(coordinator.isLoadFailure)
        XCTAssertFalse(coordinator.isRunFailure)

        client.messageError = nil
        client.blocksMessages = true
        coordinator.retryLoad()
        coordinator.retryLoad()
        try await waitUntil { client.pendingMessages != nil }
        XCTAssertEqual(client.hydratedThreadIds.count, 4, "One explicit retry follows the exhausted automatic retries")
        client.resumeMessages(with: .success(client.hydration))
        try await waitUntil { coordinator.hasHydratedMessages }
        XCTAssertNil(coordinator.error)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testNewsHydrationDoesNotRetryOtherErrorsAndNotifiesDeletionOnce() async throws {
        let cases: [(Error, String?)] = [
            (ApiAgentV2MutationError(code: .internalError, retryable: true), lang("Failed to load chat")),
            (ThreadChatClientError.unavailable, lang("Failed to load chat")),
            (ApiAgentV2MutationError(code: .threadNotFound, retryable: false), nil)
        ]
        for (error, expectedText) in cases {
            let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
            let client = try ThreadChatClient(threadId: "news-thread", news: response.thread.news)
            client.messageError = error
            WalletCoreData.addImmediately(eventObserver: client)
            let coordinator = AgentV2Coordinator(client: client, thread: client.hydration.thread)
            defer {
                coordinator.stop()
                WalletCoreData.remove(observer: client)
            }
            coordinator.start()
            await coordinator.waitForInitialLoad()

            XCTAssertEqual(client.hydratedThreadIds, ["news-thread"])
            XCTAssertEqual(coordinator.error, expectedText)
            XCTAssertFalse(coordinator.hasHydratedMessages)
            if (error as? ApiAgentV2MutationError)?.code == .threadNotFound {
                try await waitUntil { !client.deletedThreadIds.isEmpty }
                XCTAssertEqual(client.deletedThreadIds, ["news-thread"])
            } else {
                XCTAssertTrue(client.deletedThreadIds.isEmpty)
            }
        }
    }

    @MainActor
    func testWalletContextRejectionDoesNotRetryInactiveHydration() async throws {
        for interruption in ["cancelled", "stopped", "superseded"] {
            let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
            let client = try ThreadChatClient(threadId: "news-thread", news: response.thread.news)
            client.blocksMessages = true
            let coordinator = AgentV2Coordinator(client: client, thread: client.hydration.thread)
            let hydration = Task { await coordinator.hydrate() }
            defer {
                hydration.cancel()
                coordinator.stop()
                client.releasePendingRequests()
            }
            try await waitUntil { client.pendingMessages != nil }
            client.blocksMessages = false
            switch interruption {
            case "cancelled": hydration.cancel()
            case "stopped": coordinator.stop()
            default:
                let didHydrate = await coordinator.hydrate()
                XCTAssertTrue(didHydrate)
            }
            client.resumeMessages(with: .failure(ApiAgentV2MutationError(code: .walletContextChanged, retryable: true)))
            let didHydrate = await hydration.value

            XCTAssertFalse(didHydrate)
            XCTAssertEqual(client.hydratedThreadIds.count, interruption == "superseded" ? 2 : 1)
            XCTAssertNil(coordinator.error)
            XCTAssertEqual(coordinator.hasHydratedMessages, interruption == "superseded")
        }
    }

    @MainActor
    func testFailedNewsHydrationRetriesLoadingWithoutCreatingOrStartingARun() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread",
            messages: [newsMessage(text: "**\(newsItem().headline)**")],
            news: response.thread.news
        )
        client.blocksNewsCreation = true
        client.messageFailuresRemaining = 1
        let model = AgentV2Model(client: client, news: newsItem(), locale: "en") { _ in }
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        let postID = try XCTUnwrap(model.newsPostItemID)
        try await waitUntil { client.pendingNewsCreation != nil }
        client.resumeNewsCreation(with: .success(response))
        await model.waitForInitialLoad()
        let status = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first {
            $0.controls.contains { $0.id == "retry-opening" && $0.isEnabled }
        })

        model.performControl(messageID: status.id, controlID: "retry-opening")
        await model.waitForInitialLoad()

        XCTAssertEqual(model.newsPostItemID, postID)
        XCTAssertEqual(client.newsThreadRequests.count, 1)
        XCTAssertEqual(client.hydratedThreadIds, ["news-thread", "news-thread"])
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(client.retriedClientRunIds.isEmpty)
        XCTAssertFalse(model.isOpening)
    }

    @MainActor
    func testFirstExplicitNewsQuestionUsesOrdinaryQuotaFailureAndLimitRetry() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 0)
        let client = try ThreadChatClient(threadId: "news-thread", messages: [], news: response.thread.news)
        client.blocksRuns = true
        client.blocksRetries = true
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        await model.waitForInitialLoad()
        model.send(text: "What does this mean?")
        try await waitUntil { client.pendingRun != nil }
        let resetAt = Date().addingTimeInterval(0.5).timeIntervalSince1970 * 1_000
        let envelope = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: JSONSerialization.data(withJSONObject: [
            "type": "agentV2", "update": [
                "kind": "runFailed", "clientRunId": "first-run", "threadId": "news-thread",
                "code": "user_quota_exhausted", "retryable": true, "resetAt": resetAt
            ]
        ]))
        WalletCoreData.notify(event: .agentV2(envelope.update))
        client.resumeRun(with: .success(try JSONDecoder().decode(ApiAgentV2RunResult.self, from: Data("""
        {"clientRunId":"first-run","state":"failed"}
        """.utf8))))
        let expectedText = AgentV2Copy.error(.userQuotaExhausted)
        try await waitUntil { model.itemIDs.contains { model.message(for: $0)?.text == expectedText } }
        let status = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == expectedText })
        let retry = try XCTUnwrap(status.controls.first { $0.id == "retry-limit" })
        XCTAssertFalse(retry.isEnabled)
        XCTAssertFalse(model.canSendMessage(draftText: "A follow-up question"))
        XCTAssertFalse(status.controls.contains { $0.id == "retry-opening" })
        try await waitUntil { model.message(for: status.id)?.controls.first { $0.id == retry.id }?.isEnabled == true }
        model.performControl(messageID: status.id, controlID: retry.id)
        try await waitUntil { client.pendingRetry != nil }

        XCTAssertEqual(client.retriedClientRunIds, ["first-run"])
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "What does this mean?")])
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [nil])
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
    }

    @MainActor
    func testLimitFailureShowsItsCaptionWithoutRetryAndDimsTheComposerUntilTheLimitResets() async throws {
        let client = try ThreadChatClient(threadId: "limited-thread", messages: [])
        client.blocksRuns = true
        client.blocksRetries = true
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        await model.waitForInitialLoad()
        let chat = AgentVC(model: model)
        let navigation = UINavigationController(rootViewController: chat)
        let window = makeKeyWindow(showing: navigation)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
            client.releasePendingRequests()
        }
        let composer = try XCTUnwrap(descendants(of: chat.view).compactMap { $0 as? AgentComposerView }.first)
        let collection = try XCTUnwrap(descendants(of: chat.view).compactMap { $0 as? UICollectionView }.first)
        model.send(text: "What does this mean?")
        try await waitUntil { client.pendingRun != nil }
        let resetAt = Date().addingTimeInterval(1).timeIntervalSince1970 * 1_000
        let envelope = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: JSONSerialization.data(withJSONObject: [
            "type": "agentV2", "update": [
                "kind": "runFailed", "clientRunId": "first-run", "threadId": "limited-thread",
                "code": "user_quota_exhausted", "retryable": true, "resetAt": resetAt
            ]
        ]))
        WalletCoreData.notify(event: .agentV2(envelope.update))
        client.resumeRun(with: .success(try JSONDecoder().decode(ApiAgentV2RunResult.self, from: Data("""
        {"clientRunId":"first-run","state":"failed"}
        """.utf8))))
        let limitText = lang("$agent_daily_limit_reached")
        func captionText() -> String? {
            guard let index = model.itemIDs.firstIndex(where: { model.message(for: $0)?.text == limitText }),
                  let cell = collection.cellForItem(at: IndexPath(item: index, section: 0)) as? AgentSystemMessageCell else {
                return nil
            }
            let caption = descendants(of: cell).first { $0.accessibilityIdentifier == "agent_message_failure" } as? UITextView
            return caption?.attributedText.string
        }
        var blockedText: String?
        for _ in 0..<100 where blockedText == nil {
            window.layoutIfNeeded()
            blockedText = captionText()
            try await Task.sleep(for: .milliseconds(5))
        }

        // While the limit blocks sending, the caption has no Retry and the composer is at half its opacity
        XCTAssertEqual(AgentV2Copy.error(.userQuotaExhausted), limitText)
        XCTAssertEqual(blockedText, limitText)
        XCTAssertEqual(composer.contentAlpha, 0.5)
        XCTAssertTrue(model.isInputBlockedByLimit)

        // Once it resets, the question can be retried as after any failure
        var resetText: String?
        for _ in 0..<300 where resetText == limitText || resetText == nil {
            try await Task.sleep(for: .milliseconds(10))
            window.layoutIfNeeded()
            resetText = captionText()
        }
        XCTAssertEqual(resetText, limitText + " " + lang("Retry"))
        XCTAssertEqual(composer.contentAlpha, 1)
        let status = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == limitText })
        model.performControl(messageID: status.id, controlID: "retry-limit")
        try await waitUntil { client.pendingRetry != nil }
        XCTAssertEqual(client.retriedClientRunIds, ["first-run"])
    }

    @MainActor
    func testChatBlockedByALimitShowsItsStatusWithoutRetryUntilTheLimitResets() async throws {
        let question: [String: Any] = [
            "id": "question", "threadId": "limited-thread", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "What is my balance?"], "createdAt": "2026-10-02T00:00:00.000Z"
        ]
        for doesLastAnswerFail in [false, true] {
            let answer: [String: Any] = doesLastAnswerFail ? [
                "id": "answer", "threadId": "limited-thread", "role": "assistant", "status": "error",
                "error": ["code": "user_quota_exhausted", "retryable": true], "createdAt": "2026-10-02T00:00:01.000Z"
            ] : [
                "id": "answer", "threadId": "limited-thread", "role": "assistant", "status": "complete",
                "content": ["kind": "markdown", "text": "You hold 5 TON."], "createdAt": "2026-10-02T00:00:01.000Z"
            ]
            let client = try ThreadChatClient(threadId: "limited-thread", messages: [question, answer])
            let model = AgentV2Model(client: client, thread: client.hydration.thread)
            await model.waitForInitialLoad()
            let chat = AgentVC(model: model)
            let navigation = UINavigationController(rootViewController: chat)
            let window = makeKeyWindow(showing: navigation)
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                model.stop()
            }
            let composer = try XCTUnwrap(descendants(of: chat.view).compactMap { $0 as? AgentComposerView }.first)
            func captions() -> [AgentMessage] {
                model.itemIDs.compactMap { model.message(for: $0) }.filter(\.isFailureCaption)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let envelope = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: JSONSerialization.data(withJSONObject: [
                "type": "agentV2", "update": [
                    "kind": "userQuotaChanged",
                    "quota": ["limit": 100, "used": 100, "remaining": 0, "resetAt": formatter.string(from: Date().addingTimeInterval(1))]
                ]
            ]))
            WalletCoreData.notify(event: .agentV2(envelope.update))
            try await waitUntil { model.isInputBlockedByLimit }

            // The limit shows as one line under the last message, with no Retry, and the composer is at half opacity
            let limitText = lang("$agent_daily_limit_reached")
            XCTAssertEqual(captions().map(\.text), [limitText])
            XCTAssertEqual(captions().first?.id, model.itemIDs.last)
            XCTAssertEqual(captions().first?.controls.isEmpty, true)
            XCTAssertEqual(composer.contentAlpha, 0.5)

            // Once it resets the line goes, leaving a failed answer its own caption
            for _ in 0..<300 where model.isInputBlockedByLimit || composer.contentAlpha != 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(model.isInputBlockedByLimit)
            XCTAssertEqual(captions().map(\.text), doesLastAnswerFail ? [limitText] : [])
            XCTAssertEqual(composer.contentAlpha, 1)
        }
    }

    @MainActor
    func testStoppingNewsOpeningBeforeCreationReturnsDoesNotStartARunOrRegisterTheThread() async throws {
        let client = try ThreadChatClient(threadId: "news-thread", messages: [])
        client.blocksNewsCreation = true
        let preloader = AgentPreloader(client: client)
        var createdThreads: [ApiAgentV2ThreadSummary] = []
        let model = preloader.acquireNewsModel(item: newsItem(), locale: "en") { createdThreads.append($0) }
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        try await waitUntil { client.pendingNewsCreation != nil }
        model.stop()
        client.resumeNewsCreation(with: .success(try newsResponse(headline: "Server headline", messageCount: 0)))
        try await waitUntil { client.cancelledNewsCreationCount == 1 }

        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(client.hydratedThreadIds.isEmpty)
        XCTAssertTrue(createdThreads.isEmpty)
        XCTAssertNil(preloader.model(threadId: "news-thread"))
    }

    @MainActor
    func testConfirmedDeletionWaitsForTheOpeningThreadEvenIfTheUserLeaves() async throws {
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let client = try ThreadChatClient(
            threadId: "news-thread", messages: [newsPostWithSuggestion(for: newsItem())], news: response.thread.news
        )
        client.blocksNewsCreation = true
        let model = AgentV2Model(client: client, news: newsItem(), locale: "en") { _ in }
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        try await waitUntil { client.pendingNewsCreation != nil }
        let deletion = Task { try await model.deleteChat() }
        try await waitUntil { model.isDeletingChat }
        model.cancelOpeningIfNeeded()
        XCTAssertTrue(client.deletedThreadIds.isEmpty)
        client.resumeNewsCreation(with: .success(response))
        try await deletion.value
        XCTAssertEqual(client.deletedThreadIds, ["news-thread"])
    }

    @MainActor
    private func captureNewsHeader(in window: UIWindow) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        var didDraw = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(didDraw, "The application-hosted window must produce a composed frame")
        return image
    }

    private func newsHeaderBrightness(_ image: UIImage, in region: CGRect) throws -> CGFloat {
        let source = try XCTUnwrap(image.cgImage)
        let rect = region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        let crop = try XCTUnwrap(source.cropping(to: rect))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
            bytesPerRow: crop.width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var total: CGFloat = 0
        for offset in stride(from: 0, to: crop.width * crop.height * 4, by: 4) {
            total += CGFloat(pixels[offset]) + CGFloat(pixels[offset + 1]) + CGFloat(pixels[offset + 2])
        }
        return total / CGFloat(crop.width * crop.height * 3 * 255)
    }

    private func newsMessage(
        id: String = "saved-post",
        role: String = "assistant",
        text: String,
        isPost: Bool = true,
        createdAt: String = "2026-10-20T11:00:00Z"
    ) -> [String: Any] {
        [
            "id": id, "threadId": "news-thread", "role": role, "status": "complete", "newsPost": isPost,
            "content": ["kind": "markdown", "text": text], "createdAt": createdAt
        ]
    }
    /// The saved post of `item`'s discussion, with a suggestion about the news
    private func newsPostWithSuggestion(for item: ApiAgentV2NewsFeedItem) -> [String: Any] {
        var post = newsMessage(
            text: "**\(item.headline)**\n\n\(item.body)",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        post["followups"] = [[
            "id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "Why does this matter?"
        ]]
        return post
    }

    /// The chat's news post once the card flown in from the feed lands on it. `whileFlying` sees the post on every
    /// check before that.
    @MainActor
    private func waitForLandedNewsPost(
        in chat: AgentVC,
        of model: AgentV2Model,
        card: UIView,
        window: UIWindow,
        whileFlying: (AgentNewsPostCell) -> Void = { _ in }
    ) async throws -> AgentNewsPostCell {
        let postID = try XCTUnwrap(model.newsPostItemID)
        let collection = try XCTUnwrap(descendants(of: chat.view).compactMap { $0 as? UICollectionView }.first)
        for _ in 0..<300 {
            window.layoutIfNeeded()
            let post = model.itemIDs.firstIndex(of: postID).flatMap {
                collection.cellForItem(at: IndexPath(item: $0, section: 0)) as? AgentNewsPostCell
            }
            if let post {
                if post.contentView.alpha == 1, card.superview == nil { return post }
                whileFlying(post)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The card did not land on the post")
        throw ThreadChatClientError.unavailable
    }

    private func newsItem(
        imageUrl: String? = "https://example.com/image.png",
        body: String = "**A market update** from [the source](https://example.com/news)."
    ) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: 307,
            deliveredAt: "2026-10-20T10:00:00Z",
            headline: "Feed headline",
            body: body,
            imageUrl: imageUrl,
            sources: [.init(name: "First source", url: "https://example.com/news"), .init(name: "Second source", url: "https://example.org/news")]
        )
    }

    private func newsResponse(headline: String, messageCount: Int, body: String? = nil) throws -> ApiAgentV2ThreadCreateResponse {
        try JSONDecoder().decode(
            ApiAgentV2ThreadCreateResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "protocolVersion": 3,
                "created": messageCount == 0,
                "thread": [
                    "id": "news-thread", "revision": 1, "messageCount": messageCount,
                    "createdAt": "2026-10-20T11:00:00Z", "updatedAt": "2026-10-20T11:00:00Z", "lastActivityAt": "2026-10-20T11:00:00Z",
                    "news": [
                        "eventId": newsItem().eventId, "headline": headline, "excerpt": "Server excerpt",
                        "body": body ?? newsItem().body, "publishedAt": "2026-10-20T10:00:00Z",
                        "sources": newsItem().sources.map { ["url": $0.url, "name": $0.name ?? ""] }
                    ]
                ]
            ])
        )
    }

    /// The thread's news card as its chat shows it. The thread leaves the source out, so the post keeps the source the
    /// feed's card showed.
    private func makeNewsCard(of response: ApiAgentV2ThreadCreateResponse, source: String) throws -> ApiAgentV2ThreadNewsCard {
        let news = try XCTUnwrap(response.thread.news)
        XCTAssertNil(news.source)
        return ApiAgentV2ThreadNewsCard(
            eventId: news.eventId,
            headline: news.headline,
            excerpt: news.excerpt,
            imageUrl: news.imageUrl,
            publishedAt: news.publishedAt,
            source: source,
            body: news.body,
            sources: news.sources
        )
    }

    @MainActor
    private func typingIndicatorIDs(in model: AgentV2Model) -> [AgentItemID] {
        model.itemIDs.filter { id in
            if case .typingIndicator = model.item(for: id) { return true }
            return false
        }
    }

    @MainActor
    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for news opening", file: file, line: line)
        throw ThreadChatClientError.unavailable
    }

    /// A chat with answers the user hasn't seen, as the list's unread dot marks it, opens at the first of them under the
    /// "New" divider the News feed shows over its first unread news
    @MainActor
    func testChatWithUnseenMessagesOpensAtTheNewDividerOverTheFirst() async throws {
        let threadId = "unread-\(UUID().uuidString)"
        let readState = AgentThreadReadState.shared
        readState.chatDidAppear(threadId: threadId)
        readState.chatDidDisappear(threadId: threadId, seenMessageCount: 8)
        defer { readState.remove(threadId: threadId) }
        let (controller, model, window) = try await openChat(threadId: threadId, messageCount: 12)
        defer {
            window.isHidden = true
            model.stop()
        }
        let list = controller.collectionView
        let divider = try XCTUnwrap(list.visibleCells.first { $0 is AgentUnreadDividerCell })
        XCTAssertEqual(divider.accessibilityIdentifier, "agent_unread_divider")
        XCTAssertEqual(divider.frame.minY - list.contentOffset.y, list.adjustedContentInset.top, accuracy: 1)
        let dividerIndexPath = try XCTUnwrap(list.indexPath(for: divider))
        let nextID = try XCTUnwrap(controller.messageItemID(at: IndexPath(item: dividerIndexPath.item + 1, section: 0)))
        guard case .message(let first)? = model.item(for: nextID) else { return XCTFail("No message under the divider") }
        XCTAssertTrue(first.text.hasPrefix("Message 8"), first.text)
        XCTAssertTrue(controller.scrollToBottomButton.isButtonVisible)
    }

    /// A chat the user has seen opens at its latest message, without the divider
    @MainActor
    func testReadChatOpensAtItsLatestMessageWithoutTheDivider() async throws {
        let threadId = "read-\(UUID().uuidString)"
        let readState = AgentThreadReadState.shared
        readState.chatDidAppear(threadId: threadId)
        readState.chatDidDisappear(threadId: threadId, seenMessageCount: 12)
        defer { readState.remove(threadId: threadId) }
        let (controller, model, window) = try await openChat(threadId: threadId, messageCount: 12)
        defer {
            window.isHidden = true
            model.stop()
        }
        let list = controller.collectionView
        XCTAssertFalse(list.visibleCells.contains { $0 is AgentUnreadDividerCell })
        XCTAssertTrue(controller.isNearBottom())
    }

    /// A chat that fails to load with nothing to show has the News feed's failure in its middle, whose Retry loads it
    @MainActor
    func testChatThatFailsToLoadWithNothingToShowOffersRetryInItsMiddle() async throws {
        let client = try ThreadChatClient(threadId: "failing-thread")
        client.messageFailuresRemaining = 1
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        XCTAssertNotNil(model.initialLoadError)
        let controller = AgentVC(model: model)
        let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        XCTAssertFalse(controller.loadErrorView.isHidden)
        XCTAssertEqual(controller.loadErrorView.label.text, model.initialLoadError)
        // The failure shows once, in the middle rather than as a line at the bottom
        XCTAssertFalse(model.itemIDs.contains { id in
            guard case .message(let message)? = model.item(for: id) else { return false }
            return message.isFailureCaption
        })

        controller.loadErrorView.onRetry?()
        try await waitUntil { model.isReadyForPresentation }
        controller.agentModelDidUpdateState()
        XCTAssertTrue(controller.loadErrorView.isHidden)
        XCTAssertTrue(model.itemIDs.contains { id in
            guard case .message(let message)? = model.item(for: id) else { return false }
            return message.text == "The selected conversation"
        })
    }

    /// A chat that fails to load again with its messages shown keeps them, with the failure line and Retry under them
    @MainActor
    func testChatThatFailsToReloadShowsTheFailureLineWithRetry() async throws {
        for error in [
            ThreadChatClientError.unavailable,
            try readFailure(.toolFailed),
        ] as [Error] {
            let client = try ThreadChatClient(threadId: "reloading-thread")
            let model = AgentV2Model(client: client, thread: client.hydration.thread)
            defer { model.stop() }
            await model.waitForInitialLoad()
            let controller = AgentVC(model: model)
            let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
            defer { window.isHidden = true }
            client.messageFailure = error
            client.messageFailuresRemaining = 1
            model.retryLoad()
            try await waitUntil { self.failureLine(in: model) != nil }
            let line = try XCTUnwrap(failureLine(in: model))
            XCTAssertNil(model.initialLoadError)
            XCTAssertTrue(controller.loadErrorView.isHidden)
            XCTAssertEqual(line.text, lang("Failed to load chat"))
            XCTAssertEqual(line.controls.map(\.id), ["retry-load"])
            XCTAssertTrue(model.itemIDs.contains { id in
                guard case .message(let message)? = model.item(for: id) else { return false }
                return message.text == "The selected conversation"
            })
            let hydrations = client.hydratedThreadIds.count
            model.performControl(messageID: line.id, controlID: "retry-load")
            try await waitUntil { client.hydratedThreadIds.count == hydrations + 1 && self.failureLine(in: model) == nil }
        }
    }

    /// A news preview is already content even before its server history loads. Neither its first load nor a later
    /// refresh may cover the post with an empty-state error, and both failures must retry the history request.
    @MainActor
    func testNewsHistoryFailureStaysBelowPreviewOrCachedPostAndRetries() async throws {
        for wasHydrated in [false, true] {
            let response = try newsResponse(headline: "Saved news", messageCount: 1, body: "The news remains readable.")
            let client = try ThreadChatClient(
                threadId: response.thread.id,
                messages: [newsMessage(text: "Saved news")], news: response.thread.news
            )
            client.messageFailure = try readFailure(.toolFailed)
            client.messageFailuresRemaining = wasHydrated ? 0 : 1
            let model = AgentV2Model(client: client, thread: client.hydration.thread)
            defer { model.stop() }
            await model.waitForInitialLoad()
            if wasHydrated {
                client.messageFailuresRemaining = 1
                model.retryLoad()
                try await waitUntil { self.failureLine(in: model) != nil }
            }
            let postID = try XCTUnwrap(model.newsPostItemID)
            let line = try XCTUnwrap(failureLine(in: model))
            XCTAssertTrue(model.hasMessages)
            XCTAssertNil(model.initialLoadError)
            XCTAssertEqual(line.text, lang("Failed to load chat"))
            XCTAssertEqual(line.controls.map(\.id), ["retry-load"])
            XCTAssertEqual(model.itemIDs.last, line.id)

            let controller = AgentVC(model: model)
            let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            XCTAssertTrue(controller.loadErrorView.isHidden)
            let postIndex = try XCTUnwrap(controller.messageIndexPath(for: postID))
            let errorIndex = try XCTUnwrap(controller.messageIndexPath(for: line.id))
            let postFrame = try XCTUnwrap(controller.collectionView.layoutAttributesForItem(at: postIndex)?.frame)
            let errorFrame = try XCTUnwrap(controller.collectionView.layoutAttributesForItem(at: errorIndex)?.frame)
            XCTAssertGreaterThan(errorIndex.item, postIndex.item)
            XCTAssertGreaterThanOrEqual(errorFrame.minY, postFrame.maxY, "Retry occupies its own row below the post")

            let hydrations = client.hydratedThreadIds.count
            model.performControl(messageID: line.id, controlID: "retry-load")
            try await waitUntil {
                client.hydratedThreadIds.count == hydrations + 1 && model.isReadyForPresentation
                    && self.failureLine(in: model) == nil
            }
            XCTAssertEqual(model.newsPostItemID, postID)
            XCTAssertTrue(controller.loadErrorView.isHidden)
            XCTAssertTrue(client.startedCommands.isEmpty, "Retry reloads history rather than starting a wallet or Agent run")
        }
    }

    @MainActor
    func testHistoryErrorsKeepActionableCopyAndLoadRetryProvenance() async throws {
        for code: ApiAgentV2ErrorCode in [.clientUpdateRequired, .deviceTokenExpired, .networkError, .invalidEvent] {
            let client = try ThreadChatClient(threadId: "read-failure")
            client.messageFailure = try readFailure(code)
            client.messageFailuresRemaining = 1
            let coordinator = AgentV2Coordinator(client: client, thread: client.hydration.thread)
            defer { coordinator.stop() }
            await coordinator.hydrate()
            XCTAssertEqual(coordinator.error, AgentV2Copy.error(code))
            XCTAssertTrue(coordinator.isLoadFailure)
            XCTAssertFalse(coordinator.isRunFailure)
        }
    }

    @MainActor
    func testNewsHistoryRetryDoesNotWaitForHostContextOrStartParallelReads() async throws {
        let response = try newsResponse(headline: "Saved news", messageCount: 1)
        let client = try ThreadChatClient(
            threadId: response.thread.id,
            messages: [newsMessage(text: "Saved news")], news: response.thread.news
        )
        client.blocksHostContext = true
        client.messageFailure = try readFailure(.toolFailed)
        client.messageFailuresRemaining = 1
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        try await waitUntil { client.pendingHostContext != nil && self.failureLine(in: model) != nil }
        let line = try XCTUnwrap(failureLine(in: model))
        let hydrations = client.hydratedThreadIds.count
        client.blocksMessages = true
        model.performControl(messageID: line.id, controlID: "retry-load")
        model.retryLoad()
        model.retryLoad()
        try await waitUntil { client.pendingMessages != nil }
        XCTAssertEqual(client.hydratedThreadIds.count, hydrations + 1)
        XCTAssertNotNil(client.pendingHostContext, "The read retries while independent startup work is still pending")

        client.resumeMessages(with: .success(client.hydration))
        try await waitUntil { model.isReadyForPresentation && self.failureLine(in: model) == nil }
        XCTAssertEqual(client.hydratedThreadIds.count, hydrations + 1)
        XCTAssertNotNil(client.pendingHostContext)
        XCTAssertNil(model.initialLoadError)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    private func failureLine(in model: AgentV2Model) -> AgentMessage? {
        model.itemIDs.lazy.compactMap { id -> AgentMessage? in
            guard case .message(let message)? = model.item(for: id), message.isFailureCaption else { return nil }
            return message
        }.first
    }

    private func readFailure(_ code: ApiAgentV2ErrorCode) throws -> ApiAgentV2MutationError {
        try JSONDecoder().decode(
            ApiAgentV2MutationError.self,
            from: JSONSerialization.data(withJSONObject: ["code": code.rawValue, "retryable": true])
        )
    }

    /// The SDK's copy of the history shows while the history loads, with nothing in it to act on, and the history
    /// replaces it
    @MainActor
    func testCachedHistoryShowsWhileTheHistoryLoadsWithNothingToActOnAndTheHistoryReplacesIt() async throws {
        let client = try makeCachedHistoryClient(threadId: "cached-thread")
        client.blocksMessages = true
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        try await waitUntil { client.pendingMessages != nil && self.message(in: model, text: "Cached answer") != nil }

        let cachedAnswer = try XCTUnwrap(message(in: model, text: "Cached answer"))
        XCTAssertEqual(cachedAnswer.controls.count, 3)
        XCTAssertFalse(cachedAnswer.controls.contains { $0.kind == .action && $0.isEnabled })
        XCTAssertFalse(cachedAnswer.canRate)
        XCTAssertFalse(model.isReadyForPresentation)
        XCTAssertFalse(model.canSendMessage(draftText: "Another question"))
        XCTAssertFalse(model.canRegenerateMessage(cachedAnswer.id))
        let controller = AgentVC(model: model)
        let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
        defer { window.isHidden = true }
        let cachedMenuTitles = try await getQuestionMenuTitles(in: controller, model: model)
        XCTAssertFalse(cachedMenuTitles.contains(lang("Edit")))
        // The suggestion looks as the loaded history's does and ignores a tap
        let cachedSuggestions = cachedAnswer.controls.filter { $0.kind == .followup }
        try await getSuggestionButton(in: controller).sendActions(for: .touchUpInside)
        XCTAssertNil(controller.pendingSentSource)
        XCTAssertNil(controller.suggestionMorph)
        let didRate = await model.rateMessage(messageID: cachedAnswer.id, feedback: .like)
        XCTAssertFalse(didRate)
        let didLoadOlder = await model.loadOlderMessages()
        XCTAssertFalse(didLoadOlder)
        // A wallet change publishes the host context again, which refreshes the presentations of the shown actions
        let publications = client.hostContextPublishedCallCount
        WalletCoreData.notify(event: .accountNameChanged)
        try await waitUntil { client.hostContextPublishedCallCount > publications }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.actionPresentationRequestCount, 0)
        XCTAssertEqual(client.feedbackRequestCount, 0)
        XCTAssertEqual(client.hydratedThreadIds, ["cached-thread"])

        client.resumeMessages(with: .success(client.hydration))
        try await waitUntil { model.isReadyForPresentation }
        let answers = model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role == .assistant && !$0.isFailureCaption }
        XCTAssertEqual(answers.map(\.text), ["Fresh answer"])
        XCTAssertTrue(answers[0].controls.allSatisfy(\.isEnabled))
        XCTAssertEqual(answers[0].controls.filter { $0.kind == .followup }, cachedSuggestions)
        XCTAssertTrue(answers[0].canRate)
        XCTAssertTrue(model.canSendMessage(draftText: "Another question"))
        let freshMenuTitles = try await getQuestionMenuTitles(in: controller, model: model)
        XCTAssertTrue(freshMenuTitles.contains(lang("Edit")))
        try await waitUntil { client.actionPresentationRequestCount > 0 }
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertEqual(controller.composerView.draftText ?? "", "")
        try await getSuggestionButton(in: controller).sendActions(for: .touchUpInside)
        try await waitUntil { client.startedCommands.count == 1 }
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Tell me more")])
    }

    /// The suggestion under the chat's answer, once the list lays it out
    @MainActor
    private func getSuggestionButton(in controller: AgentVC) async throws -> AgentSuggestionButton {
        let controlID = "followup:adadadad-adad-4dad-8dad-adadadadadad"
        var button: AgentSuggestionButton?
        for _ in 0..<200 where button == nil {
            try await Task.sleep(for: .milliseconds(10))
            controller.collectionView.window?.layoutIfNeeded()
            button = controller.collectionView.visibleCells.lazy
                .compactMap { ($0 as? AgentMessageCell)?.getFollowupButton(controlID: controlID) }
                .first { $0.window != nil && !$0.isHidden && $0.isEnabled }
        }
        return try XCTUnwrap(button)
    }

    /// A copy doesn't show once a history request has ended, even in failure or to be retried, once another load has
    /// started, once the chat has live content of its own, or once the chat has closed
    @MainActor
    func testCachedHistoryArrivingAfterTheHistoryRequestOrTheChatEndedDoesNotShow() async throws {
        for ending in ["failure", "retry", "superseded", "live", "closed"] {
            let client = try makeCachedHistoryClient(threadId: "late-cache")
            let thread = client.hydration.thread
            client.blocksCachedHistory = true
            if ending == "failure" {
                client.messageFailuresRemaining = 1
            } else {
                client.blocksMessages = true
            }
            if ending == "retry" {
                client.messageFailure = ApiAgentV2MutationError(code: .walletContextChanged, retryable: true)
                client.messageFailuresRemaining = 1
            }
            let model = AgentV2Model(client: client, thread: thread)
            defer {
                model.stop()
                client.releasePendingRequests()
            }
            try await waitUntil {
                client.cachedHistoryThreadIds.count == 1
                    && (ending == "failure" ? model.initialLoadError != nil : client.pendingMessages != nil)
            }
            switch ending {
            case "retry":
                XCTAssertEqual(client.hydratedThreadIds.count, 2)
            case "superseded":
                client.messageError = ThreadChatClientError.unavailable
                model.refreshThreadIfNeeded(try decodeThread(id: thread.id, revision: thread.revision + 1))
                try await waitUntil { client.hydratedThreadIds.count == 2 && model.initialLoadError != nil }
            case "live":
                let runStarted = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
                    "kind": "runStarted", "clientRunId": "live-client-run", "runId": "live-run", "threadId": thread.id,
                    "threadRevision": thread.revision + 1,
                ]))
                WalletCoreData.notify(event: .agentV2(runStarted))
                try await waitUntil { model.hasActiveRun }
            case "closed":
                model.stop()
            default:
                break
            }
            client.resumeCachedHistory()
            for _ in 0..<20 { await Task.yield() }

            XCTAssertFalse(model.hasMessages, ending)
        }
    }

    /// A history that fails to load leaves the copy as it was, with the failure line whose Retry loads the history in
    /// its place; a thread the server no longer has takes the copy away
    @MainActor
    func testFailedHistoryKeepsTheCachedHistoryInertUnlessTheThreadIsGone() async throws {
        let client = try makeCachedHistoryClient(threadId: "failing-cache")
        client.blocksMessages = true
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer {
            model.stop()
            client.releasePendingRequests()
        }
        try await waitUntil { client.pendingMessages != nil && model.hasMessages }
        client.blocksMessages = false
        client.resumeMessages(with: .failure(ThreadChatClientError.unavailable))
        try await waitUntil { self.failureLine(in: model) != nil }

        let line = try XCTUnwrap(failureLine(in: model))
        XCTAssertEqual(line.controls.map(\.id), ["retry-load"])
        XCTAssertNil(model.initialLoadError)
        let cachedAnswer = try XCTUnwrap(message(in: model, text: "Cached answer"))
        XCTAssertFalse(cachedAnswer.controls.contains { $0.kind == .action && $0.isEnabled })
        XCTAssertFalse(model.canSendMessage(draftText: "Another question"))

        model.performControl(messageID: line.id, controlID: "retry-load")
        try await waitUntil { model.isReadyForPresentation }
        XCTAssertNotNil(message(in: model, text: "Fresh answer"))
        XCTAssertNil(message(in: model, text: "Cached answer"))
        XCTAssertEqual(client.cachedHistoryThreadIds, ["failing-cache"])

        let missingClient = try makeCachedHistoryClient(threadId: "missing-cache")
        missingClient.blocksMessages = true
        WalletCoreData.addImmediately(eventObserver: missingClient)
        let missingModel = AgentV2Model(client: missingClient, thread: missingClient.hydration.thread)
        defer {
            missingModel.stop()
            missingClient.releasePendingRequests()
            WalletCoreData.remove(observer: missingClient)
        }
        try await waitUntil { missingClient.pendingMessages != nil && missingModel.hasMessages }
        missingClient.resumeMessages(with: .failure(ApiAgentV2MutationError(code: .threadNotFound, retryable: false)))
        try await waitUntil { missingClient.deletedThreadIds == ["missing-cache"] }
        XCTAssertFalse(missingModel.hasMessages)
    }

    /// Only a chat opened on an existing thread reads the copy, and its loading screen gives way to the copy. A chat that
    /// opens at its first unread message, which only the history places, doesn't read it.
    @MainActor
    func testOnlyAChatOpenedOnAnExistingThreadShowsTheCachedHistoryBeforeItsHistory() async throws {
        let defaultClient = try makeCachedHistoryClient(threadId: "default-thread")
        let defaultModel = AgentV2Model(client: defaultClient)
        await defaultModel.waitForInitialLoad()
        defaultModel.stop()
        let newClient = try ThreadChatClient(threadId: "new-thread", messages: [])
        newClient.cachedHistory = try makeCachedHistory(newClient.hydration.thread, answer: "Cached answer")
        let newModel = AgentV2Model(client: newClient, thread: newClient.hydration.thread)
        await newModel.waitForInitialLoad()
        newModel.stop()
        XCTAssertTrue(defaultClient.cachedHistoryThreadIds.isEmpty)
        XCTAssertTrue(newClient.cachedHistoryThreadIds.isEmpty)

        for isUnread in [false, true] {
            let client = try makeCachedHistoryClient(threadId: "opened-\(UUID().uuidString)")
            client.blocksMessages = true
            let thread = client.hydration.thread
            let readState = AgentThreadReadState.shared
            readState.chatDidAppear(threadId: thread.id)
            readState.chatDidDisappear(threadId: thread.id, seenMessageCount: isUnread ? 1 : thread.messageCount)
            let preloader = AgentPreloader(client: client)
            let root = AgentRootVC(thread: thread, preloader: preloader)
            let navigation = UINavigationController(rootViewController: root)
            defer {
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
                client.releasePendingRequests()
                readState.remove(threadId: thread.id)
            }
            root.loadViewIfNeeded()
            if isUnread {
                // The unread chat doesn't show the copy even when its history then fails to load
                try await waitUntil { client.pendingMessages != nil }
                let model = try XCTUnwrap(preloader.model(threadId: thread.id))
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertTrue(navigation.topViewController === root)
                XCTAssertTrue(client.cachedHistoryThreadIds.isEmpty)
                client.resumeMessages(with: .failure(ThreadChatClientError.unavailable))
                try await waitUntil { navigation.topViewController is AgentVC }
                XCTAssertFalse(model.hasMessages)
                XCTAssertEqual(model.initialLoadError, lang("Failed to load chat"))
            } else {
                try await waitUntil { client.pendingMessages != nil && preloader.model(threadId: thread.id)?.hasMessages == true }
                try await waitUntil { navigation.topViewController is AgentVC }
                XCTAssertNotNil(client.pendingMessages)
            }
        }
    }

    /// A chat whose cached history is in memory opens with it in its first frame, without the loading screen, and keeps
    /// every rule of a cached history: nothing to act on, the failure with Retry, and the history in its place
    @MainActor
    func testChatWithItsCachedHistoryInMemoryOpensWithItAtOnce() async throws {
        let client = try makeCachedHistoryClient(threadId: "warm-thread")
        client.blocksMessages = true
        let thread = client.hydration.thread
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        preloader.prefetchCachedHistories(of: [thread])
        try await waitUntil { preloader.getCachedHistory(threadId: thread.id) != nil }

        let controller = AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader)
        let model = try XCTUnwrap(preloader.model(threadId: thread.id))
        XCTAssertTrue(controller is AgentVC)
        XCTAssertTrue(model.isShowingCachedMessages)
        // Reopened while it still shows the copy, the chat opens with it again
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader) is AgentVC)
        let cachedAnswer = try XCTUnwrap(message(in: model, text: "Cached answer"))
        XCTAssertFalse(cachedAnswer.controls.contains { $0.kind == .action && $0.isEnabled })
        XCTAssertFalse(cachedAnswer.canRate)
        XCTAssertFalse(model.canSendMessage(draftText: "Another question"))

        try await waitUntil { client.pendingMessages != nil }
        XCTAssertEqual(client.cachedHistoryThreadIds, [thread.id])
        client.blocksMessages = false
        client.resumeMessages(with: .failure(ThreadChatClientError.unavailable))
        try await waitUntil { self.failureLine(in: model) != nil }
        // The copy stays with the failure, without its suggestions until the history replaces it
        XCTAssertTrue(cachedAnswer.controls.contains { $0.kind == .followup })
        XCTAssertFalse(try XCTUnwrap(message(in: model, text: "Cached answer")).controls.contains { $0.kind == .followup })
        let line = try XCTUnwrap(failureLine(in: model))
        model.performControl(messageID: line.id, controlID: "retry-load")
        XCTAssertFalse(try XCTUnwrap(message(in: model, text: "Cached answer")).controls.contains { $0.kind == .followup })
        try await waitUntil { model.isReadyForPresentation }
        XCTAssertNil(message(in: model, text: "Cached answer"))
        XCTAssertTrue(try XCTUnwrap(message(in: model, text: "Fresh answer")).controls.contains { $0.kind == .followup })
        // The loaded history takes the copy's place in memory
        let history = try XCTUnwrap(preloader.getCachedHistory(threadId: thread.id))
        XCTAssertEqual(history.messages.map { AgentV2NativeMessage(persisted: $0).text }, ["What can I do?", "Fresh answer"])
    }

    /// A chat opened on its cached history whose host context can't be published keeps the copy with the failure and
    /// Retry, which starts the chat over and brings the history in its place
    @MainActor
    func testCachedChatWhoseAgentIsUnavailableKeepsTheCopyWithRetry() async throws {
        let client = try makeCachedHistoryClient(threadId: "unavailable-thread")
        client.hostContextFailuresRemaining = 3
        let thread = client.hydration.thread
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        preloader.prefetchCachedHistories(of: [thread])
        try await waitUntil { preloader.getCachedHistory(threadId: thread.id) != nil }
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader) is AgentVC)
        let model = try XCTUnwrap(preloader.model(threadId: thread.id))

        // The chat publishes its host context three times, a second apart
        for _ in 0..<100 where client.hostContextUpdateCallCount < 3 || failureLine(in: model) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let line = try XCTUnwrap(failureLine(in: model))
        XCTAssertEqual(line.text, lang("Agent is unavailable"))
        XCTAssertEqual(line.controls.map(\.id), ["retry-load"])
        XCTAssertNil(model.initialLoadError)
        XCTAssertNotNil(message(in: model, text: "Cached answer"))
        XCTAssertTrue(client.hydratedThreadIds.isEmpty)

        model.performControl(messageID: line.id, controlID: "retry-load")
        try await waitUntil { model.isReadyForPresentation }
        XCTAssertNil(message(in: model, text: "Cached answer"))
        XCTAssertNotNil(message(in: model, text: "Fresh answer"))
        XCTAssertNil(failureLine(in: model))
    }

    /// An action of the cached history isn't resolved, even when asked for directly; once the history loads, the same
    /// action reaches the client
    @MainActor
    func testCachedHistoryActionReachesTheClientOnlyAfterTheHistoryLoads() async throws {
        let client = try makeCachedHistoryClient(threadId: "resolving-thread")
        client.blocksMessages = true
        let cached = try XCTUnwrap(client.cachedHistory)
        let account = MAccount(id: "0-mainnet", title: "Wallet", type: .mnemonic, byChain: [.ton: .init(address: "ton")])
        // The host context reads the account and its saved addresses from their stores
        try await withDependencies {
            $0.accountStore = .makePreview(accounts: [account], selectedAccountId: account.id)
            $0[SavedAddressesStore.self] = .liveValue
        } operation: {
            let coordinator = AgentV2Coordinator(
                client: client,
                thread: client.hydration.thread,
                cachedHistory: AgentCachedHistory(thread: cached.thread, messages: cached.messages),
                activeAccount: { account }
            )
            defer {
                coordinator.stop()
                client.releasePendingRequests()
            }
            XCTAssertTrue(coordinator.isShowingCachedMessages)
            coordinator.start()
            try await waitUntil { client.pendingMessages != nil }

            let cachedResolution = await coordinator.resolveAction(messageId: "answer", actionId: "send")
            XCTAssertNil(cachedResolution)
            XCTAssertEqual(client.resolveActionRequestCount, 0)

            client.resumeMessages(with: .success(client.hydration))
            try await waitUntil { coordinator.hasHydratedMessages }
            _ = await coordinator.resolveAction(messageId: "answer", actionId: "send")
            XCTAssertEqual(client.resolveActionRequestCount, 1)
        }
    }

    /// Without a usable history in memory a chat opens under the loading screen as before: one never read, an unread
    /// chat, a news discussion and a new chat
    @MainActor
    func testChatWithoutAUsableCachedHistoryInMemoryOpensUnderTheLoadingScreen() async throws {
        let client = try makeCachedHistoryClient(threadId: "cold-thread")
        client.blocksMessages = true
        let thread = client.hydration.thread
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        let readState = AgentThreadReadState.shared
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
            readState.remove(threadId: thread.id)
        }
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader) is AgentRootVC)
        XCTAssertNil(preloader.model(threadId: thread.id))

        preloader.prefetchCachedHistories(of: [thread])
        try await waitUntil { preloader.getCachedHistory(threadId: thread.id) != nil }
        // An answer that just completed marks the chat unread before its summary counts the answer
        readState.chatDidAppear(threadId: thread.id)
        readState.chatDidDisappear(threadId: thread.id, seenMessageCount: thread.messageCount)
        readState.answerDidComplete(threadId: thread.id)
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader) is AgentRootVC)
        let unreadModel = try XCTUnwrap(preloader.model(threadId: thread.id))
        XCTAssertFalse(unreadModel.isShowingCachedMessages)
        XCTAssertFalse(unreadModel.hasMessages)

        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let newsClient = try ThreadChatClient(threadId: "news-thread", messages: [newsMessage(text: "Saved news")], news: response.thread.news)
        newsClient.cachedHistory = try makeCachedHistory(newsClient.hydration.thread, answer: "Cached answer")
        let newsPreloader = AgentPreloader(client: newsClient)
        newsPreloader.setWalletReady(true)
        defer { newsPreloader.setWalletReady(false) }
        newsPreloader.prefetchCachedHistories(of: [newsClient.hydration.thread])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(newsClient.cachedHistoryThreadIds.isEmpty)
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: newsClient.hydration.thread, preloader: newsPreloader) is AgentRootVC)

        XCTAssertTrue(AgentEntryPoint.makeNewChatViewController(preloader: preloader) is AgentRootVC)

        // A digest discussion, as a news one, shows no cached history
        let digestThread = try makeSummary(id: "digest-thread", minute: 2, hasDigest: true)
        let digestHistory = try makeCachedHistory(digestThread, answer: "Cached answer")
        let digestCoordinator = AgentV2Coordinator(
            client: client,
            thread: digestThread,
            cachedHistory: AgentCachedHistory(thread: digestHistory.thread, messages: digestHistory.messages)
        )
        defer { digestCoordinator.stop() }
        XCTAssertFalse(digestCoordinator.isShowingCachedMessages)
    }

    /// The list's first page, the SDK's copy of it as well, reads the copies of its top ten threads with messages,
    /// outside news, and a later page reads again only a thread whose summary changed; a thread without a copy has none
    /// in memory
    @MainActor
    func testListReadsTheCachedHistoriesOfItsTopThreadsOnceUntilTheyChange() async throws {
        let client = try makeCachedHistoryClient(threadId: "thread-0")
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        defer { preloader.setWalletReady(false) }
        let response = try newsResponse(headline: newsItem().headline, messageCount: 1)
        let news = try XCTUnwrap(response.thread.news)
        func makeList(firstRevision: Int) throws -> ApiAgentV2ThreadListResponse {
            let threads = try [
                makeSummary(id: "empty", minute: 59, messageCount: 0),
                makeSummary(id: "news", minute: 58, news: news),
                makeSummary(id: "digest", minute: 57, hasDigest: true),
            ] + (0..<12).map { index in
                try makeSummary(id: "thread-\(index)", minute: 50 - index, revision: index == 0 ? firstRevision : 1)
            }
            return ApiAgentV2ThreadListResponse(
                protocolVersion: 3,
                threads: threads.map { ApiAgentV2ThreadListItem(thread: $0, preview: nil) },
                nextCursor: nil
            )
        }
        client.cachedThreadItems = try makeList(firstRevision: 1).threads
        client.threadList = try makeList(firstRevision: 1)
        client.blocksThreadList = true
        let listModel = AgentThreadListModel(client: client, preloader: preloader)

        let firstLoad = Task { await listModel.refresh() }
        try await waitUntil { client.cachedHistoryThreadIds.count == 10 && preloader.getCachedHistory(threadId: "thread-0") != nil }
        XCTAssertTrue(listModel.isShowingCachedThreads)
        XCTAssertEqual(client.cachedHistoryThreadIds, (0..<10).map { "thread-\($0)" })
        XCTAssertNil(preloader.getCachedHistory(threadId: "thread-1"))

        client.resumeThreadList()
        await firstLoad.value
        await listModel.refresh()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.cachedHistoryThreadIds.count, 10)

        client.cachedHistory = nil
        client.threadList = try makeList(firstRevision: 2)
        await listModel.refresh()
        try await waitUntil { client.cachedHistoryThreadIds.count == 11 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.cachedHistoryThreadIds.last, "thread-0")
        XCTAssertNil(preloader.getCachedHistory(threadId: "thread-0"))
    }

    /// A history a chat outside the list loads takes the place of the list's lowest thread, not its top one, and the
    /// next prefetch reads the lowest one again
    @MainActor
    func testCachedHistoriesKeepTheListTopWhenAnotherChatsHistoryArrives() async throws {
        let client = try ThreadChatClient(
            threadId: "outside-thread",
            messages: makeConversation(threadId: "outside-thread", answer: "Fresh answer")
        )
        let threads = try (0..<10).map { try makeSummary(id: "thread-\($0)", minute: 50 - $0) }
        for thread in threads {
            client.cachedHistoriesByThreadId[thread.id] = try makeCachedHistory(thread, answer: "Cached answer")
        }
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        preloader.prefetchCachedHistories(of: threads)
        try await waitUntil { threads.allSatisfy { preloader.getCachedHistory(threadId: $0.id) != nil } }

        let model = try XCTUnwrap(preloader.acquireModel(thread: client.hydration.thread))
        defer { model.stop() }
        try await waitUntil { preloader.getCachedHistory(threadId: "outside-thread") != nil }
        XCTAssertNotNil(preloader.getCachedHistory(threadId: "thread-0"))
        XCTAssertNil(preloader.getCachedHistory(threadId: "thread-9"))

        let readCount = client.cachedHistoryThreadIds.count
        preloader.prefetchCachedHistories(of: threads)
        try await waitUntil { preloader.getCachedHistory(threadId: "thread-9") != nil }
        XCTAssertEqual(Array(client.cachedHistoryThreadIds.dropFirst(readCount)), ["thread-9"])
        XCTAssertNotNil(preloader.getCachedHistory(threadId: "thread-0"))
    }

    /// A row of the SDK's copy of the list has the summary of a past session, so a chat whose answer finished after the
    /// app was closed counts there as read. The chat shows no cached history: it loads under the skeleton and opens
    /// unread at the answer, or with its failure and Retry, leaving the chat unread.
    @MainActor
    func testChatFromACachedListRowLoadsItsHistoryBeforeOpening() async throws {
        for isHistoryLoaded in [true, false] {
            try await openChatFromACachedListRow(isHistoryLoaded: isHistoryLoaded)
        }
    }

    @MainActor
    private func openChatFromACachedListRow(isHistoryLoaded: Bool) async throws {
        let threadId = "streamed-\(UUID().uuidString)"
        let staleThread = try makeSummary(id: threadId, minute: 1)
        let client = try ThreadChatClient(threadId: threadId, messages: makeConversation(threadId: threadId, answer: "Cached answer") + [[
            "id": "finished", "threadId": threadId, "role": "assistant", "status": "complete",
            "content": ["kind": "markdown", "text": "Finished answer"],
            "createdAt": "2026-10-02T00:02:00.000Z",
        ]])
        client.cachedHistory = try makeCachedHistory(staleThread, answer: "Cached answer")
        client.blocksMessages = true
        let readState = AgentThreadReadState.shared
        readState.chatDidAppear(threadId: threadId)
        readState.chatDidDisappear(threadId: threadId, seenMessageCount: staleThread.messageCount)
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
            readState.remove(threadId: threadId)
        }
        preloader.prefetchCachedHistories(of: [staleThread])
        try await waitUntil { preloader.getCachedHistory(threadId: threadId) != nil }

        let root = AgentEntryPoint.makeRootViewController(thread: staleThread, preloader: preloader, isSummaryCached: true)
        XCTAssertTrue(root is AgentRootVC)
        let navigation = UINavigationController(rootViewController: root)
        defer { navigation.setViewControllers([], animated: false) }
        root.loadViewIfNeeded()
        try await waitUntil { client.pendingMessages != nil }
        let model = try XCTUnwrap(preloader.model(threadId: threadId))
        // Opened again from the copy while it loads, the chat still waits for its history
        XCTAssertTrue(
            AgentEntryPoint.makeRootViewController(thread: staleThread, preloader: preloader, isSummaryCached: true) is AgentRootVC
        )
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(navigation.topViewController === root)
        // Its chat takes neither the copy in memory nor the SDK's one
        XCTAssertFalse(model.hasMessages)
        XCTAssertEqual(client.cachedHistoryThreadIds, [threadId])

        if !isHistoryLoaded {
            client.blocksMessages = false
            client.resumeMessages(with: .failure(ThreadChatClientError.unavailable))
            try await waitUntil { navigation.topViewController is AgentVC }
            XCTAssertEqual(model.initialLoadError, lang("Failed to load chat"))
            XCTAssertFalse(model.hasMessages)
            XCTAssertEqual(readState.getSeenMessageCount(ifUnread: client.hydration.thread), staleThread.messageCount)
            model.retryLoad()
            try await waitUntil { model.isReadyForPresentation }
            XCTAssertNotNil(message(in: model, text: "Finished answer"))
            return
        }
        client.resumeMessages(with: .success(client.hydration))
        try await waitUntil { navigation.topViewController is AgentVC }
        XCTAssertNotNil(message(in: model, text: "Finished answer"))
        let loadedThread = try XCTUnwrap(model.thread)
        XCTAssertEqual(readState.getSeenMessageCount(ifUnread: loadedThread), staleThread.messageCount)
    }

    /// An answer that starts while the chat shows its cached history takes the copy's place, and the chat follows it
    @MainActor
    func testRunStartingOverTheCachedHistoryReplacesIt() async throws {
        let client = try makeCachedHistoryClient(threadId: "live-\(UUID().uuidString)")
        client.blocksMessages = true
        let thread = client.hydration.thread
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
        }
        preloader.prefetchCachedHistories(of: [thread])
        try await waitUntil { preloader.getCachedHistory(threadId: thread.id) != nil }
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader) is AgentVC)
        let model = try XCTUnwrap(preloader.model(threadId: thread.id))
        XCTAssertNotNil(message(in: model, text: "Cached answer"))

        let runStarted = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runStarted", "clientRunId": "live-client-run", "runId": "live-run", "threadId": thread.id,
            "threadRevision": thread.revision + 1,
        ]))
        WalletCoreData.notify(event: .agentV2(runStarted))
        try await waitUntil { model.hasActiveRun }
        XCTAssertFalse(model.isShowingCachedMessages)
        XCTAssertNil(message(in: model, text: "Cached answer"))
    }

    /// A chat left on its cached history that gets an answer off screen is unread, so it reopens under the loading
    /// screen to open at the answer
    @MainActor
    func testCachedChatThatGetsAnAnswerOffScreenReopensUnderTheLoadingScreen() async throws {
        let client = try makeCachedHistoryClient(threadId: "answered-\(UUID().uuidString)")
        client.blocksMessages = true
        let thread = client.hydration.thread
        let readState = AgentThreadReadState.shared
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        defer {
            preloader.setWalletReady(false)
            client.releasePendingRequests()
            readState.remove(threadId: thread.id)
        }
        preloader.prefetchCachedHistories(of: [thread])
        try await waitUntil { preloader.getCachedHistory(threadId: thread.id) != nil }
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader) is AgentVC)
        XCTAssertEqual(preloader.model(threadId: thread.id)?.isShowingCachedMessages, true)

        readState.answerDidComplete(threadId: thread.id)
        XCTAssertTrue(readState.isUnread(thread))
        XCTAssertTrue(AgentEntryPoint.makeRootViewController(thread: thread, preloader: preloader) is AgentRootVC)
    }

    /// A thread's history leaves memory as the chat clears it, as it is deleted or missing on the server, and as the
    /// wallet stops being ready
    @MainActor
    func testCachedHistoryInMemoryLeavesWithItsThreadOrTheWallet() async throws {
        for ending in ["cleared", "deleted", "missing", "wallet"] {
            let client = try makeCachedHistoryClient(threadId: "leaving-\(ending)")
            let thread = client.hydration.thread
            if ending == "missing" {
                client.messageError = ApiAgentV2MutationError(code: .threadNotFound, retryable: false)
            }
            let preloader = AgentPreloader(client: client)
            preloader.setWalletReady(true)
            defer {
                preloader.setWalletReady(false)
                client.releasePendingRequests()
            }
            preloader.prefetchCachedHistories(of: [thread])
            try await waitUntil { preloader.getCachedHistory(threadId: thread.id) != nil }
            // The chat stays open until its history leaves memory
            var openChat: AgentV2Model?
            switch ending {
            case "cleared":
                let model = try XCTUnwrap(preloader.acquireModel(thread: thread))
                openChat = model
                try await waitUntil { model.isReadyForPresentation }
                XCTAssertNotNil(preloader.getCachedHistory(threadId: thread.id))
                model.clearChat(animated: false)
            case "deleted":
                preloader.deleteThread(id: thread.id)
            case "missing":
                let model = try XCTUnwrap(preloader.acquireModel(thread: thread))
                openChat = model
                XCTAssertTrue(model.isShowingCachedMessages)
            default:
                preloader.setWalletReady(false)
            }
            for _ in 0..<400 where preloader.getCachedHistory(threadId: thread.id) != nil {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertNil(preloader.getCachedHistory(threadId: thread.id), ending)
            openChat?.stop()
        }
    }

    private func makeSummary(
        id: String,
        minute: Int,
        revision: Int = 1,
        messageCount: Int = 2,
        news: ApiAgentV2ThreadNewsCard? = nil,
        hasDigest: Bool = false
    ) throws -> ApiAgentV2ThreadSummary {
        let date = String(format: "2026-10-02T00:%02d:00.000Z", minute)
        var thread: [String: Any] = [
            "id": id, "revision": revision, "createdAt": date, "updatedAt": date, "lastActivityAt": date,
            "messageCount": messageCount,
        ]
        if let news {
            thread["news"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(news))
        }
        if hasDigest {
            thread["digest"] = ["id": "digest-\(id)", "windowEnd": date, "total": 0, "top": []]
        }
        return try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: thread))
    }

    /// The titles of the menu a long press opens on the chat's question
    @MainActor
    private func getQuestionMenuTitles(in controller: AgentVC, model: AgentV2Model) async throws -> [String] {
        let list = controller.collectionView
        var cell: AgentMessageCell?
        for _ in 0..<200 where cell == nil {
            try await Task.sleep(for: .milliseconds(10))
            list.window?.layoutIfNeeded()
            cell = list.visibleCells.compactMap { $0 as? AgentMessageCell }.first { cell in
                guard let indexPath = list.indexPath(for: cell), let id = controller.messageItemID(at: indexPath) else { return false }
                return model.message(for: id)?.role == .user
            }
        }
        let menu = try XCTUnwrap(try XCTUnwrap(cell).contextMenuConfigurationProvider?())
        return menu.rootPage.items.compactMap { item in
            guard case .action(let action) = item else { return nil }
            return action.title
        }
    }

    @MainActor
    private func message(in model: AgentV2Model, text: String) -> AgentMessage? {
        model.itemIDs.lazy.compactMap { model.message(for: $0) }.first { $0.text == text }
    }

    /// A client whose history has a question and its answer, "Fresh answer", and whose copy has the same messages with
    /// "Cached answer". The answer has an action of each kind and a follow-up.
    @MainActor
    private func makeCachedHistoryClient(threadId: String) throws -> ThreadChatClient {
        let client = try ThreadChatClient(threadId: threadId, messages: makeConversation(threadId: threadId, answer: "Fresh answer"))
        client.cachedHistory = try makeCachedHistory(client.hydration.thread, answer: "Cached answer")
        return client
    }

    private func makeCachedHistory(_ thread: ApiAgentV2ThreadSummary, answer: String) throws -> ApiAgentV2CachedMessages {
        try JSONDecoder().decode(ApiAgentV2CachedMessages.self, from: JSONSerialization.data(withJSONObject: [
            "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)),
            "messages": makeConversation(threadId: thread.id, answer: answer),
            "hasOlder": true,
        ]))
    }

    private func makeConversation(threadId: String, answer: String) -> [[String: Any]] {
        [
            [
                "id": "question", "threadId": threadId, "role": "user", "status": "complete",
                "content": ["kind": "markdown", "text": "What can I do?"],
                "createdAt": "2026-10-02T00:00:00.000Z",
            ],
            [
                "id": "answer", "threadId": threadId, "role": "assistant", "status": "complete",
                "content": ["kind": "markdown", "text": answer],
                "createdAt": "2026-10-02T00:01:00.000Z",
                "actions": [
                    ["id": "receive", "kind": "receive", "labelCode": "open_receive", "title": "Receive", "requiresConfirmation": false],
                    ["id": "send", "kind": "send", "labelCode": "open_send", "title": "Send", "requiresConfirmation": false],
                ],
                "followups": [[
                    "id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "Tell me more",
                ]],
            ],
        ]
    }

    /// A tap on the discussion post's picture opens it alone in the media viewer, as the feed opens its pictures
    @MainActor
    func testDiscussionPostPictureOpensInTheMediaViewer() async throws {
        let news = ApiAgentV2ThreadNewsCard(
            eventId: 41,
            headline: "Picture news",
            excerpt: nil,
            imageUrl: "invalid-news-image://post",
            publishedAt: "2026-10-01T00:00:00.000Z",
            source: nil,
            body: "Body"
        )
        let client = try ThreadChatClient(threadId: "picture-thread", news: news)
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let controller = AgentVC(model: model)
        let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
        defer { window.isHidden = true }
        var post: AgentNewsPostCell?
        for _ in 0..<200 where post == nil {
            window.layoutIfNeeded()
            post = controller.collectionView.visibleCells.compactMap { $0 as? AgentNewsPostCell }.first
            try await Task.sleep(for: .milliseconds(10))
        }
        let cell = try XCTUnwrap(post)
        cell.onPictureTap?(cell.newsView.imageView)
        let viewer = try XCTUnwrap(window.subviews.compactMap { $0 as? MediaViewer }.first)
        XCTAssertEqual(viewer.currentIndex, 0)
        XCTAssertFalse(viewer.accessibilityScroll(.left))
        // The post is the picture's caption, and the single picture has no counter: its date is the capsule's title
        XCTAssertEqual(viewer.footerView.captionTextView.attributedText.string, "Picture news\nBody")
        XCTAssertNil(viewer.counterText)
        XCTAssertNotNil(viewer.headerView.titleLabel.text)
        XCTAssertNil(viewer.headerView.subtitleLabel.text)
        viewer.close()
    }

    @MainActor
    private func openChat(threadId: String, messageCount: Int) async throws -> (AgentVC, AgentV2Model, UIWindow) {
        let messages: [[String: Any]] = (0..<messageCount).map { index in
            [
                "id": "message-\(index)",
                "threadId": threadId,
                "role": index.isMultiple(of: 2) ? "user" : "assistant",
                "status": "complete",
                "content": ["kind": "markdown", "text": "Message \(index) " + String(repeating: "about the wallet ", count: 20)],
                "createdAt": String(format: "2026-10-02T00:%02d:00.000Z", index),
            ]
        }
        let client = try ThreadChatClient(threadId: threadId, messages: messages)
        let model = AgentV2Model(client: client, thread: client.hydration.thread)
        await model.waitForInitialLoad()
        let controller = AgentVC(model: model)
        let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
        var previousOffset: CGFloat = .nan
        var stableSamples = 0
        for _ in 0..<300 where stableSamples < 10 {
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            let offset = controller.collectionView.contentOffset.y
            stableSamples = offset == previousOffset && controller.hasPerformedInitialScroll ? stableSamples + 1 : 0
            previousOffset = offset
        }
        return (controller, model, window)
    }

    private func decodeThread(id: String, revision: Int) throws -> ApiAgentV2ThreadSummary {
        try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self,
            from: JSONSerialization.data(withJSONObject: [
                "id": id,
                "revision": revision,
                "createdAt": "2026-10-01T00:00:00.000Z",
                "updatedAt": "2026-10-02T00:00:00.000Z",
                "lastActivityAt": "2026-10-02T00:00:00.000Z",
                "messageCount": 1
            ])
        )
    }
}

private enum ThreadChatClientError: Error {
    case unavailable
}

@MainActor
private final class ThreadChatClient: AgentV2Client, AgentThreadListClient, WalletCoreData.EventsObserver {
    var hydration: ApiAgentV2ThreadHydration
    private(set) var defaultThreadCallCount = 0
    private(set) var hydratedThreadIds: [String] = []
    private(set) var deletedThreadIds: [String] = []
    private(set) var consentCallCount = 0
    private(set) var acceptConsentCallCount = 0
    private(set) var hostContextUpdateCallCount = 0
    private(set) var hostContextPublishedCallCount = 0
    private(set) var hostContextPublishedCountsAtRunStart: [Int] = []
    private(set) var availabilityRequestCount = 0
    private(set) var userQuotaRequestCount = 0
    private(set) var problemReportAvailabilityRequestCount = 0
    private(set) var newsThreadCreateCallCount = 0
    private(set) var newsThreadRequests: [ApiAgentV2ThreadNewsRequest] = []
    private(set) var startedCommands: [ApiAgentV2RunCommand] = []
    private(set) var retriedClientRunIds: [String] = []
    private(set) var cancelledNewsCreationCount = 0
    private(set) var clearThreadCallCount = 0
    var blocksNewsCreation = false
    var blocksMessages = false
    var blocksHostContext = false
    var blocksRuns = false
    var blocksRetries = false
    var hasConsent = true
    /// The first consent read waits for `resumeConsent`, and the next `consentFailuresRemaining` reads fail
    var blocksFirstConsent = false
    /// The next consent read waits for `resumeConsent`
    var blocksNextConsent = false
    var consentFailuresRemaining = 0
    private var pendingConsent: CheckedContinuation<Void, Never>?
    var isConsentKnownGiven = false
    var isProblemReportAvailable = false
    private(set) var reports: [(threadId: String, report: ApiAgentV2ProblemReport)] = []
    var hostContextFailuresRemaining = 0
    var messageFailuresRemaining = 0
    var messageFailure: Error = ThreadChatClientError.unavailable
    var messageError: Error?
    /// The SDK's copy of the thread's history, which `blocksCachedHistory` holds back until `resumeCachedHistory()`
    var cachedHistory: ApiAgentV2CachedMessages?
    var blocksCachedHistory = false
    private(set) var cachedHistoryThreadIds: [String] = []
    private var pendingCachedHistory: [CheckedContinuation<Void, Never>] = []
    private(set) var feedbackRequestCount = 0
    private(set) var actionPresentationRequestCount = 0
    private(set) var pendingNewsCreation: CheckedContinuation<ApiAgentV2ThreadCreateResponse, Error>?
    private(set) var pendingMessages: CheckedContinuation<ApiAgentV2ThreadHydration, Error>?
    private(set) var pendingHostContext: CheckedContinuation<Void, Error>?
    private(set) var pendingRun: CheckedContinuation<ApiAgentV2RunResult, Error>?
    private(set) var pendingRetry: CheckedContinuation<ApiAgentV2RunResult?, Error>?

    init(threadId: String, title: String? = nil, icon: String? = nil, messages: [[String: Any]]? = nil, news: ApiAgentV2ThreadNewsCard? = nil) throws {
        var thread: [String: Any] = [
            "id": threadId,
            "revision": 2,
            "createdAt": "2026-10-01T00:00:00.000Z",
            "updatedAt": "2026-10-02T00:00:00.000Z",
            "lastActivityAt": "2026-10-02T00:00:00.000Z",
            "messageCount": messages?.count ?? 1
        ]
        thread["title"] = title
        thread["icon"] = icon
        if let news {
            thread["news"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(news))
        }
        hydration = try JSONDecoder().decode(
            ApiAgentV2ThreadHydration.self,
            from: JSONSerialization.data(withJSONObject: [
                "thread": thread,
                "messages": messages ?? [[
                    "id": "answer",
                    "threadId": threadId,
                    "role": "assistant",
                    "status": "complete",
                    "content": ["kind": "markdown", "text": "The selected conversation"],
                    "createdAt": "2026-10-02T00:00:00.000Z"
                ]]
            ])
        )
    }

    func consent() async throws -> Bool {
        consentCallCount += 1
        if (blocksFirstConsent && consentCallCount == 1) || blocksNextConsent {
            blocksNextConsent = false
            await withCheckedContinuation { pendingConsent = $0 }
        }
        if consentFailuresRemaining > 0 {
            consentFailuresRemaining -= 1
            throw ThreadChatClientError.unavailable
        }
        return hasConsent
    }
    func resumeConsent() {
        let continuation = pendingConsent
        pendingConsent = nil
        continuation?.resume()
    }
    func walletCore(event: WalletCoreData.Event) {
        if case .agentThreadDeleted(let threadId) = event {
            deletedThreadIds.append(threadId)
        }
    }
    func acceptConsent() async throws {
        acceptConsentCallCount += 1
        hasConsent = true
    }
    func updateHostContext(_ context: ApiAgentV2HostContext?) async throws {
        hostContextUpdateCallCount += 1
        if hostContextFailuresRemaining > 0 {
            hostContextFailuresRemaining -= 1
            throw ThreadChatClientError.unavailable
        }
        if blocksHostContext {
            try await withCheckedThrowingContinuation { pendingHostContext = $0 }
        }
        hostContextPublishedCallCount += 1
    }
    func resumeHostContext(with result: Result<Void, Error>) {
        let continuation = pendingHostContext
        pendingHostContext = nil
        continuation?.resume(with: result)
    }
    func hints() async throws -> ApiAgentV2HintsResponse { throw ThreadChatClientError.unavailable }
    func loadAvailability() async {
        availabilityRequestCount += 1
    }
    func loadUserQuota() async {
        userQuotaRequestCount += 1
    }
    func problemReportAvailability() async -> Bool {
        problemReportAvailabilityRequestCount += 1
        return isProblemReportAvailable
    }
    func setChatActive(_ isActive: Bool) async {}

    func defaultThread() async throws -> ApiAgentV2DefaultThreadResponse {
        defaultThreadCallCount += 1
        return try JSONDecoder().decode(
            ApiAgentV2DefaultThreadResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "protocolVersion": 3,
                "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(hydration.thread)),
                "created": false
            ])
        )
    }

    var threadList: ApiAgentV2ThreadListResponse?
    /// Holds the list back until `resumeThreadList()`
    var blocksThreadList = false
    private var pendingThreadList: CheckedContinuation<Void, Never>?
    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        if blocksThreadList {
            await withCheckedContinuation { pendingThreadList = $0 }
        }
        guard let threadList else { throw ThreadChatClientError.unavailable }
        return threadList
    }

    func resumeThreadList() {
        blocksThreadList = false
        pendingThreadList?.resume()
        pendingThreadList = nil
    }

    var cachedThreadItems: [ApiAgentV2ThreadListItem]?
    func cachedThreads() async -> [ApiAgentV2ThreadListItem]? { cachedThreadItems }

    func createThread() async throws -> ApiAgentV2ThreadCreateResponse { throw ThreadChatClientError.unavailable }
    func createThread(digest: ApiAgentV2ThreadDigestRequest) async throws -> ApiAgentV2ThreadCreateResponse {
        throw ThreadChatClientError.unavailable
    }

    func createThread(news: ApiAgentV2ThreadNewsRequest) async throws -> ApiAgentV2ThreadCreateResponse {
        newsThreadCreateCallCount += 1
        newsThreadRequests.append(news)
        guard blocksNewsCreation else { throw ThreadChatClientError.unavailable }
        let response = try await withCheckedThrowingContinuation { pendingNewsCreation = $0 }
        if Task.isCancelled { cancelledNewsCreationCount += 1 }
        try Task.checkCancellation()
        return response
    }

    func resumeNewsCreation(with result: Result<ApiAgentV2ThreadCreateResponse, Error>) {
        let continuation = pendingNewsCreation
        pendingNewsCreation = nil
        continuation?.resume(with: result)
    }

    func releasePendingRequests() {
        resumeCachedHistory()
        resumeConsent()
        resumeNewsCreation(with: .failure(CancellationError()))
        resumeMessages(with: .failure(CancellationError()))
        resumeHostContext(with: .failure(CancellationError()))
        resumeRun(with: .failure(CancellationError()))
        let continuation = pendingRetry
        pendingRetry = nil
        continuation?.resume(throwing: CancellationError())
    }

    func resumeRun(with result: Result<ApiAgentV2RunResult, Error>) {
        let continuation = pendingRun
        pendingRun = nil
        continuation?.resume(with: result)
    }
    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse {
        throw ThreadChatClientError.unavailable
    }
    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        deletedThreadIds.append(id)
        return try JSONDecoder().decode(
            ApiAgentV2ThreadDeleteResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "protocolVersion": 3, "threadId": id, "duplicate": false
            ])
        )
    }

    func messages(threadId: String, cursor: String?, limit: Int) async throws -> ApiAgentV2ThreadHydration {
        hydratedThreadIds.append(threadId)
        guard threadId == hydration.thread.id else { throw ThreadChatClientError.unavailable }
        if let messageError { throw messageError }
        if messageFailuresRemaining > 0 {
            messageFailuresRemaining -= 1
            throw messageFailure
        }
        if blocksMessages {
            return try await withCheckedThrowingContinuation { pendingMessages = $0 }
        }
        return hydration
    }

    func resumeMessages(with result: Result<ApiAgentV2ThreadHydration, Error>) {
        let continuation = pendingMessages
        pendingMessages = nil
        continuation?.resume(with: result)
    }

    /// Copies of other threads than this client's
    var cachedHistoriesByThreadId: [String: ApiAgentV2CachedMessages] = [:]
    func cachedMessages(threadId: String) async -> ApiAgentV2CachedMessages? {
        cachedHistoryThreadIds.append(threadId)
        if blocksCachedHistory {
            await withCheckedContinuation { pendingCachedHistory.append($0) }
        }
        return cachedHistoriesByThreadId[threadId] ?? cachedHistory
    }

    func resumeCachedHistory() {
        blocksCachedHistory = false
        let continuations = pendingCachedHistory
        pendingCachedHistory.removeAll()
        continuations.forEach { $0.resume() }
    }

    func makeClientRunId() -> String { "first-run" }
    func startRun(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult {
        hostContextPublishedCountsAtRunStart.append(hostContextPublishedCallCount)
        startedCommands.append(command)
        guard blocksRuns else { throw ThreadChatClientError.unavailable }
        let response = try await withCheckedThrowingContinuation { pendingRun = $0 }
        try Task.checkCancellation()
        return response
    }
    func retryRun(clientRunId: String) async throws -> ApiAgentV2RunResult? {
        retriedClientRunIds.append(clientRunId)
        guard blocksRetries else { return nil }
        let result = try await withCheckedThrowingContinuation { pendingRetry = $0 }
        try Task.checkCancellation()
        return result
    }
    func stopRun(threadId: String) async {}
    func clearThread(
        id: String,
        revision: Int
    ) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse> {
        clearThreadCallCount += 1
        var thread = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(hydration.thread)) as? [String: Any])
        thread["revision"] = revision + 1
        thread["messageCount"] = 0
        hydration = try JSONDecoder().decode(
            ApiAgentV2ThreadHydration.self,
            from: JSONSerialization.data(withJSONObject: ["thread": thread, "messages": []])
        )
        return try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse>.self,
            from: JSONSerialization.data(withJSONObject: [
                "ok": true,
                "value": ["protocolVersion": 3, "thread": thread, "duplicate": false]
            ])
        )
    }
    func reportProblem(threadId: String, report: ApiAgentV2ProblemReport) async throws {
        reports.append((threadId, report))
    }
    func transcribeAgentV2Audio(_ request: ApiAgentV2TranscriptionRequest) async throws -> ApiAgentV2TranscriptionResponse {
        throw ThreadChatClientError.unavailable
    }
    func setMessageFeedback(
        threadId: String,
        messageId: String,
        feedback: ApiAgentV2AnswerFeedback?
    ) async throws -> ApiAgentV2AnswerFeedback? {
        feedbackRequestCount += 1
        return feedback
    }
    func actionPresentation(messageId: String, actionId: String) async throws -> ApiAgentV2ActionPresentation {
        actionPresentationRequestCount += 1
        throw ThreadChatClientError.unavailable
    }
    private(set) var resolveActionRequestCount = 0
    func resolveAction(messageId: String, actionId: String) async throws -> ApiAgentV2ResolvedAction {
        resolveActionRequestCount += 1
        throw ThreadChatClientError.unavailable
    }
}
