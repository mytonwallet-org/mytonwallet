import ContextMenuKit
import XCTest
import UIComponents
import UIKit
@testable import UIAgent
import WalletContext
@testable import WalletCore
import WalletResources

private struct DeletionError: Error {}

@MainActor
final class AgentChatDeletionTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    func testChatWithMessagesDeletesItsThreadAndLeavesTheStack() async throws {
        let history = try makeHydration(threadId: "thread-a", texts: ["Hello", "Hi there"])
        let client = FakeAgentV2Client(hydrationResult: history)
        let model = AgentV2Model(client: client, thread: history.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let (navigation, chat, window) = present(model)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }

        let menuButton = try XCTUnwrap(AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem))
        XCTAssertTrue(model.canDeleteChat)
        XCTAssertTrue(menuButton.isEnabled)

        try await model.deleteChat()
        XCTAssertEqual(client.deletedThreadIds, ["thread-a"])
        try await waitUntil { !navigation.viewControllers.contains(chat) }
        XCTAssertEqual(navigation.viewControllers.count, 1)
    }

    func testEmptyServerThreadCanBeDeleted() async throws {
        let history = try makeHydration(threadId: "thread-empty", texts: [])
        let client = FakeAgentV2Client(hydrationResult: history)
        let model = AgentV2Model(client: client, thread: history.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let (navigation, chat, window) = present(model)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }

        XCTAssertTrue(model.canDeleteChat)
        let menuButton = try XCTUnwrap(AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem))
        XCTAssertTrue(menuButton.isEnabled)
        try await model.deleteChat()
        XCTAssertEqual(client.deletedThreadIds, ["thread-empty"])
        try await waitUntil { !navigation.viewControllers.contains(chat) }
    }

    func testDeletingChatClosesBeforeServerDeletionFinishes() async throws {
        let history = try makeHydration(threadId: "delayed", texts: ["Hello"])
        let client = FakeAgentV2Client(hydrationResult: history)
        var deletion: CheckedContinuation<Void, Never>?
        client.beforeThreadDeletion = { await withCheckedContinuation { deletion = $0 } }
        let model = AgentV2Model(client: client, thread: history.thread)
        await model.waitForInitialLoad()
        let (navigation, chat, window) = present(model)
        defer {
            deletion?.resume()
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        let button = try XCTUnwrap(AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem))
        let actions = AgentChatActions(
            model: model, viewController: chat, cancelDictation: {},
            refreshNavigationItemMenu: { chat.refreshNavigationItemMenu() }
        )
        actions.deleteChat()
        try await waitUntil { deletion != nil }
        XCTAssertTrue(actions.willHaveMenu)
        XCTAssertFalse(actions.canDeleteChat)
        try await waitUntil { !navigation.viewControllers.contains(chat) }
        XCTAssertTrue(AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem) === button)
        deletion?.resume()
        deletion = nil
        try await waitUntil { !navigation.viewControllers.contains(chat) }
        XCTAssertTrue(AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem) === button)
    }

    func testFailedServerDeletionShowsErrorAfterTheChatHasClosed() async throws {
        let history = try makeHydration(threadId: "thread-b", texts: ["Hello"])
        let client = FakeAgentV2Client(hydrationResult: history)
        client.threadDeletionError = DeletionError()
        var deletion: CheckedContinuation<Void, Never>?
        client.beforeThreadDeletion = { await withCheckedContinuation { deletion = $0 } }
        let model = AgentV2Model(client: client, thread: history.thread)
        var stopCount = 0
        model.onStop = { stopCount += 1 }
        await model.waitForInitialLoad()
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = makeChatWindow(showing: navigation)
        var chat: AgentVC? = AgentVC(model: model)
        weak var releasedChat = chat
        navigation.pushViewController(try XCTUnwrap(chat), animated: false)
        window.layoutIfNeeded()
        defer {
            deletion?.resume()
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        var errors: [String] = []
        var actions: AgentChatActions? = AgentChatActions(
            model: model, viewController: try XCTUnwrap(chat), cancelDictation: {}, refreshNavigationItemMenu: {},
            showToast: { errors.append($0) }
        )
        actions?.deleteChat()
        actions = nil
        try await waitUntil { deletion != nil && navigation.viewControllers.count == 1 }
        chat = nil
        try await waitUntil { releasedChat == nil }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(releasedChat)
        XCTAssertTrue(errors.isEmpty)
        deletion?.resume()
        deletion = nil
        try await waitUntil { errors.count == 1 }
        XCTAssertEqual(client.deletedThreadIds, ["thread-b"])
        XCTAssertFalse(model.canDeleteChat)
        XCTAssertEqual(stopCount, 1)
    }

    func testImmediateDeleteFailureShowsToastOnlyAfterPop() async throws {
        let history = try makeHydration(threadId: "offline-delete", texts: ["Hello"])
        let client = FakeAgentV2Client(hydrationResult: history)
        client.threadDeletionError = DeletionError()
        let model = AgentV2Model(client: client, thread: history.thread)
        await model.waitForInitialLoad()
        let (navigation, chat, window) = present(model)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        var toastCount = 0
        let actions = AgentChatActions(
            model: model, viewController: chat, cancelDictation: {}, refreshNavigationItemMenu: {},
            showToast: { _ in
                XCTAssertEqual(navigation.viewControllers.count, 1)
                XCTAssertNil(chat.viewIfLoaded?.window)
                toastCount += 1
            }
        )
        actions.deleteChat()
        try await waitUntil { toastCount == 1 }
    }

    func testDeletionDuringCreationClosesImmediatelyAndNeverSends() async throws {
        let client = FakeAgentV2Client(hydrationResult: try makeHydration(threadId: "creating", texts: []))
        client.blocksThreadCreation = true
        let model = AgentV2Model(client: client, question: "Do not send this")
        let (navigation, chat, window) = present(model)
        defer {
            client.resumeThreadCreation()
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        try await waitUntil { client.requestOrder.contains("createThread") }
        let actions = AgentChatActions(
            model: model, viewController: chat, cancelDictation: {}, refreshNavigationItemMenu: {},
            showToast: { _ in XCTFail("Creation cancellation should not show an error") }
        )
        actions.deleteChat()
        XCTAssertTrue(model.isDeletingChat)
        try await waitUntil { !navigation.viewControllers.contains(chat) }
        XCTAssertTrue(client.deletedThreadIds.isEmpty)
        client.resumeThreadCreation()
        try await model.deleteChat()
        XCTAssertEqual(client.deletedThreadIds, ["creating"])
        XCTAssertEqual(client.cancelledThreadCreationCount, 0, "Keep the create response for server cleanup")
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    func testDeletionAfterFailedCreationClosesWithoutError() async throws {
        let client = FakeAgentV2Client()
        client.threadCreationError = DeletionError()
        let model = AgentV2Model(client: client, question: "Failed question")
        await model.waitForInitialLoad()
        let (navigation, chat, window) = present(model)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        let actions = AgentChatActions(
            model: model, viewController: chat, cancelDictation: {}, refreshNavigationItemMenu: {},
            showToast: { _ in XCTFail("There is no server thread to delete") }
        )
        XCTAssertTrue(actions.canDeleteChat)
        actions.deleteChat()
        try await model.deleteChat()
        try await waitUntil { !navigation.viewControllers.contains(chat) }
        XCTAssertTrue(client.deletedThreadIds.isEmpty)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    func testOpeningWaitingForConsentStillOffersDelete() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        let client = FakeAgentV2Client()
        client.hasConsent = false
        let model = AgentV2Model(client: client, question: "Pending consent")
        await model.waitForInitialLoad()
        let (navigation, chat, window) = present(model)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }
        let actions = AgentChatActions(
            model: model, viewController: chat, cancelDictation: {}, refreshNavigationItemMenu: {}
        )
        XCTAssertTrue(model.needsOpeningConsent)
        try await waitUntil { presentation.presentedViewController(of: chat) != nil }
        XCTAssertTrue(actions.canDeleteChat)
        XCTAssertTrue(try XCTUnwrap(AgentChatNavigation.findButton(in: chat.navigationItem.rightBarButtonItem)).isEnabled)
        actions.deleteChat()
        try await model.deleteChat()
        try await waitUntil { !navigation.viewControllers.contains(chat) }
        XCTAssertNil(presentation.presentedViewController(of: chat), "The sheet goes with the chat")
        XCTAssertEqual(presentation.dismissalCount, 1)
        XCTAssertFalse(client.requestOrder.contains("createThread"))
        XCTAssertTrue(client.deletedThreadIds.isEmpty)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    func testDeletionBeforeCreationStartsDoesNotCreateOrSend() async throws {
        let client = FakeAgentV2Client()
        let model = AgentV2Model(client: client, question: "Do not create this")
        defer { model.stop() }
        XCTAssertTrue(model.beginChatDeletion())
        try await model.deleteChat()
        await model.waitForInitialLoad()
        XCTAssertFalse(client.requestOrder.contains("createThread"))
        XCTAssertTrue(client.deletedThreadIds.isEmpty)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    func testDeletionWithThreadBeforeOpeningSendDoesNotWaitForHostContext() async throws {
        let client = FakeAgentV2Client(
            hydrationResult: try makeHydration(threadId: "before-send", texts: []), blockedHostContextAttempt: 1
        )
        let model = AgentV2Model(client: client, question: "Do not send this")
        defer { client.resumeBlockedHostContextUpdate(); model.stop() }
        try await waitUntil { model.threadId != nil && client.hostContextUpdateCount == 1 }
        XCTAssertTrue(model.beginChatDeletion())
        try await model.deleteChat()
        XCTAssertEqual(client.deletedThreadIds, ["before-send"])
        client.resumeBlockedHostContextUpdate()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    func testDeletionAfterSendDoesNotWaitForTheRun() async throws {
        let client = FakeAgentV2Client(hydrationResult: try makeHydration(threadId: "sent", texts: []))
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, question: "Already sent")
        defer { client.resumeRunStart(); model.stop() }
        try await waitUntil { client.startedCommands.count == 1 }
        try await model.deleteChat()
        XCTAssertEqual(client.deletedThreadIds, ["sent"])
        client.resumeRunStart()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.count, 1)
    }

    func testMessageMenuMovesThePressedMessageIntoTheChatsVisibleArea() async throws {
        let history = try makeHydration(threadId: "thread-c", texts: ["Show me my portfolio"])
        let client = FakeAgentV2Client(hydrationResult: history)
        let model = AgentV2Model(client: client, thread: history.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let (navigation, chat, window) = present(model)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        let collection = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? UICollectionView }.first)
        let composer = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? AgentComposerView }.first)
        try await waitUntil {
            window.layoutIfNeeded()
            return collection.visibleCells.contains { $0 is AgentMessageCell }
        }
        let cell = try XCTUnwrap(collection.visibleCells.compactMap { $0 as? AgentMessageCell }.first)

        let menu = try XCTUnwrap(cell.contextMenuConfigurationProvider?())
        let relocation = try XCTUnwrap(menu.sourceRelocation)
        let contentArea = try XCTUnwrap(relocation.contentAreaInWindow)
        let composerTop = composer.convert(composer.inputBackgroundFrame, to: nil).minY
        XCTAssertEqual(contentArea.minY, collection.convert(collection.bounds, to: nil).minY + collection.adjustedContentInset.top, accuracy: 0.5)
        XCTAssertEqual(contentArea.maxY, composerTop, accuracy: 0.5)
        XCTAssertEqual(relocation.topInset, 8)
        XCTAssertEqual(relocation.bottomInset, 10)
    }

    func testFailedProblemReportReopensFormWithCommentAndKeepsTheCommentLimit() async throws {
        let backend = ProblemReportTestBackend()
        let model = AgentModel(backend: backend)
        defer { model.stop() }
        let controller = ProblemReportTestViewController()
        let window = makeKeyWindow(showing: controller)
        defer { window.isHidden = true }
        var dictationCancellations = 0
        var errors: [DisplayError] = []
        let actions = AgentChatActions(
            model: model,
            viewController: controller,
            cancelDictation: { dictationCancellations += 1 },
            refreshNavigationItemMenu: {},
            showError: { errors.append($0) },
            showToast: { _ in XCTFail("A failed report must not show a success message") }
        )
        let messageID = UUID()

        actions.reportProblem(messageID: messageID)
        let initialForm = try XCTUnwrap(controller.alerts.first)
        let initialField = try await showTextInputField(of: initialForm)
        XCTAssertEqual(initialField.text, "")
        XCTAssertEqual(initialField.attributedPlaceholder?.string, lang("Optional"))
        try checkCommentLimit(of: initialField)

        await actions.sendProblemReport(messageID: messageID, comment: "Wrong balance").value

        XCTAssertEqual(backend.reportedMessageIDs, [messageID])
        XCTAssertEqual(backend.reportedComments, ["Wrong balance"])
        XCTAssertEqual(controller.alerts.count, 2)
        let retryField = try await showTextInputField(of: try XCTUnwrap(controller.alerts.last))
        XCTAssertEqual(retryField.text, "Wrong balance")
        try checkCommentLimit(of: retryField)
        XCTAssertEqual(dictationCancellations, 2)
        XCTAssertTrue(errors.isEmpty)
    }

    func testFailedProblemReportShowsErrorWhenTheScreenHasGone() async throws {
        let backend = ProblemReportTestBackend()
        let model = AgentModel(backend: backend)
        defer { model.stop() }
        var controller: ProblemReportTestViewController? = ProblemReportTestViewController()
        weak var releasedController = controller
        var dictationCancellations = 0
        var errors: [DisplayError] = []
        let actions = AgentChatActions(
            model: model,
            viewController: try XCTUnwrap(controller),
            cancelDictation: { dictationCancellations += 1 },
            refreshNavigationItemMenu: {},
            showError: { errors.append($0) },
            showToast: { _ in XCTFail("A failed report must not show a success message") }
        )
        let send = actions.sendProblemReport(messageID: nil, comment: "Wrong balance")
        controller = nil
        XCTAssertNil(releasedController)

        await send.value

        XCTAssertEqual(backend.reportedComments, ["Wrong balance"])
        XCTAssertEqual(errors.map(\.text), [lang("$agent_report_problem_failed")])
        XCTAssertEqual(dictationCancellations, 1)
    }

    /// The form's text field, with the form shown in a window of its own
    private func showTextInputField(of alert: WAlertController) async throws -> AgentAlertTextFieldView {
        let window = makeKeyWindow(showing: alert)
        addTeardownBlock { window.isHidden = true }
        return try await waitForTextInputField(in: alert)
    }

    /// A comment can be as long as 1000 characters
    private func checkCommentLimit(of field: AgentAlertTextFieldView) throws {
        let delegate = try XCTUnwrap(field.delegate)
        let length = (field.text ?? "").utf16.count
        let fitting = String(repeating: "a", count: 1000 - length)
        let end = NSRange(location: length, length: 0)
        XCTAssertEqual(delegate.textField?(field, shouldChangeCharactersIn: end, replacementString: fitting), true)
        XCTAssertEqual(delegate.textField?(field, shouldChangeCharactersIn: end, replacementString: fitting + "a"), false)
    }

    private func makeChatWindow(showing navigation: UINavigationController) -> UIWindow {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return makeKeyWindow(showing: navigation)
        }
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        addTeardownBlock { previousKeyWindow?.makeKey() }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        return window
    }

    private func present(_ model: AgentV2Model) -> (UINavigationController, AgentVC, UIWindow) {
        let chat = AgentVC(model: model)
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = makeChatWindow(showing: navigation)
        navigation.pushViewController(chat, animated: false)
        chat.loadViewIfNeeded()
        window.layoutIfNeeded()
        return (navigation, chat, window)
    }

    private func makeHydration(threadId: String, texts: [String]) throws -> ApiAgentV2ThreadHydration {
        let messages: [[String: Any]] = texts.enumerated().map { index, text in
            [
                "id": "\(threadId)-message-\(index)",
                "threadId": threadId,
                "role": index.isMultiple(of: 2) ? "user" : "assistant",
                "status": "complete",
                "content": ["kind": "markdown", "text": text],
                "createdAt": "2026-07-22T00:00:0\(index + 1).000Z"
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "thread": [
                "id": threadId,
                "revision": 2,
                "createdAt": "2026-07-22T00:00:00.000Z",
                "updatedAt": "2026-07-22T00:00:01.000Z",
                "lastActivityAt": "2026-07-22T00:00:01.000Z",
                "messageCount": messages.count
            ],
            "messages": messages
        ])
        return try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: data)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The condition was not met in time")
    }
}

@MainActor
private final class ProblemReportTestViewController: UIViewController {
    private(set) var alerts: [WAlertController] = []

    override func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        if let alert = viewControllerToPresent as? WAlertController {
            alerts.append(alert)
        }
        completion?()
    }
}

@MainActor
private final class ProblemReportTestBackend: AgentBackend {
    var canReportProblem: Bool { true }
    private(set) var reportedMessageIDs: [AgentItemID?] = []
    private(set) var reportedComments: [String?] = []

    func attach(to context: AgentBackendContext) {}
    func detach() {}
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
    func didSendUserMessage(
        _ text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?
    ) {}
    func clearConversation() {}

    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool {
        reportedMessageIDs.append(messageID)
        reportedComments.append(comment)
        return false
    }
}
