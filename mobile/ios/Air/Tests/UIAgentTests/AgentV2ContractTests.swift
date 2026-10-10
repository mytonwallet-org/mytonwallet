import XCTest
import UIKit
@testable import UIAgent
import WalletContext
@testable import WalletCore
import WalletResources

final class AgentV2ContractTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testDefaultThreadOperationPreservesDecodeFailureForPresentation() async throws {
        let json = #"{"ok":false,"error":{"code":"invalid_event","retryable":false}}"#
        let result = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2DefaultThreadResponse>.self, from: Data(json.utf8)
        )
        XCTAssertFalse(result.ok)
        XCTAssertNil(result.value)
        XCTAssertEqual(result.error?.code, .invalidEvent)
        let client = FakeAgentV2Client()
        client.defaultThreadError = result.error
        let coordinator = AgentV2Coordinator(client: client)
        await coordinator.loadDefaultThread()
        XCTAssertEqual(coordinator.error, AgentV2Copy.error(.invalidEvent))
        coordinator.stop()
    }

    func testDefaultThreadDecodesTheContractThreadSummary() throws {
        let json = #"""
        {"ok":true,"value":{"protocolVersion":3,"thread":{"id":"5f0c1c1e-6a0a-4c8e-9a51-7b9d2b2f0a11","revision":4,"createdAt":"2026-09-29T10:00:00.000Z","updatedAt":"2026-09-30T04:00:00.000Z","lastActivityAt":"2026-09-30T04:00:00.000Z","messageCount":12},"created":false}}
        """#
        let result = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2DefaultThreadResponse>.self, from: Data(json.utf8)
        )
        XCTAssertEqual(result.value?.thread.id, "5f0c1c1e-6a0a-4c8e-9a51-7b9d2b2f0a11")
        XCTAssertEqual(result.value?.thread.revision, 4)
        XCTAssertEqual(result.value?.thread.messageCount, 12)
        XCTAssertNil(result.value?.thread.clearedAt)
    }

    func testAnswerLinkOpensAScreenOfTheAppButNoOtherDeeplink() throws {
        let screen = try XCTUnwrap(URL(string: "\(SELF_PROTOCOL)settings/appearance"))
        XCTAssertTrue(AgentTextLinks.isOpenable(screen))
        XCTAssertTrue(AgentTextLinks.isAppScreenLink(screen))
        XCTAssertFalse(AgentTextLinks.isOpenable(try XCTUnwrap(URL(string: "\(SELF_PROTOCOL)transfer?amount=1"))))
        XCTAssertFalse(AgentTextLinks.isOpenable(try XCTUnwrap(URL(string: "\(SELF_PROTOCOL)r/bonus"))))
        XCTAssertFalse(AgentTextLinks.isOpenable(try XCTUnwrap(URL(string: "tc://connect"))))
        XCTAssertFalse(AgentTextLinks.isAppScreenLink(try XCTUnwrap(URL(string: "https://help.mywallet.io/"))))
    }

    @MainActor
    func testInitialChatDoesNotWaitForStatusProbesAndCancelsThemOnExit() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        client.hintsResult = try initialHints()
        client.blocksStatusRefresh = true
        let root = AgentRootVC(client: client)
        let navigation = UINavigationController(rootViewController: root)
        defer {
            navigation.setViewControllers([], animated: false)
            client.resumeStatusRefresh()
        }
        root.loadViewIfNeeded()
        await waitForRequest("availability", client: client)
        await waitForRequest("userQuota", client: client)
        await waitForChat(in: navigation)
        XCTAssertTrue(navigation.topViewController is AgentVC)
        XCTAssertTrue(client.completedStatusRequests.isEmpty)

        navigation.setViewControllers([], animated: false)
        client.resumeStatusRefresh()
        for _ in 0..<100 where client.completedStatusRequests.count < 2 { await Task.yield() }
        XCTAssertEqual(client.cancelledStatusRequests, ["availability", "userQuota"])
    }

    @MainActor
    func testBackgroundPreparationBecomesReadyBeforeStatusProbesReturn() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        client.hintsResult = try initialHints()
        client.blocksStatusRefresh = true
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        var isPrepared = false
        let waiter = Task {
            await preloader.waitForPreparation()
            isPrepared = true
        }
        defer {
            preloader.setWalletReady(false)
            client.resumeStatusRefresh()
            waiter.cancel()
        }
        for _ in 0..<100 where !isPrepared { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(isPrepared)
        let model = try XCTUnwrap(preloader.takeReadyModel())
        XCTAssertEqual(model.visibleHints.map(\.id), ["learn.swap"])
        XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
        XCTAssertTrue(client.completedStatusRequests.isEmpty)

        client.resumeStatusRefresh()
        for _ in 0..<100 where client.completedStatusRequests.count < 2 { await Task.yield() }
        XCTAssertEqual(client.completedStatusRequests, ["availability", "userQuota"])
        XCTAssertTrue(client.cancelledStatusRequests.isEmpty)
    }

    @MainActor
    func testLeavingConsentSuppressesBothCancellationAndLateServiceErrors() async throws {
        for error in [CancellationError(), FakeAgentV2ClientError.unavailable] as [Error] {
            let client = FakeAgentV2Client()
            client.hasConsent = false
            client.blocksConsentAcceptance = true
            client.consentAcceptanceError = error
            var errorCount = 0
            let root = AgentRootVC(client: client, showConsentError: { errorCount += 1 })
            let home = UIViewController()
            let navigation = UINavigationController(rootViewController: home)
            navigation.pushViewController(root, animated: false)
            root.loadViewIfNeeded()
            let consent = try await waitForConsentView(in: root)
            consent.onContinue?()
            await waitForRequest("acceptConsent", client: client)
            XCTAssertFalse(consent.isUserInteractionEnabled)
            navigation.popViewController(animated: false)
            client.resumeConsentAcceptance()
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(errorCount, 0)
            XCTAssertTrue(navigation.topViewController === home)
            XCTAssertEqual(client.hydrationRequestCount, 0)
        }
    }

    @MainActor
    func testConsentCancellationAllowsRetryAndRealErrorsStillAppear() async throws {
        let client = FakeAgentV2Client()
        client.hasConsent = false
        client.consentAcceptanceError = CancellationError()
        var errorCount = 0
        let root = AgentRootVC(client: client, showConsentError: { errorCount += 1 })
        let navigation = UINavigationController(rootViewController: root)
        defer { navigation.setViewControllers([], animated: false) }
        root.loadViewIfNeeded()
        let consent = try await waitForConsentView(in: root)
        consent.onContinue?()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(errorCount, 0)
        XCTAssertTrue(consent.isUserInteractionEnabled)

        client.consentAcceptanceError = FakeAgentV2ClientError.unavailable
        consent.onContinue?()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(errorCount, 1)
        XCTAssertTrue(consent.isUserInteractionEnabled)
        XCTAssertEqual(client.requestOrder.filter { $0 == "acceptConsent" }.count, 2)
    }

    @MainActor
    private func waitForConsentView(in root: AgentRootVC) async throws -> AgentConsentView {
        for _ in 0..<100 {
            if let consent = root.view.subviews.first(where: { $0 is AgentConsentView }) as? AgentConsentView {
                return consent
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(root.view.subviews.first(where: { $0 is AgentConsentView }) as? AgentConsentView)
    }

    @MainActor
    func testPreloadedChatOpensDirectlyWithHistoryAndNoAdditionalRequests() async throws {
        let history = try decodeHydration(threadId: "thread-a", messages: [[
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Cached question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]])
        let client = FakeAgentV2Client(hydrationResult: history)
        client.hintsResult = try initialHints()
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        XCTAssertEqual(client.hydrationRequestCount, 1)
        let requests = client.requestOrder
        let controller = AgentEntryPoint.makeRootViewController(preloader: preloader)
        XCTAssertTrue(controller is AgentVC)
        controller.loadViewIfNeeded()
        XCTAssertEqual(client.requestOrder, requests)
        XCTAssertEqual(client.hydrationRequestCount, 1)
    }

    @MainActor
    func testEarlyNavigationJoinsBackgroundPreparation() async throws {
        let client = FakeAgentV2Client(
            hydrationResult: try decodeHydration(threadId: "thread-a", messages: []),
            blockedHydrationAttempt: 1
        )
        client.hintsResult = try initialHints()
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await waitForHydrationRequest(client, count: 1)
        let root = AgentEntryPoint.makeRootViewController(preloader: preloader)
        let navigation = UINavigationController(rootViewController: root)
        root.loadViewIfNeeded()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        client.resumeBlockedHydration()
        await waitForChat(in: navigation)
        XCTAssertTrue(navigation.topViewController is AgentVC)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        preloader.setWalletReady(false)
        navigation.setViewControllers([], animated: false)
    }

    @MainActor
    func testPreparedSearchQueryWaitsForNavigationAndIsSentOnce() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        AgentEntryPoint.enqueue(query: "Search question", entryPoint: nil)
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        XCTAssertTrue(client.startedCommands.isEmpty)
        let controller = AgentEntryPoint.makeRootViewController(preloader: preloader)
        XCTAssertTrue(controller is AgentVC)
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<100 where client.startedCommands.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Search question")])
        XCTAssertNil(AgentEntryPoint.consumePendingRequest())
        preloader.setWalletReady(false)
        navigation.setViewControllers([], animated: false)
    }

    @MainActor
    func testLeavingWhilePreloadingKeepsWarmHistoryButDiscardsQueuedQuery() async throws {
        let client = FakeAgentV2Client(
            hydrationResult: try decodeHydration(threadId: "thread-a", messages: []),
            blockedHydrationAttempt: 1
        )
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await waitForHydrationRequest(client, count: 1)
        let home = UIViewController()
        let navigation = UINavigationController(rootViewController: home)
        let root = AgentEntryPoint.makeRootViewController(preloader: preloader)
        AgentEntryPoint.enqueue(query: "Abandoned question", entryPoint: nil)
        navigation.pushViewController(root, animated: false)
        root.loadViewIfNeeded()
        for _ in 0..<20 { await Task.yield() }
        navigation.popViewController(animated: false)
        client.resumeBlockedHydration()
        await preloader.waitForPreparation()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(navigation.topViewController === home)
        XCTAssertNil(AgentEntryPoint.consumePendingRequest())
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertNotNil(preloader.takeReadyModel())
        XCTAssertEqual(client.hydrationRequestCount, 1)
    }

    @MainActor
    func testPreloadingDoesNotFetchHistoryWithoutConsent() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        client.hasConsent = false
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        XCTAssertNil(preloader.takeReadyModel())
        XCTAssertTrue(client.requestOrder.isEmpty)
        XCTAssertEqual(client.hydrationRequestCount, 0)
    }

    @MainActor
    func testWalletResetDiscardsInFlightPreload() async throws {
        let client = FakeAgentV2Client(
            hydrationResult: try decodeHydration(threadId: "thread-a", messages: []),
            blockedHydrationAttempt: 1
        )
        let preloader = AgentPreloader(client: client)
        preloader.setWalletReady(true)
        await waitForHydrationRequest(client, count: 1)
        let acquisition = Task { await preloader.acquireModel() }
        for _ in 0..<20 { await Task.yield() }
        preloader.walletCore(event: .accountsReset)
        client.resumeBlockedHydration()
        let acquiredModel = await acquisition.value
        XCTAssertNil(acquiredModel)
        XCTAssertNil(preloader.takeReadyModel())
        XCTAssertEqual(client.hydrationRequestCount, 1)
    }

    @MainActor
    func testClosingChatPreloadsFreshHistoryAndNeverSharesTheActiveModel() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        let first = try XCTUnwrap(preloader.takeReadyModel())
        preloader.prepare()
        await preloader.waitForPreparation()
        XCTAssertNil(preloader.takeReadyModel())
        XCTAssertEqual(client.hydrationRequestCount, 1)
        client.setHydrationResult(try decodeHydration(threadId: "thread-a", messages: [[
            "id": "new-question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "New question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]]))
        first.stop()
        first.stop()
        await preloader.waitForPreparation()
        let second = try XCTUnwrap(preloader.takeReadyModel())
        XCTAssertFalse(first === second)
        XCTAssertEqual(client.hydrationRequestCount, 2)
        XCTAssertTrue(second.itemIDs.contains { id in
            guard case .message(let message) = second.item(for: id) else { return false }
            return message.text == "New question"
        })
    }

    @MainActor
    func testExpiredOrDifferentLanguagePreloadIsRefreshed() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        var date = Date()
        var language = "en"
        let preloader = AgentPreloader(client: client, now: { date }, language: { language })
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        date = date.addingTimeInterval(301)
        XCTAssertNil(preloader.takeReadyModel())
        await preloader.waitForPreparation()
        XCTAssertEqual(client.hydrationRequestCount, 2)
        language = "es"
        XCTAssertNil(preloader.takeReadyModel())
        await preloader.waitForPreparation()
        XCTAssertEqual(client.hydrationRequestCount, 3)
        XCTAssertNotNil(preloader.takeReadyModel())
    }

    @MainActor
    func testClearedThreadInvalidatesPreparedHistory() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: [[
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Old question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]]))
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        let cleared = try decodeHydration(threadId: "thread-a", messages: [])
        client.setHydrationResult(cleared)
        preloader.walletCore(event: .agentV2(.threadChanged(threadId: "thread-a", thread: cleared.thread)))
        XCTAssertNil(preloader.takeReadyModel())
        await preloader.waitForPreparation()
        let model = try XCTUnwrap(preloader.takeReadyModel())
        XCTAssertFalse(model.itemIDs.contains { id in
            if case .message = model.item(for: id) { return true }
            return false
        })
        XCTAssertEqual(client.hydrationRequestCount, 2)
    }

    @MainActor
    func testClearingDuringSuggestionsLoadDoesNotCacheEarlierHistory() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: [[
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Old question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]]))
        client.hintsResult = try initialHints()
        client.blocksHints = true
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await waitForHydrationRequest(client, count: 1)
        for _ in 0..<20 { await Task.yield() }
        let cleared = try decodeHydration(threadId: "thread-a", messages: [])
        client.setHydrationResult(cleared)
        preloader.walletCore(event: .agentV2(.threadChanged(threadId: "thread-a", thread: cleared.thread)))
        await waitForHydrationRequest(client, count: 2)
        client.resumeHints()
        await preloader.waitForPreparation()
        let model = try XCTUnwrap(preloader.takeReadyModel())
        XCTAssertEqual(model.visibleHints.map(\.id), ["learn.swap"])
        XCTAssertEqual(client.hydrationRequestCount, 2)
        XCTAssertFalse(model.itemIDs.contains { id in
            if case .message = model.item(for: id) { return true }
            return false
        })
    }

    @MainActor
    func testSwitchingAccountsRebuildsPreparedHostContext() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        preloader.walletCore(event: .accountChanged(accountId: "different-account", isNew: false))
        XCTAssertNil(preloader.takeReadyModel())
        await preloader.waitForPreparation()
        XCTAssertNotNil(preloader.takeReadyModel())
        XCTAssertEqual(client.hostContextUpdateCount, 2)
        XCTAssertEqual(client.hydrationRequestCount, 2)
    }

    @MainActor
    func testAccountChangeDuringInitialContextPublicationRequiresRepublish() async throws {
        let client = FakeAgentV2Client(blockedHostContextAttempt: 1)
        let provider = AgentV2HostContextProvider(client: client)
        let startup = Task { await provider.start() }
        defer {
            startup.cancel()
            provider.stop()
            client.resumeBlockedHostContextUpdate()
        }
        try await waitForHostContextUpdate(client)

        provider.walletCore(event: .accountChanged(accountId: "different-account", isNew: false))
        XCTAssertFalse(provider.isAuthorityContextCurrent)
        client.resumeBlockedHostContextUpdate()

        let didStart = await startup.value
        XCTAssertTrue(didStart)
        XCTAssertEqual(client.hostContextUpdateCount, 2)
        XCTAssertTrue(provider.isAuthorityContextCurrent)
    }

    @MainActor
    func testBalanceUpdatesDuringInitialContextPublicationDoNotBlockStartup() async throws {
        let client = FakeAgentV2Client()
        let provider = AgentV2HostContextProvider(client: client)
        defer { provider.stop() }
        client.hostContextUpdateObserver = { [weak provider] count in
            guard count < 50 else { return }
            provider?.walletCore(event: .rawBalancesChanged(accountId: "account"))
        }

        let didStart = await provider.start()

        XCTAssertTrue(didStart)
        XCTAssertEqual(client.hostContextUpdateCount, 1)
        XCTAssertTrue(provider.isAuthorityContextCurrent)
        try await waitForHostContextUpdate(client, count: 2)
    }

    @MainActor
    func testStoppingDuringInitialContextPublicationDoesNotMarkContextCurrent() async throws {
        let client = FakeAgentV2Client(blockedHostContextAttempt: 1)
        let provider = AgentV2HostContextProvider(client: client)
        let startup = Task { await provider.start() }
        defer {
            startup.cancel()
            provider.stop()
            client.resumeBlockedHostContextUpdate()
        }
        try await waitForHostContextUpdate(client)

        provider.stop()
        client.resumeBlockedHostContextUpdate()

        let didStart = await startup.value
        XCTAssertFalse(didStart)
        XCTAssertFalse(provider.isAuthorityContextCurrent)
        XCTAssertEqual(client.hostContextUpdateCount, 1)
    }

    @MainActor
    func testLateInitialContextCompletionDoesNotInvalidateRestartedProvider() async throws {
        let client = FakeAgentV2Client(blockedHostContextAttempt: 1)
        let provider = AgentV2HostContextProvider(client: client)
        let firstStartup = Task { await provider.start() }
        defer {
            firstStartup.cancel()
            provider.stop()
            client.resumeBlockedHostContextUpdate()
        }
        try await waitForHostContextUpdate(client)
        provider.stop()

        let didRestart = await provider.start()
        XCTAssertTrue(didRestart)
        client.resumeBlockedHostContextUpdate()
        let didStart = await firstStartup.value
        XCTAssertFalse(didStart)
        XCTAssertTrue(provider.isAuthorityContextCurrent)
    }

    @MainActor
    func testFailedPreloadIsRetriedOnForeground() async throws {
        let client = FakeAgentV2Client()
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        preloader.setWalletReady(true)
        await preloader.waitForPreparation()
        client.setHydrationResult(try decodeHydration(threadId: "thread-a", messages: []))
        preloader.walletCore(event: .applicationWillEnterForeground)
        await preloader.waitForPreparation()
        XCTAssertNotNil(preloader.takeReadyModel())
        XCTAssertEqual(client.hydrationRequestCount, 2)
    }

    @MainActor
    func testInitialLoadPreparesHistoryBeforeTheChatIsPresented() async throws {
        let history = try decodeHydration(threadId: "thread-a", messages: [[
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Existing question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]])
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        client.hintsResult = try initialHints()
        let root = AgentRootVC(client: client)
        let navigation = UINavigationController(rootViewController: root)
        root.loadViewIfNeeded()
        await waitForHydrationRequest(client, count: 1)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertTrue(navigation.topViewController === root)

        client.resumeBlockedHydration()
        await waitForChat(in: navigation)
        XCTAssertTrue(navigation.topViewController is AgentVC)
        navigation.setViewControllers([], animated: false)

        let model = AgentV2Model(client: FakeAgentV2Client(hydrationResult: history))
        defer { model.stop() }
        await model.waitForInitialLoad()
        XCTAssertTrue(model.itemIDs.contains { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.text == "Existing question"
        })
        XCTAssertTrue(model.visibleHints.isEmpty)
        XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
    }

    @MainActor
    func testEmptyChatWaitsForInitialSuggestions() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        client.hintsResult = try initialHints()
        client.blocksHints = true
        let root = AgentRootVC(client: client)
        let navigation = UINavigationController(rootViewController: root)
        root.loadViewIfNeeded()
        await waitForHydrationRequest(client, count: 1)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertTrue(navigation.topViewController === root)
        client.resumeHints()
        await waitForChat(in: navigation)
        XCTAssertTrue(navigation.topViewController is AgentVC)
        navigation.setViewControllers([], animated: false)

        let model = AgentV2Model(client: client)
        defer { model.stop() }
        await model.waitForInitialLoad()
        XCTAssertEqual(model.visibleHints.map(\.id), ["learn.swap"])
    }

    @MainActor
    func testInitialLoadFailureFinishesLoadingAndPresentsTheError() async {
        let root = AgentRootVC(client: FakeAgentV2Client())
        let navigation = UINavigationController(rootViewController: root)
        root.loadViewIfNeeded()
        await waitForChat(in: navigation)
        XCTAssertTrue(navigation.topViewController is AgentVC)
        navigation.setViewControllers([], animated: false)

        let model = AgentV2Model(client: FakeAgentV2Client())
        defer { model.stop() }
        await model.waitForInitialLoad()
        XCTAssertFalse(model.canSendMessage(draftText: "Next question"))
        XCTAssertTrue(model.itemIDs.contains { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.text == lang("Failed to load chat")
        })
    }

    @MainActor
    func testSearchQueryIsSentOnceAfterInitialHistoryLoads() async throws {
        let client = FakeAgentV2Client(
            hydrationResult: try decodeHydration(threadId: "thread-a", messages: []),
            blockedHydrationAttempt: 1
        )
        let root = AgentRootVC(client: client)
        let navigation = UINavigationController(rootViewController: root)
        AgentEntryPoint.enqueue(query: "Search question", entryPoint: nil)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        root.loadViewIfNeeded()
        await waitForHydrationRequest(client, count: 1)
        XCTAssertTrue(client.startedCommands.isEmpty)
        client.resumeBlockedHydration()
        await waitForChat(in: navigation)
        navigation.topViewController?.loadViewIfNeeded()
        for _ in 0..<100 where client.startedCommands.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Search question")])
        XCTAssertNil(AgentEntryPoint.consumePendingRequest())
        navigation.setViewControllers([], animated: false)
    }

    @MainActor
    func testLeavingDuringInitialLoadDoesNotPresentChatOrKeepTheSearchQuery() async throws {
        let client = FakeAgentV2Client(
            hydrationResult: try decodeHydration(threadId: "thread-a", messages: []),
            blockedHydrationAttempt: 1
        )
        let home = UIViewController()
        let root = AgentRootVC(client: client)
        let navigation = UINavigationController(rootViewController: home)
        AgentEntryPoint.enqueue(query: "Search question", entryPoint: nil)
        navigation.pushViewController(root, animated: false)
        root.loadViewIfNeeded()
        await waitForHydrationRequest(client, count: 1)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        navigation.popViewController(animated: false)
        client.resumeBlockedHydration()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(navigation.topViewController === home)
        XCTAssertNil(AgentEntryPoint.consumePendingRequest())
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    private func initialHints() throws -> ApiAgentV2HintsResponse {
        try JSONDecoder().decode(ApiAgentV2HintsResponse.self, from: Data(
            #"{"protocolVersion":2,"catalogVersion":"initial","items":[{"id":"learn.swap"}]}"#.utf8
        ))
    }

    @MainActor
    private func waitForChat(in navigation: UINavigationController) async {
        for _ in 0..<100 {
            if navigation.topViewController is AgentVC { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testOperationalNoticesAndRetiredPresentationBoundary() throws {
        for code in ["agent_unavailable", "content_over_budget", "web_search_no_results"] {
            guard case .notice(let notice) = try decodeSemanticContent([
                "kind": "notice", "schemaVersion": 1, "code": code,
                "clarificationText": "Ignored optional extension"
            ]) else { return XCTFail("Expected operational notice") }
            XCTAssertFalse(AgentV2Copy.notice(notice).isEmpty)
            if code == "web_search_no_results" {
                XCTAssertEqual(
                    withMessageLanguage("en") { AgentV2Copy.notice(notice) },
                    "No matching information could be found for your request."
                )
            }
        }
        for kind in ["walletQuery", "portfolio", "assetSearch", "webDigest"] {
            guard case .clientUnsupported = try decodeSemanticContent([
                "kind": kind, "schemaVersion": 1
            ]) else { return XCTFail("Expected unsupported presentation") }
        }
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "notice", "schemaVersion": 1, "code": "consent_required"
        ]) else { return XCTFail("Domain notices must be writer text") }
    }

    @MainActor
    func testAgentSearchPreviewStripsMarkdownFormatting() {
        XCTAssertEqual(
            AgentSearchProvider.makeSearchPreviewText("I am **My Wallet** with a [guide](https://mywallet.io)."),
            "I am My Wallet with a guide."
        )
    }

    func testInlineTableSnapshotPreservesUtf16PositionAndLiteralCells() throws {
        let json = #"{"kind":"markdown","text":"🪙\n\nAfter","tables":[{"id":"t1","content":{"kind":"display","headers":["Name","Network","Address"],"rows":[["[Person](https://example.com)","ton","abcd…1234"]],"notes":[]}}],"tableReferences":[{"tableId":"t1","textOffset":4}]}"#
        let decoded = try JSONDecoder().decode(ApiAgentV2MessageContent.self, from: Data(json.utf8))
        guard case .composedMarkdown(let content) = decoded else { return XCTFail("Missing table snapshot") }
        let output = AgentV2AnswerTables.text(content.text, tables: content.tables, references: content.tableReferences)
        let blocks = AgentV2AnswerTables.blocks(content.text, tables: content.tables, references: content.tableReferences)
        XCTAssertEqual(blocks.count, 3)
        guard case .table(let table) = blocks[1] else { return XCTFail("Missing atomic table") }
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[1][0].text, "[Person](https://example.com)")
        XCTAssertTrue(table.rows[1][0].isPlainText)
        XCTAssertTrue(output.hasSuffix("After"))
        XCTAssertFalse(output.contains("[Person]("))
        let roundtrip = try JSONDecoder().decode(ApiAgentV2MessageContent.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(decoded, roundtrip)
    }

    func testReadyTableKeepsWriterLabelsAndLiteralCells() throws {
        let json = #"{"kind":"markdown","text":"","tables":[{"id":"t1","content":{"kind":"display","headers":["Актив","Количество"],"rows":[["[Token](https://example.com)","12.500000001 TON"]],"notes":[]}}],"tableReferences":[{"tableId":"t1","textOffset":0}]}"#
        let decoded = try JSONDecoder().decode(ApiAgentV2MessageContent.self, from: Data(json.utf8))
        guard case .composedMarkdown(let content) = decoded else { return XCTFail("Missing table snapshot") }
        for block in AgentV2AnswerTables.blocks(content.text, tables: content.tables, references: content.tableReferences) {
            if case .table(let table) = block {
                XCTAssertEqual(table.rows[0][0].text, "Актив")
                XCTAssertEqual(table.rows[1][0].text, "[Token](https://example.com)")
                XCTAssertEqual(table.rows[1][1].text, "12.500000001 TON")
                XCTAssertTrue(table.rows[1][0].isPlainText)
                return
            }
        }
        XCTFail("Missing ready table")
    }

    func testReadyTableDoesNotChangeSurroundingMarkdownTables() {
        let source = "| Heading |\n| --- |\n| **Formatted** |\n\n"
        let literal = "&#124; <b>Literal</b> | [Link](https://example.com)"
        let table = ApiAgentV2AnswerTable(id: "table", content: ApiAgentV2DisplayTable(
            kind: "display", headers: ["Heading"], rows: [[literal]], notes: []
        ))
        let blocks = AgentV2AnswerTables.blocks(source, tables: [table], references: [
            ApiAgentV2AnswerTableReference(tableId: table.id, textOffset: source.utf16.count)
        ])
        let markdownBlocks = AgentMessageBlockParser.parse(source)
        XCTAssertEqual(Array(blocks.dropLast()), markdownBlocks)
        guard let last = blocks.last, case .table(let rendered) = last else { return XCTFail("Missing ready table") }
        XCTAssertEqual(rendered.rows[1][0].text, literal)
        XCTAssertTrue(rendered.rows[1][0].isPlainText)
    }

    func testReadyTableWaitsForItsTextOffsetWhileStreaming() {
        let table = ApiAgentV2AnswerTable(id: "table", content: ApiAgentV2DisplayTable(
            kind: "display", headers: ["Asset"], rows: [["TON"]], notes: []
        ))
        let references = [ApiAgentV2AnswerTableReference(tableId: table.id, textOffset: 4)]
        XCTAssertEqual(
            AgentV2AnswerTables.blocks("🪙", tables: [table], references: references),
            AgentMessageBlockParser.parse("🪙")
        )
        let blocks = AgentV2AnswerTables.blocks("🪙\n\n", tables: [table], references: references)
        XCTAssertEqual(blocks.count, 2)
        guard let last = blocks.last, case .table(let rendered) = last else { return XCTFail("Missing ready table") }
        XCTAssertEqual(rendered.rows[1][0].text, "TON")
    }

    func testReadyTablesPreserveOrderAtTheSameOffsetAndNotesWithoutRows() {
        let first = ApiAgentV2AnswerTable(id: "first", content: ApiAgentV2DisplayTable(
            kind: "display", headers: ["Asset"], rows: [["TON"]], notes: []
        ))
        let second = ApiAgentV2AnswerTable(id: "second", content: ApiAgentV2DisplayTable(
            kind: "display", headers: ["Asset"], rows: [], notes: ["No matching assets"]
        ))
        let blocks = AgentV2AnswerTables.blocks("", tables: [second, first], references: [
            ApiAgentV2AnswerTableReference(tableId: first.id, textOffset: 0),
            ApiAgentV2AnswerTableReference(tableId: second.id, textOffset: 0)
        ])
        XCTAssertEqual(blocks.count, 2)
        guard let firstBlock = blocks.first, case .table(let rendered) = firstBlock else { return XCTFail("Missing first table") }
        XCTAssertEqual(rendered.rows[1][0].text, "TON")
        XCTAssertEqual(blocks.last, .text("No matching assets"))
    }

    func testHistoryUpdatesActionTitlesAndPreservesLivePresentation() {
        var live = AgentV2NativeMessage(id: "message", threadId: "thread", role: .assistant, text: "Answer")
        live.actions = [
            AgentV2NativeAction(id: "shared", kind: .send, labelCode: .openSend, title: "Open Send", presentation: .inactive),
            AgentV2NativeAction(id: "live-only", kind: .send, labelCode: .openSend, title: "Prepare another transfer", presentation: nil)
        ]
        var saved = live
        saved.actions = [
            AgentV2NativeAction(id: "shared", kind: .send, labelCode: .openSend, title: "Review transfer", presentation: nil),
            AgentV2NativeAction(id: "saved-only", kind: .receive, labelCode: .openReceive, title: "Receive tokens", presentation: nil)
        ]
        var conversation = AgentV2ConversationState()
        conversation.appendMessage(live)
        conversation.replaceMessages([saved], preservingLiveActions: true)

        let actions = conversation.messages.first?.actions ?? []
        XCTAssertEqual(actions.map(\.id), ["shared", "saved-only", "live-only"])
        XCTAssertEqual(actions.map(\.title), ["Review transfer", "Receive tokens", "Prepare another transfer"])
        XCTAssertEqual(actions.first?.presentation, .inactive)

        conversation.replaceMessages([saved])
        XCTAssertEqual(conversation.messages.first?.actions, saved.actions)
    }

    @MainActor
    func testMarketAnswerUsesStreamedMarkdownWithoutLocalFormatting() throws {
        var message = AgentV2NativeMessage(
            id: "market-answer", threadId: "thread", role: .assistant, text: "",
            responseLanguage: "ru", status: .streaming
        )
        message.appendMarkdown("**Цена**: 0.000001")
        XCTAssertEqual(AgentV2MessagePresentation.bubble(for: message)?.text, "**Цена**: 0.000001")
        message.appendMarkdown("234567 USD. Изменение: −2.75%.")
        message.finalize()
        XCTAssertEqual(
            AgentV2MessagePresentation.bubble(for: message)?.text,
            "**Цена**: 0.000001234567 USD. Изменение: −2.75%."
        )
        XCTAssertNil(message.semanticContent)
        let retiredPayloads: [[String: Any]] = [
            ["kind": "market", "schemaVersion": 1, "view": "overview"],
            ["kind": "notice", "schemaVersion": 1, "code": "market_quote"]
        ]
        for payload in retiredPayloads {
            guard case .clientUnsupported = try decodeSemanticContent(payload) else {
                return XCTFail("Removed market formats must not render")
            }
        }
    }

    func testRequiresTitleForLiveAndPersistedActions() throws {
        let json = #"{"id":"a","kind":"openDapp","labelCode":"open_external_link","requiresConfirmation":true}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ApiAgentV2ActionProposal.self, from: Data(json.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ApiAgentV2PersistedAction.self, from: Data(json.utf8)))
    }

    func testPreservesWriterActionTitles() throws {
        let json = #"{"id":"a","kind":"openDapp","labelCode":"open_external_link","title":"Открыть приложение","requiresConfirmation":true}"#
        let live = try JSONDecoder().decode(ApiAgentV2ActionProposal.self, from: Data(json.utf8))
        let saved = try JSONDecoder().decode(ApiAgentV2PersistedAction.self, from: Data(json.utf8))
        XCTAssertEqual(live.title, "Открыть приложение")
        XCTAssertEqual(saved.title, live.title)
        XCTAssertEqual(live.kind, .openDapp)
        XCTAssertTrue(live.requiresConfirmation)
    }

    func testDecodesModelOwnedFollowUpCopy() throws {
        let payloads = [
            (#"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Explain market analysis."}"#, "Explain market analysis."),
            (#"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Объясни анализ рынка."}"#, "Объясни анализ рынка."),
            (#"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}"#, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"),
        ]

        for (payload, text) in payloads {
            let followup = try JSONDecoder().decode(ApiAgentV2FollowUp.self, from: Data(payload.utf8))
            XCTAssertEqual(followup.kind, "suggested_prompt")
            XCTAssertEqual(followup.text, text)
        }
    }

    func testRejectsInvalidModelOwnedFollowUpCopy() {
        let overlongText = String(repeating: "x", count: 81)
        let payloads = [
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"deterministic","code":"prepare_send","intent":"prepare_candidate"}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":" Detailed analysis"}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Explain\nthis market analysis."}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"**Detailed analysis**"}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"\#(overlongText)"}"#,
        ]

        for payload in payloads {
            XCTAssertThrowsError(
                try JSONDecoder().decode(ApiAgentV2FollowUp.self, from: Data(payload.utf8)),
                payload
            )
        }
    }

    func testFiltersInvalidFollowUpsWithoutDroppingPersistedMessage() throws {
        let json = #"{"id":"11111111-1111-4111-8111-111111111111","threadId":"22222222-2222-4222-8222-222222222222","role":"assistant","status":"complete","content":{"kind":"markdown","text":"Still readable"},"createdAt":"2026-08-27T00:00:00.000Z","followups":[{"id":"33333333-3333-4333-8333-333333333333","kind":"deterministic","code":"prepare_send","intent":"prepare_candidate"},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Help me prepare a transfer."},{"id":"44444444-4444-4444-8444-444444444444","kind":"suggested_prompt","text":"**Invalid**"}]}"#
        let message = try JSONDecoder().decode(ApiAgentV2PersistedMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message.followups?.map(\.text), ["Help me prepare a transfer."])
        guard case .some(.markdown(let text)) = message.content else {
            return XCTFail("Expected persisted Markdown body")
        }
        XCTAssertEqual(text, "Still readable")
    }

    func testFiltersInvalidFollowUpsFromClientUpdate() throws {
        let json = #"{"kind":"followupsAvailable","clientRunId":"11111111-1111-4111-8111-111111111111","runId":"22222222-2222-4222-8222-222222222222","threadId":"33333333-3333-4333-8333-333333333333","messageId":"44444444-4444-4444-8444-444444444444","items":[{"id":"55555555-5555-4555-8555-555555555555","kind":"deterministic","code":"prepare_send","intent":"prepare_candidate"},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Help me prepare a transfer."}]}"#
        let update = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data(json.utf8))

        guard case .followupsAvailable(_, _, let items) = update else {
            return XCTFail("Expected follow-up update")
        }
        XCTAssertEqual(items.map(\.text), ["Help me prepare a transfer."])
    }

    func testCapsClientFollowUpsWithoutDroppingValidItems() throws {
        let json = #"{"kind":"followupsAvailable","clientRunId":"11111111-1111-4111-8111-111111111111","runId":"22222222-2222-4222-8222-222222222222","threadId":"33333333-3333-4333-8333-333333333333","messageId":"44444444-4444-4444-8444-444444444444","items":[{"id":"55555555-5555-4555-8555-555555555555","kind":"deterministic"},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"First prompt."},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Duplicate id."},{"id":"bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd","kind":"suggested_prompt","text":"Second prompt."},{"id":"cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd","kind":"suggested_prompt","text":"Third prompt."},{"id":"dededede-dede-4ede-8ede-dededededede","kind":"suggested_prompt","text":"Fourth prompt."}]}"#
        let update = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data(json.utf8))

        guard case .followupsAvailable(_, _, let items) = update else {
            return XCTFail("Expected follow-up update")
        }
        XCTAssertEqual(items.map(\.text), ["First prompt.", "Second prompt.", "Third prompt."])
    }

    func testDecodesMessageContentEndIndependentlyFromRunCompletion() throws {
        let json = #"{"kind":"messageContentEnded","clientRunId":"11111111-1111-4111-8111-111111111111","runId":"22222222-2222-4222-8222-222222222222","threadId":"33333333-3333-4333-8333-333333333333","messageId":"44444444-4444-4444-8444-444444444444"}"#
        let update = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data(json.utf8))

        guard case .messageContentEnded(_, let messageId) = update else {
            return XCTFail("Expected message content end update")
        }
        XCTAssertEqual(messageId, "44444444-4444-4444-8444-444444444444")
    }

    @MainActor
    func testDecodesLiveSendContract() throws {
        let action = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"sendForm","url":"mtw://send/ton:UQ-recipient?token=toncoin"}"#.utf8)
        )
        XCTAssertEqual(action.kind, .openSend)
        XCTAssertEqual(action.url, "mtw://send/ton:UQ-recipient?token=toncoin")
        XCTAssertFalse(action.isMaxAmount)

        let maxAction = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"sendForm","url":"mtw://send/ton:UQ-recipient?token=toncoin","isMaxAmount":true}"#.utf8)
        )
        XCTAssertTrue(maxAction.isMaxAmount)
        XCTAssertEqual(try JSONDecoder().decode(ApiAgentV2ResolvedAction.self, from: JSONEncoder().encode(maxAction)), maxAction)
    }

    @MainActor
    func testDecodesNativeStakeAndSwapActionContracts() throws {
        let stakeProposal = try JSONDecoder().decode(
            ApiAgentV2ActionProposal.self,
            from: Data(#"{"id":"action-stake","kind":"stake","labelCode":"open_staking","title":"Review prepared action","requiresConfirmation":false}"#.utf8)
        )
        XCTAssertEqual(stakeProposal.kind, .stake)
        XCTAssertEqual(stakeProposal.labelCode, .openStaking)

        let persistedSwap = try JSONDecoder().decode(
            ApiAgentV2PersistedAction.self,
            from: Data(#"{"id":"action-swap","kind":"swap","labelCode":"open_swap","title":"Review prepared action","requiresConfirmation":false}"#.utf8)
        )
        XCTAssertEqual(persistedSwap.kind, .swap)
        XCTAssertEqual(persistedSwap.labelCode, .openSwap)

        let staking = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openStaking","productId":"liquid","tokenSlug":"toncoin","amount":{"kind":"exact","value":"10"}}"#.utf8)
        )
        XCTAssertEqual(staking.kind, .openStaking)
        XCTAssertEqual(staking.productId, "liquid")
        XCTAssertEqual(staking.tokenSlug, "toncoin")
        XCTAssertEqual(staking.stakeAmount?.kind, .exact)
        XCTAssertEqual(staking.stakeAmount?.value, "10")

        let swap = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openSwap","tokenInSlug":"toncoin","tokenOutSlug":"usdton","amount":"10","amountSide":"source"}"#.utf8)
        )
        XCTAssertEqual(swap.kind, .openSwap)
        XCTAssertEqual(swap.tokenInSlug, "toncoin")
        XCTAssertEqual(swap.tokenOutSlug, "usdton")
        XCTAssertEqual(swap.swapAmount, "10")
        XCTAssertEqual(swap.amountSide, .source)
        let swapAssets = [
            ApiToken(slug: "toncoin", name: "Toncoin", symbol: "TON", decimals: 9, chain: .ton),
            ApiToken(slug: "usdton", name: "Tether", symbol: "USDT", decimals: 6, chain: .ton)
        ]
        let sourceParameters = try XCTUnwrap(AgentV2ActionExecutor.resolveSwapParameters(swap, swapAssets: swapAssets))
        XCTAssertEqual(sourceParameters.sellingToken, "toncoin")
        XCTAssertEqual(sourceParameters.buyingToken, "usdton")
        XCTAssertEqual(sourceParameters.sellingAmount, 10)
        XCTAssertNil(sourceParameters.buyingAmount)
        let buyAmountSwap = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openSwap","tokenInSlug":"toncoin","tokenOutSlug":"usdton","amount":"10","amountSide":"destination"}"#.utf8)
        )
        let destinationParameters = try XCTUnwrap(AgentV2ActionExecutor.resolveSwapParameters(buyAmountSwap, swapAssets: swapAssets))
        XCTAssertNil(destinationParameters.sellingAmount)
        XCTAssertEqual(destinationParameters.buyingAmount, 10)

        let dapp = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openDapp","url":"https://fragment.com/"}"#.utf8)
        )
        XCTAssertEqual(dapp.kind, .openDapp)
        XCTAssertEqual(dapp.url, "https://fragment.com/")
    }

    @MainActor
    func testSwapNavigationPreservesPartialPurchaseWithoutAnAmount() throws {
        let action = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openSwap","tokenOutSlug":"trx"}"#.utf8)
        )
        let token = ApiToken(slug: "trx", name: "TRON", symbol: "TRX", decimals: 6, chain: .tron)
        let parameters = try XCTUnwrap(AgentV2ActionExecutor.resolveSwapParameters(action, swapAssets: [token]))
        XCTAssertNil(parameters.sellingToken)
        XCTAssertEqual(parameters.buyingToken, "trx")
        XCTAssertNil(parameters.sellingAmount)
        XCTAssertNil(parameters.buyingAmount)
        XCTAssertEqual(try JSONDecoder().decode(ApiAgentV2ResolvedAction.self, from: JSONEncoder().encode(action)), action)
    }

    @MainActor
    func testSwapNavigationRejectsMalformedAmountInsteadOfOpeningABlankForm() throws {
        let token = ApiToken(slug: "trx", name: "TRON", symbol: "TRX", decimals: 6, chain: .tron)
        let payloads = [
            #"{"kind":"openSwap","tokenOutSlug":"trx","amount":"invalid","amountSide":"destination"}"#,
            #"{"kind":"openSwap","tokenOutSlug":"trx","amount":"nan","amountSide":"destination"}"#,
            #"{"kind":"openSwap","tokenOutSlug":"trx","amount":"0","amountSide":"destination"}"#,
            #"{"kind":"openSwap","tokenOutSlug":"trx","amount":"-1","amountSide":"destination"}"#,
            #"{"kind":"openSwap","tokenOutSlug":"trx","amount":"1"}"#,
            #"{"kind":"openSwap","tokenOutSlug":"trx","amount":"1","amountSide":"source"}"#,
            #"{"kind":"openSwap","tokenOutSlug":"trx","amountSide":"destination"}"#
        ]
        for payload in payloads {
            let action = try JSONDecoder().decode(ApiAgentV2ResolvedAction.self, from: Data(payload.utf8))
            XCTAssertNil(AgentV2ActionExecutor.resolveSwapParameters(action, swapAssets: [token]), payload)
        }
    }

    @MainActor
    func testSwapNavigationRejectsAnAssetRemovedFromTheCatalog() throws {
        let action = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openSwap","tokenOutSlug":"trx"}"#.utf8)
        )
        XCTAssertNil(AgentV2ActionExecutor.resolveSwapParameters(action, swapAssets: []))
        XCTAssertNil(AgentV2ActionExecutor.resolveSwapParameters(action, swapAssets: nil))
    }

    func testNativeMessagePreservesPersistedOpenDappAction() throws {
        var messageObject = persistedMessageObject(content: [
            "kind": "markdown",
            "text": "Open Fragment"
        ])
        messageObject["actions"] = [[
            "id": "action-dapp",
            "kind": "openDapp",
            "labelCode": "open_external_link",
                    "title": "Review prepared action",
            "requiresConfirmation": false
        ]]
        let persistedMessage = try JSONDecoder().decode(
            ApiAgentV2PersistedMessage.self,
            from: JSONSerialization.data(withJSONObject: messageObject)
        )

        let nativeMessage = AgentV2NativeMessage(persisted: persistedMessage)

        XCTAssertEqual(nativeMessage.actions.first?.kind.rawValue, "openDapp")
    }

    @MainActor
    func testHostHoldingUsesCurrentBalanceAsAvailableBalance() {
        let token = ApiToken(
            slug: "test-token",
            name: "Test Token",
            symbol: "TEST",
            decimals: 9,
            chain: .ton
        )
        let tokenBalance = MTokenBalance(
            tokenSlug: token.slug,
            balance: 1_234_567_890,
            isStaking: false
        )

        let holding = AgentV2HostContextProvider.makeHolding(tokenBalance: tokenBalance, token: token)

        XCTAssertEqual(holding.balance, "1.23456789")
        XCTAssertEqual(holding.availableBalance, holding.balance)
        XCTAssertEqual(holding.visibility, "visible")

        let hiddenHolding = AgentV2HostContextProvider.makeHolding(
            tokenBalance: tokenBalance,
            token: token,
            visibility: "hidden"
        )
        XCTAssertEqual(hiddenHolding.visibility, "hidden")

        let stakedHolding = AgentV2HostContextProvider.makeHolding(
            tokenBalance: MTokenBalance(tokenSlug: token.slug, balance: 1_234_567_890, isStaking: true),
            token: token
        )
        XCTAssertNil(stakedHolding.availableBalance)
    }

    @MainActor
    func testSavedAddressIdentifiersRemainStableAcrossReordering() {
        let addresses = [
            SavedAddress(name: "Mom", address: "EQ-mom", chain: .ton),
            SavedAddress(name: "Alice", address: "0x-alice", chain: .ethereum)
        ]

        let first = AgentV2HostContextProvider.makeSavedAddresses(addresses)
        let reordered = AgentV2HostContextProvider.makeSavedAddresses(Array(addresses.reversed()))

        XCTAssertEqual(first.map(\.id), ["ton:EQ-mom", "ethereum:0x-alice"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: first.map { ($0.address, $0.id) }),
            Dictionary(uniqueKeysWithValues: reordered.map { ($0.address, $0.id) })
        )
    }

    @MainActor
    func testSwapCatalogDoesNotApplyTheFormerIOSOnlyFiveHundredAssetCap() {
        let ordinary = (0..<600).map { index in
            ApiToken(
                slug: "ordinary-\(index)",
                name: "Ordinary \(index)",
                symbol: "O\(index)",
                decimals: 9,
                chain: .ton,
                tokenAddress: "token-\(index)"
            )
        }
        let tether = ApiToken(
            slug: "ton-tether",
            name: "Tether USD",
            symbol: "USD₮",
            decimals: 6,
            chain: .ton,
            tokenAddress: "tether-token",
            isPopular: true
        )

        let catalog = AgentV2HostContextProvider.makeSwapAssetCatalog(
            tokens: ordinary + [tether]
        )

        XCTAssertEqual(catalog?.count, 601)
        XCTAssertTrue(catalog?.contains(where: { $0.slug == tether.slug }) == true)
    }

    func testHydratedMarkdownMessageUsesTheContentUnion() throws {
        let source = "Wallet **warning:** keep TON for fees."
        let persisted = try decodePersistedMessage(content: [
            "kind": "markdown",
            "text": source
        ])

        let message = AgentV2NativeMessage(persisted: persisted)

        XCTAssertEqual(message.contentKind, .markdown)
        XCTAssertEqual(message.text, source)
        XCTAssertNil(message.semanticContent)
    }

    func testHydratedAssistantMessageKeepsItsOwnResponseLanguage() throws {
        var object = persistedMessageObject(content: [
            "kind": "semantic",
            "content": ["kind": "notice", "schemaVersion": 1, "code": "content_over_budget"],
        ])
        object["responseLanguage"] = "ru"
        let persisted = try JSONDecoder().decode(
            ApiAgentV2PersistedMessage.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(persisted.responseLanguage, "ru")
        XCTAssertEqual(AgentV2NativeMessage(persisted: persisted).responseLanguage, "ru")
        guard case .semantic(let semantic)? = persisted.content,
              case .notice(let notice) = semantic
        else { return XCTFail("Expected localized notice") }
        XCTAssertEqual(
            withMessageLanguage(persisted.responseLanguage) {
                AgentV2Copy.notice(notice)
            },
            "Результат слишком большой для полного отображения."
        )
    }

    func testUnsupportedPersistedResponseLanguageFallsBackToTheInterfaceLanguage() throws {
        var object = persistedMessageObject(content: ["kind": "markdown", "text": "こんにちは"])
        object["responseLanguage"] = "ja"
        let persisted = try JSONDecoder().decode(
            ApiAgentV2PersistedMessage.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(persisted.responseLanguage, "ja")
        XCTAssertNil(supportedMessageLanguageCode(persisted.responseLanguage))
        XCTAssertEqual(
            withMessageLanguage(persisted.responseLanguage) { lang("$agent_error_generic") },
            lang("$agent_error_generic")
        )
    }

    func testRemovedPersistedPresentationFieldsFailClosed() throws {
        for field in ["text", "textFormat", "widget"] {
            var object = persistedMessageObject(content: ["kind": "markdown", "text": "Current"])
            object[field] = field == "widget" ? ["kind": "removedWidget"] : "legacy"
            let data = try JSONSerialization.data(withJSONObject: object)

            XCTAssertThrowsError(
                try JSONDecoder().decode(ApiAgentV2PersistedMessage.self, from: data),
                "Expected removed field \(field) to fail closed"
            )
        }
    }

    @MainActor
    func testAgentMarkdownV1RendersRestrainedInlineAndListSyntax() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "Wallet **warning:** keep `GRAM` for fees.\n- First item\n- Second *item*\n1. Verify\n2) Review",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(
            rendered.string,
            "Wallet warning: keep GRAM for fees.\n•\tFirst item\n•\tSecond item\n1.\tVerify\n2.\tReview"
        )
    }

    @MainActor
    func testAgentMarkdownV1RendersEscapedPunctuationAsLiteralText() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            #"Daily changes: \+1\.62% and \-2\.01%. Escaped \*\*literal\*\*."#,
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(
            rendered.string,
            "Daily changes: +1.62% and -2.01%. Escaped **literal**."
        )
    }

    @MainActor
    func testAgentMarkdownV1KeepsLinksPassiveAndUnsupportedBlocksReadable() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "# Heading\n> Quote\n**unfinished\n[Source](https://example.com/path_with_value)\n[Receive](mtw://receive)",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(
            rendered.string,
            "# Heading\n> Quote\n**unfinished\nSource (https://example.com/path_with_value)\nReceive"
        )
        let fullRange = NSRange(location: 0, length: rendered.length)
        var containsLink = false
        rendered.enumerateAttribute(.link, in: fullRange) { value, _, stop in
            if value != nil {
                containsLink = true
                stop.pointee = true
            }
        }
        XCTAssertFalse(containsLink)
    }

    func testAnswerLinksDecodeFromHistoryAndLiveUpdates() throws {
        let content = try JSONDecoder().decode(ApiAgentV2MessageContent.self, from: Data(
            #"{"kind":"markdown","text":"See Help","links":[{"textOffset":4,"textLength":4,"url":"https://help.mywallet.io/"}]}"#.utf8
        ))
        guard case .composedMarkdown(let markdown) = content else { return XCTFail("Missing links") }
        XCTAssertEqual(markdown.links, [ApiAgentV2AnswerLink(textOffset: 4, textLength: 4, url: "https://help.mywallet.io/")])
        XCTAssertEqual(try JSONDecoder().decode(ApiAgentV2MessageContent.self, from: JSONEncoder().encode(content)), content)

        let update = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data(
            #"{"kind":"answerLinkAdded","clientRunId":"c","runId":"r","threadId":"t","messageId":"m","link":{"textOffset":0,"textLength":4,"url":"https://ton.org/"}}"#.utf8
        ))
        guard case .answerLinkAdded(_, let messageId, let link) = update else { return XCTFail("Missing link update") }
        XCTAssertEqual(messageId, "m")
        XCTAssertEqual(link.url, "https://ton.org/")
    }

    @MainActor
    func testAnswerLinksStyleTheirLabelsWithoutChangingTheRenderedText() {
        let source = "- **Guide** and Docs"
        let links = [
            ApiAgentV2AnswerLink(textOffset: 2, textLength: 9, url: "https://help.mywallet.io/guide?a=1&b=*_*"),
            ApiAgentV2AnswerLink(textOffset: 16, textLength: 4, url: "http://docs.example.com/"),
            ApiAgentV2AnswerLink(textOffset: 18, textLength: 9, url: "https://past.example.com/"),
        ]
        let marked = AgentV2AnswerTables.text(source, tables: [], references: [], links: links)
        let plain = AgentMessageTextRenderer.makeAttributedText(
            source, textColor: .label, rendersMarkdown: true, detectsLinks: false, markdownProfile: .agentMarkdownV1
        )
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            marked, textColor: .label, rendersMarkdown: true, detectsLinks: false, markdownProfile: .agentMarkdownV1,
            linkColor: .systemRed
        )

        XCTAssertEqual(rendered.string, plain.string)
        let guideRange = (rendered.string as NSString).range(of: "Guide")
        var effectiveRange = NSRange()
        XCTAssertEqual(
            rendered.attribute(.link, at: guideRange.location, effectiveRange: &effectiveRange) as? URL,
            URL(string: "https://help.mywallet.io/guide?a=1&b=*_*")
        )
        XCTAssertEqual(effectiveRange, guideRange)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: guideRange.location, effectiveRange: nil) as? UIColor, .systemRed)
        XCTAssertNil(rendered.attribute(.link, at: (rendered.string as NSString).range(of: "Docs").location, effectiveRange: nil))
        XCTAssertEqual(AgentTextLinks.copyText(marked), "- **Guide** (https://help.mywallet.io/guide?a=1&b=*_*) and Docs")
    }

    @MainActor
    func testAnswerLinkMarkerCarriesANonAsciiURL() {
        let url = "https://ru.wikipedia.org/wiki/Тон"
        let marked = AgentV2AnswerTables.text("Тон", tables: [], references: [], links: [
            ApiAgentV2AnswerLink(textOffset: 0, textLength: 3, url: url)
        ])
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            marked, textColor: .label, rendersMarkdown: true, detectsLinks: false, markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(rendered.string, "Тон")
        XCTAssertNotNil(rendered.attribute(.link, at: 0, effectiveRange: nil))
        XCTAssertEqual(AgentTextLinks.copyText(marked), "Тон (\(URL(string: url)!.absoluteString))")
    }

    func testAnswerLinksKeepTablePlacementAndSkipALinkAcrossATable() {
        let source = "See Help\n\nAfter Docs"
        let table = ApiAgentV2AnswerTable(id: "t1", content: ApiAgentV2DisplayTable(
            kind: "display", headers: ["Asset"], rows: [["TON"]], notes: []
        ))
        let references = [ApiAgentV2AnswerTableReference(tableId: table.id, textOffset: 10)]
        let blocks = AgentV2AnswerTables.blocks(source, tables: [table], references: references, links: [
            ApiAgentV2AnswerLink(textOffset: 4, textLength: 4, url: "https://help.mywallet.io/"),
            ApiAgentV2AnswerLink(textOffset: 9, textLength: 3, url: "https://across.example.com/"),
            ApiAgentV2AnswerLink(textOffset: 16, textLength: 4, url: "https://docs.example.com/"),
        ])

        XCTAssertEqual(blocks.count, 3)
        guard case .text(let before) = blocks[0], case .table = blocks[1], case .text(let after) = blocks[2] else {
            return XCTFail("Unexpected blocks")
        }
        XCTAssertEqual(AgentTextLinks.copyText(before), "See Help (https://help.mywallet.io/)")
        XCTAssertEqual(AgentTextLinks.copyText(after), "After Docs (https://docs.example.com/)")
    }

    @MainActor
    func testAgentMarkdownV1RendersTaggedFencedCodeWithoutMarkers() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "```javascript\nconst safe = true;\n```",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(rendered.string, "const safe = true;")
    }

    @MainActor
    func testAgentMarkdownV1KeepsUntaggedFencesReadable() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "```\nconst safe = true;\n```",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(rendered.string, "```\nconst safe = true;\n```")
    }

    func testDecodesBoundTextDelta() throws {
        let data = Data(#"""
        {
          "type":"agentV2",
          "update":{
            "kind":"textDelta",
            "clientRunId":"client-run",
            "runId":"run-1",
            "threadId":"thread-1",
            "messageId":"message-1",
            "delta":"Hello"
          }
        }
        """#.utf8)

        let envelope = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data)
        guard case .textDelta(let bound, let messageId, let delta) = envelope.update else {
            return XCTFail("Expected text delta")
        }
        XCTAssertEqual(bound.threadId, "thread-1")
        XCTAssertEqual(messageId, "message-1")
        XCTAssertEqual(delta, "Hello")
    }

    @MainActor
    func testChatActivityFollowsTheScreenTheAppAndEachNewSdkRuntime() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: []))
        let coordinator = AgentV2Coordinator(client: client)
        let runtimeReady = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"runtimeReady","generation":2}}"#.utf8)
        ).update

        coordinator.setChatVisible(true)
        coordinator.walletCore(event: .agentV2(runtimeReady))
        coordinator.walletCore(event: .applicationDidEnterBackground)
        coordinator.walletCore(event: .applicationWillEnterForeground)
        coordinator.setChatVisible(false)
        coordinator.walletCore(event: .agentV2(runtimeReady))
        coordinator.setChatVisible(true)
        coordinator.stop()
        for _ in 0..<100 where client.chatActivity.count < 7 {
            await Task.yield()
        }

        XCTAssertEqual(client.chatActivity, [true, true, false, true, false, true, false])
    }

    func testDecodesRuntimeReadyAndToolActivityUpdates() throws {
        let ready = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"runtimeReady","generation":7}}"#.utf8)
        )
        guard case .runtimeReady(let generation) = ready.update else {
            return XCTFail("Expected runtime-ready update")
        }
        XCTAssertEqual(generation, 7)

        let activity = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"""
            {
              "type":"agentV2",
              "update":{
                "kind":"toolActivityChanged",
                "clientRunId":"client-run",
                "runId":"run-1",
                "threadId":"thread-1",
                "toolCallId":"tool-call-1",
                "toolName":"wallet.data.query",
                "operation":"positions.list",
                "status":"complete"
              }
            }
            """#.utf8)
        )
        guard case .toolActivityChanged(
            let bound,
            let toolCallId,
            let toolName,
            let operation,
            let status
        ) = activity.update else {
            return XCTFail("Expected tool-activity update")
        }
        XCTAssertEqual(bound.threadId, "thread-1")
        XCTAssertEqual(toolCallId, "tool-call-1")
        XCTAssertEqual(toolName, "wallet.data.query")
        XCTAssertEqual(operation, "positions.list")
        XCTAssertEqual(status, "complete")
    }

    func testDecodesRunActivityUpdate() throws {
        let update = try decodeRunActivityUpdate(threadId: "thread-1")

        guard case .runActivityChanged(let bound, let event) = update else {
            return XCTFail("Expected run-activity update")
        }
        XCTAssertEqual(bound.threadId, "thread-1")
        XCTAssertEqual(event.protocolVersion, 2)
        XCTAssertEqual(event.sequence, 3)
        XCTAssertEqual(event.code, .webReadingSources)
        XCTAssertEqual(event.status, .completed)
        XCTAssertEqual(event.detail?.kind, .sourceCount)
        XCTAssertEqual(event.detail?.count, 4)
    }

    func testDecodesAvailabilityAndQuotaUpdates() throws {
        let availabilityEnvelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"availabilityChanged","availability":{"state":"capacity_exhausted","resetAt":1787752800000}}}"#.utf8)
        )
        guard case .availabilityChanged(let availability) = availabilityEnvelope.update else {
            return XCTFail("Expected availability update")
        }
        XCTAssertEqual(availability.state, .capacityExhausted)
        XCTAssertEqual(availability.resetAt, 1_787_752_800_000)

        let quotaEnvelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"userQuotaChanged","quota":{"limit":100,"used":100,"remaining":0,"resetAt":"2099-08-27T00:00:00.000Z"}}}"#.utf8)
        )
        guard case .userQuotaChanged(let quota) = quotaEnvelope.update else {
            return XCTFail("Expected user-quota update")
        }
        XCTAssertEqual(quota?.limit, 100)
        XCTAssertEqual(quota?.remaining, 0)

        let clearedQuotaEnvelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"userQuotaChanged"}}"#.utf8)
        )
        guard case .userQuotaChanged(nil) = clearedQuotaEnvelope.update else {
            return XCTFail("Expected cleared user-quota update")
        }
    }

    func testRunFailurePreservesRetryBinding() throws {
        let envelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"runFailed","clientRunId":"client-1","threadId":"thread-1","messageId":"message-1","code":"user_quota_exhausted","retryable":true,"resetAt":1787752800000}}"#.utf8)
        )
        guard case .runFailed(
            _,
            let clientRunId,
            let threadId,
            let messageId,
            let code,
            let retryable,
            let resetAt
        ) = envelope.update else {
            return XCTFail("Expected run failure")
        }
        XCTAssertEqual(clientRunId, "client-1")
        XCTAssertEqual(threadId, "thread-1")
        XCTAssertEqual(messageId, "message-1")
        XCTAssertEqual(code, .userQuotaExhausted)
        XCTAssertTrue(retryable)
        XCTAssertEqual(resetAt, 1_787_752_800_000)
    }

    func testDecodesAgentPortfolioHistoryUpdate() throws {
        let data = Data(#"{"type":"agentV2PortfolioHistory","accountId":"account-1","baseCurrency":"USD","range":"1D","fetchedAtSlot":7,"netWorth":{"status":"ok","datasets":[],"base":"USD","density":"5m"}}"#.utf8)
        let update = try JSONDecoder().decode(ApiAgentV2PortfolioHistoryUpdate.self, from: data)

        XCTAssertEqual(update.type, .portfolioHistory)
        XCTAssertEqual(update.accountId, "account-1")
        XCTAssertEqual(update.range, .day)
        XCTAssertEqual(update.fetchedAtSlot, 7)
    }

    func testRejectsUnknownUpdateKind() {
        let data = Data(#"{"type":"agentV2","update":{"kind":"futureUpdate"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data))
    }

    @MainActor
    func testUnsupportedSemanticExtensionsUseLocalFallbackAndKnownMalformedContentFailsClosed() throws {
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "clientUnsupported", "schemaVersion": 1
        ]) else {
            return XCTFail("Expected local unsupported semantic placeholder")
        }
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "futureContent", "schemaVersion": 1
        ]) else {
            return XCTFail("Expected unknown semantic kind fallback")
        }
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "notice", "schemaVersion": 2, "code": "empty_result"
        ]) else {
            return XCTFail("Expected unknown semantic version fallback")
        }
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "notice", "schemaVersion": 1, "code": "future_notice"
        ]) else {
            return XCTFail("Expected unknown notice code fallback")
        }
        XCTAssertThrowsError(try decodeSemanticContent([
            "kind": "notice",
            "schemaVersion": 1,
            "code": 42
        ]))

        let removedEvent = try JSONSerialization.data(withJSONObject: [
            "type": "agentV2",
            "update": ["kind": "widgetAvailable", "widget": ["kind": "removedWidget"]]
        ])
        XCTAssertThrowsError(try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: removedEvent))
    }

    func testRunStartedPreservesCanonicalInputMessageId() throws {
        let envelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"runStarted","clientRunId":"client-1","runId":"run-1","threadId":"thread-1","threadRevision":2,"inputMessageId":"message-1"}}"#.utf8)
        )
        guard case .runStarted(_, _, let inputMessageId) = envelope.update else {
            return XCTFail("Expected run start")
        }

        XCTAssertEqual(inputMessageId, "message-1")
    }

    func testRejectsUnknownWalletPresentationKinds() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openArbitraryRoute"}"#.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2ActionPresentation.self,
            from: Data(#"{"kind":"futurePresentation"}"#.utf8)
        ))
    }

    func testActionPresentationRejectsIncompleteSendState() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2ActionPresentation.self,
            from: Data(#"{"kind":"send","status":"active"}"#.utf8)
        ))
    }

    func testSendNavigationPreservesAtomicAmountInURL() throws {
        let data = Data(#"{"kind":"sendForm","url":"mtw://send/ton:UQ-recipient?token=toncoin&amount=1250000000&text=hello"}"#.utf8)
        let action = try JSONDecoder().decode(ApiAgentV2ResolvedAction.self, from: data)
        XCTAssertEqual(action.kind, .openSend)
        XCTAssertEqual(action.url, "mtw://send/ton:UQ-recipient?token=toncoin&amount=1250000000&text=hello")
        XCTAssertEqual(try JSONDecoder().decode(ApiAgentV2ResolvedAction.self, from: JSONEncoder().encode(action)), action)
    }

    @MainActor
    func testCoordinatorPreservesLiveOpenDappAction() async throws {
        let coordinator = AgentV2Coordinator(client: FakeAgentV2Client(defaultThreadId: "thread-a"))
        await coordinator.loadDefaultThread()
        coordinator.walletCore(event: .agentV2(try decodeUpdate(
            kind: "messageStarted",
            threadId: "thread-a",
            messageId: "message-a"
        )))
        coordinator.walletCore(event: .agentV2(try decodeOpenDappActionUpdate(
            threadId: "thread-a",
            messageId: "message-a"
        )))

        XCTAssertEqual(coordinator.messages.first?.actions.first?.kind.rawValue, "openDapp")
    }

    @MainActor
    func testWalletAuthorityUpdatePreservesOnlySelectionRuns() async throws {
        for preservesActiveRuns in [true, false, nil] as [Bool?] {
            let coordinator = AgentV2Coordinator(client: FakeAgentV2Client())
            defer { coordinator.stop() }
            await coordinator.loadDefaultThread()
            coordinator.send(input: .append(text: "Start response"))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "messageStarted", threadId: "thread-a", messageId: "message-a"
            )))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "textDelta", threadId: "thread-a", messageId: "message-a", delta: "Before"
            )))
            var authorityUpdate: [String: Any] = ["kind": "walletAuthorityChanged"]
            if let preservesActiveRuns { authorityUpdate["preservesActiveRuns"] = preservesActiveRuns }
            coordinator.walletCore(event: .agentV2(try JSONDecoder().decode(
                ApiAgentV2ClientUpdate.self,
                from: JSONSerialization.data(withJSONObject: authorityUpdate)
            )))

            let shouldContinue = preservesActiveRuns == true
            XCTAssertEqual(coordinator.activeRun?.isRunning, shouldContinue)
            XCTAssertEqual(coordinator.messages.first?.status, shouldContinue ? .streaming : .cancelled)
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "textDelta", threadId: "thread-a", messageId: "message-a", delta: " after"
            )))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "messageCompleted", threadId: "thread-a", messageId: "message-a"
            )))
            XCTAssertEqual(coordinator.messages.first?.text, shouldContinue ? "Before after" : "Before")
            XCTAssertEqual(coordinator.messages.first?.status, shouldContinue ? .complete : .cancelled)
        }
    }

    @MainActor
    func testPostRunHydrationPreservesLiveSendFormAction() async throws {
        let initialHydration = try decodeHydration(threadId: "thread-a", messages: [])
        let completedHydration = try decodeHydration(threadId: "thread-a", messages: [[
            "id": "message-a",
            "threadId": "thread-a",
            "role": "assistant",
            "status": "complete",
            "content": [
                "kind": "markdown",
                "text": "The transfer form is ready."
            ],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]])
        let client = FakeAgentV2Client(
            hydrationResult: initialHydration,
            hydrationResults: [initialHydration, completedHydration],
            shouldCompleteRun: true
        )
        let coordinator = AgentV2Coordinator(client: client)
        let messageStarted = try decodeUpdate(
            kind: "messageStarted",
            threadId: "thread-a",
            messageId: "message-a",
            contentKind: .markdown
        )
        let sendFormAction = try decodeSendFormActionUpdate(
            threadId: "thread-a",
            messageId: "message-a"
        )
        let messageCompleted = try decodeUpdate(
            kind: "messageCompleted",
            threadId: "thread-a",
            messageId: "message-a"
        )
        await coordinator.loadDefaultThread()
        client.startRunObserver = {
            coordinator.walletCore(event: .agentV2(messageStarted))
            coordinator.walletCore(event: .agentV2(sendFormAction))
            coordinator.walletCore(event: .agentV2(messageCompleted))
        }

        coordinator.send(input: .append(text: "Open Send"))
        await waitForHydrationRequest(client, count: 2)
        for _ in 0..<100 where coordinator.activeRun?.isRunning == true {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.messages.first?.actions.first?.labelCode, .openSend)
    }

    @MainActor
    func testProblemReportIsOfferedWhileTheServerTakesItAndNamesTheAnswerOrTheConversation() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: [
            [
                "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
                "content": ["kind": "markdown", "text": "What is my balance?"],
                "createdAt": "2026-07-22T00:00:01.000Z"
            ],
            [
                "id": "answer", "threadId": "thread-a", "role": "assistant", "status": "complete",
                "content": ["kind": "markdown", "text": "You hold 5 TON."],
                "createdAt": "2026-07-22T00:00:02.000Z"
            ]
        ]))
        client.isProblemReportAvailable = false
        let model = AgentV2Model(client: client)
        defer { model.stop() }
        await model.waitForInitialLoad()
        await waitForProblemReportAvailabilityRequest(client, count: 1)
        XCTAssertFalse(model.canReportProblem)

        client.isProblemReportAvailable = true
        model.isActive = true
        await waitForProblemReportAvailabilityRequest(client, count: 2)
        for _ in 0..<100 where !model.canReportProblem {
            await Task.yield()
        }
        let answerID = try XCTUnwrap(model.itemIDs.first { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.role == .assistant
        })
        XCTAssertTrue(model.canReportProblem)

        let didReportAnswer = await model.reportProblem(messageID: answerID, comment: "Wrong balance")
        let didReportConversation = await model.reportProblem(messageID: nil, comment: nil)
        let didReportUnknownAnswer = await model.reportProblem(messageID: UUID(), comment: nil)

        XCTAssertTrue(didReportAnswer)
        XCTAssertTrue(didReportConversation)
        XCTAssertFalse(didReportUnknownAnswer)
        XCTAssertEqual(client.problemReports.map(\.threadId), ["thread-a", "thread-a"])
        XCTAssertEqual(client.problemReports.map(\.report), [
            ApiAgentV2ProblemReport(messageId: "answer", comment: "Wrong balance"),
            ApiAgentV2ProblemReport(messageId: nil, comment: nil)
        ])
    }

    @MainActor
    func testFailedAnswerShowsItsErrorOnceWithoutAStatusRow() async throws {
        let initialHydration = try decodeHydration(threadId: "thread-a", messages: [])
        let failedHydration = try decodeHydration(threadId: "thread-a", messages: [[
            "id": "message-a",
            "threadId": "thread-a",
            "role": "assistant",
            "status": "error",
            "error": ["code": "internal_error", "retryable": false],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]])
        let client = FakeAgentV2Client(
            hydrationResult: initialHydration,
            hydrationResults: [initialHydration, failedHydration],
            shouldCompleteRun: true
        )
        client.runResultState = .failed
        let coordinator = AgentV2Coordinator(client: client)
        let messageStarted = try decodeUpdate(kind: "messageStarted", threadId: "thread-a", messageId: "message-a")
        let runFailed = try decodeUpdate(
            kind: "runFailed",
            threadId: "thread-a",
            messageId: "message-a",
            code: .internalError
        )
        await coordinator.loadDefaultThread()
        client.startRunObserver = {
            coordinator.walletCore(event: .agentV2(messageStarted))
            coordinator.walletCore(event: .agentV2(runFailed))
            XCTAssertNil(coordinator.error)
            XCTAssertEqual(coordinator.messages.last?.error?.code, .internalError)
        }

        coordinator.send(input: .append(text: "Send 10 to Mom"))
        await waitForHydrationRequest(client, count: 2)
        for _ in 0..<100 where coordinator.messages.last?.status != .error || coordinator.messages.count != 1 {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.messages.map(\.id), ["message-a"])
        XCTAssertEqual(coordinator.messages.first?.error?.code, .internalError)
        XCTAssertNil(coordinator.error)
    }

    private func decodeUpdate(
        kind: String,
        threadId: String,
        messageId: String,
        delta: String? = nil,
        contentKind: ApiAgentV2ContentKind = .markdown,
        code: ApiAgentV2ErrorCode? = nil
    ) throws -> ApiAgentV2ClientUpdate {
        var update: [String: Any] = [
            "kind": kind,
            "clientRunId": "client-\(threadId)",
            "runId": "run-\(threadId)",
            "threadId": threadId,
            "messageId": messageId
        ]
        if let delta { update["delta"] = delta }
        if kind == "messageStarted" { update["contentKind"] = contentKind.rawValue }
        if kind == "messageCompleted" { update["finishReason"] = "complete" }
        if let code {
            update["code"] = code.rawValue
            update["retryable"] = false
        }
        let data = try JSONSerialization.data(withJSONObject: ["type": "agentV2", "update": update])
        return try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data).update
    }

    private func decodeSendFormActionUpdate(threadId: String, messageId: String) throws -> ApiAgentV2ClientUpdate {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "agentV2",
            "update": [
                "kind": "actionAvailable",
                "clientRunId": "client-\(threadId)",
                "runId": "run-\(threadId)",
                "threadId": threadId,
                "messageId": messageId,
                "action": [
                    "id": "action-send-form",
                    "kind": "send",
                    "labelCode": "open_send",
                    "title": "Review prepared action",
                    "effect": "open_send",
                    "requiresConfirmation": false
                ]
            ]
        ])
        return try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data).update
    }

    private func decodeOpenDappActionUpdate(threadId: String, messageId: String) throws -> ApiAgentV2ClientUpdate {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "agentV2",
            "update": [
                "kind": "actionAvailable",
                "clientRunId": "client-\(threadId)",
                "runId": "run-\(threadId)",
                "threadId": threadId,
                "messageId": messageId,
                "action": [
                    "id": "action-dapp",
                    "kind": "openDapp",
                    "labelCode": "open_external_link",
                    "title": "Review prepared action",
                    "requiresConfirmation": false
                ]
            ]
        ])
        return try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data).update
    }

    private func decodeRunActivityUpdate(threadId: String) throws -> ApiAgentV2ClientUpdate {
        let runId = "run-\(threadId)"
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "agentV2",
            "update": [
                "kind": "runActivityChanged",
                "clientRunId": "client-\(threadId)",
                "runId": runId,
                "threadId": threadId,
                "event": [
                    "type": "run_activity",
                    "protocolVersion": 2,
                    "runId": runId,
                    "sequence": 3,
                    "code": "web.reading_sources",
                    "status": "completed",
                    "detail": ["kind": "source_count", "count": 4]
                ]
            ]
        ])
        return try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data).update
    }

    private func decodeHydration(
        threadId: String,
        messages: [[String: Any]],
        nextCursor: String? = nil
    ) throws -> ApiAgentV2ThreadHydration {
        var hydration: [String: Any] = [
            "thread": [
                "id": threadId,
                "revision": 2,
                "createdAt": "2026-07-22T00:00:00.000Z",
                "updatedAt": "2026-07-22T00:00:01.000Z",
                "lastActivityAt": "2026-07-22T00:00:01.000Z",
                "messageCount": messages.count
            ],
            "messages": messages
        ]
        hydration["nextCursor"] = nextCursor
        let data = try JSONSerialization.data(withJSONObject: hydration)
        return try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: data)
    }

    private func decodeSemanticContent(_ object: [String: Any]) throws -> ApiAgentV2SemanticContent {
        try JSONDecoder().decode(
            ApiAgentV2SemanticContent.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func decodeSendPresentation(accountLabel: String) throws -> ApiAgentV2ActionPresentation {
        try JSONDecoder().decode(
            ApiAgentV2ActionPresentation.self,
            from: JSONSerialization.data(withJSONObject: [
                "kind": "send",
                "status": "active",
                "network": "ton",
                "accountLabel": accountLabel,
                "recipient": ["kind": "external"],
                "feeStatus": "calculated_in_wallet",
                "warningCodes": []
            ])
        )
    }

    private func decodePersistedMessage(content: [String: Any]) throws -> ApiAgentV2PersistedMessage {
        try JSONDecoder().decode(
            ApiAgentV2PersistedMessage.self,
            from: JSONSerialization.data(withJSONObject: persistedMessageObject(content: content))
        )
    }

    private func persistedMessageObject(
        content: [String: Any],
        messageId: String = "message-1",
        threadId: String = "thread-1"
    ) -> [String: Any] {
        [
            "id": messageId,
            "threadId": threadId,
            "role": "assistant",
            "status": "complete",
            "content": content,
            "createdAt": "2026-07-31T12:00:00.000Z"
        ]
    }
    @MainActor
    private func waitForHostContextUpdate(_ client: FakeAgentV2Client, count: Int = 1) async throws {
        for _ in 0..<100 {
            guard client.hostContextUpdateCount < count else { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for host context publication")
        throw FakeAgentV2ClientError.unavailable
    }

    @MainActor
    private func waitForActionPresentationRequest(_ client: FakeAgentV2Client, count: Int = 1) async {
        for _ in 0..<100 {
            guard client.actionPresentationRequestCount < count else { return }
            await Task.yield()
        }
    }

    @MainActor
    private func waitForHydrationRequest(_ client: FakeAgentV2Client, count: Int) async {
        for _ in 0..<100 {
            guard client.hydrationRequestCount < count else { return }
            await Task.yield()
        }
    }

    @MainActor
    private func waitForProblemReportAvailabilityRequest(_ client: FakeAgentV2Client, count: Int) async {
        for _ in 0..<100 {
            guard client.problemReportAvailabilityRequestCount < count else { return }
            await Task.yield()
        }
    }

    @MainActor
    private func waitForRequest(_ request: String, client: FakeAgentV2Client) async {
        for _ in 0..<100 {
            guard !client.requestOrder.contains(request) else { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class AgentV2RunActivityProbe {
    var isActive = false
}

@MainActor
private final class AgentV2CoordinatorObserverSpy: AgentV2CoordinatorObserver {
    private(set) var changes: [AgentV2CoordinatorChange] = []

    func agentV2CoordinatorDidChange(_ coordinator: AgentV2Coordinator, change: AgentV2CoordinatorChange) {
        changes.append(change)
    }
}

private enum FakeAgentV2ClientError: Error {
    case unavailable
}

@MainActor
private final class FakeAgentV2Client: AgentV2Client {
    var defaultThreadError: ApiAgentV2MutationError?
    var hintsResult: ApiAgentV2HintsResponse?
    var blocksHints = false
    private var hintsContinuations: [CheckedContinuation<Void, Never>] = []
    private let defaultThreadId: String
    private let actionPresentationResults: [ApiAgentV2ActionPresentation]
    private let hydrationResults: [ApiAgentV2ThreadHydration]
    private var hydrationResult: ApiAgentV2ThreadHydration?
    private let shouldCompleteRun: Bool
    private let retryResultState: ApiAgentV2RunResultState?
    private let blockedHostContextAttempt: Int?
    private let blockedHydrationAttempt: Int?
    private let blockedActionPresentationAttempt: Int?
    private var hostContextFailuresRemaining: Int
    private var hostContextFailureAttempts: Set<Int>
    private var blockedHostContextContinuation: CheckedContinuation<Void, Never>?
    private var blockedHydrationContinuation: CheckedContinuation<Void, Never>?
    private var blockedActionPresentationContinuation: CheckedContinuation<Void, Never>?
    private(set) var startedCommands: [ApiAgentV2RunCommand] = []
    private(set) var retriedClientRunIds: [String] = []
    private(set) var hostContextUpdateCount = 0
    private(set) var hydrationRequestCount = 0
    private(set) var actionPresentationRequestCount = 0
    private(set) var lastHostContext: ApiAgentV2HostContext?
    private(set) var requestOrder: [String] = []
    private(set) var chatActivity: [Bool] = []
    private(set) var problemReports: [(threadId: String, report: ApiAgentV2ProblemReport)] = []
    private(set) var problemReportAvailabilityRequestCount = 0
    var isProblemReportAvailable = true
    var hostContextUpdateObserver: ((Int) -> Void)?
    var startRunObserver: (() -> Void)?
    var runResultState: ApiAgentV2RunResultState = .completed

    init(
        defaultThreadId: String = "thread-a",
        actionPresentationResult: ApiAgentV2ActionPresentation? = nil,
        actionPresentationResults: [ApiAgentV2ActionPresentation] = [],
        hydrationResult: ApiAgentV2ThreadHydration? = nil,
        hydrationResults: [ApiAgentV2ThreadHydration] = [],
        shouldCompleteRun: Bool = false,
        retryResultState: ApiAgentV2RunResultState? = nil,
        hostContextFailuresRemaining: Int = 0,
        blockedHostContextAttempt: Int? = nil,
        blockedHydrationAttempt: Int? = nil,
        blockedActionPresentationAttempt: Int? = nil,
        hostContextFailureAttempts: Set<Int> = []
    ) {
        self.defaultThreadId = defaultThreadId
        self.actionPresentationResults = actionPresentationResults.isEmpty
            ? actionPresentationResult.map { [$0] } ?? []
            : actionPresentationResults
        self.hydrationResult = hydrationResult
        self.hydrationResults = hydrationResults
        self.shouldCompleteRun = shouldCompleteRun
        self.retryResultState = retryResultState
        self.hostContextFailuresRemaining = hostContextFailuresRemaining
        self.blockedHostContextAttempt = blockedHostContextAttempt
        self.blockedHydrationAttempt = blockedHydrationAttempt
        self.blockedActionPresentationAttempt = blockedActionPresentationAttempt
        self.hostContextFailureAttempts = hostContextFailureAttempts
    }

    var hasConsent = true
    func consent() async throws -> Bool { hasConsent }
    var blocksConsentAcceptance = false
    var consentAcceptanceError: Error?
    private var consentAcceptanceContinuation: CheckedContinuation<Void, Never>?
    func acceptConsent() async throws {
        requestOrder.append("acceptConsent")
        if blocksConsentAcceptance {
            await withCheckedContinuation { consentAcceptanceContinuation = $0 }
        }
        if let consentAcceptanceError { throw consentAcceptanceError }
    }
    func resumeConsentAcceptance() {
        blocksConsentAcceptance = false
        consentAcceptanceContinuation?.resume()
        consentAcceptanceContinuation = nil
    }
    func updateHostContext(_ context: ApiAgentV2HostContext?) async throws {
        requestOrder.append("hostContext")
        hostContextUpdateCount += 1
        hostContextUpdateObserver?(hostContextUpdateCount)
        if hostContextUpdateCount == blockedHostContextAttempt {
            await withCheckedContinuation { continuation in
                blockedHostContextContinuation = continuation
            }
        }
        if hostContextFailuresRemaining > 0 {
            hostContextFailuresRemaining -= 1
            throw FakeAgentV2ClientError.unavailable
        }
        if hostContextFailureAttempts.remove(hostContextUpdateCount) != nil {
            throw FakeAgentV2ClientError.unavailable
        }
        lastHostContext = context
    }
    func resumeBlockedHostContextUpdate() {
        blockedHostContextContinuation?.resume()
        blockedHostContextContinuation = nil
    }
    func resumeBlockedHydration() {
        blockedHydrationContinuation?.resume()
        blockedHydrationContinuation = nil
    }
    func resumeBlockedActionPresentation() {
        blockedActionPresentationContinuation?.resume()
        blockedActionPresentationContinuation = nil
    }
    func resetHostContextUpdateCount() {
        hostContextUpdateCount = 0
    }
    func setHydrationResult(_ hydrationResult: ApiAgentV2ThreadHydration) {
        self.hydrationResult = hydrationResult
    }
    func hints() async throws -> ApiAgentV2HintsResponse {
        if blocksHints {
            await withCheckedContinuation { hintsContinuations.append($0) }
        }
        guard let hintsResult else { throw FakeAgentV2ClientError.unavailable }
        return hintsResult
    }
    func resumeHints() {
        blocksHints = false
        hintsContinuations.forEach { $0.resume() }
        hintsContinuations.removeAll()
    }
    var blocksStatusRefresh = false
    private var statusContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var completedStatusRequests = Set<String>()
    private(set) var cancelledStatusRequests = Set<String>()
    func loadAvailability() async {
        await loadStatus("availability")
    }
    func loadUserQuota() async {
        await loadStatus("userQuota")
    }
    func problemReportAvailability() async -> Bool {
        problemReportAvailabilityRequestCount += 1
        return isProblemReportAvailable
    }
    func setChatActive(_ isActive: Bool) async {
        chatActivity.append(isActive)
    }
    private func loadStatus(_ request: String) async {
        requestOrder.append(request)
        if blocksStatusRefresh {
            await withCheckedContinuation { statusContinuations.append($0) }
        }
        if Task.isCancelled { cancelledStatusRequests.insert(request) }
        completedStatusRequests.insert(request)
    }
    func resumeStatusRefresh() {
        blocksStatusRefresh = false
        statusContinuations.forEach { $0.resume() }
        statusContinuations.removeAll()
    }
    func defaultThread() async throws -> ApiAgentV2DefaultThreadResponse {
        requestOrder.append("defaultThread")
        if let defaultThreadError { throw defaultThreadError }
        let thread = hydrationResult?.thread ?? makeThread(id: defaultThreadId)
        return try JSONDecoder().decode(
            ApiAgentV2DefaultThreadResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "protocolVersion": 2,
                "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)),
                "created": false
            ])
        )
    }
    func messages(threadId: String, cursor: String?, limit: Int) async throws -> ApiAgentV2ThreadHydration {
        requestOrder.append("messages")
        hydrationRequestCount += 1
        let attempt = hydrationRequestCount
        let result = hydrationResults.isEmpty
            ? hydrationResult
            : hydrationResults[min(attempt - 1, hydrationResults.count - 1)]
        if attempt == blockedHydrationAttempt {
            await withCheckedContinuation { continuation in
                blockedHydrationContinuation = continuation
            }
        }
        guard let result else { throw FakeAgentV2ClientError.unavailable }
        return result
    }
    func startRun(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult {
        startedCommands.append(command)
        startRunObserver?()
        guard shouldCompleteRun else { throw FakeAgentV2ClientError.unavailable }
        return try JSONDecoder().decode(
            ApiAgentV2RunResult.self,
            from: JSONSerialization.data(withJSONObject: [
                "clientRunId": "client-thread-a",
                "runId": "run-thread-a",
                "state": runResultState.rawValue
            ])
        )
    }
    func retryRun(clientRunId: String) async throws -> ApiAgentV2RunResult? {
        retriedClientRunIds.append(clientRunId)
        guard let retryResultState else { return nil }
        return try JSONDecoder().decode(
            ApiAgentV2RunResult.self,
            from: JSONSerialization.data(withJSONObject: [
                "clientRunId": clientRunId,
                "runId": "run-retry",
                "state": retryResultState.rawValue
            ])
        )
    }
    func cancelRun(_ runId: String) async {}
    func clearThread(
        id: String,
        revision: Int
    ) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse> {
        let thread = makeThread(id: id, revision: revision + 1)
        return try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse>.self,
            from: JSONSerialization.data(withJSONObject: [
                "ok": true,
                "value": [
                    "protocolVersion": 2,
                    "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)),
                    "duplicate": false
                ]
            ])
        )
    }
    func reportProblem(threadId: String, report: ApiAgentV2ProblemReport) async throws {
        problemReports.append((threadId, report))
    }
    func actionPresentation(messageId: String, actionId: String) async throws -> ApiAgentV2ActionPresentation {
        actionPresentationRequestCount += 1
        let attempt = actionPresentationRequestCount
        if attempt == blockedActionPresentationAttempt {
            await withCheckedContinuation { continuation in
                blockedActionPresentationContinuation = continuation
            }
        }
        guard !actionPresentationResults.isEmpty else { throw FakeAgentV2ClientError.unavailable }
        return actionPresentationResults[min(attempt - 1, actionPresentationResults.count - 1)]
    }
    func resolveAction(messageId: String, actionId: String) async throws -> ApiAgentV2ResolvedAction { fatalError() }
    private func makeThread(id: String, revision: Int = 1) -> ApiAgentV2ThreadSummary {
        try! JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self,
            from: JSONSerialization.data(withJSONObject: [
                "id": id,
                "revision": revision,
                "createdAt": "2026-07-22T00:00:00.000Z",
                "updatedAt": "2026-07-22T00:00:00.000Z",
                "lastActivityAt": "2026-07-22T00:00:00.000Z",
                "messageCount": 0
            ])
        )
    }
}
