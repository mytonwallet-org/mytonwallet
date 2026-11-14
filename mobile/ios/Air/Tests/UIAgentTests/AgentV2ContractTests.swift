import ContextMenuKit
import Dependencies
import XCTest
import UIKit
@testable import UIAgent
import WalletContext
@testable import WalletCore
import WalletResources
import WebKit

private struct MessageLinkCase {
    let link: String
    let policy: AgentMessageRenderingPolicy
    let isHandled: Bool
    let expected: [String]
}

final class AgentV2ContractTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testSupportHistoryExposesAuthorsPlainTextEventsAndTheLatestOperator() async throws {
        let alex = ApiAgentV2OperatorAuthor(operatorId: "alex", name: "Alex")
        let maya = ApiAgentV2OperatorAuthor(operatorId: "maya", name: "Maya", avatarUrl: "https://example.com/maya.png")
        let text = "**Literal**\n```\ncode\n```\n\u{E004}https%3A%2F%2Fexample%2Ecom\u{E005}label\u{E006}"
        let base = try decodeRatedConversation(answerFeedback: nil)
        let thread = try makeThread(base.thread, revision: 3, support: .init(state: .operator))
        let eventFields: [[String: Any]] = [
            ["code": "support_requested"],
            ["code": "operator_joined", "author": ["operatorId": alex.operatorId, "name": alex.name]],
            ["code": "support_closed", "reason": "inactivity"],
            ["code": "support_requested"],
            ["code": "operator_joined", "author": ["operatorId": maya.operatorId, "name": maya.name, "avatarUrl": maya.avatarUrl!]]
        ]
        let events = eventFields.enumerated().map { index, fields in
            fields.merging([
                "id": "event-\(index)", "threadId": "thread-a", "role": "event", "status": "complete",
                "createdAt": "2026-07-22T00:00:03.000Z"
            ]) { existing, _ in existing }
        }
        var messages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
        messages += events
        messages.append([
            "id": "operator", "threadId": "thread-a", "role": "operator", "status": "complete",
            "text": text, "createdAt": "2026-07-22T00:00:04.000Z",
            "author": ["operatorId": maya.operatorId, "name": maya.name, "avatarUrl": maya.avatarUrl!]
        ])
        let history = try decodeHydration(threadId: thread.id, messages: messages, thread: thread)
        let model = AgentV2Model(client: FakeAgentV2Client(hydrationResult: history), thread: thread)
        defer { model.stop() }
        await model.waitForInitialLoad()

        let presented = model.itemIDs.compactMap { model.message(for: $0) }.filter { !$0.isDateTimeSystemMessage }
        XCTAssertEqual(presented.count, messages.count)
        XCTAssertEqual(presented.first?.author, .user)
        XCTAssertEqual(presented.dropFirst().first?.author, .agent)
        XCTAssertEqual(presented.compactMap(\.supportEvent), [
            .supportRequested, .operatorJoined(alex), .supportClosed(.inactivity), .supportRequested, .operatorJoined(maya)
        ])
        XCTAssertTrue(presented.filter { $0.supportEvent != nil }.allSatisfy { $0.role == .system })
        let reply = try XCTUnwrap(presented.last)
        XCTAssertEqual(reply.role, .assistant)
        XCTAssertEqual(reply.author, .operator(maya))
        XCTAssertTrue(reply.isPlainText)
        XCTAssertEqual(reply.text, text)
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            reply.text, textColor: .label, rendersMarkdown: false, detectsLinks: false, markdownProfile: .plainText
        )
        XCTAssertEqual(rendered.string, text)
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            XCTAssertNil(value)
        }
        XCTAssertTrue(reply.canRate)
        XCTAssertEqual(model.supportState, .operator(maya))
        XCTAssertTrue(model.isSupportActive)
        // Once an operator has joined, every answer names its author, the Agent's before it too
        XCTAssertEqual(presented.filter(\.shouldShowAuthor).map(\.author), [.agent, .operator(maya)])
        XCTAssertEqual(presented.compactMap(\.supportEvent).last?.text, L10n.agentSupportOperatorJoined(name: maya.name))
        XCTAssertEqual(AgentSupportPresentation.getSubtitle(for: model.supportState), L10n.agentSupportWithOperator(name: maya.name))
        XCTAssertEqual(AgentSupportPresentation.getComposerPlaceholder(for: model.supportState), lang("$agent_support_placeholder"))
    }

    @MainActor
    func testStoredOperatorReplyIsRatedByItsOwnIDWhileSupportEventsAreNot() async throws {
        let alex = ApiAgentV2OperatorAuthor(operatorId: "alex", name: "Alex")
        let author: [String: Any] = ["operatorId": alex.operatorId, "name": alex.name]
        let base = try decodeRatedConversation(answerFeedback: nil)
        let thread = try makeThread(base.thread, revision: 3, support: .init(state: .operator))
        let supportMessages: [[String: Any]] = [
            ["id": "requested", "role": "event", "code": "support_requested"],
            ["id": "joined", "role": "event", "code": "operator_joined", "author": author],
            ["id": "operator", "role": "operator", "text": "Your transfer is on its way", "author": author, "feedback": "like"],
            ["id": "closed", "role": "event", "code": "support_closed", "reason": "operator"]
        ]
        var messages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
        messages += supportMessages.map { fields in
            fields.merging([
                "threadId": "thread-a", "status": "complete", "createdAt": "2026-07-22T00:00:04.000Z"
            ]) { existing, _ in existing }
        }
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: thread.id, messages: messages, thread: thread))
        let model = AgentV2Model(client: client, thread: thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let eventIDs = model.itemIDs.filter { presentedMessage($0, in: model)?.supportEvent != nil }
        let replyID = try XCTUnwrap(model.itemIDs.first { presentedMessage($0, in: model)?.author == .operator(alex) })
        XCTAssertEqual(eventIDs.count, 3)

        // Support events take no rating, as on the web
        XCTAssertFalse(eventIDs.contains { presentedMessage($0, in: model)?.canRate != false })
        XCTAssertFalse(eventIDs.contains { presentedMessage($0, in: model)?.feedback != nil })
        for eventID in eventIDs {
            let didRate = await model.rateMessage(messageID: eventID, feedback: .like)
            XCTAssertFalse(didRate)
        }
        XCTAssertTrue(client.feedbackRequests.isEmpty)

        // The stored reply shows its rating and is rated by its own ID
        XCTAssertEqual(presentedMessage(replyID, in: model)?.canRate, true)
        XCTAssertEqual(presentedMessage(replyID, in: model)?.feedback, .like)
        let rating = Task { await model.rateMessage(messageID: replyID, feedback: .dislike) }
        await waitForFeedbackRequest(client, count: 1)
        let request = try XCTUnwrap(client.feedbackRequests.first)
        XCTAssertEqual(client.feedbackRequests.count, 1)
        XCTAssertEqual(request.messageId, "operator")
        XCTAssertEqual(request.feedback, .dislike)
        client.settleFeedbackRequest(at: 0, with: .success(.dislike))
        let didSave = await rating.value
        XCTAssertTrue(didSave)
        XCTAssertEqual(presentedMessage(replyID, in: model)?.feedback, .dislike)
    }

    @MainActor
    func testSupportDisablesAgentActionsAndClosedRestoresThem() async throws {
        let base = try decodeRatedConversation(answerFeedback: nil)
        var messages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
        messages[1]["followups"] = [[
            "id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "More?"
        ]]
        messages.insert([
            "id": "earlier-failure", "threadId": "thread-a", "role": "assistant", "status": "error",
            "content": ["kind": "markdown", "text": "Earlier partial answer"],
            "error": ["code": "network_error", "retryable": true], "createdAt": "2026-07-22T00:00:00.000Z"
        ], at: 0)
        let history = try decodeHydration(threadId: base.thread.id, messages: messages)
        let client = FakeAgentV2Client(hydrationResult: history)
        let model = AgentV2Model(client: client, thread: history.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let questionID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
        let answerID = try XCTUnwrap(model.itemIDs.last { model.message(for: $0)?.text == "You hold 5 TON." })
        let oldFailureID = try XCTUnwrap(model.itemIDs.first { model.message(for: $0)?.text == "Earlier partial answer" })
        let followupID = try XCTUnwrap(presentedMessage(answerID, in: model)?.controls.first { $0.kind == .followup }?.id)
        XCTAssertEqual(model.supportState, .none)
        XCTAssertNil(AgentSupportPresentation.getSubtitle(for: model.supportState))
        XCTAssertEqual(AgentSupportPresentation.getComposerPlaceholder(for: model.supportState), lang("Ask anything"))
        XCTAssertTrue(model.canEditMessage(questionID))
        XCTAssertTrue(model.canRegenerateMessage(answerID))

        for (index, state) in [ApiAgentV2ThreadSupport.State.waiting, .operator].enumerated() {
            let thread = try makeThread(history.thread, revision: 3 + index, support: .init(state: state))
            coordinator.walletCore(event: .agentV2(.threadChanged(threadId: thread.id, thread: thread)))
            XCTAssertTrue(model.isSupportActive)
            XCTAssertEqual(model.supportState, state == .waiting ? .waiting : .operator(nil))
            XCTAssertEqual(
                AgentSupportPresentation.getSubtitle(for: model.supportState),
                lang(state == .waiting ? "$agent_support_waiting" : "$agent_support_label")
            )
            XCTAssertEqual(AgentSupportPresentation.getComposerPlaceholder(for: model.supportState), lang("$agent_support_placeholder"))
            // Before an operator joins, no author shows
            XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.shouldShowAuthor == true })
            XCTAssertFalse(model.canEditMessage(questionID))
            XCTAssertFalse(model.canRegenerateMessage(answerID))
            XCTAssertFalse(model.canRegenerateMessage(oldFailureID))
            XCTAssertFalse(try XCTUnwrap(presentedMessage(answerID, in: model)).controls.contains { $0.kind == .followup })
            let question = try XCTUnwrap(presentedMessage(questionID, in: model))
            let menu = AgentMessageMenuItems.makeItems(
                for: question, copyText: question.text, canEdit: model.canEditMessage(questionID), canRegenerate: false,
                canReportProblem: false, edit: {}, regenerate: {}, reportProblem: {}
            )
            XCTAssertFalse(menu.contains { item in
                if case .action(let action) = item { return action.title == lang("Edit") }
                return false
            })
            let itemIDs = model.itemIDs
            model.send(text: "Edited question", editingMessageID: questionID)
            model.regenerateMessage(answerID)
            model.performControl(messageID: answerID, controlID: followupID)
            XCTAssertEqual(model.itemIDs, itemIDs)
            XCTAssertFalse(model.hasActiveRun)
            XCTAssertEqual(model.message(for: questionID)?.text, "What is my balance?")
        }

        let closed = try makeThread(history.thread, revision: 5, support: .init(state: .closed))
        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: closed.id, thread: closed)))
        XCTAssertEqual(model.supportState, .closed)
        XCTAssertFalse(model.isSupportActive)
        XCTAssertNil(AgentSupportPresentation.getSubtitle(for: model.supportState))
        XCTAssertEqual(AgentSupportPresentation.getComposerPlaceholder(for: model.supportState), lang("Ask anything"))
        XCTAssertTrue(model.canEditMessage(questionID))
        XCTAssertTrue(model.canRegenerateMessage(answerID))
        XCTAssertTrue(model.canRegenerateMessage(oldFailureID))
        XCTAssertEqual(presentedMessage(answerID, in: model)?.controls.map(\.id), [followupID])

        let failure = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runFailed", "clientRunId": "earlier-run", "threadId": history.thread.id,
            "code": "rate_limited", "retryable": true
        ]))
        coordinator.walletCore(event: .agentV2(failure))
        let retry = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first {
            $0.controls.contains { $0.id == "retry-limit" }
        })
        for (index, state) in [ApiAgentV2ThreadSupport.State.waiting, .operator].enumerated() {
            let thread = try makeThread(history.thread, revision: 6 + index, support: .init(state: state))
            coordinator.walletCore(event: .agentV2(.threadChanged(threadId: thread.id, thread: thread)))
            XCTAssertTrue(model.itemIDs.compactMap { model.message(for: $0) }.allSatisfy {
                !$0.controls.contains { $0.title == lang("Retry") }
            })
            model.performControl(messageID: retry.id, controlID: "retry-limit")
            XCTAssertFalse(model.hasActiveRun)
        }
        let reclosed = try makeThread(history.thread, revision: 8, support: .init(state: .closed))
        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: reclosed.id, thread: reclosed)))
        XCTAssertEqual(model.message(for: retry.id)?.controls.map(\.id), ["retry-limit"])
        model.performControl(messageID: retry.id, controlID: "retry-limit")
        try await waitForDiscussionUI { !client.retriedClientRunIds.isEmpty }
        XCTAssertEqual(client.retriedClientRunIds, ["earlier-run"])
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testSupportKeepsHistoryLoadRetryAvailable() async throws {
        let base = try decodeRatedConversation(answerFeedback: nil)
        for state in [ApiAgentV2ThreadSupport.State.waiting, .operator] {
            let thread = try makeThread(base.thread, revision: 3, support: .init(state: state))
            let messages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
            let history = try decodeHydration(threadId: thread.id, messages: messages, thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history)
            let model = AgentV2Model(client: client, thread: thread)
            defer { model.stop() }
            await model.waitForInitialLoad()
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
            client.hydrationError = FakeAgentV2ClientError.unavailable

            await coordinator.hydrate()

            XCTAssertEqual(client.hydrationRequestCount, 2)
            XCTAssertEqual(coordinator.messages.map(\.id), base.messages.map(\.id))
            let failure = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.isFailureCaption })
            let retry = try XCTUnwrap(failure.controls.first { $0.id == "retry-load" && $0.isEnabled })
            client.hydrationError = nil
            model.performControl(messageID: failure.id, controlID: retry.id)
            try await waitForDiscussionUI { client.hydrationRequestCount == 3 && coordinator.error == nil }

            XCTAssertTrue(model.isSupportActive)
            XCTAssertEqual(model.thread?.support?.state, state)
            XCTAssertEqual(coordinator.messages.map(\.id), base.messages.map(\.id))
            XCTAssertFalse(model.itemIDs.compactMap { model.message(for: $0) }.contains { $0.isFailureCaption })
            XCTAssertTrue(client.startedCommands.isEmpty)
            XCTAssertTrue(client.retriedClientRunIds.isEmpty)
        }
    }

    @MainActor
    func testSupportAppendResendsARevisionConflictOnceWithoutReplacingItsBubble() async throws {
        let base = try decodeRatedConversation(answerFeedback: nil)
        let savedMessages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
        let failure = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runFailed", "clientRunId": "client-thread-a", "threadId": "thread-a",
            "code": "thread_revision_conflict", "retryable": false
        ]))
        for state in [ApiAgentV2ThreadSupport.State.waiting, .operator] {
            let initialThread = try makeThread(base.thread, revision: 2, support: .init(state: state))
            let latestThread = try makeThread(base.thread, revision: 4, support: .init(state: state))
            let initial = try decodeHydration(threadId: "thread-a", messages: savedMessages, thread: initialThread)
            let latest = try decodeHydration(threadId: "thread-a", messages: savedMessages, thread: latestThread)
            let accepted = try decodeHydration(threadId: "thread-a", messages: savedMessages + [[
                "id": "accepted-help", "threadId": "thread-a", "role": "user", "status": "complete",
                "content": ["kind": "markdown", "text": "Help"], "createdAt": "2026-11-08T10:30:00.000Z"
            ]], thread: latestThread)
            let client = FakeAgentV2Client(hydrationResult: initial, shouldCompleteRun: true)
            let model = AgentV2Model(client: client, thread: initialThread)
            defer { model.stop() }
            await model.waitForInitialLoad()
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
            client.startRunObserver = { [weak client, weak coordinator] in
                guard let client, let coordinator else { return }
                if client.startedCommands.count == 1 {
                    client.runResultRunId = nil
                    client.runResultState = .failed
                    client.setHydrationResult(latest)
                    coordinator.walletCore(event: .agentV2(failure))
                    XCTAssertNil(coordinator.error)
                    XCTAssertTrue(coordinator.activeRun?.isRunning == true)
                } else {
                    XCTAssertNil(coordinator.error)
                    XCTAssertEqual(coordinator.messages.filter { $0.text == "Help" }.count, 1)
                    client.runResultRunId = "run-thread-a"
                    client.runResultState = .completed
                    client.runInputMessageId = "accepted-help"
                    client.setHydrationResult(accepted)
                }
            }

            model.send(text: "Help")
            let inputID = try XCTUnwrap(model.itemIDs.first { model.message(for: $0)?.text == "Help" })
            try await waitForDiscussionUI { client.startedCommands.count == 2 && !model.hasActiveRun }

            XCTAssertEqual(client.startedCommands.map(\.expectedThreadRevision), [2, 4])
            XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Help"), .append(text: "Help")])
            XCTAssertEqual(Set(client.startedCommands.map(\.clientRunId)).count, 1)
            XCTAssertEqual(model.message(for: inputID)?.text, "Help")
            XCTAssertEqual(coordinator.messages.filter { $0.text == "Help" }.map(\.id), ["accepted-help"])
            XCTAssertNil(coordinator.error)
        }
    }

    @MainActor
    func testSupportConflictReportsTheOriginalErrorWhenItsRefreshFailsOrIsSuperseded() async throws {
        let base = try decodeRatedConversation(answerFeedback: nil)
        let thread = try makeThread(base.thread, revision: 2, support: .init(state: .operator))
        let messages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
        let history = try decodeHydration(threadId: "thread-a", messages: messages, thread: thread)
        let failure = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runFailed", "clientRunId": "client-thread-a", "threadId": "thread-a",
            "code": "thread_revision_conflict", "retryable": false
        ]))
        for isSuperseded in [false, true] {
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 2)
            let coordinator = AgentV2Coordinator(client: client, thread: thread)
            let observer = AgentV2CoordinatorObserverSpy()
            coordinator.addObserver(observer)
            defer {
                coordinator.stop()
                client.resumeBlockedHydration()
            }
            coordinator.start()
            await coordinator.waitForInitialLoad()
            client.runResultRunId = nil
            client.runResultState = .failed
            client.startRunObserver = { [weak coordinator] in coordinator?.walletCore(event: .agentV2(failure)) }
            coordinator.send(input: .append(text: "Help"), visibleText: "Help", localInputMessageId: "local-help")
            try await waitForDiscussionUI { client.hydrationRequestCount == 2 }
            XCTAssertNil(coordinator.error)
            XCTAssertEqual(coordinator.messages.filter { $0.text == "Help" }.count, 1)
            if isSuperseded {
                let didHydrate = await coordinator.hydrate(isFailureSilent: true)
                XCTAssertTrue(didHydrate)
            } else {
                client.hydrationError = FakeAgentV2ClientError.unavailable
            }

            client.resumeBlockedHydration()
            try await waitForDiscussionUI { observer.changes.contains(.runTerminated(.failed)) }

            XCTAssertEqual(client.startedCommands.count, 1)
            XCTAssertEqual(coordinator.error, AgentV2Copy.error(.threadRevisionConflict))
            XCTAssertEqual(coordinator.messages.filter { $0.text == "Help" }.count, 1)
        }
    }

    @MainActor
    func testSupportConflictDoesNotResendAfterCancellationOrThreadRetirement() async throws {
        let base = try decodeRatedConversation(answerFeedback: nil)
        let thread = try makeThread(base.thread, revision: 2, support: .init(state: .operator))
        let messages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
        let history = try decodeHydration(threadId: "thread-a", messages: messages, thread: thread)
        let failure = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runFailed", "clientRunId": "client-thread-a", "threadId": "thread-a",
            "code": "thread_revision_conflict", "retryable": false
        ]))
        for isThreadRetired in [false, true] {
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 2)
            let coordinator = AgentV2Coordinator(client: client, thread: thread)
            defer {
                coordinator.stop()
                client.resumeBlockedHydration()
            }
            coordinator.start()
            await coordinator.waitForInitialLoad()
            client.runResultRunId = nil
            client.runResultState = .failed
            client.startRunObserver = { [weak coordinator] in coordinator?.walletCore(event: .agentV2(failure)) }
            coordinator.send(input: .append(text: "Help"), visibleText: "Help", localInputMessageId: "local-help")
            try await waitForDiscussionUI { client.hydrationRequestCount == 2 }
            if isThreadRetired {
                coordinator.stop()
            } else {
                coordinator.stopRun()
            }

            client.resumeBlockedHydration()
            try await waitForDiscussionUI { client.cancelledHydrationRequestCount == 1 }

            XCTAssertEqual(client.startedCommands.count, 1)
        }
    }

    @MainActor
    func testSupportConflictDoesNotRepeatTwiceOrResendOtherAdmissions() async throws {
        struct AdmissionCase {
            let supportState: ApiAgentV2ThreadSupport.State?
            let input: ApiAgentV2RunInput
            var code: ApiAgentV2ErrorCode = .threadRevisionConflict
            var hasAdmittedRun = false
            var expectedCommands = 1
        }
        let base = try decodeRatedConversation(answerFeedback: nil)
        let messages = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.messages)) as? [[String: Any]])
        let cases: [AdmissionCase] = [
            .init(supportState: .operator, input: .append(text: "Help"), expectedCommands: 2),
            .init(supportState: nil, input: .append(text: "Help")),
            .init(supportState: .closed, input: .append(text: "Help")),
            .init(supportState: nil, input: .edit(targetUserMessageId: "question", text: "Help")),
            .init(supportState: nil, input: .regenerate(targetAssistantMessageId: "answer")),
            .init(supportState: .operator, input: .append(text: "Help"), code: .internalError),
            .init(supportState: .operator, input: .append(text: "Help"), hasAdmittedRun: true)
        ]
        for admission in cases {
            let supportState = admission.supportState
            let input = admission.input
            let code = admission.code
            let hasAdmittedRun = admission.hasAdmittedRun
            let thread = try makeThread(base.thread, revision: 2, support: supportState.map { .init(state: $0) })
            let history = try decodeHydration(threadId: "thread-a", messages: messages, thread: thread)
            var fields: [String: Any] = [
                "kind": "runFailed", "clientRunId": "client-thread-a", "threadId": "thread-a",
                "code": code.rawValue, "retryable": false
            ]
            if hasAdmittedRun { fields["runId"] = "run-thread-a" }
            let failure = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: fields))
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            let coordinator = AgentV2Coordinator(client: client, thread: thread)
            let observer = AgentV2CoordinatorObserverSpy()
            coordinator.addObserver(observer)
            defer { coordinator.stop() }
            coordinator.start()
            await coordinator.waitForInitialLoad()
            client.runResultRunId = hasAdmittedRun ? "run-thread-a" : nil
            client.runResultState = .failed
            client.startRunObserver = { [weak client, weak coordinator] in
                guard let client, let coordinator else { return }
                coordinator.walletCore(event: .agentV2(failure))
                let shouldDeferConflict = admission.expectedCommands == 2 && client.startedCommands.count == 1
                XCTAssertEqual(coordinator.error, shouldDeferConflict ? nil : AgentV2Copy.error(code))
            }

            if case .append = input {
                coordinator.send(input: input, visibleText: "Help", localInputMessageId: "local-help")
            } else {
                coordinator.send(input: input)
            }
            try await waitForDiscussionUI { observer.changes.filter { $0 == .runTerminated(.failed) }.count >= 2 }

            XCTAssertEqual(client.startedCommands.count, admission.expectedCommands)
        }
    }

    @MainActor
    func testDeliveredToSupportKeepsTheSavedInputWithoutAnAnswerOrRetry() async throws {
        let initial = try decodeHydration(threadId: "thread-a", messages: [])
        let waiting = try makeThread(initial.thread, revision: 3, support: .init(state: .waiting))
        let saved = try decodeHydration(threadId: "thread-a", messages: [[
            "id": "saved-question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Please help"], "createdAt": "2026-07-22T00:00:01.000Z"
        ]], thread: waiting)
        let client = FakeAgentV2Client(hydrationResults: [initial, saved], shouldCompleteRun: true)
        client.runInputMessageId = "saved-question"
        let model = AgentV2Model(client: client, thread: initial.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let delivered = try decodeUpdate(
            kind: "messageCompleted", threadId: "thread-a", messageId: "saved-question", finishReason: "delivered_to_support"
        )
        client.startRunObserver = { coordinator.walletCore(event: .agentV2(delivered)) }

        model.send(text: "Please help")
        try await waitForDiscussionUI { client.hydrationRequestCount == 2 && !model.hasActiveRun }

        XCTAssertEqual(coordinator.messages.map(\.id), ["saved-question"])
        XCTAssertEqual(coordinator.messages.map(\.role), [.user])
        XCTAssertNil(coordinator.error)
        XCTAssertFalse(model.isRunFailed)
        let presented = model.itemIDs.compactMap { model.message(for: $0) }.filter { !$0.isDateTimeSystemMessage }
        XCTAssertEqual(presented.map(\.text), ["Please help"])
        XCTAssertTrue(presented.allSatisfy { $0.controls.isEmpty })
        XCTAssertFalse(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
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
        XCTAssertNil(result.value?.thread.title)
        XCTAssertNil(result.value?.thread.icon)
        XCTAssertNil(result.value?.thread.hasCustomTitle)
        XCTAssertNil(result.value?.thread.isPinned)
    }

    /// As the SDK's `getIsAgentV2ThreadStarted` has it, a news discussion with its post alone is not started, one the
    /// user wrote in is, and so is every other chat, however few its messages
    func testThreadStartsAsTheSdkRuleHasIt() throws {
        func makeThread(messageCount: Int, isNews: Bool) throws -> ApiAgentV2ThreadSummary {
            let news = isNews ? #","news":{"eventId":7,"headline":"Headline","publishedAt":"2026-10-20T10:00:00Z"}"# : ""
            let json = """
            {"id":"thread","revision":1,"createdAt":"2026-10-20T12:00:00Z","updatedAt":"2026-10-20T12:00:00Z",\
            "lastActivityAt":"2026-10-20T12:00:00Z","messageCount":\(messageCount)\(news)}
            """
            return try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data(json.utf8))
        }
        XCTAssertFalse(try makeThread(messageCount: 0, isNews: true).isStarted)
        XCTAssertFalse(try makeThread(messageCount: 1, isNews: true).isStarted)
        XCTAssertTrue(try makeThread(messageCount: 2, isNews: true).isStarted)
        XCTAssertTrue(try makeThread(messageCount: 0, isNews: false).isStarted)
        XCTAssertTrue(try makeThread(messageCount: 1, isNews: false).isStarted)
    }

    func testThreadListDecodesMetadataPreviewsAndPagination() throws {
        let thread: [String: Any] = [
            "id": "thread-a", "revision": 4,
            "createdAt": "2026-09-29T10:00:00.000Z", "updatedAt": "2026-09-30T04:00:00.000Z",
            "lastActivityAt": "2026-09-30T04:00:00.000Z", "messageCount": 12,
            "title": "My portfolio", "icon": "💼", "hasCustomTitle": true, "isPinned": true
        ]
        let response = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2ThreadListResponse>.self,
            from: JSONSerialization.data(withJSONObject: [
                "ok": true, "value": [
                    "protocolVersion": 3,
                    "threads": [["thread": thread, "preview": "You hold 5 TON."], ["thread": thread]],
                    "nextCursor": "next-page"
                ]
            ])
        )
        let list = try XCTUnwrap(response.value)
        XCTAssertEqual(list.protocolVersion, 3)
        XCTAssertEqual(list.threads.count, 2)
        XCTAssertEqual(list.nextCursor, "next-page")
        XCTAssertEqual(list.threads.first?.thread.title, "My portfolio")
        XCTAssertEqual(list.threads.first?.thread.icon, "💼")
        XCTAssertEqual(list.threads.first?.thread.hasCustomTitle, true)
        XCTAssertEqual(list.threads.first?.thread.isPinned, true)
        XCTAssertEqual(list.threads.first?.preview, "You hold 5 TON.")
        XCTAssertNil(list.threads.last?.preview)
        XCTAssertEqual(try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: JSONEncoder().encode(list)), list)

        let empty = try JSONDecoder().decode(
            ApiAgentV2ThreadListResponse.self, from: Data(#"{"protocolVersion":3,"threads":[]}"#.utf8)
        )
        XCTAssertTrue(empty.threads.isEmpty)
        XCTAssertNil(empty.nextCursor)
    }

    func testThreadUpdateEncodesOnlyProvidedFieldsAndAnExplicitTitleReset() throws {
        let updates: [(ApiAgentV2ThreadUpdate, NSDictionary)] = [
            (.init(title: "My portfolio"), ["title": "My portfolio"]),
            (.init(title: nil), ["title": NSNull()]),
            (.init(isPinned: true), ["isPinned": true]),
            (.init(isPinned: false), ["isPinned": false]),
            (.init(title: "My portfolio", isPinned: true), ["title": "My portfolio", "isPinned": true]),
            (.init(title: nil, isPinned: false), ["title": NSNull(), "isPinned": false])
        ]
        for (update, expected) in updates {
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? NSDictionary)
            XCTAssertEqual(encoded, expected)
            XCTAssertGreaterThan(encoded.count, 0)
        }
    }

    @MainActor
    func testLiveThreadClientUsesSdkOperationsAndUnwrapsTheirResponses() async throws {
        let probe = try installThreadBridgeProbe()
        defer { Api.stop() }
        let client = LiveAgentV2Client()
        let thread = try decodeHydration(threadId: "thread-a", messages: []).thread
        let threadJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread))

        probe.response = try threadOperationJSON(["protocolVersion": 3, "threads": [["thread": threadJSON]], "nextCursor": "next"])
        let list = try await client.listThreads(cursor: "cursor", limit: 20, query: "staking")
        XCTAssertEqual(list.threads.map(\.thread), [thread])
        XCTAssertEqual(list.nextCursor, "next")
        XCTAssertEqual(probe.calls.last?.method, "listAgentV2Threads")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [["cursor": "cursor", "limit": 20, "query": "staking"]] as NSArray)

        _ = try await Api.listAgentV2Threads()
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [[:]] as NSArray)

        probe.response = try threadOperationJSON(["protocolVersion": 3, "thread": threadJSON, "created": true])
        let created = try await client.createThread()
        XCTAssertTrue(created.created)
        XCTAssertEqual(created.thread, thread)
        XCTAssertEqual(probe.calls.last?.method, "createAgentV2Thread")
        XCTAssertEqual(probe.calls.last?.arguments.count, 0)

        probe.response = try threadOperationJSON(["protocolVersion": 3, "thread": threadJSON])
        let updated = try await client.updateThread(id: thread.id, update: .init(title: nil, isPinned: false))
        XCTAssertEqual(updated.thread, thread)
        XCTAssertEqual(probe.calls.last?.method, "updateAgentV2Thread")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [thread.id, ["title": NSNull(), "isPinned": false]] as NSArray)

        probe.response = try threadOperationJSON(["protocolVersion": 3, "threadId": thread.id, "duplicate": true])
        let deleted = try await client.deleteThread(id: thread.id)
        XCTAssertEqual(deleted.threadId, thread.id)
        XCTAssertTrue(deleted.duplicate)
        XCTAssertEqual(probe.calls.last?.method, "deleteAgentV2Thread")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [thread.id] as NSArray)
    }

    @MainActor
    func testNewsPushOpeningUsesTheFeedLocaleAndAvailablePreview() async throws {
        for hasPreview in [false, true] {
            let item = newsFeedItem(eventId: 307)
            let thread = try decodeNewsThread(id: "push-news", eventId: 307, headline: "News", messageCount: 1)
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history)
            client.hasConsent = false
            client.createdThread = thread
            client.blocksThreadCreation = true
            let feedClient = ThreadListNewsClient(items: hasPreview ? [item] : [])
            feedClient.locale = "ru"
            let preloader = AgentPreloader(client: client)
            defer {
                client.resumeThreadCreation()
                preloader.setWalletReady(false)
            }
            let controller = try await AgentEntryPoint.makeNewsChatViewController(
                eventId: 307, client: feedClient, preloader: preloader
            )
            let chat = try XCTUnwrap(controller as? AgentVC)
            let model = try chatModel(in: chat)
            XCTAssertEqual(model.news?.body, hasPreview ? item.body : nil)
            XCTAssertEqual(model.newsPostItemID != nil, hasPreview)
            client.resumeThreadCreation()
            await model.waitForInitialLoad()
            XCTAssertEqual(client.newsThreadRequests, [.init(eventId: 307, locale: "ru")])
            XCTAssertTrue(model.needsConsentToSend)
            XCTAssertFalse(model.isStarted)
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testDigestDiscussionOpensAndHydratesBeforeConsentWithoutStartingARun() async throws {
        let digestId = "ru:2026-11-08T18:00:00.000Z"
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data("""
        {"id":"digest-thread","revision":1,"createdAt":"2026-11-08T18:00:00.000Z",
         "updatedAt":"2026-11-08T18:00:00.000Z","lastActivityAt":"2026-11-08T18:00:00.000Z","messageCount":1,
         "digest":{"id":"\(digestId)","windowEnd":"2026-11-08T18:00:00.000Z","total":1,
                   "top":[{"eventId":307,"headline":"News"}]}}
        """.utf8))
        let history = try decodeHydration(threadId: thread.id, messages: [
            newsPostMessage(id: "digest-post", text: "Daily digest", role: "assistant", threadId: thread.id, newsPost: true)
        ], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history)
        client.hasConsent = false
        client.createdThread = thread
        let coordinator = AgentV2Coordinator(client: client, digestRequest: .init(id: digestId))
        defer { coordinator.stop() }
        coordinator.start()
        await coordinator.waitForInitialLoad()
        XCTAssertEqual(client.digestThreadRequests, [.init(id: digestId)])
        XCTAssertEqual(coordinator.thread?.digest?.id, digestId)
        XCTAssertTrue(coordinator.hasHydratedMessages)
        XCTAssertTrue(coordinator.needsConsentToSend)
        XCTAssertEqual(coordinator.messages.first?.newsPost, true)
        XCTAssertFalse(coordinator.thread!.isStarted)
        XCTAssertTrue(client.startedCommands.isEmpty)
        // The chat shows the server's post as a news thread shows its post, with the digest's card in place of the news
        let model = AgentV2Model(client: client, digestRequest: .init(id: digestId)) { _ in }
        defer { model.stop() }
        await model.waitForInitialLoad()
        let postID = try XCTUnwrap(model.newsPostItemID)
        XCTAssertEqual(model.itemIDs.filter { model.message(for: $0)?.newsPost == true }, [postID])
        XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.text == "Daily digest" })
        let post = try XCTUnwrap(model.message(for: postID))
        XCTAssertNil(model.newsPost(for: post))
        XCTAssertEqual(model.newsPostContent(for: post), AgentNewsPostView.Content(digest: try XCTUnwrap(thread.digest)))
        XCTAssertEqual(model.newsPostContent(for: post)?.digestHeadlines.map(\.headline), ["News"])
        XCTAssertEqual(AgentV2Copy.error(.digestUnavailable), lang("$agent_digest_unavailable"))
        client.threadCreationError = ApiAgentV2MutationError(code: .digestUnavailable, retryable: false)
        let unavailable = AgentV2Coordinator(client: client, digestRequest: .init(id: digestId))
        defer { unavailable.stop() }
        unavailable.start()
        await unavailable.waitForInitialLoad()
        XCTAssertEqual(unavailable.error, lang("$agent_digest_unavailable"))
    }

    @MainActor
    func testNewsOperationsForwardLanguageCursorAndOptionalThreadNews() async throws {
        let probe = try installThreadBridgeProbe()
        defer { Api.stop() }
        probe.response = try threadOperationJSON(["locale": "ru", "items": [], "nextCursor": "older"])

        let page = try await LiveAgentNewsFeedClient().getNewsFeed(
            lang: "ru-RU", cursor: "cursor", schedule: .init(hour: 21, minute: 45, timeZone: "Europe/Moscow")
        )
        XCTAssertEqual(page.locale, "ru")
        XCTAssertEqual(page.nextCursor, "older")
        XCTAssertEqual(probe.calls.last?.method, "getAgentV2NewsFeed")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [["lang": "ru-RU", "cursor": "cursor", "digestHour": 21, "digestMinute": 45, "timeZone": "Europe/Moscow"]] as NSArray)
        probe.response = try threadOperationJSON(["locale": "en", "items": []])
        let firstPage = try await Api.getAgentV2NewsFeed(lang: "es", digestHour: 21, digestMinute: 0, timeZone: "Europe/Madrid")
        XCTAssertEqual(firstPage.locale, "en")
        XCTAssertNil(firstPage.nextCursor)
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [["lang": "es", "digestHour": 21, "digestMinute": 0, "timeZone": "Europe/Madrid"]] as NSArray)

        _ = try await LiveAgentNewsFeedClient().getNewsFeed(
            lang: "ru", cursor: "older-digests", schedule: .init(hour: 9, minute: 15, timeZone: "UTC"), view: .digests
        )
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [[
            "lang": "ru", "cursor": "older-digests", "digestHour": 9, "digestMinute": 15, "timeZone": "UTC", "view": "digests"
        ]] as NSArray)

        let thread = try decodeHydration(threadId: "news-thread", messages: []).thread
        probe.response = try threadOperationJSON([
            "protocolVersion": 3,
            "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)),
            "created": true
        ])
        _ = try await Api.createAgentV2Thread(news: .init(eventId: 307, locale: "ru"))
        XCTAssertEqual(probe.calls.last?.method, "createAgentV2Thread")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [["news": ["eventId": 307, "locale": "ru"]]] as NSArray)
        let created = try await LiveAgentV2Client().createThread(news: .init(eventId: 308, locale: "es"))
        XCTAssertEqual(created.thread, thread)
        XCTAssertTrue(created.created)
        XCTAssertEqual(probe.calls.last?.method, "createAgentV2Thread")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [["news": ["eventId": 308, "locale": "es"]]] as NSArray)

        _ = try await LiveAgentV2Client().createThread(digest: .init(id: "ru:2026-11-08T18:00:00.000Z"))
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [["digest": ["id": "ru:2026-11-08T18:00:00.000Z"]]] as NSArray)

        probe.response = #"{"ok":true}"#
        let notificationResult = try await Api.setNewsNotifications(props: .init(
            mode: .digest, userToken: "push-token", platform: .ios, langCode: "ru", digestHour: 21, digestMinute: 30, timeZone: "Europe/Moscow"
        ))
        XCTAssertTrue(notificationResult.ok)
        XCTAssertEqual(probe.calls.last?.method, "setNewsNotifications")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [[
            "mode": "digest", "userToken": "push-token", "platform": "ios", "langCode": "ru",
            "digestHour": 21, "digestMinute": 30, "timeZone": "Europe/Moscow"
        ]] as NSArray)

        probe.response = #"{"ok":false,"error":{"code":"news_unavailable","retryable":true}}"#
        do {
            _ = try await Api.getAgentV2NewsFeed(lang: "en", digestHour: 21, digestMinute: 0, timeZone: "UTC")
            XCTFail("Expected news_unavailable")
        } catch let error as ApiAgentV2MutationError {
            XCTAssertEqual(error.code, .newsUnavailable)
            XCTAssertTrue(error.retryable)
            XCTAssertEqual(AgentV2Copy.error(error.code), lang("$agent_news_unavailable"))
        }
    }

    @MainActor
    func testThreadOperationsThrowSdkFailuresAndRejectMissingValues() async throws {
        let probe = try installThreadBridgeProbe()
        defer { Api.stop() }
        let operations: [(String, @MainActor () async throws -> Void)] = [
            ("getAgentV2NewsFeed", { _ = try await Api.getAgentV2NewsFeed(lang: "en", digestHour: 21, digestMinute: 0, timeZone: "UTC") }),
            ("listAgentV2Threads", { _ = try await Api.listAgentV2Threads() }),
            ("createAgentV2Thread", { _ = try await Api.createAgentV2Thread() }),
            ("updateAgentV2Thread", { _ = try await Api.updateAgentV2Thread(threadId: "thread-a", update: .init(isPinned: true)) }),
            ("deleteAgentV2Thread", { _ = try await Api.deleteAgentV2Thread(threadId: "thread-a") })
        ]
        for (method, operation) in operations {
            probe.response = #"{"ok":false,"error":{"code":"thread_not_found","retryable":false}}"#
            do {
                try await operation()
                XCTFail("Expected operation failure for \(method)")
            } catch let error as ApiAgentV2MutationError {
                XCTAssertEqual(error.code, .threadNotFound)
                XCTAssertFalse(error.retryable)
            }
            for response in [#"{"ok":true}"#, #"{"ok":false}"#] {
                probe.response = response
                do {
                    try await operation()
                    XCTFail("Expected invalid operation response for \(method)")
                } catch SdkError.invalidResponse(let methodName, _, _) {
                    XCTAssertEqual(methodName, method)
                }
            }
        }
    }

    @MainActor
    func testCachedThreadReadsDecodeTheSdkCacheAndTurnEveryFailureIntoNil() async throws {
        let probe = try installThreadBridgeProbe()
        defer { Api.stop() }
        let thread = try decodeHydration(threadId: "thread-a", messages: []).thread
        let threadJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread))
        let message: [String: Any] = [
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Cached question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]

        probe.response = String(bytes: try JSONSerialization.data(withJSONObject: [
            ["thread": threadJSON, "preview": "You hold 5 TON."]
        ]), encoding: .utf8)
        let threads = await Api.getAgentV2CachedThreads()
        XCTAssertEqual(threads, [ApiAgentV2ThreadListItem(thread: thread, preview: "You hold 5 TON.")])
        XCTAssertEqual(probe.calls.last?.method, "getAgentV2CachedThreads")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, [] as NSArray)

        probe.response = String(bytes: try JSONSerialization.data(withJSONObject: [
            "thread": threadJSON, "messages": [message], "hasOlder": true
        ]), encoding: .utf8)
        let cachedResult = await Api.getAgentV2CachedMessages(threadId: "thread-a")
        let cached = try XCTUnwrap(cachedResult)
        XCTAssertEqual(cached.thread, thread)
        XCTAssertEqual(cached.messages.map(\.id), ["question"])
        XCTAssertTrue(cached.hasOlder)
        XCTAssertEqual(probe.calls.last?.method, "getAgentV2CachedMessages")
        XCTAssertEqual(probe.calls.last?.arguments as? NSArray, ["thread-a"] as NSArray)

        for response in [nil, #"{"thread":"#, #"{"ok":false,"error":{"code":"thread_not_found"}}"#] {
            probe.response = response
            let cachedThreads = await Api.getAgentV2CachedThreads()
            let cachedMessages = await Api.getAgentV2CachedMessages(threadId: "thread-a")
            XCTAssertNil(cachedThreads)
            XCTAssertNil(cachedMessages)
        }
    }

    @MainActor
    private func installThreadBridgeProbe() throws -> AgentThreadBridgeWebView {
        Api.prepare(on: UIViewController())
        let probe = AgentThreadBridgeWebView()
        let bridge = try Api.bridge
        bridge.replaceWebView(probe)
        bridge.webView(probe, didFinish: nil)
        return probe
    }

    private func threadOperationJSON(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "value": value]), as: UTF8.self)
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
    func testMessageLinkRoutesRespectTheRenderingPolicy() throws {
        let cases: [MessageLinkCase] = [
            .init(link: "\(SELF_PROTOCOL)settings/appearance", policy: .agentV2Safe, isHandled: true, expected: ["deeplink"]),
            .init(link: "\(SELF_PROTOCOL)settings/appearance", policy: .agentV2Safe, isHandled: false, expected: ["deeplink", "error"]),
            .init(link: "https://t.me/mywallet", policy: .agentV2Safe, isHandled: true, expected: ["telegram"]),
            .init(link: "https://help.mywallet.io/", policy: .agentV2Safe, isHandled: true, expected: ["browser"]),
            .init(link: "http://example.com/", policy: .agentV2Safe, isHandled: false, expected: ["error"]),
            .init(link: "tg://resolve?domain=mywallet", policy: .agentV2Safe, isHandled: false, expected: ["error"]),
            .init(link: "javascript:alert(1)", policy: .agentV2Safe, isHandled: true, expected: ["error"]),
            .init(link: "\(SELF_PROTOCOL)settings/appearance", policy: .classic, isHandled: true, expected: ["deeplink"]),
            .init(link: "https://t.me/mywallet", policy: .classic, isHandled: false, expected: ["deeplink", "telegram"]),
            .init(link: "tg://resolve?domain=mywallet", policy: .classic, isHandled: false, expected: ["deeplink", "telegram"]),
            .init(link: "http://example.com/", policy: .classic, isHandled: false, expected: ["deeplink", "browser"]),
            .init(link: "https://example.com/", policy: .classic, isHandled: false, expected: ["deeplink", "browser"]),
            .init(link: "javascript:alert(1)", policy: .classic, isHandled: false, expected: ["deeplink", "error"]),
            .init(link: "https://mywallet.io/agent?prompt=Hello", policy: .classic, isHandled: true, expected: ["deeplink"]),
            .init(link: "https://mywallet.io/agent?prompt=Hello", policy: .agentV2Safe, isHandled: true, expected: ["browser"]),
            .init(link: "\(SELF_PROTOCOL)agent?prompt=Hello", policy: .classic, isHandled: true, expected: ["deeplink"]),
            .init(link: "\(SELF_PROTOCOL)agent?prompt=Hello", policy: .agentV2Safe, isHandled: true, expected: ["error"])
        ]
        for testCase in cases {
            let url = try XCTUnwrap(URL(string: testCase.link))
            var events: [String] = []
            AgentMessageLinks.openMessageURL(
                url,
                renderingPolicy: testCase.policy,
                handleDeeplink: {
                    XCTAssertEqual($0, url)
                    events.append("deeplink")
                    return testCase.isHandled
                },
                openTelegram: {
                    XCTAssertEqual($0, url)
                    events.append("telegram")
                },
                openBrowser: {
                    XCTAssertEqual($0, url)
                    events.append("browser")
                },
                showError: {
                    XCTAssertEqual($0.text, lang("Unsupported link"))
                    events.append("error")
                }
            )
            XCTAssertEqual(events, testCase.expected, "\(testCase.link), \(testCase.policy)")
        }
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
    func testSupportChatFromTheChatListAsksOnlyWhileTheUserStaysOnItsLoadingScreen() async throws {
        for isLeft in [false, true] {
            let client = FakeAgentV2Client(
                hydrationResult: try decodeHydration(threadId: "thread-a", messages: []), blockedHydrationAttempt: 1
            )
            let root = AgentRootVC(client: client, shouldRequestSupport: true)
            let navigation = UINavigationController(rootViewController: root)
            let window = makeKeyWindow(showing: navigation)
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                client.resumeBlockedHydration()
            }
            window.layoutIfNeeded()
            for _ in 0..<300 where client.hydrationRequestCount == 0 {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(client.hydrationRequestCount, 1, "left: \(isLeft)")

            // The user goes back or switches tabs while the new chat's history loads, or stays
            if isLeft {
                root.beginAppearanceTransition(false, animated: false)
                root.endAppearanceTransition()
            }
            client.resumeBlockedHydration()
            await waitForChat(in: navigation)
            XCTAssertTrue(navigation.topViewController is AgentVC, "left: \(isLeft)")
            for _ in 0..<30 where client.startedCommands.isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(
                client.startedCommands.map(\.entryPoint),
                isLeft ? [] : [.supportRequest(source: .starterHint)],
                "left: \(isLeft)"
            )
        }
    }

    @MainActor
    func testLeavingConsentSuppressesBothCancellationAndLateServiceErrors() async throws {
        for error in [CancellationError(), FakeAgentV2ClientError.unavailable] as [Error] {
            let client = FakeAgentV2Client()
            client.hasConsent = false
            client.blocksConsentAcceptance = true
            client.consentAcceptanceError = error
            var errorCount = 0
            let root = AgentRootVC(client: client, showError: { _ in errorCount += 1 })
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
        var errors: [String] = []
        let root = AgentRootVC(client: client, showError: { errors.append($0) })
        let navigation = UINavigationController(rootViewController: root)
        defer { navigation.setViewControllers([], animated: false) }
        root.loadViewIfNeeded()
        let consent = try await waitForConsentView(in: root)
        let cases: [(Error, String?)] = [
            (CancellationError(), nil),
            (ApiAgentV2MutationError(code: .runInterrupted, retryable: false), nil),
            (ApiAgentV2MutationError(code: .networkError, retryable: true), AgentV2Copy.error(.networkError)),
            (FakeAgentV2ClientError.unavailable, lang("$agent_error_generic"))
        ]
        var expectedErrors: [String] = []
        for (error, expectedText) in cases {
            client.consentAcceptanceError = error
            consent.onContinue?()
            for _ in 0..<100 { await Task.yield() }
            if let expectedText { expectedErrors.append(expectedText) }
            XCTAssertEqual(errors, expectedErrors)
            XCTAssertTrue(consent.isUserInteractionEnabled)
        }
        XCTAssertEqual(client.requestOrder.filter { $0 == "acceptConsent" }.count, cases.count)
    }

    /// The consent in the sheet that `controller` asks with
    @MainActor
    private func waitForConsentView(in controller: UIViewController) async throws -> AgentConsentView {
        try await waitForConsentSheet(over: controller, in: self).consentView
    }

    @MainActor
    func testThreadEntryRequiresConsentBeforeHydratingTheSelectedThread() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        let history = try decodeHydration(threadId: "thread-b", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history)
        client.hasConsent = false
        let preloader = AgentPreloader(client: client)
        let root = try XCTUnwrap(
            AgentEntryPoint.makeRootViewController(thread: history.thread, preloader: preloader) as? AgentRootVC
        )
        let navigation = UINavigationController(rootViewController: root)
        defer { navigation.setViewControllers([], animated: false) }
        root.loadViewIfNeeded()
        let consent = try await waitForConsentView(in: root)
        XCTAssertEqual(presentation.presentedSheets.count, 1, "The thread asks in the sheet")
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertEqual(client.hydrationRequestCount, 0)
        XCTAssertFalse(client.requestOrder.contains("defaultThread"))

        client.hasConsent = true
        consent.onContinue?()
        await waitForChat(in: navigation)
        XCTAssertTrue(navigation.topViewController is AgentVC)
        XCTAssertEqual(presentation.dismissalCount, 1, "Allow closes the sheet")
        XCTAssertEqual(client.hydratedThreadIds, ["thread-b"])
        XCTAssertFalse(client.requestOrder.contains("defaultThread"))
        XCTAssertEqual(client.requestOrder.filter { $0 == "acceptConsent" }.count, 1)
    }

    @MainActor
    func testThreadRegistrySharesOneLiveModelAndHydrationPerThread() async throws {
        let history = try decodeHydration(threadId: "selected", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        let preloader = AgentPreloader(client: client)
        let first = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        defer { preloader.setWalletReady(false) }
        await waitForHydrationRequest(client, count: 1)
        let second = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        XCTAssertTrue(first === second)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        client.resumeBlockedHydration()
        await second.waitForInitialLoad()
        XCTAssertTrue(second.isReadyForPresentation)
        XCTAssertFalse(client.requestOrder.contains("defaultThread"))
    }

    /// A news discussion first opened from the chats list, without the feed's language, takes the language of the feed
    /// that reopens it, and its Share link carries it rather than the app language. The app language is the
    /// simulator's, so the feed's is the other one.
    @MainActor
    func testReopenedNewsDiscussionSharesTheLinkInTheFeedsLanguage() async throws {
        let feedLocale = AgentNewsFeedModel.getLocale(langCode: LocalizationSupport.shared.langCode) == "en" ? "ru" : "en"
        let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: "Feed headline", messageCount: 1)
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: thread.id, messages: [], thread: thread))
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let model = try XCTUnwrap(preloader.acquireModel(thread: thread))
        XCTAssertNil(model.newsLocale)
        let item = ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline", body: "News body",
            discussion: .init(threadId: thread.id)
        )
        let reopened = try XCTUnwrap(preloader.acquireModel(thread: thread, news: (item, feedLocale)))
        XCTAssertTrue(reopened === model)
        await model.waitForInitialLoad()
        var sharedItems: [Any]?
        let items = AgentMessageMenuItems.makeItems(
            for: try XCTUnwrap(model.newsPostContent), locale: model.newsLocale, openSource: { _ in }, share: { sharedItems = $0 }
        )
        guard case .action(let share)? = items.last else { return XCTFail("The post's menu has no Share") }
        share.handler?()
        XCTAssertEqual(sharedItems?.last as? URL, URL(string: "https://my.tt/agent?news=307&lang=\(feedLocale)&utm_source=pulse_share"))
    }

    @MainActor
    func testThreadRegistryKeepsDifferentThreadsIsolatedAndReplacesStoppedModels() async throws {
        let firstHistory = try decodeHydration(threadId: "first", messages: [])
        let secondHistory = try decodeHydration(threadId: "second", messages: [])
        let client = FakeAgentV2Client(hydrationResults: [firstHistory, secondHistory, firstHistory])
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let first = try XCTUnwrap(preloader.acquireModel(thread: firstHistory.thread))
        await first.waitForInitialLoad()
        let second = try XCTUnwrap(preloader.acquireModel(thread: secondHistory.thread))
        await second.waitForInitialLoad()
        XCTAssertFalse(first === second)
        XCTAssertEqual(first.threadId, "first")
        XCTAssertEqual(second.threadId, "second")
        first.stop()
        let replacement = try XCTUnwrap(preloader.acquireModel(thread: firstHistory.thread))
        await replacement.waitForInitialLoad()
        XCTAssertFalse(first === replacement)
        XCTAssertTrue(second === preloader.acquireModel(thread: secondHistory.thread))
        XCTAssertEqual(client.hydratedThreadIds, ["first", "second", "first"])
        XCTAssertFalse(client.requestOrder.contains("defaultThread"))
    }

    @MainActor
    func testWalletResetStopsEveryThreadAndClearsTheRegistry() async throws {
        let history = try decodeHydration(threadId: "selected", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history)
        let preloader = AgentPreloader(client: client)
        let original = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        await original.waitForInitialLoad()
        preloader.walletCore(event: .accountsReset)
        XCTAssertFalse(original.isReadyForPresentation)
        let replacement = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        defer { preloader.setWalletReady(false) }
        XCTAssertFalse(original === replacement)
        await replacement.waitForInitialLoad()
        XCTAssertTrue(replacement.isReadyForPresentation)
    }

    @MainActor
    func testSharedThreadStaysActiveAndRunningWhileAnotherChatControllerIsRemoved() async throws {
        let history = try decodeHydration(threadId: "shared", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history)
        let preloader = AgentPreloader(client: client)
        let model = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        await model.waitForInitialLoad()
        let first = AgentVC(model: model)
        let second = AgentVC(model: try XCTUnwrap(preloader.acquireModel(thread: history.thread)))
        first.loadViewIfNeeded()
        second.loadViewIfNeeded()
        first.viewIsAppearing(false)
        second.viewIsAppearing(false)
        first.viewWillDisappear(false)
        XCTAssertTrue(model.isActive)
        XCTAssertTrue(model.delegate === second)
        first.didMove(toParent: nil)
        XCTAssertTrue(model.isReadyForPresentation)
        XCTAssertTrue(model.isActive)
        second.viewWillDisappear(false)
        XCTAssertFalse(model.isActive)
        second.didMove(toParent: nil)
        XCTAssertTrue(model.isReadyForPresentation)
        first.viewIsAppearing(false)
        XCTAssertTrue(model.isActive)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        preloader.setWalletReady(false)
    }

    @MainActor
    func testSharedDeferredNewsKeepsCreationRetryWhenOneChatControllerLeaves() async throws {
        let item = ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline", body: "News body"
        )
        let thread = try decodeNewsThread(id: "news-thread", eventId: item.eventId, headline: "News", messageCount: 1)
        let history = try decodeHydration(threadId: thread.id, messages: [
            newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
        ], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksThreadCreation = true
        client.threadCreationError = FakeAgentV2ClientError.unavailable
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let model = preloader.acquireNewsModel(item: item, locale: "en", onThreadCreated: { _ in })
        let first = AgentVC(model: model)
        let second = AgentVC(model: model)
        defer {
            model.stop()
            client.resumeThreadCreation()
            client.resumeRunStart()
            preloader.setWalletReady(false)
        }
        await model.waitForInitialLoad()
        first.loadViewIfNeeded()
        second.loadViewIfNeeded()
        first.viewIsAppearing(false)
        second.viewIsAppearing(false)
        model.send(text: "First question")
        await waitForRequest("createThread", client: client)
        first.viewWillDisappear(false)
        first.didMove(toParent: nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertTrue(model.isActive)
        XCTAssertTrue(model.delegate === second)
        client.resumeThreadCreation()
        await model.waitForInitialLoad()

        XCTAssertTrue(model.isReadyForPresentation)
        XCTAssertTrue(model.isActive)
        XCTAssertTrue(model.delegate === second)
        let failure = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.isFailureCaption })
        XCTAssertEqual(failure.text, lang("Agent is unavailable"))
        let retry = try XCTUnwrap(failure.controls.first { $0.id == "retry-opening" })
        XCTAssertTrue(retry.isEnabled)
        XCTAssertTrue(client.startedCommands.isEmpty)
        client.threadCreationError = nil
        client.blocksThreadCreation = true
        model.performControl(messageID: failure.id, controlID: retry.id)
        model.performControl(messageID: failure.id, controlID: retry.id)
        try await waitForDiscussionUI { client.newsThreadRequests.count == 2 }
        client.resumeThreadCreation()
        await model.waitForInitialLoad()
        try await waitForDiscussionUI { client.startedCommands.count == 1 }

        XCTAssertEqual(client.newsThreadRequests.count, 2)
        XCTAssertEqual(client.cancelledThreadCreationCount, 0)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question")])
        XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role == .user }.map(\.text), ["First question"])
    }

    @MainActor
    func testChatModelStopsAfterItsLastControllerDeallocates() async throws {
        let history = try decodeHydration(threadId: "shared", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history)
        let preloader = AgentPreloader(client: client)
        let model = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        await model.waitForInitialLoad()
        var first: AgentVC? = AgentVC(model: model)
        var second: AgentVC? = AgentVC(model: model)
        weak var weakFirst = first
        weak var weakSecond = second
        first = nil
        for _ in 0..<100 where weakFirst != nil { await Task.yield() }
        XCTAssertNil(weakFirst)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(model.isReadyForPresentation)
        second = nil
        for _ in 0..<100 where weakSecond != nil { await Task.yield() }
        XCTAssertNil(weakSecond)
        for _ in 0..<100 where model.isReadyForPresentation { await Task.yield() }
        XCTAssertFalse(model.isReadyForPresentation)
    }

    @MainActor
    func testDeletingThreadClosesEveryChatAcrossNavigationStacksAndStopsSending() async throws {
        let history = try decodeHydration(threadId: "deleted", messages: [])
        let otherHistory = try decodeHydration(threadId: "other", messages: [])
        let client = FakeAgentV2Client(hydrationResults: [history, otherHistory])
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let model = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        await model.waitForInitialLoad()
        let otherModel = try XCTUnwrap(preloader.acquireModel(thread: otherHistory.thread))
        await otherModel.waitForInitialLoad()
        let first = AgentVC(model: model)
        let second = AgentVC(model: model)
        let rootChat = AgentVC(model: model)
        let otherChat = AgentVC(model: otherModel)
        let firstRoot = UIViewController()
        let secondRoot = UIViewController()
        let detail = UIViewController()
        let firstNavigation = UINavigationController()
        firstNavigation.setViewControllers([firstRoot, first, otherChat], animated: false)
        let secondNavigation = UINavigationController()
        secondNavigation.setViewControllers([secondRoot, second], animated: false)
        let rootChatNavigation = UINavigationController()
        rootChatNavigation.setViewControllers([rootChat, detail], animated: false)
        let visibleChat = AgentVC(model: model)
        let visibleNavigation = UINavigationController(rootViewController: visibleChat)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = visibleNavigation
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            visibleNavigation.setViewControllers([], animated: false)
        }
        let listModel = AgentThreadListModel(client: client, preloader: preloader)
        XCTAssertTrue(model.canSendMessage(draftText: "Before deletion"))

        await listModel.delete(history.thread)

        XCTAssertEqual(client.deletedThreadIds, [history.thread.id])
        XCTAssertTrue(preloader.isThreadDeleted(history.thread.id))
        XCTAssertNil(preloader.acquireModel(thread: history.thread))
        XCTAssertFalse(model.isReadyForPresentation)
        XCTAssertFalse(model.canSendMessage(draftText: "After deletion"))
        let itemIDs = model.itemIDs
        model.send(text: "After deletion")
        XCTAssertEqual(model.itemIDs, itemIDs)
        XCTAssertTrue(client.startedCommands.isEmpty)
        for _ in 0..<100 where secondNavigation.viewControllers.contains(second) {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<100 where visibleNavigation.viewControllers.contains(visibleChat) {
            try await Task.sleep(for: .milliseconds(10))
        }
        window.layoutIfNeeded()
        let visibleFallback = try XCTUnwrap(visibleNavigation.viewControllers.first as? AgentThreadListVC)
        XCTAssertTrue(visibleFallback.isViewLoaded)
        XCTAssertTrue(WalletCoreData.eventObservers.contains { $0.value === visibleFallback })
        XCTAssertEqual(visibleNavigation.viewControllers.count, 1)
        XCTAssertEqual(firstNavigation.viewControllers, [firstRoot, otherChat])
        XCTAssertEqual(secondNavigation.viewControllers, [secondRoot])
        XCTAssertTrue(rootChatNavigation.viewControllers.first is AgentThreadListVC)
        XCTAssertTrue(rootChatNavigation.topViewController === detail)
        XCTAssertEqual(rootChatNavigation.viewControllers.count, 2)
        XCTAssertTrue(otherModel.isReadyForPresentation)
        XCTAssertTrue(otherModel.canSendMessage(draftText: "Other thread"))
    }

    @MainActor
    func testDeletingThreadDuringHydrationClosesItsPendingRootWithoutReopening() async throws {
        let history = try decodeHydration(threadId: "deleted-loading", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let root = AgentEntryPoint.makeRootViewController(thread: history.thread, preloader: preloader)
        let tabRoot = UIViewController()
        let navigation = UINavigationController(rootViewController: tabRoot)
        navigation.pushViewController(root, animated: false)
        root.loadViewIfNeeded()
        await waitForHydrationRequest(client, count: 1)
        let model = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        let listModel = AgentThreadListModel(client: client, preloader: preloader)

        await listModel.delete(history.thread)
        XCTAssertFalse(model.isReadyForPresentation)
        for _ in 0..<100 where navigation.viewControllers.contains(root) {
            try await Task.sleep(for: .milliseconds(10))
        }
        client.resumeBlockedHydration()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(navigation.viewControllers, [tabRoot])
        XCTAssertFalse(model.isReadyForPresentation)
        XCTAssertTrue(client.startedCommands.isEmpty)
        let staleRoot = AgentEntryPoint.makeRootViewController(thread: history.thread, preloader: preloader)
        navigation.pushViewController(staleRoot, animated: false)
        staleRoot.loadViewIfNeeded()
        for _ in 0..<100 where navigation.viewControllers.contains(staleRoot) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(navigation.viewControllers, [tabRoot])
        XCTAssertEqual(client.hydrationRequestCount, 1)
    }

    @MainActor
    func testCreatingQuestionCannotReopenADeletedEmptyThread() async throws {
        let history = try decodeHydration(threadId: "deleted-empty", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history)
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let root = AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader)
        let tabRoot = UIViewController()
        let navigation = UINavigationController(rootViewController: tabRoot)
        navigation.pushViewController(root, animated: false)
        root.loadViewIfNeeded()
        await waitForRequest("createThread", client: client)
        let listModel = AgentThreadListModel(client: client, preloader: preloader)

        await listModel.delete(history.thread)
        client.resumeThreadCreation()
        for _ in 0..<100 where navigation.viewControllers.contains(root) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(navigation.viewControllers, [tabRoot])
        XCTAssertEqual(client.hydrationRequestCount, 0)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testFailedThreadDeletionKeepsItsOpenChatAndModel() async throws {
        let history = try decodeHydration(threadId: "kept", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksRunStart = true
        client.threadDeletionError = FakeAgentV2ClientError.unavailable
        let preloader = AgentPreloader(client: client)
        defer {
            preloader.setWalletReady(false)
            client.resumeRunStart()
            client.beforeThreadDeletion = nil
        }
        let model = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        await model.waitForInitialLoad()
        let controller = AgentVC(model: model)
        let navigation = UINavigationController(rootViewController: controller)
        let listModel = AgentThreadListModel(client: client, preloader: preloader)
        var errorCount = 0
        listModel.onError = { _ in errorCount += 1 }

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.send(text: "Second question")
        client.beforeThreadDeletion = { @MainActor [weak client] in
            client?.resumeRunStart()
            try? await self.waitForDiscussionUI { !model.hasActiveRun }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(client?.startedCommands.count, 1, "The waiting question stays held during deletion")
            XCTAssertTrue(model.hasQueuedQuestions)
            XCTAssertEqual(model.itemIDs.last.flatMap { self.presentedMessage($0, in: model) }?.text, "Second question")
        }
        await listModel.delete(history.thread)
        try await waitForDiscussionUI { client.startedCommands.count == 2 && !model.hasActiveRun }

        XCTAssertEqual(errorCount, 1)
        XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertFalse(preloader.isThreadDeleted(history.thread.id))
        XCTAssertTrue(model.isReadyForPresentation)
        XCTAssertTrue(model.canSendMessage(draftText: "Still open"))
        XCTAssertTrue(model === preloader.acquireModel(thread: history.thread))
    }

    @MainActor
    func testLeavingQuestionBeforeThreadCreationCancelsItsOpening() async throws {
        let history = try decodeHydration(threadId: "abandoned", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader) as? AgentVC)
        let model = try chatModel(in: chat)
        let home = UIViewController()
        let navigation = UINavigationController(rootViewController: home)
        // On screen, as the user leaves it: off screen, UIKit doesn't tell a popped chat that it left its stack
        let window = makeKeyWindow(showing: navigation)
        navigation.pushViewController(chat, animated: false)
        chat.loadViewIfNeeded()
        defer {
            window.isHidden = true
            client.resumeThreadCreation()
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        await waitForRequest("createThread", client: client)

        navigation.popViewController(animated: false)
        try await waitForDiscussionUI { !model.isReadyForPresentation }
        client.resumeThreadCreation()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertTrue(navigation.topViewController === home)
        XCTAssertNil(model.threadId)
        XCTAssertNil(preloader.model(threadId: history.thread.id))
        XCTAssertEqual(client.cancelledThreadCreationCount, 1)
        XCTAssertEqual(client.hydrationRequestCount, 0)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    /// A question sent from the chat list's field grows into the new chat's first bubble as the chat comes in: in the
    /// window, over both screens, from where the field showed its text to the bubble, which stays out of sight until
    /// the morph lands, while the field is empty at once
    @MainActor
    func testQuestionSentFromTheListGrowsOutOfItsFieldIntoTheNewChatsFirstBubble() async throws {
        let history = try decodeHydration(threadId: "list-question", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        var chat: AgentVC?
        let list = AgentThreadListVC(
            model: AgentThreadListModel(client: client, newsClient: ThreadListNewsClient()),
            loadConsent: { true },
            acceptConsent: {},
            makeNewChat: { query in
                let controller = AgentEntryPoint.makeNewChatViewController(query: query, preloader: preloader)
                chat = controller as? AgentVC
                return controller
            },
            loadSuggestions: { [] }
        )
        let navigation = ListQuestionTestNavigationController(rootViewController: list)
        let window = makeKeyWindow(showing: navigation)
        defer {
            window.isHidden = true
            client.resumeThreadCreation()
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        window.layoutIfNeeded()
        let composer = list.bottomBar.composerView
        composer.setDraftText("Explain my portfolio", focus: false)
        window.layoutIfNeeded()
        let field = composer.convert(composer.inputBackgroundFrame, to: window)

        let sentTime = CACurrentMediaTime()
        composer.onSend?()
        try await waitForDiscussionUI { chat != nil && navigation.topViewController === chat }
        let opened = try XCTUnwrap(chat)
        XCTAssertTrue(composer.draftText?.isEmpty != false, "The field gives the text up at once")
        window.layoutIfNeeded()
        for _ in 0..<300 where opened.suggestionMorph == nil {
            try await Task.sleep(for: .milliseconds(10))
            window.layoutIfNeeded()
        }
        let morph = try XCTUnwrap(
            opened.suggestionMorph,
            "No morph: source \(opened.openingSentSource != nil), scrolled \(opened.hasPerformedInitialScroll), "
                + "opening \(String(describing: opened.initialOpeningInputItemID)), "
                + "cells \(opened.collectionView.visibleCells.count), window \(opened.view.window != nil), "
                + "after \(CACurrentMediaTime() - sentTime) s"
        )
        // It goes to the bubble once the chat shows it
        for _ in 0..<300 where morph.targetFrame == nil {
            try await Task.sleep(for: .milliseconds(10))
            window.layoutIfNeeded()
            morph.step(at: morph.startTime)
        }
        XCTAssertTrue(morph.morphView.superview === window, "Over both screens")
        XCTAssertFalse(morph.startFrame.isEmpty)
        XCTAssertTrue(field.insetBy(dx: -0.5, dy: -0.5).contains(morph.startFrame), "From the list's field: \(morph.startFrame) in \(field)")

        let cells = opened.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.sorted { $0.frame.minY < $1.frame.minY }
        let cell = try XCTUnwrap(cells.first, "The first bubble")
        let bubble = cell.bubbleBackgroundView.convert(cell.bubbleBackgroundView.bodyFrame, to: window)
        let target = try XCTUnwrap(morph.targetFrame, "Into the first bubble")
        XCTAssertEqual(target.minX, bubble.minX, accuracy: 0.5)
        XCTAssertEqual(target.minY, bubble.minY, accuracy: 0.5)
        XCTAssertEqual(target.width, bubble.width, accuracy: 0.5)
        XCTAssertEqual(target.height, bubble.height, accuracy: 0.5)
        XCTAssertEqual(cell.sentAppearanceView.alpha, 0, "The bubble is out of sight until the morph lands")

        morph.step(at: morph.startTime + AgentSuggestionMorph.duration + 1)
        XCTAssertTrue(morph.isFinished)
        XCTAssertNil(morph.morphView.superview)
        XCTAssertEqual(cell.sentAppearanceView.alpha, 1, "Landed, the bubble shows")
    }

    @MainActor
    func testQuestionKeepsItsOpeningWhenMovedToAnotherNavigationStack() async throws {
        let history = try decodeHydration(threadId: "transferred-question", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader) as? AgentVC)
        let model = try chatModel(in: chat)
        let source = UINavigationController(rootViewController: chat)
        let destination = UINavigationController()
        chat.loadViewIfNeeded()
        defer {
            client.resumeThreadCreation()
            source.setViewControllers([], animated: false)
            destination.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        await waitForRequest("createThread", client: client)

        source.setViewControllers([], animated: false)
        destination.setViewControllers([chat], animated: false)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertTrue(chat.parent === destination)
        XCTAssertTrue(model.isReadyForPresentation)
        XCTAssertTrue(client.startedCommands.isEmpty)

        client.resumeThreadCreation()
        try await waitForDiscussionUI { client.startedCommands.count == 1 && !model.hasActiveRun }

        XCTAssertTrue(destination.topViewController === chat)
        XCTAssertTrue(try chatModel(in: chat) === model)
        XCTAssertTrue(preloader.model(threadId: history.thread.id) === model)
        XCTAssertEqual(client.cancelledThreadCreationCount, 0)
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Question")])
    }

    @MainActor
    func testThreadCreationFailureWhileDetachedLeavesARetryActionWithoutShowingAnError() async throws {
        let client = FakeAgentV2Client()
        client.blocksThreadCreation = true
        client.threadCreationError = FakeAgentV2ClientError.unavailable
        var errorCount = 0
        let root = AgentRootVC(client: client, showError: { _ in errorCount += 1 })
        let source = UINavigationController(rootViewController: root)
        root.loadViewIfNeeded()
        await waitForRequest("createThread", client: client)
        source.setViewControllers([UIViewController()], animated: false)
        client.resumeThreadCreation()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(errorCount, 0)
        // The failure shows in the chat's middle with Retry, as the News feed shows a failure with nothing to show
        let errorView = try XCTUnwrap(findDescendants(of: root.view).compactMap { $0 as? AgentLoadErrorView }.first)
        XCTAssertFalse(errorView.isHidden)
        XCTAssertNotNil(errorView.onRetry)
        XCTAssertEqual(client.hydrationRequestCount, 0)
    }

    @MainActor
    func testReturningToSharedChatRefreshesMessagesReceivedByTheOtherController() async throws {
        let initialHistory = try decodeHydration(threadId: "shared", messages: [], nextCursor: "older")
        let olderHistory = try decodeHydration(threadId: "shared", messages: [[
            "id": "older", "threadId": "shared", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Earlier question"],
            "createdAt": "2026-07-21T00:00:01.000Z"
        ]])
        let client = FakeAgentV2Client(hydrationResults: [initialHistory, olderHistory])
        let preloader = AgentPreloader(client: client)
        let model = try XCTUnwrap(preloader.acquireModel(thread: initialHistory.thread))
        await model.waitForInitialLoad()
        let first = AgentVC(model: model)
        let second = AgentVC(model: model)
        first.loadViewIfNeeded()
        first.viewIsAppearing(false)
        first.viewWillDisappear(false)
        second.loadViewIfNeeded()
        second.viewIsAppearing(false)
        defer {
            first.didMove(toParent: nil)
            second.didMove(toParent: nil)
        }
        let collection = try XCTUnwrap(first.view.subviews.compactMap { $0 as? UICollectionView }.first)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        let didLoad = await model.loadOlderMessages()
        XCTAssertTrue(didLoad)
        XCTAssertFalse(model.itemIDs.isEmpty)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        second.viewWillDisappear(false)
        first.viewIsAppearing(false)
        XCTAssertTrue(model.delegate === first)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), model.itemIDs.count + 1)
        XCTAssertEqual(first.title, "Earlier question")
    }

    @MainActor
    func testNewQuestionAppearsImmediatelyAndStartsOnceWithoutHydratingAnEmptyThread() async throws {
        for isCreated in [true, false] {
            let history = try decodeHydration(threadId: "new-thread", messages: [])
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            client.blocksThreadCreation = true
            client.createdThreadIsNew = isCreated
            client.blocksRunStart = true
            client.hintsResult = try initialHints()
            let preloader = AgentPreloader(client: client)
            let entryPoint = ApiAgentV2EntryPoint.globalSearch(query: "Search question")
            let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(
                query: "  Search question \n  ", entryPoint: entryPoint, preloader: preloader
            ) as? AgentVC)
            let model = try chatModel(in: chat)
            let inputID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
            let inputDate = try XCTUnwrap(presentedMessage(inputID, in: model)?.timestamp)
            XCTAssertNil(model.threadId)
            XCTAssertEqual(presentedMessage(inputID, in: model)?.text, "Search question")
            XCTAssertTrue(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
            XCTAssertFalse(model.canSendMessage(draftText: "Follow-up"))
            let navigation = UINavigationController(rootViewController: chat)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            defer {
                client.resumeThreadCreation()
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
                client.resumeRunStart()
            }
            await waitForRequest("createThread", client: client)
            window.layoutIfNeeded()
            XCTAssertEqual(chat.title, "Search question")
            XCTAssertTrue(chat.view.subviews.contains { $0 is AgentComposerView })
            XCTAssertTrue(client.startedCommands.isEmpty)
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertEqual(client.hintsRequestCount, 0)

            client.resumeThreadCreation()
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            for _ in 0..<20 { await Task.yield() }
            chat.viewIsAppearing(false)
            window.layoutIfNeeded()

            XCTAssertTrue(navigation.topViewController === chat)
            XCTAssertTrue(preloader.model(threadId: history.thread.id) === model)
            XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
            XCTAssertFalse(client.requestOrder.contains("defaultThread"))
            XCTAssertEqual(client.hostContextUpdateCount, 1)
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertEqual(client.hintsRequestCount, 0)
            XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Search question")])
            XCTAssertEqual(client.startedCommands.map(\.threadId), [history.thread.id])
            XCTAssertEqual(client.startedCommands.map(\.entryPoint), [entryPoint])
            XCTAssertEqual(presentedMessageID(in: model, role: .user), inputID)
            XCTAssertEqual(presentedMessage(inputID, in: model)?.timestamp, inputDate)
            XCTAssertEqual(model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role == .user }.count, 1)
        }
    }

    @MainActor
    func testQuestionOpeningFailuresKeepTheQuestionAndRetryInsideTheSameChat() async throws {
        for failsConsentCheck in [false, true] {
            let history = try decodeHydration(threadId: "retried-question", messages: [])
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            client.blocksRunStart = true
            if failsConsentCheck {
                client.consentError = FakeAgentV2ClientError.unavailable
            } else {
                client.threadCreationError = FakeAgentV2ClientError.unavailable
            }
            let preloader = AgentPreloader(client: client)
            let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader) as? AgentVC)
            let model = try chatModel(in: chat)
            let inputID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
            let navigation = UINavigationController(rootViewController: chat)
            chat.loadViewIfNeeded()
            defer {
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
                client.resumeRunStart()
            }
            try await waitForDiscussionUI {
                model.itemIDs.compactMap { model.message(for: $0) }.contains { $0.text == lang("Agent is unavailable") && !$0.controls.isEmpty }
            }
            let error = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == lang("Agent is unavailable") })
            let retry = try XCTUnwrap(error.controls.first { $0.title == lang("Retry") })
            XCTAssertTrue(retry.isEnabled)
            XCTAssertEqual(presentedMessage(inputID, in: model)?.text, "Question")
            XCTAssertFalse(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
            XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, failsConsentCheck ? 0 : 1)
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertTrue(client.startedCommands.isEmpty)

            client.consentError = nil
            client.threadCreationError = nil
            model.performControl(messageID: error.id, controlID: retry.id)
            try await waitForDiscussionUI { client.startedCommands.count == 1 }

            XCTAssertTrue(navigation.topViewController === chat)
            XCTAssertTrue(preloader.model(threadId: history.thread.id) === model)
            XCTAssertEqual(presentedMessageID(in: model, role: .user), inputID)
            XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, failsConsentCheck ? 1 : 2)
            XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Question")])
            XCTAssertEqual(client.hydrationRequestCount, 0)
        }
    }

    @MainActor
    func testRetryingOpeningReloadsStartupStatusesAfterTheirFirstRequest() async throws {
        let history = try decodeHydration(threadId: "retried-statuses", messages: [
            newsPostMessage(id: "earlier-question", text: "Earlier question", threadId: "retried-statuses")
        ])
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.hydrationError = FakeAgentV2ClientError.unavailable
        client.blocksRunStart = true
        let coordinator = AgentV2Coordinator(client: client, question: "Question")
        defer {
            coordinator.stop()
            client.resumeRunStart()
        }
        coordinator.start()
        await coordinator.waitForInitialLoad()
        await waitForRequest("availability", client: client)
        await waitForRequest("userQuota", client: client)

        XCTAssertTrue(coordinator.canRetryOpening)
        XCTAssertEqual(client.hostContextUpdateCount, 1)
        XCTAssertEqual(client.requestOrder.filter { $0 == "availability" }.count, 1)
        XCTAssertEqual(client.requestOrder.filter { $0 == "userQuota" }.count, 1)

        client.hydrationError = nil
        coordinator.retryOpening()
        await coordinator.waitForInitialLoad()
        for _ in 0..<100 where client.requestOrder.filter({ $0 == "availability" }).count < 2
            || client.requestOrder.filter({ $0 == "userQuota" }).count < 2 || client.startedCommands.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(client.hostContextUpdateCount, 1)
        XCTAssertEqual(client.requestOrder.filter { $0 == "availability" }.count, 2)
        XCTAssertEqual(client.requestOrder.filter { $0 == "userQuota" }.count, 2)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Question")])
    }

    @MainActor
    func testConsentAcceptanceFailureKeepsTheQuestionAndRetriesInsideTheChat() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "consent-retry", messages: []), shouldCompleteRun: true)
        client.hasConsent = false
        client.consentAcceptanceError = FakeAgentV2ClientError.unavailable
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader) as? AgentVC)
        let model = try chatModel(in: chat)
        let inputID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
        let navigation = UINavigationController(rootViewController: chat)
        chat.loadViewIfNeeded()
        defer {
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.resumeRunStart()
        }
        let consent = try await waitForConsentView(in: chat)
        XCTAssertTrue(client.startedCommands.isEmpty, "Nothing is sent before Allow")
        consent.onContinue?()
        try await waitForDiscussionUI {
            model.itemIDs.compactMap { model.message(for: $0) }.contains { $0.text == lang("Agent is unavailable") && !$0.controls.isEmpty }
        }
        XCTAssertTrue(client.startedCommands.isEmpty, "Nor after a failed acceptance")
        let error = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == lang("Agent is unavailable") })
        let retry = try XCTUnwrap(error.controls.first { $0.title == lang("Retry") })
        XCTAssertEqual(presentedMessage(inputID, in: model)?.text, "Question")
        XCTAssertFalse(client.requestOrder.contains("createThread"))

        client.consentAcceptanceError = nil
        model.performControl(messageID: error.id, controlID: retry.id)
        let retryConsent = try await waitForConsentView(in: chat)
        XCTAssertEqual(presentation.presentedSheets.count, 2, "Retry asks again")
        retryConsent.onContinue?()
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.count, 1, "Sent once")

        XCTAssertTrue(navigation.topViewController === chat)
        XCTAssertEqual(client.requestOrder.filter { $0 == "acceptConsent" }.count, 2)
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Question")])
        XCTAssertEqual(presentedMessageID(in: model, role: .user), inputID)
    }

    @MainActor
    func testReusedLiveEmptyThreadQueuesBothUnsentQuestionsOnceInOrder() async throws {
        let threadId = "shared-opening"
        let empty = try decodeHydration(threadId: threadId, messages: [])
        let firstHistory = try decodeHydration(threadId: threadId, messages: [
            newsPostMessage(id: "first-question", text: "First question", threadId: threadId),
            newsPostMessage(id: "first-answer", text: "First answer", role: "assistant", threadId: threadId)
        ])
        let bothHistory = try decodeHydration(threadId: threadId, messages: [
            newsPostMessage(id: "first-question", text: "First question", threadId: threadId),
            newsPostMessage(id: "first-answer", text: "First answer", role: "assistant", threadId: threadId),
            newsPostMessage(id: "second-question", text: "Second question", threadId: threadId)
        ])
        let firstUpdates = try ([
            ["kind": "runStarted", "threadRevision": 2, "inputMessageId": "first-question"],
            ["kind": "messageStarted", "messageId": "first-answer", "contentKind": "markdown"],
            ["kind": "textDelta", "messageId": "first-answer", "delta": "First answer"]
        ] as [[String: Any]]).map { payload in
            var update: [String: Any] = payload
            update["clientRunId"] = "client-thread-a"
            update["runId"] = "run-thread-a"
            update["threadId"] = threadId
            return try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: update))
        }
        let client = FakeAgentV2Client(hydrationResult: empty, shouldCompleteRun: true, blockedHostContextAttempt: 1)
        client.createdThread = empty.thread
        client.createdThreadIsNew = false
        client.blocksRunStart = true
        client.startRunObserver = { [weak client] in
            guard let client else { return }
            client.runInputMessageId = client.startedCommands.count == 1 ? "first-question" : "second-question"
            client.setHydrationResult(client.startedCommands.count == 1 ? firstHistory : bothHistory)
            if client.startedCommands.count == 1 {
                for update in firstUpdates { WalletCoreData.notify(event: .agentV2(update)) }
            }
        }
        let preloader = AgentPreloader(client: client)
        let firstEntryPoint = ApiAgentV2EntryPoint.globalSearch(query: "First question")
        let secondEntryPoint = ApiAgentV2EntryPoint.globalSearch(query: "Second question")
        let first = preloader.acquireQuestionModel(query: "First question", entryPoint: firstEntryPoint)
        let firstChat = AgentVC(model: first)
        let navigation = UINavigationController(rootViewController: firstChat)
        defer {
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.resumeBlockedHostContextUpdate()
            client.resumeRunStart()
        }
        try await waitForHostContextUpdate(client)
        XCTAssertTrue(preloader.model(threadId: threadId) === first)
        XCTAssertTrue(client.startedCommands.isEmpty)

        let secondChat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(
            query: "Second question", entryPoint: secondEntryPoint, preloader: preloader
        ) as? AgentVC)
        let second = try chatModel(in: secondChat)
        navigation.pushViewController(secondChat, animated: false)
        try await waitForDiscussionUI { second.presentationModel === first && navigation.topViewController !== secondChat }
        let replacement = try XCTUnwrap(navigation.topViewController as? AgentVC)
        XCTAssertTrue(try chatModel(in: replacement) === first)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.viewControllers.first === firstChat)
        XCTAssertNil(second.threadId)
        XCTAssertTrue(preloader.model(threadId: threadId) === first)
        XCTAssertEqual(first.itemIDs.compactMap { presentedMessage($0, in: first) }.filter { $0.role == .user }.map(\.text), ["First question", "Second question"])
        XCTAssertTrue(client.startedCommands.isEmpty)

        client.resumeBlockedHostContextUpdate()
        try await waitForDiscussionUI { client.startedCommands.count == 1 && first.itemIDs.contains { presentedMessage($0, in: first)?.text == "First answer" } }
        XCTAssertEqual(first.itemIDs.compactMap { presentedMessage($0, in: first) }.filter { $0.role != .system }.map(\.text), ["First question", "First answer", "Second question"])
        XCTAssertEqual(client.hydrationRequestCount, 0)

        client.resumeRunStart()
        try await waitForDiscussionUI { client.startedCommands.count == 2 && !first.isOpening && !first.hasActiveRun }

        XCTAssertTrue(second.presentationModel === first)
        XCTAssertTrue(navigation.topViewController === replacement)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(try chatModel(in: replacement) === first)
        XCTAssertTrue(preloader.acquireModel(thread: empty.thread) === first)
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 2)
        XCTAssertEqual(client.startedCommands.map(\.threadId), [threadId, threadId])
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question"), .append(text: "Second question")])
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [firstEntryPoint, secondEntryPoint])
        XCTAssertEqual(first.itemIDs.compactMap { presentedMessage($0, in: first) }.filter { $0.role == .user }.map(\.text), ["First question", "Second question"])
        XCTAssertEqual(first.itemIDs.compactMap { presentedMessage($0, in: first) }.filter { $0.role != .system }.map(\.text), ["First question", "First answer", "Second question"])
        XCTAssertEqual(client.hydrationRequestCount, 2)
    }

    @MainActor
    func testOpeningRunRecoveryHydratesAcceptedQuestionAndStartsItsQueuedQuestionOnce() async throws {
        for code in [ApiAgentV2ErrorCode.threadRevisionConflict, .runReplayExpired] {
            let threadId = "recovered-opening"
            let empty = try decodeHydration(threadId: threadId, messages: [])
            let firstHistory = try decodeHydration(threadId: threadId, messages: [
                newsPostMessage(id: "first-question", text: "First question", threadId: threadId)
            ])
            let bothHistory = try decodeHydration(threadId: threadId, messages: [
                newsPostMessage(id: "first-question", text: "First question", threadId: threadId),
                newsPostMessage(id: "second-question", text: "Second question", threadId: threadId)
            ])
            let client = FakeAgentV2Client(hydrationResult: empty, shouldCompleteRun: true)
            client.createdThread = empty.thread
            client.createdThreadIsNew = false
            client.clientRunIds = ["first-client-run"]
            client.blocksRunStart = true
            client.startRunObserver = { [weak client] in
                guard let client, client.startedCommands.count == 2 else { return }
                client.runInputMessageId = "second-question"
                client.setHydrationResult(bothHistory)
            }
            let preloader = AgentPreloader(client: client)
            let first = preloader.acquireQuestionModel(query: "First question", entryPoint: nil)
            defer {
                preloader.setWalletReady(false)
                client.resumeRunStart()
            }
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            let second = preloader.acquireQuestionModel(query: "Second question", entryPoint: nil)
            try await waitForDiscussionUI { second.presentationModel === first }
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertEqual(first.itemIDs.compactMap { presentedMessage($0, in: first) }.filter { $0.role == .user }.map(\.text), ["First question", "Second question"])
            let failure = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
                "kind": "runFailed", "clientRunId": "first-client-run", "threadId": threadId,
                "code": code.rawValue, "retryable": false
            ]))
            client.setHydrationResult(firstHistory)
            client.blocksRunStart = false

            WalletCoreData.notify(event: .agentV2(failure))
            try await waitForDiscussionUI { client.startedCommands.count == 2 && !first.isOpening && !first.hasActiveRun }

            XCTAssertTrue(preloader.model(threadId: threadId) === first)
            XCTAssertTrue(second.presentationModel === first)
            XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 2)
            XCTAssertEqual(client.hydrationRequestCount, 2)
            XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question"), .append(text: "Second question")])
            XCTAssertEqual(first.itemIDs.compactMap { presentedMessage($0, in: first) }.filter { $0.role == .user }.map(\.text), ["First question", "Second question"])
        }
    }

    @MainActor
    func testOpeningRunFailuresKeepTheirQuotaAndRateLimitCopy() async throws {
        for code in [ApiAgentV2ErrorCode.userQuotaExhausted, .rateLimited] {
            let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "limited-opening", messages: []))
            client.runStartError = ApiAgentV2MutationError(code: code, retryable: true)
            let preloader = AgentPreloader(client: client)
            let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader) as? AgentVC)
            let model = try chatModel(in: chat)
            defer { preloader.setWalletReady(false) }
            try await waitForDiscussionUI {
                model.itemIDs.compactMap { model.message(for: $0) }.contains { $0.text == AgentV2Copy.error(code) && !$0.controls.isEmpty }
            }
            let error = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == AgentV2Copy.error(code) })
            XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Question")])
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertEqual(model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role == .user }.map(\.text), ["Question"])
            XCTAssertTrue(error.controls.contains { $0.title == lang("Retry") })
        }
    }

    @MainActor
    func testLostOpeningRunResponseReloadsRedactedQuestionBeforeRetryWithoutResending() async throws {
        let threadId = "accepted-opening"
        let empty = try decodeHydration(threadId: threadId, messages: [])
        let accepted = try decodeHydration(threadId: threadId, messages: [
            newsPostMessage(id: "accepted-question", text: "Question [hidden secret phrase]", threadId: threadId),
            newsPostMessage(id: "accepted-answer", text: "Answer", role: "assistant", threadId: threadId)
        ])
        let client = FakeAgentV2Client(hydrationResult: empty)
        client.createdThread = empty.thread
        let preloader = AgentPreloader(client: client)
        let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader) as? AgentVC)
        let model = try chatModel(in: chat)
        let inputID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
        let inputDate = try XCTUnwrap(presentedMessage(inputID, in: model)?.timestamp)
        let navigation = UINavigationController(rootViewController: chat)
        chat.loadViewIfNeeded()
        defer {
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        try await waitForDiscussionUI {
            model.itemIDs.compactMap { model.message(for: $0) }.contains { $0.text == lang("Agent is unavailable") && !$0.controls.isEmpty }
        }
        XCTAssertEqual(client.startedCommands.count, 1)
        XCTAssertEqual(client.hydrationRequestCount, 0)
        let error = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == lang("Agent is unavailable") })
        let retry = try XCTUnwrap(error.controls.first { $0.title == lang("Retry") })
        client.setHydrationResult(accepted)

        model.performControl(messageID: error.id, controlID: retry.id)
        try await waitForDiscussionUI { !model.isOpening && model.isReadyForPresentation }

        XCTAssertTrue(navigation.topViewController === chat)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Question")])
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertEqual(presentedMessageID(in: model, role: .user), inputID)
        XCTAssertEqual(presentedMessage(inputID, in: model)?.timestamp, inputDate)
        XCTAssertEqual(model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role == .user }.map(\.text), ["Question [hidden secret phrase]"])
    }

    @MainActor
    func testNewsChatShowsPreviewThenSavedPostWithoutStartingARunForNewAndClearedThreads() async throws {
        let item = ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00.000Z", headline: "Feed headline",
            body: "Full **news** body", sources: [.init(name: "Source", url: "https://example.com/news")],
            discussion: .init(threadId: "news-thread")
        )
        for isCreated in [true, false] {
            let thread = try decodeNewsThread(
                id: "news-thread", eventId: item.eventId, headline: "Server headline",
                messageCount: 1, isCleared: !isCreated, body: item.body, sources: item.sources
            )
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(
                    id: "saved-post", text: "**Server headline**\n\nFull **news** body", role: "assistant", newsPost: true,
                    followups: [["id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "What changed?"]]
                )
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
            client.hintsResult = try initialHints()
            client.blocksThreadCreation = true
            client.createdThreadIsNew = isCreated
            client.createdThread = thread
            let preloader = AgentPreloader(client: client)
            var createdThreads: [ApiAgentV2ThreadSummary] = []
            let chat = try XCTUnwrap(AgentEntryPoint.makeNewsChatViewController(item: item, locale: "ru", preloader: preloader) {
                createdThreads.append($0)
            } as? AgentVC)
            let model = try chatModel(in: chat)
            let navigation = UINavigationController(rootViewController: chat)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            defer {
                client.resumeThreadCreation()
                client.resumeBlockedHydration()
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
            }
            await waitForRequest("createThread", client: client)
            window.layoutIfNeeded()
            let postID = try XCTUnwrap(model.newsPostItemID)
            let preview = try XCTUnwrap(presentedMessage(postID, in: model))
            XCTAssertEqual(chat.title, item.headline)
            XCTAssertEqual(model.news?.body, item.body)
            XCTAssertEqual(model.news?.sources, item.sources)
            XCTAssertTrue(preview.newsPost)
            XCTAssertEqual(preview.role, .assistant)
            XCTAssertEqual(preview.text, "**Feed headline**\n\nFull **news** body")
            XCTAssertTrue(preview.controls.isEmpty)
            XCTAssertTrue(model.visibleHints.isEmpty)
            XCTAssertEqual(client.hintsRequestCount, 0)
            XCTAssertFalse(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
            let collection = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? UICollectionView }.first)
            let composer = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? AgentComposerView }.first)
            XCTAssertTrue(collection.visibleCells.contains { $0 is AgentNewsPostCell })
            XCTAssertEqual(composer.placeholder, lang("Ask anything"))
            XCTAssertFalse(model.canSendMessage(draftText: "Follow-up"))
            XCTAssertTrue(client.startedCommands.isEmpty)
            XCTAssertTrue(createdThreads.isEmpty)
            XCTAssertEqual(client.hydrationRequestCount, 0)

            client.resumeThreadCreation()
            await waitForHydrationRequest(client, count: 1)
            XCTAssertEqual(model.newsPostItemID, postID)
            XCTAssertEqual(model.news?.headline, thread.news?.headline)
            XCTAssertFalse(model.canSendMessage(draftText: "Follow-up"))
            XCTAssertFalse(model.canClearChat)
            XCTAssertTrue(try XCTUnwrap(presentedMessage(postID, in: model)).controls.isEmpty)
            XCTAssertTrue(model.visibleHints.isEmpty)
            XCTAssertEqual(client.hintsRequestCount, 0)
            XCTAssertTrue(client.startedCommands.isEmpty)
            XCTAssertFalse(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
            let previewIDs = model.itemIDs.filter { presentedMessage($0, in: model)?.role != .system }
            client.resumeBlockedHydration()
            try await waitForDiscussionUI { model.isReadyForPresentation && !model.isOpening }
            chat.viewIsAppearing(false)
            window.layoutIfNeeded()
            for _ in 0..<20 { await Task.yield() }

            XCTAssertEqual(model.itemIDs.filter { presentedMessage($0, in: model)?.role != .system }, previewIDs)
            XCTAssertEqual(model.newsPostItemID, postID)
            XCTAssertEqual(model.news?.headline, thread.news?.headline)
            XCTAssertTrue(model.canSendMessage(draftText: "Follow-up"))
            XCTAssertTrue(model.canClearChat)
            XCTAssertEqual(presentedMessage(postID, in: model)?.text, "**Server headline**\n\nFull **news** body")
            XCTAssertEqual(presentedMessage(postID, in: model)?.controls.map(\.title), ["What changed?"])
            XCTAssertTrue(model.visibleHints.isEmpty)
            XCTAssertEqual(client.hintsRequestCount, 0)
            XCTAssertEqual(model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter(\.newsPost).count, 1)
            XCTAssertEqual(createdThreads, [thread])
            XCTAssertTrue(preloader.model(threadId: thread.id) === model)
            XCTAssertEqual(client.newsThreadRequests, [.init(eventId: item.eventId, locale: "ru")])
            XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
            XCTAssertFalse(client.requestOrder.contains("defaultThread"))
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testDeferredDiscussionUsesTheFeedUntilTheFirstMessageCreatesAndLoadsOneThread() async throws {
        for kind in DeferredDiscussion.allCases {
            let thread = try decodeDiscussionThread(kind, id: "discussion-thread", messageCount: 1)
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(id: "post", text: "Saved headline", role: "assistant", threadId: thread.id, newsPost: true)
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
            client.blocksStatusRefresh = true
            client.blocksThreadCreation = true
            client.blocksRunStart = true
            let preloader = AgentPreloader(client: client)
            var createdThreads: [ApiAgentV2ThreadSummary] = []
            let model = acquireDeferredDiscussionModel(kind, preloader: preloader) { createdThreads.append($0) }
            defer {
                model.stop()
                client.resumeStatusRefresh()
                client.resumeThreadCreation()
                client.resumeBlockedHydration()
                client.resumeRunStart()
                preloader.setWalletReady(false)
            }
            await waitForRequest("availability", client: client)
            await waitForRequest("userQuota", client: client)
            XCTAssertTrue(client.completedStatusRequests.isEmpty)
            XCTAssertFalse(model.canSendMessage(draftText: "First question"))
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
            client.resumeStatusRefresh()
            await model.waitForInitialLoad()
            XCTAssertEqual(client.completedStatusRequests, ["availability", "userQuota"])
            XCTAssertTrue(acquireDeferredDiscussionModel(kind, preloader: preloader, onThreadCreated: { _ in }) === model)
            XCTAssertNil(model.threadId)
            XCTAssertFalse(model.isStarted)
            XCTAssertFalse(model.canDeleteChat)
            XCTAssertFalse(model.canReportProblem)
            switch kind {
            case .news:
                XCTAssertEqual(model.chatTitleText, "Feed headline")
                XCTAssertEqual(model.news?.body, "News body")
            case .digest:
                XCTAssertEqual(model.chatTitleText, lang("$agent_digest_title"))
                XCTAssertEqual(model.newsPostContent?.digestHeadlines.map(\.headline), ["Feed headline"])
            }
            let postID = try XCTUnwrap(model.newsPostItemID)
            XCTAssertTrue(try XCTUnwrap(model.message(for: postID)).controls.isEmpty)
            XCTAssertTrue(model.canSendMessage(draftText: "First question"))
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
            XCTAssertEqual(client.hydrationRequestCount, 0)

            model.send(text: "First question")
            model.send(text: "First question")
            let inputID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
            XCTAssertEqual(model.message(for: inputID)?.text, "First question")
            await waitForRequest("createThread", client: client)
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertTrue(client.startedCommands.isEmpty)
            client.resumeThreadCreation()
            await waitForHydrationRequest(client, count: 1)
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
            XCTAssertTrue(model.isStarted)
            XCTAssertTrue(client.startedCommands.isEmpty)
            XCTAssertEqual(model.message(for: inputID)?.text, "First question")
            client.resumeBlockedHydration()
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question")])
            XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role == .user }.map(\.id), [inputID])
            XCTAssertEqual(createdThreads.map(\.id), [thread.id])
            XCTAssertTrue(model.isStarted)
            XCTAssertTrue(preloader.model(threadId: thread.id) === model)
        }
    }

    @MainActor
    func testDeferredDiscussionHeaderSupportCreatesItsThreadAndSendsOnlyTheSupportRequest() async throws {
        for kind in DeferredDiscussion.allCases {
            for hasCreationFailed in [false, true] {
                let thread = try decodeDiscussionThread(kind, id: "discussion-support", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(id: "post", text: "Saved headline", role: "assistant", threadId: thread.id, newsPost: true)
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
                client.createdThreadIsNew = false
                client.blocksThreadCreation = true
                client.blocksRunStart = true
                if hasCreationFailed {
                    client.threadCreationError = FakeAgentV2ClientError.unavailable
                }
                switch kind {
                case .news: client.userQuotaResult = .init(limit: 100, used: 100, remaining: 0, resetAt: "2099-08-27T00:00:00.000Z")
                case .digest: client.availabilityResult = .init(state: .capacityExhausted, resetAt: 4_102_444_800_000)
                }
                let preloader = AgentPreloader(client: client)
                let model = acquireDeferredDiscussionModel(kind, preloader: preloader, onThreadCreated: { _ in })
                defer {
                    model.stop()
                    client.resumeThreadCreation()
                    client.resumeBlockedHydration()
                    client.resumeRunStart()
                    preloader.setWalletReady(false)
                }
                await model.waitForInitialLoad()
                XCTAssertNil(model.threadId)
                XCTAssertTrue(model.canRequestSupport)
                guard model.canRequestSupport else { continue }
                XCTAssertTrue(model.requestSupport(source: .header))
                XCTAssertFalse(model.requestSupport(source: .header))
                await waitForRequest("createThread", client: client)
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
                XCTAssertTrue(client.startedCommands.isEmpty)
                XCTAssertFalse(model.canRequestSupport)
                XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.role == .user })
                client.resumeThreadCreation()
                if hasCreationFailed {
                    await model.waitForInitialLoad()
                    XCTAssertNil(model.threadId)
                    XCTAssertTrue(client.startedCommands.isEmpty)
                    XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.role == .user })
                    XCTAssertTrue(model.canRequestSupport)
                    client.threadCreationError = nil
                    model.retryLoad()
                    await model.waitForInitialLoad()
                    XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
                    XCTAssertTrue(client.startedCommands.isEmpty)
                    XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.role == .user })
                    XCTAssertTrue(model.canRequestSupport)
                    guard model.canRequestSupport else { continue }
                    XCTAssertTrue(model.requestSupport(source: .header))
                }
                await waitForHydrationRequest(client, count: 1)
                XCTAssertFalse(model.canRequestSupport)
                XCTAssertTrue(client.startedCommands.isEmpty)
                client.resumeBlockedHydration()
                try await waitForDiscussionUI { client.startedCommands.count == 1 }
                client.resumeRunStart()
                try await waitForDiscussionUI { !model.hasActiveRun && !model.isOpening }
                XCTAssertEqual(client.startedCommands.map(\.threadId), [thread.id])
                XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: lang("$agent_support_request_message"))])
                XCTAssertEqual(client.startedCommands.map(\.entryPoint), [.supportRequest(source: .header)])
                let expectedCreationCount = hasCreationFailed ? 2 : 1
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), expectedCreationCount)
                switch kind {
                case .news: XCTAssertEqual(client.newsThreadRequests, Array(repeating: .init(eventId: 307, locale: "en"), count: expectedCreationCount))
                case .digest: XCTAssertEqual(client.digestThreadRequests, Array(repeating: .init(id: Self.deferredDigestId), count: expectedCreationCount))
                }
            }
        }
    }

    @MainActor
    func testDeferredDiscussionHeaderSupportDropsAfterWalletChangesBeforeItsThreadLoads() async throws {
        for kind in DeferredDiscussion.allCases {
            try await withDependencies {
                $0.accountStore = .makePreview(
                    accounts: ["wallet-a", "wallet-b"].map { Self.makeWalletAccount(id: $0) },
                    selectedAccountId: "wallet-a"
                )
                $0[SavedAddressesStore.self] = .liveValue
            } operation: {
                let thread = try decodeDiscussionThread(kind, id: "discussion-support", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
                client.blocksThreadCreation = true
                var accountID: String? = "wallet-a"
                let existing: AgentV2Model?
                switch kind {
                case .news:
                    existing = nil
                case .digest:
                    accountID = nil
                    existing = AgentV2Model(client: client, thread: thread, activeAccount: { accountID.map { Self.makeWalletAccount(id: $0) } })
                }
                let model = makeDeferredDiscussionModel(
                    kind, client: client, activeAccount: { accountID.map { Self.makeWalletAccount(id: $0) } }
                )
                model.resolveOpeningThreadModel = { _ in existing }
                defer {
                    model.stop()
                    existing?.stop()
                    client.resumeThreadCreation()
                    client.resumeBlockedHydration()
                }
                await model.waitForInitialLoad()
                XCTAssertTrue(model.requestSupport(source: .header))
                await waitForRequest("createThread", client: client)

                accountID = "wallet-b"
                WalletCoreData.notify(event: .accountChanged(accountId: "wallet-b", isNew: false))
                if case .news = kind {
                    accountID = "wallet-a"
                    WalletCoreData.notify(event: .accountChanged(accountId: "wallet-a", isNew: false))
                }
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                client.resumeThreadCreation()
                if let existing {
                    await model.waitForInitialLoad()
                    XCTAssertTrue(model.presentationModel === existing)
                }
                await waitForHydrationRequest(client, count: 1)
                client.resumeBlockedHydration()
                await model.presentationModel.waitForInitialLoad()
                try await waitForDiscussionUI { !model.presentationModel.isOpening && !model.presentationModel.hasActiveRun }

                XCTAssertTrue(client.startedCommands.isEmpty)
                XCTAssertFalse(model.presentationModel.itemIDs.contains { model.presentationModel.message(for: $0)?.role == .user })
            }
        }
    }

    @MainActor
    func testDeferredDiscussionHeaderSupportDropsAfterWalletChangesBeforeSubmission() async throws {
        for kind in DeferredDiscussion.allCases {
            try await withDependencies {
                $0.accountStore = .makePreview(
                    accounts: ["wallet-a", "wallet-b"].map { Self.makeWalletAccount(id: $0) },
                    selectedAccountId: "wallet-a"
                )
                $0[SavedAddressesStore.self] = .liveValue
            } operation: {
                let thread = try decodeDiscussionThread(kind, id: "discussion-support", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
                ], thread: thread)
                let client = FakeAgentV2Client(
                    hydrationResult: history, shouldCompleteRun: true,
                    hostContextFailuresRemaining: 3, blockedHostContextAttempt: 4
                )
                var accountID: String? = kind == .news ? "wallet-a" : nil
                let model = makeDeferredDiscussionModel(
                    kind, client: client, activeAccount: { accountID.map { Self.makeWalletAccount(id: $0) } }
                )
                defer {
                    model.stop()
                    client.resumeBlockedHostContextUpdate()
                }
                await model.waitForInitialLoad()
                XCTAssertTrue(model.requestSupport(source: .header))
                await model.waitForInitialLoad()
                try await waitForDiscussionUI { client.hostContextUpdateCount == 4 }
                XCTAssertTrue(model.hasActiveRun)
                XCTAssertTrue(client.startedCommands.isEmpty)
                let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
                let runTask = try XCTUnwrap(Mirror(reflecting: coordinator).children.first { $0.label == "runTask" }?.value as? Task<Void, Never>)

                accountID = "wallet-b"
                WalletCoreData.notify(event: .accountChanged(accountId: "wallet-b", isNew: false))
                if case .news = kind {
                    accountID = "wallet-a"
                    WalletCoreData.notify(event: .accountChanged(accountId: "wallet-a", isNew: false))
                }
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                client.resumeBlockedHostContextUpdate()
                await runTask.value
                try await waitForDiscussionUI { !model.hasActiveRun && !model.isOpening }
                XCTAssertTrue(client.startedCommands.isEmpty)
                XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.role == .user })
            }
        }
    }

    @MainActor
    func testDeferredDiscussionSendsTheFirstMessageAfterLeavingDuringThreadCreation() async throws {
        for kind in DeferredDiscussion.allCases {
            let thread = try decodeDiscussionThread(kind, id: "discussion-thread", messageCount: 1)
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
            client.blocksThreadCreation = true
            client.blocksRunStart = true
            let preloader = AgentPreloader(client: client)
            var chat: AgentVC? = makeDeferredDiscussionChat(kind, preloader: preloader)
            var model: AgentV2Model? = try chatModel(in: XCTUnwrap(chat))
            weak var retainedModel = model
            weak var poppedChat = chat
            let home = UIViewController()
            let navigation = UINavigationController(rootViewController: home)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            navigation.pushViewController(try XCTUnwrap(chat), animated: false)
            defer {
                retainedModel?.stop()
                client.resumeThreadCreation()
                client.resumeBlockedHydration()
                client.resumeRunStart()
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
            }
            await model?.waitForInitialLoad()
            model?.send(text: "First question")
            await waitForRequest("createThread", client: client)

            navigation.popViewController(animated: false)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            chat = nil
            model = nil
            try await waitForDiscussionUI { poppedChat == nil }
            XCTAssertTrue(navigation.topViewController === home)
            XCTAssertNotNil(retainedModel)
            // Opening the feed's post again while its thread is being created returns the chat with the first message
            let reopened = acquireDeferredDiscussionModel(kind, preloader: preloader, onThreadCreated: { _ in })
            XCTAssertTrue(reopened === retainedModel, "\(kind)")
            XCTAssertEqual(reopened.itemIDs.compactMap { reopened.message(for: $0) }.filter { $0.role == .user }.map(\.text), ["First question"])
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
            client.resumeThreadCreation()
            await waitForHydrationRequest(client, count: 1)
            XCTAssertTrue(retainedModel?.isStarted == true)
            XCTAssertTrue(client.startedCommands.isEmpty)
            client.resumeBlockedHydration()
            try await waitForDiscussionUI { client.startedCommands.count == 1 }

            XCTAssertEqual(client.cancelledThreadCreationCount, 0)
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
            XCTAssertEqual(client.hydrationRequestCount, 1)
            XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question")])
            XCTAssertTrue(preloader.model(threadId: thread.id) === retainedModel)
        }
    }

    @MainActor
    func testDeferredDiscussionCreationFailureReleasesTheThreadlessModelAfterDeparture() async throws {
        for kind in DeferredDiscussion.allCases {
            for shouldFailAfterDeparture in [false, true] {
                let client = FakeAgentV2Client()
                client.blocksThreadCreation = true
                client.threadCreationError = FakeAgentV2ClientError.unavailable
                let preloader = AgentPreloader(client: client)
                var chat: AgentVC? = makeDeferredDiscussionChat(kind, preloader: preloader)
                var model: AgentV2Model? = try chatModel(in: XCTUnwrap(chat))
                weak var releasedModel = model
                weak var poppedChat = chat
                let home = UIViewController()
                let navigation = UINavigationController(rootViewController: home)
                let window = makeKeyWindow(showing: navigation)
                navigation.pushViewController(try XCTUnwrap(chat), animated: false)
                defer {
                    releasedModel?.stop()
                    client.resumeThreadCreation()
                    window.isHidden = true
                    navigation.setViewControllers([], animated: false)
                    preloader.setWalletReady(false)
                }
                await model?.waitForInitialLoad()
                model?.send(text: "First question")
                await waitForRequest("createThread", client: client)
                if !shouldFailAfterDeparture {
                    client.resumeThreadCreation()
                    await model?.waitForInitialLoad()
                    let messages = model?.itemIDs.compactMap { model?.message(for: $0) } ?? []
                    XCTAssertTrue(messages.contains { $0.controls.contains { $0.id == "retry-opening" } })
                }
                navigation.popViewController(animated: false)
                chat = nil
                model = nil
                try await waitForDiscussionUI { poppedChat == nil }
                if shouldFailAfterDeparture {
                    XCTAssertNotNil(releasedModel)
                    client.resumeThreadCreation()
                }
                try await waitForDiscussionUI { releasedModel == nil }
                XCTAssertNil(deferredDiscussionModel(kind, in: preloader))
                XCTAssertTrue(preloader.getLoadedModels().isEmpty)
                XCTAssertEqual(client.cancelledThreadCreationCount, 0)
                XCTAssertTrue(client.startedCommands.isEmpty)

                let reopened = acquireDeferredDiscussionModel(kind, preloader: preloader, onThreadCreated: { _ in })
                defer { reopened.stop() }
                await reopened.waitForInitialLoad()
                XCTAssertNil(reopened.threadId)
                XCTAssertFalse(reopened.hasPendingDiscussionMessage)
                XCTAssertFalse(reopened.isStarted)
                XCTAssertFalse(reopened.itemIDs.contains { reopened.message(for: $0)?.role == .user })
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
                XCTAssertEqual(client.hydrationRequestCount, 0)
                XCTAssertTrue(client.startedCommands.isEmpty)
            }
        }
    }

    @MainActor
    func testDeferredDiscussionConsentDoesNotCreateOrLoadTheThread() async throws {
        for kind in DeferredDiscussion.allCases {
            let client = FakeAgentV2Client()
            client.hasConsent = false
            let model = makeDeferredDiscussionModel(kind, client: client)
            defer { model.stop() }
            XCTAssertTrue(model.needsConsentToSend)
            await model.waitForInitialLoad()
            XCTAssertTrue(model.needsConsentToSend)
            XCTAssertTrue(model.canSendMessage(draftText: "Question"))
            XCTAssertFalse(model.canDeleteChat)
            XCTAssertFalse(model.canReportProblem)

            XCTAssertFalse(client.requestOrder.contains("availability"))
            XCTAssertFalse(client.requestOrder.contains("userQuota"))
            try await model.acceptConsent()
            model.markConsentGiven()
            await model.waitForInitialLoad()
            for _ in 0..<20 { await Task.yield() }

            XCTAssertEqual(client.completedStatusRequests, ["availability", "userQuota"])
            XCTAssertFalse(model.needsConsentToSend)
            XCTAssertFalse(model.canDeleteChat)
            XCTAssertFalse(model.canReportProblem)
            XCTAssertNil(model.threadId)
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertEqual(client.problemReportAvailabilityRequestCount, 0)
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testDeferredDiscussionOpeningAppliesQuotaAndCapacityBeforeCreatingAThread() async throws {
        for kind in DeferredDiscussion.allCases {
            for hasQuotaLimit in [true, false] {
                let client = FakeAgentV2Client()
                client.blocksStatusRefresh = true
                if hasQuotaLimit {
                    client.userQuotaResult = .init(limit: 100, used: 100, remaining: 0, resetAt: "2099-08-27T00:00:00.000Z")
                } else {
                    client.availabilityResult = .init(state: .capacityExhausted, resetAt: 4_102_444_800_000)
                }
                let model = makeDeferredDiscussionModel(
                    kind, client: client, naming: .init(title: "Market discussion", followups: ["What changed?"])
                )
                let chat = AgentVC(model: model)
                let navigation = UINavigationController(rootViewController: chat)
                let window = makeKeyWindow(showing: navigation)
                defer {
                    model.stop()
                    client.resumeStatusRefresh()
                    window.isHidden = true
                    navigation.setViewControllers([], animated: false)
                }
                await waitForRequest("availability", client: client)
                await waitForRequest("userQuota", client: client)
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
                XCTAssertFalse(model.canSendMessage(draftText: "Question"))
                client.resumeStatusRefresh()
                await model.waitForInitialLoad()
                try await waitForDiscussionUI { model.isInputBlockedByLimit && chat.composerView.contentAlpha == 0.5 }
                let postID = try XCTUnwrap(model.newsPostItemID)
                let control = try XCTUnwrap(model.message(for: postID)?.controls.first)
                XCTAssertFalse(control.isEnabled)
                XCTAssertFalse(model.canSendMessage(draftText: "Question"))
                chat.composerView.setDraftText("Question", focus: false)
                chat.composerView.onSend?()
                model.performControl(messageID: postID, controlID: control.id)
                for _ in 0..<20 { await Task.yield() }

                XCTAssertEqual(chat.composerView.draftText, "Question")
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
                XCTAssertEqual(client.hydrationRequestCount, 0)
                XCTAssertTrue(client.startedCommands.isEmpty)
                XCTAssertEqual(client.completedStatusRequests, ["availability", "userQuota"])
            }
        }
    }

    @MainActor
    func testDeferredDiscussionComposerWaitsForPostConsentStatusAndKeepsALimitedDraft() async throws {
        for kind in DeferredDiscussion.allCases {
            let presentation = AgentTestConsentSheetPresentation.install(in: self)
            for hasCapacityLimit in [true, false] {
                let thread = try decodeDiscussionThread(kind, id: "discussion-thread", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
                client.hasConsent = false
                client.blocksStatusRefresh = true
                client.blocksRunStart = true
                if hasCapacityLimit {
                    client.availabilityResult = .init(state: .capacityExhausted, resetAt: 4_102_444_800_000)
                }
                let model = makeDeferredDiscussionModel(kind, client: client)
                let chat = AgentVC(model: model)
                let navigation = UINavigationController(rootViewController: chat)
                let window = makeKeyWindow(showing: navigation)
                defer {
                    model.stop()
                    client.resumeStatusRefresh()
                    client.resumeRunStart()
                    window.isHidden = true
                    navigation.setViewControllers([], animated: false)
                }
                await model.waitForInitialLoad()
                XCTAssertFalse(client.requestOrder.contains("availability"))
                XCTAssertFalse(client.requestOrder.contains("userQuota"))
                let composer = chat.composerView
                composer.setDraftText("First question", focus: false)
                composer.onSend?()
                let consent = try await waitForConsentView(in: chat)
                consent.onContinue?()
                consent.onContinue?()
                await waitForRequest("availability", client: client)
                await waitForRequest("userQuota", client: client)
                XCTAssertEqual(composer.draftText, "First question")
                XCTAssertTrue(client.completedStatusRequests.isEmpty)
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
                XCTAssertTrue(client.startedCommands.isEmpty)
                client.resumeStatusRefresh()
                try await waitForDiscussionUI {
                    client.completedStatusRequests.count == 2
                        && (hasCapacityLimit ? model.isInputBlockedByLimit : client.startedCommands.count == 1)
                }
                try await waitForDiscussionUI { presentation.presentedViewController(of: chat) == nil }

                XCTAssertEqual(client.completedStatusRequests, ["availability", "userQuota"])
                if hasCapacityLimit {
                    XCTAssertEqual(composer.draftText, "First question")
                    XCTAssertEqual(composer.contentAlpha, 0.5)
                    XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
                    XCTAssertEqual(client.hydrationRequestCount, 0)
                    XCTAssertTrue(client.startedCommands.isEmpty)
                } else {
                    XCTAssertTrue(composer.draftText?.isEmpty != false)
                    XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
                    XCTAssertEqual(client.hydrationRequestCount, 1)
                    XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question")])
                }
            }
        }
    }

    @MainActor
    func testDeferredDiscussionFollowupResolvesTheSavedPostByExactTextOrSendsPlainText() async throws {
        for kind in DeferredDiscussion.allCases {
            let question = "What changed?"
            let followupID = "adadadad-adad-4dad-8dad-adadadadadad"
            for hasExactFollowup in [true, false] {
                let thread = try decodeDiscussionThread(kind, id: "discussion-thread", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(
                        id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true,
                        followups: [["id": followupID, "kind": "suggested_prompt", "text": hasExactFollowup ? question : question.lowercased()]]
                    )
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
                client.blocksRunStart = true
                let model = makeDeferredDiscussionModel(
                    kind, client: client,
                    naming: .init(title: "Market discussion", icon: "📰", followups: [question, "What happens next?"])
                )
                defer {
                    model.stop()
                    client.resumeBlockedHydration()
                    client.resumeRunStart()
                }
                await model.waitForInitialLoad()
                let postID = try XCTUnwrap(model.newsPostItemID)
                let controls = try XCTUnwrap(model.message(for: postID)).controls
                XCTAssertEqual(model.chatTitleText, "Market discussion")
                XCTAssertEqual(model.chatIcon, "📰")
                XCTAssertEqual(controls.map(\.title), [question, "What happens next?"])
                XCTAssertTrue(controls.allSatisfy { $0.kind == .followup && $0.isEnabled })
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)

                model.performControl(messageID: postID, controlID: controls[0].id)
                model.performControl(messageID: postID, controlID: controls[1].id)
                XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role == .user }.map(\.text), [question])
                await waitForHydrationRequest(client, count: 1)
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
                XCTAssertTrue(client.startedCommands.isEmpty)
                client.resumeBlockedHydration()
                try await waitForDiscussionUI { client.startedCommands.count == 1 }
                let command = try XCTUnwrap(client.startedCommands.first)
                XCTAssertEqual(command.input, .append(text: question))
                XCTAssertEqual(command.followupOf, hasExactFollowup ? .init(messageId: "post", followupId: followupID) : nil)
                XCTAssertNil(command.entryPoint)
            }
        }
    }

    @MainActor
    func testDeferredDiscussionTransfersTheFirstFollowupToTheExistingModelBeforeHistoryLoads() async throws {
        for kind in DeferredDiscussion.allCases {
            let question = "What changed?"
            let followupID = "adadadad-adad-4dad-8dad-adadadadadad"
            let thread = try decodeDiscussionThread(kind, id: "existing-discussion-thread", messageCount: 1)
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(
                    id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true,
                    followups: [["id": followupID, "kind": "suggested_prompt", "text": question]]
                )
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
            client.blocksThreadCreation = true
            client.blocksRunStart = true
            let preloader = AgentPreloader(client: client)
            let existing = try XCTUnwrap(preloader.acquireModel(thread: thread))
            let opening = acquireDeferredDiscussionModel(
                kind, preloader: preloader, naming: .init(title: "Market discussion", followups: [question]), onThreadCreated: { _ in }
            )
            defer {
                opening.stop()
                existing.stop()
                client.resumeThreadCreation()
                client.resumeBlockedHydration()
                client.resumeRunStart()
                preloader.setWalletReady(false)
            }
            await opening.waitForInitialLoad()
            await waitForHydrationRequest(client, count: 1)
            let postID = try XCTUnwrap(opening.newsPostItemID)
            let control = try XCTUnwrap(opening.message(for: postID)?.controls.first)
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
            opening.performControl(messageID: postID, controlID: control.id)
            let inputID = try XCTUnwrap(presentedMessageID(in: opening, role: .user))
            await waitForRequest("createThread", client: client)
            client.resumeThreadCreation()
            await opening.waitForInitialLoad()
            XCTAssertTrue(opening.presentationModel === existing)
            XCTAssertEqual(existing.message(for: inputID)?.text, question)
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
            XCTAssertEqual(client.hydrationRequestCount, 1)
            XCTAssertTrue(client.startedCommands.isEmpty)

            client.resumeBlockedHydration()
            try await waitForDiscussionUI { client.startedCommands.count == 1 }

            let command = try XCTUnwrap(client.startedCommands.first)
            XCTAssertEqual(command.input, .append(text: question))
            XCTAssertEqual(command.followupOf, .init(messageId: "post", followupId: followupID))
            XCTAssertEqual(existing.itemIDs.compactMap { existing.message(for: $0) }.filter { $0.role == .user }.map(\.id), [inputID])
            XCTAssertTrue(preloader.model(threadId: thread.id) === existing)
        }
    }

    @MainActor
    func testDeferredDiscussionKeepsTheFirstFailedFollowupAfterWalletSwitchDepartureAndRedirect() async throws {
        for kind in DeferredDiscussion.allCases {
            try await withDependencies {
                $0.accountStore = .makePreview(
                    accounts: ["wallet-a", "wallet-b"].map { Self.makeWalletAccount(id: $0) },
                    selectedAccountId: "wallet-a"
                )
                $0[SavedAddressesStore.self] = .liveValue
            } operation: {
                let question = "What changed?"
                let followupID = "adadadad-adad-4dad-8dad-adadadadadad"
                let naming = ApiAgentV2NewsFeedItem.DiscussionNaming(title: "Market discussion", followups: [question])
                let thread = try decodeDiscussionThread(kind, id: "existing-discussion-thread", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(
                        id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true,
                        followups: [["id": followupID, "kind": "suggested_prompt", "text": question]]
                    )
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
                client.blocksThreadCreation = true
                client.blocksRunStart = true
                var runAccountIds: [String?] = []
                client.startRunObserver = { [weak client] in runAccountIds.append(client?.lastHostContext?.activeAccountId) }
                var accountID = "wallet-a"
                let existing = AgentV2Model(client: client, thread: thread, activeAccount: { Self.makeWalletAccount(id: accountID) })
                let opening = makeDeferredDiscussionModel(
                    kind, client: client, naming: naming, activeAccount: { Self.makeWalletAccount(id: accountID) }
                )
                let preloader = AgentPreloader(client: client)
                opening.onDiscussionMessageQueued = { [weak opening] in
                    if let opening { preloader.keepRecent(opening) }
                }
                opening.resolveOpeningThreadModel = { _ in
                    preloader.keepRecent(existing)
                    return existing
                }
                let chat = AgentVC(model: opening)
                let home = UIViewController()
                let navigation = UINavigationController(rootViewController: home)
                let window = makeKeyWindow(showing: navigation)
                navigation.pushViewController(chat, animated: false)
                defer {
                    opening.stop()
                    existing.stop()
                    client.resumeThreadCreation()
                    client.resumeBlockedHydration()
                    client.resumeRunStart()
                    window.isHidden = true
                    navigation.setViewControllers([], animated: false)
                    preloader.setWalletReady(false)
                }
                await opening.waitForInitialLoad()
                await waitForHydrationRequest(client, count: 1)
                let postID = try XCTUnwrap(opening.newsPostItemID)
                let control = try XCTUnwrap(opening.message(for: postID)?.controls.first)
                opening.performControl(messageID: postID, controlID: control.id)
                let inputID = try XCTUnwrap(presentedMessageID(in: opening, role: .user))
                await waitForRequest("createThread", client: client)
                accountID = "wallet-b"
                try notifyAccountChanged(to: accountID, in: [opening, existing])
                updateDeferredDiscussionPreview(kind, of: opening, naming: naming)
                let failureID = try XCTUnwrap(opening.itemIDs.last)
                XCTAssertEqual(opening.message(for: failureID)?.controls.map(\.id), ["retry-failed-questions"])
                XCTAssertTrue(opening.hasPendingDiscussionMessage)
                navigation.popViewController(animated: false)
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                XCTAssertTrue(opening.isReadyForPresentation)
                client.resumeThreadCreation()
                await opening.waitForInitialLoad()
                XCTAssertTrue(opening.presentationModel === existing)
                XCTAssertEqual(existing.message(for: inputID)?.text, question)
                XCTAssertEqual(existing.message(for: failureID)?.controls.map(\.id), ["retry-failed-questions"])
                client.resumeBlockedHydration()
                await existing.waitForInitialLoad()
                XCTAssertTrue(client.startedCommands.isEmpty)
                existing.performControl(messageID: failureID, controlID: "retry-failed-questions")
                try await waitForDiscussionUI { client.startedCommands.count == 1 }

                XCTAssertEqual(client.cancelledThreadCreationCount, 0)
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
                XCTAssertEqual(client.startedCommands.first?.input, .append(text: question))
                XCTAssertEqual(client.startedCommands.first?.followupOf, .init(messageId: "post", followupId: followupID))
                XCTAssertEqual(runAccountIds, ["wallet-b"], "\(kind)")
            }
        }
    }

    @MainActor
    func testDeferredDiscussionSendsTheFirstMessageFromTheWalletChosenBeforeIt() async throws {
        for kind in DeferredDiscussion.allCases {
            try await withDependencies {
                $0.accountStore = .makePreview(
                    accounts: ["wallet-a", "wallet-b"].map { Self.makeWalletAccount(id: $0) },
                    selectedAccountId: "wallet-a"
                )
                $0[SavedAddressesStore.self] = .liveValue
            } operation: {
                let thread = try decodeDiscussionThread(kind, id: "discussion-thread", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
                client.blocksRunStart = true
                var runAccountIds: [String?] = []
                client.startRunObserver = { [weak client] in runAccountIds.append(client?.lastHostContext?.activeAccountId) }
                var accountID = "wallet-a"
                let model = makeDeferredDiscussionModel(kind, client: client, activeAccount: { Self.makeWalletAccount(id: accountID) })
                defer {
                    model.stop()
                    client.resumeRunStart()
                }
                await model.waitForInitialLoad()
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
                accountID = "wallet-b"
                try notifyAccountChanged(to: accountID, in: [model])

                model.send(text: "First question")
                try await waitForDiscussionUI { client.startedCommands.count == 1 }

                XCTAssertEqual(runAccountIds, ["wallet-b"], "\(kind)")
                XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question")])
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
            }
        }
    }

    @MainActor
    func testSavedNewsPostFollowupSendsItsReferenceAndHidesTheButtons() async throws {
        let followupID = "adadadad-adad-4dad-8dad-adadadadadad"
        let question = "What changed?"
        let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: "News headline", messageCount: 1)
        let history = try decodeHydration(threadId: thread.id, messages: [
            newsPostMessage(
                id: "saved-post", text: "News headline", role: "assistant", newsPost: true,
                followups: [["id": followupID, "kind": "suggested_prompt", "text": question]]
            )
        ], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let postID = try XCTUnwrap(model.newsPostItemID)
        let control = try XCTUnwrap(presentedMessage(postID, in: model)?.controls.first)
        XCTAssertEqual(control.id, "followup:\(followupID)")
        XCTAssertEqual(control.title, question)
        XCTAssertEqual(control.kind, .followup)
        XCTAssertTrue(control.isEnabled)

        model.performControl(messageID: postID, controlID: control.id)
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        XCTAssertTrue(model.hasActiveRun)

        let command = try XCTUnwrap(client.startedCommands.first)
        XCTAssertEqual(command.input, .append(text: question))
        XCTAssertEqual(command.followupOf, .init(messageId: "saved-post", followupId: followupID))
        XCTAssertNil(command.entryPoint)
        XCTAssertEqual(model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role == .user }.map(\.text), [question])
        XCTAssertTrue(try XCTUnwrap(presentedMessage(postID, in: model)).controls.isEmpty)
        model.performControl(messageID: postID, controlID: control.id)
        XCTAssertEqual(client.startedCommands.count, 1)
    }

    @MainActor
    func testNewsPostFollowupsOnlyAppearWhileThePostIsTheLastMessage() async throws {
        let followup = ["id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "What changed?"]
        let post = newsPostMessage(id: "saved-post", text: "News headline", role: "assistant", newsPost: true, followups: [followup])
        let question = newsPostMessage(id: "question", text: "Tell me more")
        let answer = newsPostMessage(
            id: "answer", text: "More details", role: "assistant",
            followups: [["id": "bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd", "kind": "suggested_prompt", "text": "What happens next?"]]
        )
        for trailingMessages in [[], [question], [question, answer]] {
            let thread = try decodeNewsThread(
                id: "news-thread", eventId: 307, headline: "News headline", messageCount: trailingMessages.count + 1
            )
            let history = try decodeHydration(threadId: thread.id, messages: [post] + trailingMessages, thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history)
            let model = AgentV2Model(client: client, thread: thread)
            defer { model.stop() }
            await model.waitForInitialLoad()
            let messages = model.itemIDs.compactMap { presentedMessage($0, in: model) }
            let presentedPost = try XCTUnwrap(messages.first(where: \.newsPost))
            XCTAssertEqual(presentedPost.controls.map(\.title), trailingMessages.isEmpty ? ["What changed?"] : [])
            if trailingMessages.count == 2 {
                XCTAssertEqual(messages.last?.controls.map(\.title), ["What happens next?"])
            }
        }
    }

    @MainActor
    func testNewsDiscoveredDuringHydrationDiscardsStarterHintsEvenAfterClear() async throws {
        for isLegacy in [true, false] {
            for hintsArriveAfterHistory in [false, true] {
                let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: "News headline", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(
                        id: "saved-post", text: "News headline", role: isLegacy ? "user" : "assistant",
                        newsPost: isLegacy ? nil : true
                    )
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
                client.hintsResult = try initialHints()
                client.blocksHints = hintsArriveAfterHistory
                client.blocksClear = true
                let initialThread = try decodeHydration(threadId: thread.id, messages: []).thread
                let model = AgentV2Model(client: client, thread: initialThread)
                defer {
                    model.stop()
                    client.resumeBlockedHydration()
                    client.resumeHints()
                    client.resumeClear()
                }
                await waitForHydrationRequest(client, count: 1)
                try await waitForDiscussionUI { client.hintsRequestCount > 0 }
                let hintsRequestCount = client.hintsRequestCount
                XCTAssertTrue(model.visibleHints.isEmpty)

                client.resumeBlockedHydration()
                try await waitForDiscussionUI { model.isReadyForPresentation }
                XCTAssertNotNil(model.newsPostItemID)
                XCTAssertTrue(model.visibleHints.isEmpty)
                client.resumeHints()
                await model.waitForInitialLoad()
                XCTAssertEqual(client.hintsRequestCount, hintsRequestCount)
                XCTAssertTrue(model.visibleHints.isEmpty)

                model.clearChat(animated: false)
                await waitForRequest("clearThread", client: client)
                XCTAssertEqual(client.hintsRequestCount, hintsRequestCount)
                XCTAssertTrue(model.visibleHints.isEmpty)
                client.resumeClear()
                try await waitForDiscussionUI { model.canSendMessage(draftText: "Next question") }
                XCTAssertEqual(client.hintsRequestCount, hintsRequestCount)
                XCTAssertTrue(model.visibleHints.isEmpty)
                XCTAssertTrue(try XCTUnwrap(presentedMessage(try XCTUnwrap(model.newsPostItemID), in: model)).controls.isEmpty)
            }
        }
    }

    @MainActor
    func testSavedNewsPostTakesPriorityAndOffersOnlySourceCopyAndShare() async throws {
        let headline = "News headline"
        for sourceURL in ["https://example.com/news", "javascript:alert(1)"] {
            let thread = try decodeNewsThread(
                id: "news-thread", eventId: 307, headline: headline, messageCount: 3,
                body: "A **bold** update.", sources: [.init(name: "Source", url: sourceURL)]
            )
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(id: "legacy-headline", text: headline),
                newsPostMessage(id: "saved-post", text: "**News headline**\n\nA **bold** update.", role: "assistant", newsPost: true),
                newsPostMessage(id: "question", text: headline)
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history)
            let model = AgentV2Model(client: client, thread: thread)
            await model.waitForInitialLoad()
            forgetChatReadState(threadId: thread.id)
            let controller = AgentVC(model: model)
            let navigation = UINavigationController(rootViewController: controller)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                model.stop()
            }
            let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
            let composer = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? AgentComposerView }.first)
            let postID = try XCTUnwrap(model.newsPostItemID)
            let post = try XCTUnwrap(presentedMessage(postID, in: model))
            let messages = model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role != .system }
            XCTAssertEqual(messages.count, 3)
            XCTAssertEqual(messages.first?.id, postID)
            XCTAssertEqual(messages.filter { $0.role == .user }.count, 2)
            XCTAssertTrue(post.newsPost)
            XCTAssertFalse(post.canRate)
            XCTAssertTrue(post.controls.isEmpty)
            XCTAssertEqual(composer.placeholder, lang("Ask anything"))
            let postIndexPath = IndexPath(item: try XCTUnwrap(model.itemIDs.firstIndex(of: postID)), section: 0)
            for _ in 0..<100 where collection.cellForItem(at: postIndexPath) == nil {
                window.layoutIfNeeded()
                await Task.yield()
            }
            let cell = try XCTUnwrap(collection.cellForItem(at: postIndexPath) as? AgentNewsPostCell)
            let menu = try XCTUnwrap(cell.contextMenuConfigurationProvider?())
            let titles = menu.rootPage.items.compactMap { item -> String? in
                switch item {
                case .action(let action): action.title
                case .submenu(let submenu): submenu.title
                default: nil
                }
            }
            XCTAssertEqual(titles, sourceURL.hasPrefix("https:")
                ? [lang("$agent_news_sources"), lang("Copy"), lang("Share")]
                : [lang("Copy"), lang("Share")])
            // A post's menu is a message's: headed by its date, hanging under the post, which slides into view
            guard case .custom? = menu.rootPage.items.first else { return XCTFail("The post's menu has no date") }
            XCTAssertEqual(menu.style.sourceSpacing, 7)
            XCTAssertNotNil(menu.sourceRelocation)
            XCTAssertNil(menu.accessory)
            XCTAssertNotNil(cell.openSourceAction)
            XCTAssertEqual(controller.copyText(for: postID), "News headline\n\nA bold update.\n\n\(sourceURL)")
            let didRate = await model.rateMessage(messageID: postID, feedback: .like)
            let didReport = await model.reportProblem(messageID: postID, comment: "News post")
            XCTAssertFalse(didRate)
            XCTAssertFalse(didReport)
            model.send(text: "Edited post", editingMessageID: postID)
            XCTAssertTrue(client.startedCommands.isEmpty)

            let question = try XCTUnwrap(messages.last)
            let questionIndexPath = IndexPath(item: try XCTUnwrap(model.itemIDs.firstIndex(of: question.id)), section: 0)
            for _ in 0..<100 where collection.cellForItem(at: questionIndexPath) == nil {
                window.layoutIfNeeded()
                await Task.yield()
            }
            let questionCell = try XCTUnwrap(collection.cellForItem(at: questionIndexPath) as? AgentMessageCell)
            let questionMenu = try XCTUnwrap(questionCell.contextMenuConfigurationProvider?())
            XCTAssertEqual(questionMenu.rootPage.items.compactMap { item -> String? in
                guard case .action(let action) = item else { return nil }
                return action.title
            }, [lang("Copy"), lang("Edit")])
            // A message's menu is headed by its date and hangs under the bubble on the bubble's side
            XCTAssertTrue({
                guard case .custom? = questionMenu.rootPage.items.first else { return false }
                return true
            }())
            XCTAssertEqual(questionMenu.rootPage.items.count, 3)
            XCTAssertEqual(questionMenu.style.horizontalAlignment, .trailing)
            XCTAssertEqual(questionMenu.style.sourceSpacing, 7)
            XCTAssertEqual(questionMenu.style.minWidth, 180)
            XCTAssertEqual(questionMenu.style.maxWidth, 250)
            // As in Telegram, the pressed message and the post move into view under their menus
            XCTAssertNotNil(questionMenu.sourceRelocation)
            XCTAssertNotNil(menu.sourceRelocation)
            // The post's menu hangs under it on its side, as an incoming message's does
            XCTAssertEqual(menu.style.horizontalAlignment, .leading)
        }
    }

    @MainActor
    func testLegacyNewsHeadlineBecomesOnePostAndPreservesLaterQuestions() async throws {
        let headline = "News headline"
        let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: headline, messageCount: 3)
        let history = try decodeHydration(threadId: thread.id, messages: [
            newsPostMessage(id: "answer", text: "Earlier answer", role: "assistant"),
            newsPostMessage(id: "legacy-headline", text: headline),
            newsPostMessage(id: "question", text: headline)
        ], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history)
        client.hintsResult = try initialHints()
        let model = AgentV2Model(client: client, thread: thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let messages = model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role != .system }
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages.first?.id, model.newsPostItemID)
        XCTAssertEqual(messages.first?.role, .assistant)
        XCTAssertEqual(messages.filter { $0.role == .user }.map(\.text), [headline])
        XCTAssertEqual(model.newsPost(for: try XCTUnwrap(messages.first)), thread.news)
        XCTAssertTrue(try XCTUnwrap(messages.first).controls.isEmpty)
        XCTAssertTrue(model.visibleHints.isEmpty)
        XCTAssertEqual(client.hintsRequestCount, 0)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testNewsWithoutAnExactLegacyHeadlineUsesALocalPostWithoutSending() async throws {
        let headline = "News headline"
        for firstText in [" \(headline)", "\(headline) ", "\(headline)\n", "Different question"] {
            let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: headline, messageCount: 3)
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(id: "answer", text: headline, role: "assistant"),
                newsPostMessage(id: "first", text: firstText),
                newsPostMessage(id: "second", text: headline)
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history)
            let model = AgentV2Model(client: client, thread: thread)
            defer { model.stop() }
            await model.waitForInitialLoad()
            let messages = model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role != .system }
            XCTAssertEqual(messages.count, 4, firstText)
            XCTAssertEqual(messages.filter(\.newsPost).count, 1, firstText)
            XCTAssertEqual(messages.filter { $0.role == .user }.map(\.text), [firstText, headline])
            XCTAssertEqual(messages.first?.id, model.newsPostItemID)
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testEmptyNewsThreadShowsALocalPostWithoutSending() async throws {
        let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: "News headline", messageCount: 0, body: "News body")
        let history = try decodeHydration(threadId: thread.id, messages: [], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history)
        let model = AgentV2Model(client: client, thread: thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let messages = model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role != .system }
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(try XCTUnwrap(messages.first).newsPost)
        XCTAssertEqual(messages.first?.text, "**News headline**\n\nNews body")
        XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testNewsPostWaitsForTheFirstUserMessageWhenHistoryIsPaginated() async throws {
        let headline = "News headline"
        let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: headline, messageCount: 2)
        let recent = try decodeHydration(
            threadId: thread.id, messages: [newsPostMessage(id: "second", text: headline)],
            nextCursor: "older", thread: thread
        )
        let oldest = try decodeHydration(
            threadId: thread.id, messages: [newsPostMessage(id: "first", text: headline)], thread: thread
        )
        let client = FakeAgentV2Client(hydrationResults: [recent, oldest])
        let model = AgentV2Model(client: client, thread: thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let laterMessage = try XCTUnwrap(model.itemIDs.compactMap { presentedMessage($0, in: model) }.first { $0.role == .user })
        XCTAssertNil(model.newsPostItemID)
        XCTAssertNil(model.newsPost(for: laterMessage))

        let didLoad = await model.loadOlderMessages()
        XCTAssertTrue(didLoad)
        let messages = model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role != .system }
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.id, model.newsPostItemID)
        XCTAssertEqual(model.newsPost(for: try XCTUnwrap(messages.first)), thread.news)
        XCTAssertNil(model.newsPost(for: laterMessage))
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testFeedReopensLiveDiscussionWithTheSameModelAndReleasesItWhenDismissed() async throws {
        let item = ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline",
            body: "Full **news** body", sources: [.init(name: "Source", url: "https://example.com/news")],
            discussion: .init(threadId: "news-thread")
        )
        let thread = try decodeNewsThread(
            id: "news-thread", eventId: item.eventId, headline: item.headline, messageCount: 1
        )
        let history = try decodeHydration(threadId: thread.id, messages: [
            newsPostMessage(id: "saved-post", text: "**Feed headline**", role: "assistant", newsPost: true)
        ], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history)
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        var model: AgentV2Model? = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        await model?.waitForInitialLoad()
        let postID = try XCTUnwrap(model?.newsPostItemID)
        let initialPost = try XCTUnwrap(presentedMessage(postID, in: try XCTUnwrap(model)))
        XCTAssertNil(model?.newsPost(for: initialPost)?.body)
        XCTAssertNil(model?.newsPost(for: initialPost)?.sources)
        weak var weakModel = model
        let defaultsName = "AgentV2ContractTests.LiveDiscussion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName) }
        var feed: AgentNewsFeedVC? = AgentNewsFeedVC(
            model: AgentNewsFeedModel(
                client: ThreadListNewsClient(items: [item]), readState: AgentNewsReadState(userDefaults: defaults)
            ), preloader: preloader
        )
        weak var weakFeed = feed
        let (window, navigation) = presentDiscussionFeed(try XCTUnwrap(feed))
        defer { window.isHidden = true }
        let open = try await discussionAction(in: try XCTUnwrap(feed), window: window)

        open()
        open()

        XCTAssertEqual(navigation.viewControllers.count, 2)
        try assertChatModel(in: navigation, is: try XCTUnwrap(model))
        do {
            let chat = try XCTUnwrap(navigation.topViewController as? AgentVC)
            let liveModel = try XCTUnwrap(model)
            let post = try XCTUnwrap(presentedMessage(postID, in: liveModel))
            XCTAssertEqual(liveModel.newsPostItemID, postID)
            XCTAssertEqual(post.text, "**Feed headline**\n\nFull **news** body")
            XCTAssertEqual(liveModel.newsPost(for: post)?.body, item.body)
            XCTAssertEqual(liveModel.newsPost(for: post)?.sources, item.sources)
            XCTAssertEqual(chat.copyText(for: postID), "Feed headline\n\nFull news body\n\nhttps://example.com/news")
            XCTAssertEqual(liveModel.itemIDs.compactMap { presentedMessage($0, in: liveModel) }.filter(\.newsPost).count, 1)
        }
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
        XCTAssertFalse(client.requestOrder.contains("createThread"))
        XCTAssertEqual(client.hydrationRequestCount, 1)
        try await waitForDiscussionUI { navigation.transitionCoordinator == nil }
        navigation.popViewController(animated: false)
        try await waitForDiscussionUI { navigation.topViewController === feed && navigation.transitionCoordinator == nil }
        model = nil
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(weakModel?.isReadyForPresentation == true)

        open()

        try assertChatModel(in: navigation, is: try XCTUnwrap(weakModel))
        do {
            let chat = try XCTUnwrap(navigation.topViewController as? AgentVC)
            let liveModel = try XCTUnwrap(weakModel)
            let post = try XCTUnwrap(presentedMessage(postID, in: liveModel))
            XCTAssertEqual(liveModel.newsPostItemID, postID)
            XCTAssertEqual(post.text, "**Feed headline**\n\nFull **news** body")
            XCTAssertEqual(liveModel.newsPost(for: post)?.body, item.body)
            XCTAssertEqual(liveModel.newsPost(for: post)?.sources, item.sources)
            XCTAssertEqual(chat.copyText(for: postID), "Feed headline\n\nFull news body\n\nhttps://example.com/news")
            XCTAssertEqual(liveModel.itemIDs.compactMap { presentedMessage($0, in: liveModel) }.filter(\.newsPost).count, 1)
        }
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
        XCTAssertFalse(client.requestOrder.contains("createThread"))
        XCTAssertTrue(client.startedCommands.isEmpty)
        try await waitForDiscussionUI { navigation.transitionCoordinator == nil }
        navigation.setViewControllers([], animated: false)
        window.rootViewController = nil
        feed = nil
        try await waitForDiscussionUI { weakFeed == nil && weakModel == nil }
        XCTAssertNil(preloader.model(threadId: history.thread.id))
    }

    @MainActor
    func testFeedUsesLoadedThreadSummaryWithoutCreatingANewsThread() async throws {
        let item = ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline",
            body: "Full **news** body", sources: [.init(name: "Source", url: "https://example.com/news")],
            discussion: .init(threadId: "news-thread")
        )
        let thread = try decodeNewsThread(
            id: "news-thread", eventId: item.eventId, headline: item.headline, messageCount: 1
        )
        let history = try decodeHydration(threadId: thread.id, messages: [
            newsPostMessage(id: "saved-post", text: "**Feed headline**", role: "assistant", newsPost: true)
        ], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        client.threadListResult = try JSONDecoder().decode(
            ApiAgentV2ThreadListResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "protocolVersion": 3,
                "threads": [["thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread))]]
            ])
        )
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let defaultsName = "AgentV2ContractTests.LoadedDiscussion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName) }
        let listModel = AgentThreadListModel(
            client: client, newsClient: ThreadListNewsClient(items: [item]),
            readState: AgentNewsReadState(userDefaults: defaults), preloader: preloader
        )
        await listModel.refresh()
        XCTAssertEqual(listModel.items.map(\.thread), [thread])
        XCTAssertNil(preloader.model(threadId: thread.id))
        let feed = AgentNewsFeedVC(model: listModel.makeNewsFeedModel(), preloader: preloader)
        let (window, navigation) = presentDiscussionFeed(feed)
        defer {
            client.resumeBlockedHydration()
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        let open = try await discussionAction(in: feed, window: window)

        open()

        let chat = try XCTUnwrap(navigation.topViewController as? AgentVC)
        let model = try chatModel(in: chat)
        let postID = try XCTUnwrap(model.newsPostItemID)
        let preview = try XCTUnwrap(presentedMessage(postID, in: model))
        XCTAssertEqual(preview.text, "**Feed headline**\n\nFull **news** body")
        XCTAssertEqual(model.newsPost(for: preview)?.body, item.body)
        XCTAssertEqual(model.newsPost(for: preview)?.sources, item.sources)
        XCTAssertEqual(chat.copyText(for: postID), "Feed headline\n\nFull news body\n\nhttps://example.com/news")
        window.layoutIfNeeded()
        let collection = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? UICollectionView }.first)
        try await waitForDiscussionUI {
            window.layoutIfNeeded()
            return collection.visibleCells.contains { $0 is AgentNewsPostCell }
        }
        XCTAssertTrue(collection.visibleCells.contains { $0 is AgentNewsPostCell })
        XCTAssertFalse(model.canSendMessage(draftText: "Follow-up"))
        XCTAssertFalse(model.canClearChat)
        await waitForHydrationRequest(client, count: 1)
        XCTAssertEqual(client.hydratedThreadIds, [thread.id])
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
        XCTAssertFalse(client.requestOrder.contains("createThread"))
        client.resumeBlockedHydration()
        await model.waitForInitialLoad()
        XCTAssertTrue(navigation.topViewController === chat)
        try assertChatModel(in: navigation, is: try XCTUnwrap(preloader.model(threadId: thread.id)))
        XCTAssertEqual(model.newsPostItemID, postID)
        let savedPost = try XCTUnwrap(presentedMessage(postID, in: model))
        XCTAssertEqual(savedPost.text, preview.text)
        XCTAssertEqual(model.newsPost(for: savedPost)?.body, item.body)
        XCTAssertEqual(model.newsPost(for: savedPost)?.sources, item.sources)
        XCTAssertEqual(chat.copyText(for: postID), "Feed headline\n\nFull news body\n\nhttps://example.com/news")
        XCTAssertEqual(model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter(\.newsPost).count, 1)
        XCTAssertTrue(model.canSendMessage(draftText: "Follow-up"))
        XCTAssertTrue(model.canClearChat)
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
        XCTAssertFalse(client.requestOrder.contains("createThread"))
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testFeedFallsBackToNewsCreationThenRetainsTheCreatedDiscussionForReopen() async throws {
        let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: "Server headline", messageCount: 1)
        let history = try decodeHydration(
            threadId: thread.id, messages: [newsPostMessage(id: "question", text: "Already discussed")], thread: thread
        )
        let client = FakeAgentV2Client(hydrationResult: history)
        client.createdThreadIsNew = false
        client.createdThread = thread
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let feedModel = makeDiscussionFeedModel(threadId: thread.id)
        let feed = AgentNewsFeedVC(model: feedModel, preloader: preloader)
        let (window, navigation) = presentDiscussionFeed(feed)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        let open = try await discussionAction(in: feed, window: window)
        open()
        await waitForChat(in: navigation)
        try await waitForDiscussionUI {
            guard let model = preloader.model(threadId: thread.id) else { return false }
            return !model.isOpening && model.isReadyForPresentation
        }
        XCTAssertEqual(client.newsThreadRequests, [.init(eventId: 307, locale: "en")])
        XCTAssertEqual(feedModel.items.first?.discussion?.threadId, thread.id)
        weak var retainedModel = preloader.model(threadId: thread.id)
        XCTAssertNotNil(retainedModel)
        try await waitForDiscussionUI { navigation.transitionCoordinator == nil }
        navigation.popViewController(animated: false)
        try await waitForDiscussionUI { navigation.topViewController === feed && navigation.transitionCoordinator == nil }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(retainedModel?.isReadyForPresentation == true)

        open()

        try assertChatModel(in: navigation, is: try XCTUnwrap(retainedModel))
        XCTAssertEqual(client.newsThreadRequests.count, 1)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testExistingNewsMissingFromTheThreadListKeepsEagerCreationCancellationAndRetry() async throws {
        for shouldLeaveDuringCreation in [true, false] {
            let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: "News", messageCount: 1)
            let history = try decodeHydration(threadId: thread.id, messages: [
                newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
            ], thread: thread)
            let client = FakeAgentV2Client(hydrationResult: history)
            client.blocksThreadCreation = true
            if !shouldLeaveDuringCreation { client.threadCreationError = FakeAgentV2ClientError.unavailable }
            let preloader = AgentPreloader(client: client)
            let feed = AgentNewsFeedVC(model: makeDiscussionFeedModel(threadId: thread.id), preloader: preloader)
            let (window, navigation) = presentDiscussionFeed(feed)
            defer {
                client.resumeThreadCreation()
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
                preloader.setWalletReady(false)
            }
            let open = try await discussionAction(in: feed, window: window)
            open()
            await waitForChat(in: navigation)
            let chat = try XCTUnwrap(navigation.topViewController as? AgentVC)
            let model = try chatModel(in: chat)
            await waitForRequest("createThread", client: client)
            XCTAssertEqual(client.newsThreadRequests, [.init(eventId: 307, locale: "en")])
            XCTAssertTrue(client.startedCommands.isEmpty)
            if shouldLeaveDuringCreation {
                try await waitForDiscussionUI { navigation.transitionCoordinator == nil }
                navigation.popViewController(animated: false)
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                client.resumeThreadCreation()
                try await waitForDiscussionUI { client.cancelledThreadCreationCount == 1 }
                XCTAssertFalse(model.isReadyForPresentation)
                XCTAssertEqual(client.cancelledThreadCreationCount, 1)
                XCTAssertEqual(client.hydrationRequestCount, 0)
            } else {
                client.resumeThreadCreation()
                await model.waitForInitialLoad()
                let failure = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.isFailureCaption })
                let retry = try XCTUnwrap(failure.controls.first { $0.id == "retry-opening" })
                client.threadCreationError = nil
                client.blocksThreadCreation = true
                model.performControl(messageID: failure.id, controlID: retry.id)
                model.performControl(messageID: failure.id, controlID: retry.id)
                try await waitForDiscussionUI { client.newsThreadRequests.count == 2 }
                XCTAssertEqual(client.hydrationRequestCount, 0)
                client.resumeThreadCreation()
                await model.waitForInitialLoad()
                XCTAssertEqual(client.newsThreadRequests.count, 2)
                XCTAssertEqual(client.hydrationRequestCount, 1)
                XCTAssertEqual(model.threadId, thread.id)
            }
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testFeedReopensClearedDiscussionsAsPostsWithoutStartingARun() async throws {
        let headline = "  Headline from thread creation\nwith a second line  \n"
        let initialThread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: headline, messageCount: 1)
        let initialHistory = try decodeHydration(
            threadId: initialThread.id, messages: [newsPostMessage(id: "question", text: "Already discussed")],
            thread: initialThread
        )
        let emptyThread = try decodeNewsThread(
            id: initialThread.id, eventId: 307, headline: headline, messageCount: 0, isCleared: true
        )
        let emptyHistory = try decodeHydration(threadId: emptyThread.id, messages: [], thread: emptyThread)
        for keepsLiveModel in [true, false] {
            let client = FakeAgentV2Client(hydrationResult: initialHistory, shouldCompleteRun: true)
            client.createdThreadIsNew = false
            client.createdThread = emptyThread
            let preloader = AgentPreloader(client: client)
            defer { preloader.setWalletReady(false) }
            let originalModel = try XCTUnwrap(preloader.acquireModel(thread: initialThread))
            await originalModel.waitForInitialLoad()
            var listedThread = initialThread
            let feed = AgentNewsFeedVC(model: makeDiscussionFeedModel(threadId: initialThread.id, findThread: { id in
                id == listedThread.id ? listedThread : nil
            }), preloader: preloader)
            let appearance = DiscussionNavigationObserver()
            let (window, navigation) = presentDiscussionFeed(feed, navigationDelegate: appearance)
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
            }
            let open = try await discussionAction(in: feed, window: window)
            try await waitForDiscussionUI { appearance.shownController === feed }
            open()
            try assertChatModel(in: navigation, is: originalModel)
            XCTAssertTrue(client.newsThreadRequests.isEmpty)

            client.setHydrationResult(emptyHistory)
            originalModel.clearChat(animated: false)
            await waitForRequest("clearThread", client: client)
            try await waitForDiscussionUI {
                originalModel.canSendMessage(draftText: "Next question")
                    && originalModel.itemIDs.compactMap { originalModel.message(for: $0) }.filter(\.newsPost).count == 1
            }
            try await waitForDiscussionUI { appearance.shownController === navigation.topViewController }
            navigation.popViewController(animated: false)
            try await waitForDiscussionUI { appearance.shownController === feed }
            if !keepsLiveModel {
                listedThread = emptyThread
                originalModel.stop()
            }

            open()
            open()

            await waitForChat(in: navigation)
            try await waitForDiscussionUI {
                guard let model = preloader.model(threadId: initialThread.id) else { return false }
                return model.canSendMessage(draftText: "Next question") && !model.isOpening
            }
            XCTAssertTrue(navigation.topViewController is AgentVC)
            XCTAssertEqual(client.newsThreadRequests, keepsLiveModel ? [] : [.init(eventId: 307, locale: "en")])
            XCTAssertTrue(client.startedCommands.isEmpty)
            let reopenedModel = try XCTUnwrap(preloader.model(threadId: initialThread.id))
            try await waitForDiscussionUI {
                reopenedModel.canSendMessage(draftText: "Next question")
                    && reopenedModel.itemIDs.compactMap { reopenedModel.message(for: $0) }.filter(\.newsPost).count == 1
            }
            try await waitForDiscussionUI { appearance.shownController === navigation.topViewController }
            navigation.popViewController(animated: false)
            try await waitForDiscussionUI { appearance.shownController === feed }

            open()

            try assertChatModel(in: navigation, is: reopenedModel)
            XCTAssertEqual(client.newsThreadRequests.count, keepsLiveModel ? 0 : 1)
            XCTAssertTrue(client.startedCommands.isEmpty)
            try await waitForDiscussionUI { appearance.shownController === navigation.topViewController }
        }
    }

    @MainActor
    func testFeedLeavesAndReopensUntouchedDiscussionWithoutCreatingAThread() async throws {
        for kind in DeferredDiscussion.allCases {
            let client = FakeAgentV2Client()
            let preloader = AgentPreloader(client: client)
            defer { preloader.setWalletReady(false) }
            let feedModel = makeDiscussionFeedModel(threadId: nil, digests: [makeFeedDigest()])
            let feed = AgentNewsFeedVC(model: feedModel, preloader: preloader)
            let appearance = DiscussionNavigationObserver()
            let (window, navigation) = presentDiscussionFeed(feed, navigationDelegate: appearance)
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
            }
            let open = try await discussionAction(in: feed, window: window, kind: kind)
            try await waitForDiscussionUI { appearance.shownController === feed }
            open()
            let firstChat = try XCTUnwrap(navigation.topViewController as? AgentVC)
            let firstModel = try chatModel(in: firstChat)
            await firstModel.waitForInitialLoad()
            XCTAssertNil(firstModel.threadId)
            XCTAssertTrue(firstModel.canSendMessage(draftText: "Question"))
            XCTAssertFalse(firstModel.canDeleteChat)
            XCTAssertFalse(firstModel.canReportProblem)
            XCTAssertFalse(firstModel.isStarted)
            try await waitForDiscussionUI { appearance.shownController === firstChat }
            navigation.popViewController(animated: false)
            try await waitForDiscussionUI { appearance.shownController === feed }
            XCTAssertNil(feedDiscussion(kind, in: feedModel))
            // The chat stops its untouched opening a main-queue turn after it leaves the navigation stack
            try await waitForDiscussionUI { deferredDiscussionModel(kind, in: preloader) == nil }

            open()
            open()

            let reopenedChat = try XCTUnwrap(navigation.topViewController as? AgentVC)
            let reopenedModel = try chatModel(in: reopenedChat)
            await reopenedModel.waitForInitialLoad()
            XCTAssertFalse(reopenedModel === firstModel, "\(kind)")
            XCTAssertNil(reopenedModel.threadId)
            XCTAssertTrue(reopenedModel.canSendMessage(draftText: "Question"))
            XCTAssertNil(feedDiscussion(kind, in: feedModel))
            XCTAssertTrue(preloader.getLoadedModels().isEmpty)
            XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
            XCTAssertEqual(client.hydrationRequestCount, 0)
            XCTAssertEqual(client.problemReportAvailabilityRequestCount, 0)
            XCTAssertTrue(client.startedCommands.isEmpty)
        }
    }

    @MainActor
    func testFeedRetriesFailedInitialHydrationAndRetainsTheRecoveredModel() async throws {
        let history = try decodeHydration(
            threadId: "news-thread", messages: [newsPostMessage(id: "question", text: "Already discussed")]
        )
        let client = FakeAgentV2Client(hydrationResult: history)
        client.hydrationError = FakeAgentV2ClientError.unavailable
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let feed = AgentNewsFeedVC(model: makeDiscussionFeedModel(threadId: history.thread.id, findThread: { id in
            id == history.thread.id ? history.thread : nil
        }), preloader: preloader)
        let appearance = DiscussionNavigationObserver()
        let (window, navigation) = presentDiscussionFeed(feed, navigationDelegate: appearance)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        let open = try await discussionAction(in: feed, window: window)
        try await waitForDiscussionUI { appearance.shownController === feed }
        open()
        var failedModel = preloader.model(threadId: history.thread.id)
        weak var discardedModel = failedModel
        XCTAssertNotNil(failedModel)
        await failedModel?.waitForInitialLoad()
        XCTAssertTrue(navigation.topViewController is AgentVC)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertFalse(failedModel?.isReadyForPresentation == true)
        // The feed's preview is already readable; the failed history read belongs below it with Retry.
        XCTAssertNil(failedModel?.initialLoadError)
        XCTAssertNotNil(failedModel?.newsPostItemID)
        do {
            let model = try XCTUnwrap(failedModel)
            let failures = model.itemIDs.compactMap { id -> AgentMessage? in
                guard case .message(let message)? = model.item(for: id), message.isFailureCaption else { return nil }
                return message
            }
            XCTAssertEqual(failures.count, 1)
            XCTAssertEqual(failures.first?.text, lang("Failed to load chat"))
            XCTAssertEqual(failures.first?.controls.map(\.id), ["retry-load"])
            let failedChat = try XCTUnwrap(navigation.topViewController as? AgentVC)
            failedChat.view.layoutIfNeeded()
            XCTAssertTrue(failedChat.loadErrorView.isHidden)
        }
        try await waitForDiscussionUI { appearance.shownController === navigation.topViewController }
        navigation.popViewController(animated: false)
        try await waitForDiscussionUI { appearance.shownController === feed }
        client.hydrationError = nil

        open()

        let recoveredModel = try XCTUnwrap(preloader.model(threadId: history.thread.id))
        await recoveredModel.waitForInitialLoad()
        XCTAssertEqual(client.hydrationRequestCount, 2)
        XCTAssertEqual(client.hydratedThreadIds, [history.thread.id, history.thread.id])
        XCTAssertFalse(recoveredModel === failedModel)
        failedModel = nil
        try await waitForDiscussionUI { discardedModel == nil }
        try assertChatModel(in: navigation, is: recoveredModel)
        XCTAssertTrue(recoveredModel.hasMessages)
        XCTAssertTrue(recoveredModel.canSendMessage(draftText: "Next question"))
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
        XCTAssertTrue(client.startedCommands.isEmpty)
        try await waitForDiscussionUI { appearance.shownController === navigation.topViewController }
        navigation.popViewController(animated: false)
        try await waitForDiscussionUI { appearance.shownController === feed }

        open()

        try assertChatModel(in: navigation, is: recoveredModel)
        XCTAssertEqual(client.hydrationRequestCount, 2)
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
        try await waitForDiscussionUI { appearance.shownController === navigation.topViewController }
    }

    @MainActor
    func testFeedClearsMissingThreadAndUsesTheNewsRouteOnTheNextTap() async throws {
        let history = try decodeHydration(
            threadId: "missing-thread", messages: [newsPostMessage(id: "question", text: "Already discussed", threadId: "missing-thread")]
        )
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        client.hydrationError = ApiAgentV2MutationError(code: .threadNotFound, retryable: false)
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let item = ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline", body: "News body"
        )
        let newsClient = ThreadListNewsClient(items: [ApiAgentV2NewsFeedItem(
            eventId: item.eventId, deliveredAt: item.deliveredAt, headline: item.headline, body: item.body,
            discussion: .init(threadId: history.thread.id)
        )])
        let defaultsName = "AgentV2ContractTests.MissingDiscussion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        addTeardownBlock { UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName) }
        let feedModel = AgentNewsFeedModel(
            client: newsClient, readState: AgentNewsReadState(userDefaults: defaults),
            findThread: { $0 == history.thread.id ? history.thread : nil }
        )
        var newsRequests: [ApiAgentV2ThreadNewsRequest] = []
        let newDiscussion = UIViewController()
        let feed = AgentNewsFeedVC(model: feedModel, preloader: preloader, makeNewsChatViewController: { item, locale, _ in
            newsRequests.append(.init(eventId: item.eventId, locale: locale))
            return newDiscussion
        })
        let (window, navigation) = presentDiscussionFeed(feed)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
        }
        let open = try await discussionAction(in: feed, window: window)
        open()
        weak var pendingChat = navigation.topViewController as? AgentVC
        XCTAssertNotNil(pendingChat)
        await waitForHydrationRequest(client, count: 1)
        weak var discardedModel = preloader.model(threadId: history.thread.id)
        XCTAssertNotNil(discardedModel)
        newsClient.items = [item]

        client.resumeBlockedHydration()

        try await waitForDiscussionUI {
            navigation.topViewController === feed && navigation.transitionCoordinator == nil
                && feedModel.items.first?.discussion == nil && pendingChat == nil && discardedModel == nil
        }
        XCTAssertEqual(client.hydratedThreadIds, [history.thread.id])
        XCTAssertTrue(client.newsThreadRequests.isEmpty)
        XCTAssertTrue(newsRequests.isEmpty)
        let reopen = try await discussionAction(in: feed, window: window)

        reopen()

        XCTAssertTrue(navigation.topViewController === newDiscussion)
        XCTAssertEqual(newsRequests, [.init(eventId: 307, locale: "en")])
        XCTAssertEqual(client.hydrationRequestCount, 1)
    }

    @MainActor
    func testFeedReleasesItsDiscussionOnDeletionResetAndOpeningAnotherDiscussion() async throws {
        for reason in ["deletion", "accountsReset", "walletReset", "anotherDiscussion"] {
            let history = try decodeHydration(
                threadId: "news-thread", messages: [newsPostMessage(id: "question", text: "Already discussed")]
            )
            let otherHistory = try decodeHydration(
                threadId: "other-thread", messages: [newsPostMessage(id: "other-question", text: "Another discussion", threadId: "other-thread")]
            )
            let client = FakeAgentV2Client(hydrationResults: [history, otherHistory])
            let preloader = AgentPreloader(client: client)
            defer { preloader.setWalletReady(false) }
            let feedModel = makeDiscussionFeedModel(threadId: history.thread.id, findThread: { id in
                id == history.thread.id ? history.thread : id == otherHistory.thread.id ? otherHistory.thread : nil
            })
            let feed = AgentNewsFeedVC(model: feedModel, preloader: preloader)
            let (window, navigation) = presentDiscussionFeed(feed)
            defer {
                window.isHidden = true
                navigation.setViewControllers([], animated: false)
            }
            let open = try await discussionAction(in: feed, window: window)
            open()
            await waitForChat(in: navigation)
            weak var retainedModel = preloader.model(threadId: history.thread.id)
            XCTAssertNotNil(retainedModel, reason)
            await retainedModel?.waitForInitialLoad()
            try await waitForDiscussionUI { navigation.transitionCoordinator == nil }
            navigation.popViewController(animated: false)
            try await waitForDiscussionUI { navigation.topViewController === feed && navigation.transitionCoordinator == nil }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertTrue(retainedModel?.isReadyForPresentation == true, reason)

            switch reason {
            case "deletion":
                feed.walletCore(event: .agentThreadDeleted(threadId: history.thread.id))
                XCTAssertNil(feedModel.items.first?.discussion)
            case "accountsReset":
                feed.walletCore(event: .accountsReset)
            case "walletReset":
                preloader.setWalletReady(false)
            default:
                feedModel.markDiscussion(eventId: 307, thread: otherHistory.thread)
                let openOther = try await discussionAction(in: feed, window: window)
                openOther()
                await waitForChat(in: navigation)
                XCTAssertNotNil(preloader.model(threadId: otherHistory.thread.id))
            }

            try await waitForDiscussionUI { retainedModel == nil }
            XCTAssertNil(preloader.model(threadId: history.thread.id), reason)
        }
    }

    @MainActor
    func testReopeningNewsChatWithMessagesReusesItsThreadWithoutSending() async throws {
        let history = try decodeHydration(threadId: "existing-news-thread", messages: [[
            "id": "question", "threadId": "existing-news-thread", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Already discussed"],
            "createdAt": "2026-10-20T10:00:01.000Z"
        ]])
        let client = FakeAgentV2Client(hydrationResult: history)
        client.createdThreadIsNew = false
        client.createdThread = try decodeNewsThread(
            id: history.thread.id, eventId: 308, headline: "Server headline", messageCount: 1
        )
        let preloader = AgentPreloader(client: client)
        let home = UIViewController()
        let navigation = UINavigationController(rootViewController: home)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        var createdThreads: [ApiAgentV2ThreadSummary] = []
        var retainedChat: AgentVC?
        var retainedModel: AgentV2Model?
        for attempt in 1...2 {
            let root = AgentEntryPoint.makeNewsChatViewController(item: newsFeedItem(eventId: 308), locale: "es", preloader: preloader) {
                createdThreads.append($0)
            }
            navigation.pushViewController(root, animated: false)
            await waitForChat(in: navigation)
            try await waitForDiscussionUI {
                guard createdThreads.count == attempt,
                      let chat = navigation.topViewController as? AgentVC,
                      let model = try? chatModel(in: chat) else { return false }
                return model.threadId == history.thread.id && !model.isOpening && model.isReadyForPresentation
                    && model.itemIDs.compactMap { model.message(for: $0) }.contains { $0.text == "Already discussed" }
            }
            window.layoutIfNeeded()
            for _ in 0..<20 { await Task.yield() }
            let chat = try XCTUnwrap(navigation.topViewController as? AgentVC)
            let model = try chatModel(in: chat)
            if attempt == 1 {
                retainedChat = chat
                retainedModel = model
                XCTAssertTrue(chat === root)
            } else {
                XCTAssertTrue(model === retainedModel)
                XCTAssertFalse(chat === root)
            }
            XCTAssertTrue(preloader.model(threadId: history.thread.id) === model)
            let questionID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
            XCTAssertEqual(presentedMessage(questionID, in: model)?.text, "Already discussed")
            let collection = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? UICollectionView }.first)
            let questionIndex = try XCTUnwrap(model.itemIDs.firstIndex(of: questionID))
            XCTAssertTrue(collection.cellForItem(at: IndexPath(item: questionIndex, section: 0)) is AgentMessageCell)
            XCTAssertEqual(client.hydrationRequestCount, 1)
            XCTAssertTrue(client.startedCommands.isEmpty)
            navigation.popViewController(animated: false)
        }
        XCTAssertTrue(try chatModel(in: XCTUnwrap(retainedChat)) === retainedModel)
        XCTAssertEqual(client.newsThreadRequests, Array(repeating: .init(eventId: 308, locale: "es"), count: 2))
        XCTAssertEqual(createdThreads.map(\.id), [history.thread.id, history.thread.id])
        XCTAssertEqual(client.hydratedThreadIds, [history.thread.id])
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 2)
        XCTAssertFalse(client.requestOrder.contains("defaultThread"))
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testSharedNewsOpeningReplacesEveryControllerWithTheLiveThreadModel() async throws {
        let item = ApiAgentV2NewsFeedItem(
            eventId: 308, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline", body: "News body",
            sources: [.init(name: "Source", url: "https://example.com/news")],
            discussion: .init(threadId: "shared-news-thread")
        )
        let thread = try decodeNewsThread(
            id: "shared-news-thread", eventId: item.eventId, headline: "Already discussed", messageCount: 1
        )
        let history = try decodeHydration(
            threadId: thread.id,
            messages: [newsPostMessage(id: "question", text: "Already discussed", threadId: thread.id)],
            thread: thread
        )
        let client = FakeAgentV2Client(hydrationResult: history)
        client.createdThread = thread
        client.createdThreadIsNew = false
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        let liveModel = try XCTUnwrap(preloader.acquireModel(thread: thread))
        await liveModel.waitForInitialLoad()
        let postID = try XCTUnwrap(liveModel.newsPostItemID)
        XCTAssertNil(liveModel.news?.body)
        XCTAssertNil(liveModel.news?.sources)
        let opening = preloader.acquireNewsModel(item: item, locale: "es", onThreadCreated: { _ in })
        let secondOpening = preloader.acquireNewsModel(item: item, locale: "es", onThreadCreated: { _ in })
        XCTAssertTrue(secondOpening === opening)
        let firstChat = AgentVC(model: opening)
        let secondChat = AgentVC(model: secondOpening)
        let home = UIViewController()
        let navigation = UINavigationController(rootViewController: home)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.pushViewController(firstChat, animated: false)
        navigation.pushViewController(secondChat, animated: false)
        defer {
            client.resumeThreadCreation()
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        await waitForRequest("createThread", client: client)
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertNil(opening.threadId)
        XCTAssertTrue(preloader.model(threadId: thread.id) === liveModel)

        client.resumeThreadCreation()
        try await waitForDiscussionUI {
            navigation.viewControllers.count == 3
                && navigation.viewControllers[1] !== firstChat
                && navigation.viewControllers[2] !== secondChat
        }

        XCTAssertTrue(navigation.viewControllers[0] === home)
        let firstReplacement = try XCTUnwrap(navigation.viewControllers[1] as? AgentVC)
        let secondReplacement = try XCTUnwrap(navigation.viewControllers[2] as? AgentVC)
        XCTAssertFalse(firstReplacement === secondReplacement)
        XCTAssertTrue(try chatModel(in: firstReplacement) === liveModel)
        XCTAssertTrue(try chatModel(in: secondReplacement) === liveModel)
        XCTAssertEqual(liveModel.news?.body, item.body)
        XCTAssertEqual(liveModel.news?.sources, item.sources)
        XCTAssertEqual(liveModel.newsPostItemID, postID)
        let post = try XCTUnwrap(presentedMessage(postID, in: liveModel))
        XCTAssertEqual(post.text, "**Already discussed**\n\nNews body")
        XCTAssertEqual(liveModel.itemIDs.compactMap { presentedMessage($0, in: liveModel) }.filter(\.newsPost).count, 1)
        for chat in [firstReplacement, secondReplacement] {
            XCTAssertEqual(chat.copyText(for: postID), "Already discussed\n\nNews body\n\nhttps://example.com/news")
        }
        XCTAssertTrue(opening.presentationModel === liveModel)
        XCTAssertFalse(opening.isReadyForPresentation)
        XCTAssertNil(opening.threadId)
        XCTAssertNil(opening.thread)
        XCTAssertTrue(preloader.model(threadId: thread.id) === liveModel)
        XCTAssertNil(preloader.newsModel(eventId: item.eventId))
        XCTAssertEqual(client.newsThreadRequests, [.init(eventId: item.eventId, locale: "es")])
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertEqual(client.hydratedThreadIds, [thread.id])
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testNewsOpeningRehydratesTheLoadedThreadModelAtAHigherRevision() async throws {
        let item = newsFeedItem(eventId: 308)
        let thread = try decodeNewsThread(
            id: "shared-news-thread", eventId: item.eventId, headline: "Already discussed", messageCount: 1
        )
        let history = try decodeHydration(
            threadId: thread.id,
            messages: [newsPostMessage(id: "question", text: "Already discussed", threadId: thread.id)],
            thread: thread
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)) as? [String: Any])
        object["revision"] = thread.revision + 1
        var news = try XCTUnwrap(object["news"] as? [String: Any])
        news["body"] = "Rebuilt news post"
        object["news"] = news
        let rebuiltThread = try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: object)
        )
        let rebuiltHistory = try decodeHydration(
            threadId: thread.id,
            messages: [newsPostMessage(
                id: "question", text: "Rebuilt news post", role: "assistant", threadId: thread.id, newsPost: true
            )],
            thread: rebuiltThread
        )
        let client = FakeAgentV2Client(hydrationResults: [history, rebuiltHistory])
        client.createdThread = rebuiltThread
        client.createdThreadIsNew = false
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        defer { preloader.setWalletReady(false) }
        let liveModel = try XCTUnwrap(preloader.acquireModel(thread: thread))
        await liveModel.waitForInitialLoad()
        preloader.keepRecent(liveModel)
        let opening = preloader.acquireNewsModel(item: item, locale: "ru", onThreadCreated: { _ in })
        await waitForRequest("createThread", client: client)

        client.resumeThreadCreation()
        await opening.waitForInitialLoad()
        await waitForHydrationRequest(client, count: 2)

        XCTAssertTrue(opening.presentationModel === liveModel)
        XCTAssertEqual(client.hydratedThreadIds, [thread.id, thread.id])
        XCTAssertEqual(liveModel.thread?.revision, rebuiltThread.revision)
        let postID = try XCTUnwrap(liveModel.newsPostItemID)
        let post = try XCTUnwrap(presentedMessage(postID, in: liveModel))
        XCTAssertEqual(post.text, "**Already discussed**\n\nRebuilt news post")
    }

    @MainActor
    func testInitialHydrationSurvivesAnUnmatchedRunThatIsCancelled() async throws {
        let history = try decodeHydration(threadId: "initial-thread", messages: [
            newsPostMessage(id: "earlier-question", text: "Earlier question", threadId: "initial-thread")
        ])
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        let coordinator = AgentV2Coordinator(client: client, thread: history.thread)
        defer {
            coordinator.stop()
            client.resumeBlockedHydration()
        }
        coordinator.start()
        try await waitForDiscussionUI { client.hydrationRequestCount == 1 }

        let started = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runStarted", "clientRunId": "client-\(history.thread.id)", "runId": "run-\(history.thread.id)",
            "threadId": history.thread.id, "threadRevision": history.thread.revision + 1
        ]))
        coordinator.walletCore(event: .agentV2(started))
        coordinator.walletCore(event: .agentV2(try decodeUpdate(
            kind: "runCancelled", threadId: history.thread.id, messageId: "remote-question"
        )))
        client.resumeBlockedHydration()
        await coordinator.waitForInitialLoad()

        XCTAssertTrue(coordinator.hasHydratedMessages)
        XCTAssertEqual(coordinator.messages.map(\.text), ["Earlier question"])
    }

    @MainActor
    func testWalletAuthorityChangeDoesNotDiscardInitialNewsHistory() async throws {
        let thread = try decodeNewsThread(id: "news-thread", eventId: 308, headline: "News", messageCount: 1)
        let history = try decodeHydration(threadId: thread.id, messages: [
            newsPostMessage(id: "news-post", text: "News post", threadId: thread.id, newsPost: true)
        ], thread: thread)
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        let coordinator = AgentV2Coordinator(client: client, thread: thread)
        defer {
            coordinator.stop()
            client.resumeBlockedHydration()
        }
        coordinator.start()
        await waitForHydrationRequest(client, count: 1)

        coordinator.walletCore(event: .agentV2(try JSONDecoder().decode(
            ApiAgentV2ClientUpdate.self,
            from: JSONSerialization.data(withJSONObject: ["kind": "walletAuthorityChanged"])
        )))
        client.resumeBlockedHydration()
        await coordinator.waitForInitialLoad()

        XCTAssertTrue(coordinator.hasHydratedMessages)
    }

    @MainActor
    func testRefreshHydrationPreservesAMessageSentDuringItsFetch() async throws {
        let history = try decodeHydration(threadId: "refresh-thread", messages: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(history.thread)) as? [String: Any])
        object["revision"] = history.thread.revision + 1
        let refreshedThread = try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: object)
        )
        let refreshedHistory = try decodeHydration(threadId: history.thread.id, messages: [], thread: refreshedThread)
        let client = FakeAgentV2Client(hydrationResults: [history, refreshedHistory], blockedHydrationAttempt: 2)
        client.clientRunIds = ["client-\(history.thread.id)"]
        client.blocksRunStart = true
        let coordinator = AgentV2Coordinator(client: client, thread: history.thread)
        defer {
            coordinator.stop()
            client.resumeBlockedHydration()
            client.resumeRunStart()
        }
        await coordinator.hydrate()

        let refresh = Task { await coordinator.hydrate() }
        await waitForHydrationRequest(client, count: 2)
        XCTAssertTrue(coordinator.send(
            input: .append(text: "Next question"), visibleText: "Next question", localInputMessageId: "new-question"
        ))
        try await waitForDiscussionUI { client.startedCommands.count == 1 }

        let started = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runStarted", "clientRunId": "client-\(history.thread.id)", "runId": "run-\(history.thread.id)",
            "threadId": history.thread.id, "threadRevision": history.thread.revision + 1
        ]))
        coordinator.walletCore(event: .agentV2(started))
        coordinator.walletCore(event: .agentV2(try decodeUpdate(
            kind: "runCancelled", threadId: history.thread.id, messageId: "new-question"
        )))
        XCTAssertEqual(coordinator.activeRun?.isRunning, false)

        client.resumeBlockedHydration()
        await refresh.value

        XCTAssertEqual(coordinator.messages.first { $0.id == "new-question" }?.text, "Next question")
    }

    @MainActor
    func testRefreshDoesNotInterruptAHydratingQuestionOpening() async throws {
        let history = try decodeHydration(threadId: "opening-thread", messages: [
            newsPostMessage(id: "earlier-question", text: "Earlier question", threadId: "opening-thread")
        ])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(history.thread)) as? [String: Any])
        object["revision"] = history.thread.revision + 1
        let refreshedThread = try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: object)
        )
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        client.blocksRunStart = true
        let coordinator = AgentV2Coordinator(client: client, thread: history.thread, question: "Opening question")
        defer {
            coordinator.stop()
            client.resumeBlockedHydration()
            client.resumeRunStart()
        }
        coordinator.start()
        await waitForHydrationRequest(client, count: 1)

        coordinator.refreshThreadIfNeeded(refreshedThread)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.hydrationRequestCount, 1)
        client.resumeBlockedHydration()
        await coordinator.waitForInitialLoad()
        for _ in 0..<100 where client.startedCommands.isEmpty { await Task.yield() }

        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Opening question")])
    }

    @MainActor
    func testDeferredDiscussionCreationErrorsKeepTheFirstMessageAndRetryItOnce() async throws {
        for kind in DeferredDiscussion.allCases {
            let unavailable: (Error, String) = switch kind {
            case .news: (ApiAgentV2MutationError(code: .newsUnavailable, retryable: true), lang("$agent_news_unavailable"))
            case .digest: (ApiAgentV2MutationError(code: .digestUnavailable, retryable: true), lang("$agent_digest_unavailable"))
            }
            let errors: [(Error, String)] = [
                unavailable,
                (ApiAgentV2MutationError(code: .rateLimited, retryable: true), lang("Agent is unavailable")),
                (FakeAgentV2ClientError.unavailable, lang("Agent is unavailable"))
            ]
            for (error, expectedText) in errors {
                let thread = try decodeDiscussionThread(kind, id: "retried-discussion-thread", messageCount: 1)
                let history = try decodeHydration(threadId: thread.id, messages: [
                    newsPostMessage(id: "post", text: "News", role: "assistant", threadId: thread.id, newsPost: true)
                ], thread: thread)
                let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
                client.threadCreationError = error
                client.blocksRunStart = true
                let model = makeDeferredDiscussionModel(kind, client: client)
                defer {
                    model.stop()
                    client.resumeBlockedHydration()
                    client.resumeRunStart()
                }
                await model.waitForInitialLoad()
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 0)
                model.send(text: "First question")
                XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role == .user }.map(\.text), ["First question"])
                try await waitForDiscussionUI {
                    model.itemIDs.compactMap { model.message(for: $0) }.contains { $0.text == expectedText && !$0.controls.isEmpty }
                }
                let errorMessage = try XCTUnwrap(model.itemIDs.compactMap { model.message(for: $0) }.first { $0.text == expectedText })
                let retry = try XCTUnwrap(errorMessage.controls.first { $0.title == lang("Retry") })
                XCTAssertEqual(client.hydrationRequestCount, 0)
                XCTAssertEqual(discussionThreadRequestCount(kind, in: client), 1)
                XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role == .user }.map(\.text), ["First question"])
                let existingClient = FakeAgentV2Client()
                existingClient.threadCreationError = error
                let existing = makeDeferredDiscussionModel(kind, client: existingClient, threadId: thread.id)
                defer { existing.stop() }
                await existing.waitForInitialLoad()
                let existingError = existing.itemIDs.compactMap { existing.message(for: $0) }.first { !$0.controls.isEmpty }
                XCTAssertEqual(existingError?.text, errorMessage.text)
                XCTAssertEqual(discussionThreadRequestCount(kind, in: existingClient), 1)

                client.threadCreationError = nil
                model.performControl(messageID: errorMessage.id, controlID: retry.id)
                model.performControl(messageID: errorMessage.id, controlID: retry.id)
                await waitForHydrationRequest(client, count: 1)
                XCTAssertTrue(client.startedCommands.isEmpty)
                client.resumeBlockedHydration()
                try await waitForDiscussionUI { client.startedCommands.count == 1 }

                switch kind {
                case .news:
                    XCTAssertEqual(client.newsThreadRequests, Array(repeating: .init(eventId: 307, locale: "en"), count: 2))
                case .digest:
                    XCTAssertEqual(client.digestThreadRequests, Array(repeating: .init(id: Self.deferredDigestId), count: 2))
                }
                XCTAssertEqual(client.hydrationRequestCount, 1)
                XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question")])
                XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role == .user }.map(\.text), ["First question"])
            }
        }
    }

    @MainActor
    func testNewsCreationWithoutNewsKeepsThePreviewPostWithoutStartingARun() async throws {
        let item = newsFeedItem(eventId: 310)
        let history = try decodeHydration(threadId: "missing-news-thread", messages: [])
        let client = FakeAgentV2Client(hydrationResult: history, blockedHydrationAttempt: 1)
        client.createdThread = history.thread
        let preloader = AgentPreloader(client: client)
        var createdThreads: [ApiAgentV2ThreadSummary] = []
        let chat = try XCTUnwrap(AgentEntryPoint.makeNewsChatViewController(
            item: item, locale: "de", preloader: preloader,
            onThreadCreated: { createdThreads.append($0) }
        ) as? AgentVC)
        let model = try chatModel(in: chat)
        let navigation = UINavigationController(rootViewController: chat)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            client.resumeBlockedHydration()
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        await waitForHydrationRequest(client, count: 1)
        let postID = try XCTUnwrap(model.newsPostItemID)
        let previewIDs = model.itemIDs
        XCTAssertEqual(model.threadId, history.thread.id)
        XCTAssertFalse(model.canSendMessage(draftText: "Next question"))
        XCTAssertFalse(model.canClearChat)
        XCTAssertEqual(presentedMessage(postID, in: model)?.text, "**Feed headline**\n\nNews body")
        XCTAssertFalse(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
        XCTAssertTrue(client.startedCommands.isEmpty)

        client.resumeBlockedHydration()
        try await waitForDiscussionUI { !model.isOpening && model.isReadyForPresentation }

        let messages = model.itemIDs.compactMap { model.message(for: $0) }.filter { $0.role != .system }
        XCTAssertTrue(navigation.topViewController === chat)
        XCTAssertEqual(model.itemIDs, previewIDs)
        XCTAssertEqual(model.newsPostItemID, postID)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(try XCTUnwrap(messages.first).newsPost)
        XCTAssertEqual(model.news?.headline, item.headline)
        XCTAssertEqual(model.news?.body, item.body)
        XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
        XCTAssertTrue(model.canClearChat)
        XCTAssertEqual(client.newsThreadRequests, [.init(eventId: 310, locale: "de")])
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertEqual(createdThreads, [history.thread])
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testNewsChatWithExistingMessagesLoadsHistoryAndDoesNotSendAfterClear() async throws {
        let history = try decodeHydration(threadId: "hydrated-news-thread", messages: [[
            "id": "existing-question", "threadId": "hydrated-news-thread", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Already discussed"],
            "createdAt": "2026-10-20T10:00:01.000Z"
        ]])
        let client = FakeAgentV2Client(hydrationResult: history)
        client.createdThread = try decodeNewsThread(
            id: history.thread.id, eventId: 311, headline: "Headline from creation", messageCount: 1
        )
        let preloader = AgentPreloader(client: client)
        let root = AgentEntryPoint.makeNewsChatViewController(item: newsFeedItem(eventId: 311), locale: "it", preloader: preloader) { _ in }
        let navigation = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        await waitForChat(in: navigation)
        let chat = try XCTUnwrap(navigation.topViewController as? AgentVC)
        let model = try chatModel(in: chat)
        try await waitForDiscussionUI { !model.isOpening && model.isReadyForPresentation }
        for _ in 0..<2 {
            chat.viewIsAppearing(false)
            window.layoutIfNeeded()
            for _ in 0..<20 { await Task.yield() }
        }
        XCTAssertTrue(model.itemIDs.contains { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.text == "Already discussed"
        })
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertTrue(model.canClearChat)

        client.setHydrationResult(try decodeHydration(threadId: history.thread.id, messages: []))
        model.clearChat(animated: false)
        await waitForRequest("clearThread", client: client)
        for _ in 0..<100 where !model.canSendMessage(draftText: "Next question") {
            await Task.yield()
        }
        XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter(\.newsPost).count, 1)
        XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
        for _ in 0..<2 {
            chat.viewIsAppearing(false)
            window.layoutIfNeeded()
            for _ in 0..<20 { await Task.yield() }
        }

        XCTAssertEqual(client.newsThreadRequests, [.init(eventId: 311, locale: "it")])
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertEqual(model.itemIDs.compactMap { model.message(for: $0) }.filter(\.newsPost).count, 1)
    }

    @MainActor
    func testNewChatWithoutQuestionCreatesTheThreadAndDoesNotSendAMessage() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "empty", messages: []))
        let preloader = AgentPreloader(client: client)
        let root = AgentEntryPoint.makeNewChatViewController(preloader: preloader)
        XCTAssertTrue(root is AgentRootVC)
        XCTAssertTrue(AgentEntryPoint.makeNewChatViewController(query: " \n ", preloader: preloader) is AgentRootVC)
        let navigation = UINavigationController(rootViewController: root)
        defer {
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
        }
        root.loadViewIfNeeded()
        await waitForChat(in: navigation)
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertFalse(client.requestOrder.contains("defaultThread"))
        XCTAssertTrue(client.startedCommands.isEmpty)
        XCTAssertEqual(navigation.topViewController?.title, lang("New Chat"))
    }

    @MainActor
    func testNewQuestionWaitsForConsentInsideTheSameChatThenContinues() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "consented", messages: []), shouldCompleteRun: true)
        client.hasConsent = false
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader) as? AgentVC)
        let model = try chatModel(in: chat)
        let inputID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
        let navigation = UINavigationController(rootViewController: chat)
        defer {
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.resumeRunStart()
        }
        chat.loadViewIfNeeded()
        let consent = try await waitForConsentView(in: chat)
        XCTAssertTrue(model.needsOpeningConsent)
        XCTAssertEqual(presentedMessage(inputID, in: model)?.text, "Question")
        XCTAssertFalse(client.requestOrder.contains("createThread"))
        XCTAssertTrue(client.startedCommands.isEmpty)

        let sheet = try XCTUnwrap(presentation.presentedSheets.first)
        consent.onContinue?()
        consent.onContinue?()
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.count, 1, "Allow sends the question once")
        XCTAssertFalse(presentation.isPresented(sheet), "Allow closes the sheet")
        XCTAssertEqual(presentation.presentedSheets.count, 1, "It asks once")

        XCTAssertTrue(navigation.topViewController === chat)
        XCTAssertFalse(model.needsOpeningConsent)
        XCTAssertEqual(client.requestOrder.first, "acceptConsent")
        XCTAssertEqual(client.requestOrder.filter { $0 == "createThread" }.count, 1)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Question")])
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [.agentTab])
        XCTAssertEqual(presentedMessageID(in: model, role: .user), inputID)
        XCTAssertEqual(client.hydrationRequestCount, 0)
    }

    /// A question asked from search by a user who has consent goes at once, without the sheet, also when consent was
    /// read as missing as the chat opened: it is read again before the sheet would ask
    @MainActor
    func testQuestionAskedFromSearchByAConsentedUserRunsOnceWithoutTheSheet() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "searched", messages: []), shouldCompleteRun: true)
        client.hasConsent = false
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let entryPoint = ApiAgentV2EntryPoint.globalSearch(query: "токены")
        let chat = try XCTUnwrap(
            AgentEntryPoint.makeNewChatViewController(query: "Получить токены", entryPoint: entryPoint, preloader: preloader)
                as? AgentVC
        )
        let model = try chatModel(in: chat)
        let navigation = UINavigationController(rootViewController: chat)
        defer {
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.resumeRunStart()
        }
        // Read as missing as the chat opens, while the user has consent
        try await waitForDiscussionUI { model.needsOpeningConsent }
        client.hasConsent = true
        let window = makeKeyWindow(showing: navigation)
        defer { window.isHidden = true }

        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(presentation.presentedSheets.isEmpty, "A user with consent never sees the sheet")
        XCTAssertEqual(client.startedCommands.count, 1, "One run")
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Получить токены")])
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [entryPoint])
        XCTAssertFalse(model.needsOpeningConsent)
    }

    /// A question asked from search by a user without consent waits in its chat under the sheet, and Allow sends it once
    @MainActor
    func testQuestionAskedFromSearchWithoutConsentAsksInTheSheetAndAllowSendsItOnce() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "searched", messages: []), shouldCompleteRun: true)
        client.hasConsent = false
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let entryPoint = ApiAgentV2EntryPoint.globalSearch(query: "токены")
        let chat = try XCTUnwrap(
            AgentEntryPoint.makeNewChatViewController(query: "Получить токены", entryPoint: entryPoint, preloader: preloader)
                as? AgentVC
        )
        let navigation = UINavigationController(rootViewController: chat)
        defer {
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.resumeRunStart()
        }
        let window = makeKeyWindow(showing: navigation)
        defer { window.isHidden = true }

        let consent = try await waitForConsentView(in: chat)
        XCTAssertEqual(presentation.presentedSheets.count, 1)
        XCTAssertTrue(client.startedCommands.isEmpty, "Nothing goes before Allow")
        consent.onContinue?()
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.count, 1, "Allow sends it once")
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [entryPoint])
        XCTAssertEqual(presentation.presentedSheets.count, 1, "It asks once")
    }

    @MainActor
    func testNewQuestionCannotBeCapturedByAnotherThread() async throws {
        let selectedClient = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "selected", messages: []))
        let questionClient = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "new", messages: []))
        let selectedPreloader = AgentPreloader(client: selectedClient)
        let questionPreloader = AgentPreloader(client: questionClient)
        let questionRoot = AgentEntryPoint.makeNewChatViewController(query: "Scoped question", preloader: questionPreloader)
        let selected = AgentEntryPoint.makeRootViewController(
            thread: try decodeHydration(threadId: "selected", messages: []).thread, preloader: selectedPreloader
        )
        let navigation = UINavigationController(rootViewController: selected)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            selectedPreloader.setWalletReady(false)
            questionPreloader.setWalletReady(false)
        }
        await waitForChat(in: navigation)
        window.layoutIfNeeded()
        XCTAssertTrue(selectedClient.startedCommands.isEmpty)
        navigation.pushViewController(questionRoot, animated: false)
        await waitForChat(in: navigation)
        for _ in 0..<100 where questionClient.startedCommands.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(selectedClient.startedCommands.isEmpty)
        XCTAssertEqual(questionClient.startedCommands.map(\.threadId), ["new"])
        XCTAssertEqual(questionClient.startedCommands.map(\.input), [.append(text: "Scoped question")])
    }

    @MainActor
    func testResetDuringThreadCreationDoesNotHydrateOrSendTheQuestion() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "empty", messages: []))
        client.blocksThreadCreation = true
        let preloader = AgentPreloader(client: client)
        let root = AgentEntryPoint.makeNewChatViewController(query: "Question", preloader: preloader)
        let navigation = UINavigationController(rootViewController: root)
        defer { navigation.setViewControllers([], animated: false) }
        root.loadViewIfNeeded()
        await waitForRequest("createThread", client: client)
        preloader.walletCore(event: .accountsReset)
        client.resumeThreadCreation()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertEqual(client.hydrationRequestCount, 0)
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    @MainActor
    func testChatHeaderUsesFirstQuestionThenUpdatesEmojiAndTitleFromThreadChanged() async throws {
        let hydration = try decodeHydration(threadId: "header", messages: [[
            "id": "question", "threadId": "header", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "How is my portfolio doing?"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]])
        let model = AgentV2Model(client: FakeAgentV2Client(hydrationResult: hydration), thread: hydration.thread)
        await model.waitForInitialLoad()
        let controller = AgentVC(model: model)
        controller.loadViewIfNeeded()
        defer { controller.didMove(toParent: nil) }
        XCTAssertEqual(controller.title, "How is my portfolio doing?")
        var summary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(hydration.thread)) as? [String: Any])
        summary["title"] = "Portfolio review"
        summary["icon"] = "💼"
        let renamed = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: summary))
        WalletCoreData.notify(event: .agentV2(.threadChanged(threadId: renamed.id, thread: renamed)))
        for _ in 0..<100 where controller.title != "💼 Portfolio review" {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.chatTitle, "💼 Portfolio review")
        XCTAssertEqual(controller.title, "💼 Portfolio review")
        let foreign = try decodeHydration(threadId: "foreign", messages: []).thread
        WalletCoreData.notify(event: .agentV2(.threadChanged(threadId: foreign.id, thread: foreign)))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(controller.title, "💼 Portfolio review")
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
        let client = FakeAgentV2Client(
            hydrationResult: try decodeHydration(threadId: "thread-a", messages: []), blockedHydrationAttempt: 1
        )
        client.hintsResult = try initialHints()
        client.blocksHints = true
        let root = AgentRootVC(client: client)
        let navigation = UINavigationController(rootViewController: root)
        defer {
            client.resumeBlockedHydration()
            client.resumeHints()
            navigation.setViewControllers([], animated: false)
        }
        root.loadViewIfNeeded()
        await waitForHydrationRequest(client, count: 1)
        XCTAssertEqual(client.hydrationRequestCount, 1)
        try await waitForDiscussionUI { client.hintsRequestCount > 0 }
        XCTAssertTrue(navigation.topViewController === root)
        client.resumeBlockedHydration()
        client.resumeHints()
        await waitForChat(in: navigation)
        XCTAssertTrue(navigation.topViewController is AgentVC)
        navigation.setViewControllers([], animated: false)

        let model = AgentV2Model(client: client)
        defer { model.stop() }
        await model.waitForInitialLoad()
        XCTAssertEqual(model.visibleHints.map(\.id), ["learn.swap", AgentHint.supportRequest.id])
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
        // With nothing to show, the chat has the failure in its middle rather than as a line
        XCTAssertEqual(model.initialLoadError, lang("Failed to load chat"))
        XCTAssertFalse(model.itemIDs.contains { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.isFailureCaption || message.text == lang("Failed to load chat")
        })
    }

    @MainActor
    func testClearChatEmptiesTheChatAtOnceAndRestoresItWhenClearingFails() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: [[
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Existing question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]]))
        client.blocksClear = true
        client.clearError = FakeAgentV2ClientError.unavailable
        let model = AgentV2Model(client: client)
        defer { model.stop() }
        await model.waitForInitialLoad()
        XCTAssertTrue(model.canClearChat)

        model.clearChat(animated: false)
        XCTAssertTrue(model.itemIDs.isEmpty)
        XCTAssertFalse(model.canSendMessage(draftText: "Next question"))

        await waitForRequest("clearThread", client: client)
        client.resumeClear()
        for _ in 0..<100 {
            guard model.itemIDs.isEmpty else { break }
            await Task.yield()
        }
        XCTAssertTrue(model.itemIDs.contains { id in
            guard case .message(let message) = model.item(for: id) else { return false }
            return message.text == "Existing question"
        })
        XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
    }

    @MainActor
    func testClearChatKeepsTheChatEmptyAndUnblocksSendingWhenClearingSucceeds() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeHydration(threadId: "thread-a", messages: [[
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Existing question"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]]))
        client.blocksClear = true
        let model = AgentV2Model(client: client)
        defer { model.stop() }
        await model.waitForInitialLoad()

        model.clearChat(animated: false)
        XCTAssertTrue(model.itemIDs.isEmpty)
        XCTAssertFalse(model.canSendMessage(draftText: "Next question"))

        await waitForRequest("clearThread", client: client)
        client.resumeClear()
        for _ in 0..<100 {
            guard !model.canSendMessage(draftText: "Next question") else { break }
            await Task.yield()
        }
        XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
        XCTAssertTrue(model.itemIDs.isEmpty)
    }

    @MainActor
    func testNewQuestionLoadsExistingHistoryAndSendsItsQuestionAfterIt() async throws {
        let history = try decodeHydration(threadId: "reused-history", messages: [
            newsPostMessage(id: "old-question", text: "Earlier question", threadId: "reused-history")
        ])
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHydrationAttempt: 1)
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let entryPoint = ApiAgentV2EntryPoint.globalSearch(query: "Search question")
        let chat = try XCTUnwrap(AgentEntryPoint.makeNewChatViewController(
            query: "Search question", entryPoint: entryPoint, preloader: preloader
        ) as? AgentVC)
        let model = try chatModel(in: chat)
        let inputID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
        let navigation = UINavigationController(rootViewController: chat)
        chat.loadViewIfNeeded()
        defer {
            client.resumeBlockedHydration()
            navigation.setViewControllers([], animated: false)
            preloader.setWalletReady(false)
            client.resumeRunStart()
        }
        await waitForHydrationRequest(client, count: 1)
        XCTAssertEqual(presentedMessage(inputID, in: model)?.text, "Search question")
        XCTAssertTrue(client.startedCommands.isEmpty)

        client.resumeBlockedHydration()
        try await waitForDiscussionUI { client.startedCommands.count == 1 }

        XCTAssertTrue(navigation.topViewController === chat)
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "Search question")])
        XCTAssertEqual(client.startedCommands.map(\.entryPoint), [entryPoint])
        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertEqual(model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role == .user }.map(\.text), ["Earlier question", "Search question"])
        XCTAssertEqual(presentedMessage(inputID, in: model)?.text, "Search question")
        XCTAssertTrue(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
    }

    private func initialHints() throws -> ApiAgentV2HintsResponse {
        try JSONDecoder().decode(ApiAgentV2HintsResponse.self, from: Data(
            #"{"protocolVersion":2,"catalogVersion":"initial","items":[{"id":"learn.swap"}]}"#.utf8
        ))
    }

    @MainActor
    private func makeDiscussionFeedModel(
        threadId: String?,
        digests: [ApiAgentV2NewsFeedDigest]? = nil,
        findThread: @escaping (String) -> ApiAgentV2ThreadSummary? = { _ in nil }
    ) -> AgentNewsFeedModel {
        let defaultsName = "AgentV2ContractTests.Discussion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        addTeardownBlock { UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName) }
        let item = ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline", body: "News body",
            discussion: threadId.map { .init(threadId: $0) }
        )
        let client = ThreadListNewsClient(items: [item])
        client.digests = digests
        return AgentNewsFeedModel(client: client, readState: AgentNewsReadState(userDefaults: defaults), findThread: findThread)
    }

    @MainActor
    private func presentDiscussionFeed(
        _ feed: AgentNewsFeedVC,
        navigationDelegate: UINavigationControllerDelegate? = nil
    ) -> (UIWindow, UINavigationController) {
        let navigation = UINavigationController(rootViewController: feed)
        navigation.delegate = navigationDelegate
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        return (window, navigation)
    }

    @MainActor
    private final class DiscussionNavigationObserver: NSObject, UINavigationControllerDelegate {
        weak var shownController: UIViewController?

        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            shownController = nil
        }

        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            shownController = viewController
        }
    }

    @MainActor
    private func discussionAction(
        in feed: AgentNewsFeedVC,
        window: UIWindow,
        kind: DeferredDiscussion = .news
    ) async throws -> () -> Void {
        let collection = try XCTUnwrap(feed.view.subviews.compactMap { $0 as? UICollectionView }.first)
        func findAction() -> (() -> Void)? {
            switch kind {
            case .news: collection.visibleCells.compactMap { ($0 as? AgentNewsFeedCardCell)?.discussionAction }.first
            case .digest: collection.visibleCells.compactMap { ($0 as? AgentNewsDigestCardCell)?.discussionAction }.first
            }
        }
        try await waitForDiscussionUI {
            window.layoutIfNeeded()
            return findAction() != nil
        }
        return try XCTUnwrap(findAction())
    }

    @MainActor
    private func assertChatModel(in navigation: UINavigationController, is model: AgentV2Model) throws {
        let chat = try XCTUnwrap(navigation.topViewController as? AgentVC)
        XCTAssertTrue(try chatModel(in: chat) === model)
    }

    @MainActor
    private func chatModel(in chat: AgentVC) throws -> AgentV2Model {
        try XCTUnwrap(Mirror(reflecting: chat).children.first { $0.label == "model" }?.value as? AgentV2Model)
    }

    /// A news item's or a digest's discussion opened from the feed's copy without a thread, which waits for its first
    /// message
    private enum DeferredDiscussion: CaseIterable {
        case news
        case digest
    }

    private static let deferredDigestId = "en:2026-10-20T10:00:00.000Z"

    private func makeFeedNewsItem(
        naming: ApiAgentV2NewsFeedItem.DiscussionNaming? = nil,
        threadId: String? = nil
    ) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: 307, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline", body: "News body",
            discussion: threadId.map { .init(threadId: $0) }, discussionNaming: naming
        )
    }

    private func makeFeedDigest(
        naming: ApiAgentV2NewsFeedItem.DiscussionNaming? = nil,
        threadId: String? = nil
    ) -> ApiAgentV2NewsFeedDigest {
        ApiAgentV2NewsFeedDigest(
            id: Self.deferredDigestId, deliveredAt: "2026-10-20T10:00:00Z",
            top: [.init(eventId: 307, headline: "Feed headline", imageUrl: nil)], total: 1,
            discussion: threadId.map { .init(threadId: $0) }, discussionNaming: naming
        )
    }

    @MainActor
    private func makeDeferredDiscussionModel(
        _ kind: DeferredDiscussion,
        client: AgentV2Client,
        naming: ApiAgentV2NewsFeedItem.DiscussionNaming? = nil,
        threadId: String? = nil,
        activeAccount: @escaping @MainActor () -> MAccount? = { AccountStore.account }
    ) -> AgentV2Model {
        switch kind {
        case .news:
            AgentV2Model(
                client: client, news: makeFeedNewsItem(naming: naming, threadId: threadId), locale: "en", activeAccount: activeAccount
            ) { _ in }
        case .digest:
            AgentV2Model(client: client, digest: makeFeedDigest(naming: naming, threadId: threadId), activeAccount: activeAccount) { _ in }
        }
    }

    @MainActor
    private func acquireDeferredDiscussionModel(
        _ kind: DeferredDiscussion,
        preloader: AgentPreloader,
        naming: ApiAgentV2NewsFeedItem.DiscussionNaming? = nil,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) -> AgentV2Model {
        switch kind {
        case .news: preloader.acquireNewsModel(item: makeFeedNewsItem(naming: naming), locale: "en", onThreadCreated: onThreadCreated)
        case .digest: preloader.acquireDigestModel(digest: makeFeedDigest(naming: naming), onThreadCreated: onThreadCreated)
        }
    }

    @MainActor
    private func makeDeferredDiscussionChat(_ kind: DeferredDiscussion, preloader: AgentPreloader) -> AgentVC? {
        switch kind {
        case .news:
            AgentEntryPoint.makeNewsChatViewController(
                item: makeFeedNewsItem(), locale: "en", preloader: preloader, onThreadCreated: { _ in }
            ) as? AgentVC
        case .digest:
            AgentVC(model: preloader.acquireDigestModel(digest: makeFeedDigest(), onThreadCreated: { _ in }))
        }
    }

    @MainActor
    private func deferredDiscussionModel(_ kind: DeferredDiscussion, in preloader: AgentPreloader) -> AgentV2Model? {
        switch kind {
        case .news: preloader.newsModel(eventId: 307)
        case .digest: preloader.digestModel(id: Self.deferredDigestId)
        }
    }

    @MainActor
    private func updateDeferredDiscussionPreview(
        _ kind: DeferredDiscussion,
        of model: AgentV2Model,
        naming: ApiAgentV2NewsFeedItem.DiscussionNaming?
    ) {
        switch kind {
        case .news: model.updateNewsPreview(makeFeedNewsItem(naming: naming))
        case .digest: model.updateDigestPreview(makeFeedDigest(naming: naming))
        }
    }

    @MainActor
    private func feedDiscussion(_ kind: DeferredDiscussion, in feedModel: AgentNewsFeedModel) -> ApiAgentV2NewsFeedItem.Discussion? {
        switch kind {
        case .news: feedModel.items.first?.discussion
        case .digest: feedModel.digests.first?.discussion
        }
    }

    @MainActor
    private func discussionThreadRequestCount(_ kind: DeferredDiscussion, in client: FakeAgentV2Client) -> Int {
        switch kind {
        case .news: client.newsThreadRequests.count
        case .digest: client.digestThreadRequests.count
        }
    }

    private func decodeDiscussionThread(_ kind: DeferredDiscussion, id: String, messageCount: Int) throws -> ApiAgentV2ThreadSummary {
        switch kind {
        case .news:
            return try decodeNewsThread(id: id, eventId: 307, headline: "News", messageCount: messageCount)
        case .digest:
            let thread = try decodeHydration(threadId: id, messages: []).thread
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)) as? [String: Any])
            object["messageCount"] = messageCount
            object["digest"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
                AgentV2Model.digestPreview(for: makeFeedDigest())
            ))
            return try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    private func newsFeedItem(eventId: Int) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: eventId, deliveredAt: "2026-10-20T10:00:00Z", headline: "Feed headline", body: "News body",
            discussion: .init(threadId: "existing-news-thread")
        )
    }

    @MainActor
    private func waitForDiscussionUI(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Discussion UI did not settle within 2 seconds", file: file, line: line)
        throw NSError(domain: "AgentV2ContractTests.Discussion", code: 1)
    }

    @MainActor
    private func waitForChat(in navigation: UINavigationController) async {
        for _ in 0..<300 {
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

        let viewOnly = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"inactive","reason":"viewOnlyWallet"}"#.utf8)
        )
        XCTAssertEqual(viewOnly.inactiveReason, .viewOnlyWallet)
        XCTAssertEqual(try JSONDecoder().decode(ApiAgentV2ResolvedAction.self, from: JSONEncoder().encode(viewOnly)), viewOnly)
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
            "Heading\n> Quote\n**unfinished\nSource (https://example.com/path_with_value)\nReceive"
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

    /// Headings are Telegram's: semibold from 6 pt over the body for the first level to 1 pt for the sixth, in the body's
    /// color, on lines 1.4 times their size, 6 pt further from the text above than paragraphs unless they open it
    @MainActor
    func testAgentMarkdownV1DrawsHeadingsAsTelegramDoes() throws {
        let baseFont = UIFont.systemFont(ofSize: 17)
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "# Title #\nIntro\n\n## Section with **bold** and `code`\n###### Small\n####### Seven\n#NoSpace",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            baseFont: baseFont
        )

        XCTAssertEqual(rendered.string, "Title\nIntro\n\nSection with bold and code\nSmall\n####### Seven\n#NoSpace")
        let string = rendered.string as NSString
        func attributes(of text: String) -> [NSAttributedString.Key: Any] {
            rendered.attributes(at: string.range(of: text).location, effectiveRange: nil)
        }
        let intro = attributes(of: "Intro")
        let introStyle = try XCTUnwrap(intro[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertNil(intro[.accessibilityTextHeadingLevel])
        XCTAssertEqual((intro[.font] as? UIFont)?.pointSize, 17)

        let title = attributes(of: "Title")
        XCTAssertEqual(title[.accessibilityTextHeadingLevel] as? Int, 1)
        XCTAssertEqual((title[.font] as? UIFont)?.fontName, UIFont.systemFont(ofSize: 23, weight: .semibold).fontName)
        XCTAssertEqual((title[.font] as? UIFont)?.pointSize, 23)
        XCTAssertEqual(title[.foregroundColor] as? UIColor, .label)
        let titleStyle = try XCTUnwrap(title[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(titleStyle.minimumLineHeight, ceil(23 * 1.4))
        XCTAssertEqual(titleStyle.maximumLineHeight, ceil(23 * 1.4))
        XCTAssertEqual(titleStyle.paragraphSpacingBefore, 0)
        XCTAssertEqual(titleStyle.paragraphSpacing, introStyle.paragraphSpacing)

        let section = attributes(of: "Section")
        XCTAssertEqual(section[.accessibilityTextHeadingLevel] as? Int, 2)
        XCTAssertEqual((section[.font] as? UIFont)?.pointSize, 22)
        let sectionStyle = try XCTUnwrap(section[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(sectionStyle.paragraphSpacingBefore, 6)
        XCTAssertEqual(sectionStyle.paragraphSpacing, introStyle.paragraphSpacing)
        let bold = try XCTUnwrap(attributes(of: "bold")[.font] as? UIFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(bold.pointSize, 22)
        let code = try XCTUnwrap(attributes(of: "code")[.font] as? UIFont)
        XCTAssertTrue(code.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        XCTAssertEqual(code.pointSize, 22)
        XCTAssertEqual(attributes(of: "code")[.accessibilityTextHeadingLevel] as? Int, 2)

        XCTAssertEqual(attributes(of: "Small")[.accessibilityTextHeadingLevel] as? Int, 6)
        XCTAssertEqual((attributes(of: "Small")[.font] as? UIFont)?.pointSize, 18)
        XCTAssertNil(attributes(of: "Seven")[.accessibilityTextHeadingLevel])
        XCTAssertNil(attributes(of: "NoSpace")[.accessibilityTextHeadingLevel])
    }

    /// A line still arriving with only a heading's marks waits for its text, and marks alone stay text once complete
    @MainActor
    func testAgentMarkdownV1ArrivingHeadingWaitsForItsText() {
        for partial in ["#", "##", "## ", "## **"] {
            let rendered = AgentMessageTextRenderer.makeAttributedText(
                "Intro\n\(partial)",
                textColor: .label,
                rendersMarkdown: true,
                detectsLinks: false,
                markdownProfile: .agentMarkdownV1,
                isStreaming: true
            )
            XCTAssertEqual(rendered.string, "Intro\n", partial)
        }
        let complete = AgentMessageTextRenderer.makeAttributedText(
            "Intro\n##",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )
        XCTAssertEqual(complete.string, "Intro\n##")
        XCTAssertNil(complete.attribute(.accessibilityTextHeadingLevel, at: complete.length - 1, effectiveRange: nil))
        let arriving = AgentMessageTextRenderer.makeAttributedText(
            "Intro\n## Ti",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            isStreaming: true
        )
        XCTAssertEqual(arriving.string, "Intro\nTi")
        XCTAssertEqual(arriving.attribute(.accessibilityTextHeadingLevel, at: arriving.length - 1, effectiveRange: nil) as? Int, 2)
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
    func testAgentMarkdownV1RendersUntaggedFencedCodeWithoutMarkers() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "```\nconst safe = true;\n```",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(rendered.string, "const safe = true;")
        XCTAssertNotNil(rendered.attribute(.agentCodeBlock, at: 0, effectiveRange: nil))
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

    @MainActor
    func testOrdinaryRunReconcilesItsInputOnceWhenBothStartUpdateAndResultNameIt() async throws {
        let started = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data("""
        {"kind":"runStarted","clientRunId":"client-thread-a","runId":"run-thread-a","threadId":"thread-a","threadRevision":2,"inputMessageId":"canonical-input"}
        """.utf8))
        for startsBeforeResult in [true, false] {
            let client = FakeAgentV2Client(
                hydrationResult: try decodeHydration(threadId: "thread-a", messages: []),
                shouldCompleteRun: true,
                blockedHydrationAttempt: 2
            )
            client.runInputMessageId = "canonical-input"
            let coordinator = AgentV2Coordinator(client: client)
            let observer = AgentV2CoordinatorObserverSpy()
            coordinator.addObserver(observer)
            defer {
                client.startRunObserver = nil
                coordinator.stop()
                client.resumeBlockedHydration()
            }
            await coordinator.loadDefaultThread()
            if startsBeforeResult {
                client.startRunObserver = { coordinator.walletCore(event: .agentV2(started)) }
            }

            coordinator.send(
                input: .append(text: "Question"),
                visibleText: "Question",
                localInputMessageId: "local-input"
            )
            await waitForHydrationRequest(client, count: 2)
            XCTAssertEqual(coordinator.messages.map(\.id), ["canonical-input"])
            coordinator.walletCore(event: .agentV2(started))

            XCTAssertEqual(observer.changes.filter {
                if case .messageIdReconciled = $0 { return true }
                return false
            }, [.messageIdReconciled(localId: "local-input", canonicalId: "canonical-input")])
            client.resumeBlockedHydration()
        }
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
        for _ in 0..<100 where model.canReportProblem {
            await Task.yield()
        }
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
    func testOnlyAnswersTheServerStoresAsCompleteCanBeRated() async throws {
        let hydration = try decodeHydration(threadId: "thread-a", messages: [
            [
                "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
                "content": ["kind": "markdown", "text": "What is my balance?"],
                "createdAt": "2026-07-22T00:00:01.000Z"
            ],
            [
                "id": "liked", "threadId": "thread-a", "role": "assistant", "status": "complete",
                "content": ["kind": "markdown", "text": "You hold 5 TON."], "feedback": "like",
                "createdAt": "2026-07-22T00:00:02.000Z"
            ],
            [
                "id": "unknown-rating", "threadId": "thread-a", "role": "assistant", "status": "complete",
                "content": ["kind": "markdown", "text": "You hold 6 TON."], "feedback": "love",
                "createdAt": "2026-07-22T00:00:03.000Z"
            ],
            [
                "id": "failed", "threadId": "thread-a", "role": "assistant", "status": "error",
                "error": ["code": "internal_error", "retryable": false],
                "createdAt": "2026-07-22T00:00:04.000Z"
            ]
        ])
        let persistedMessages = hydration.messages.map(AgentV2NativeMessage.init(persisted:))
        XCTAssertEqual(persistedMessages.map(\.isStoredAsComplete), [false, true, true, false])
        XCTAssertEqual(persistedMessages.map(\.feedback), [nil, .like, nil, nil])

        let coordinator = AgentV2Coordinator(client: FakeAgentV2Client())
        defer { coordinator.stop() }
        await coordinator.loadDefaultThread()
        for (messageId, finishReason) in [
            ("complete", "complete"),
            ("tool-unavailable", "tool_unavailable"),
            ("interrupted", "run_interrupted")
        ] {
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "messageStarted", threadId: "thread-a", messageId: messageId
            )))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "messageCompleted", threadId: "thread-a", messageId: messageId, finishReason: finishReason
            )))
        }
        XCTAssertEqual(coordinator.messages.map(\.isStoredAsComplete), [true, true, false])
    }

    @MainActor
    func testRatingShowsAtOnceAndAFailedSaveRestoresThePreviousRating() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeRatedConversation(answerFeedback: "like"))
        let model = AgentV2Model(client: client)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let questionID = try XCTUnwrap(presentedMessageID(in: model, role: .user))
        let answerID = try XCTUnwrap(presentedMessageID(in: model, role: .assistant))
        XCTAssertEqual(presentedMessage(answerID, in: model)?.canRate, true)
        XCTAssertEqual(presentedMessage(answerID, in: model)?.feedback, .like)

        let didRateQuestion = await model.rateMessage(messageID: questionID, feedback: .like)
        XCTAssertFalse(didRateQuestion)
        XCTAssertTrue(client.feedbackRequests.isEmpty)

        let rating = Task { await model.rateMessage(messageID: answerID, feedback: .dislike) }
        await waitForFeedbackRequest(client, count: 1)
        XCTAssertEqual(presentedMessage(answerID, in: model)?.feedback, .dislike)

        client.settleFeedbackRequest(at: 0, with: .failure(FakeAgentV2ClientError.unavailable))
        let didSave = await rating.value
        XCTAssertFalse(didSave)
        XCTAssertEqual(presentedMessage(answerID, in: model)?.feedback, .like)
        XCTAssertEqual(client.feedbackRequests.map(\.messageId), ["answer"])
    }

    @MainActor
    func testTheLatestRatingRequestSettlesTheRatingAndAFailedOneShowsTheSavedRating() async throws {
        let client = FakeAgentV2Client(hydrationResult: try decodeRatedConversation(answerFeedback: nil))
        let model = AgentV2Model(client: client)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let answerID = try XCTUnwrap(presentedMessageID(in: model, role: .assistant))

        let like = Task { await model.rateMessage(messageID: answerID, feedback: .like) }
        await waitForFeedbackRequest(client, count: 1)
        let withdrawal = Task { await model.rateMessage(messageID: answerID, feedback: nil) }
        await waitForFeedbackRequest(client, count: 2)
        XCTAssertNil(presentedMessage(answerID, in: model)?.feedback)

        client.settleFeedbackRequest(at: 0, with: .success(.like))
        let didLike = await like.value
        XCTAssertNil(presentedMessage(answerID, in: model)?.feedback)
        client.settleFeedbackRequest(at: 1, with: .failure(FakeAgentV2ClientError.unavailable))
        let didWithdraw = await withdrawal.value

        XCTAssertTrue(didLike)
        XCTAssertFalse(didWithdraw)
        XCTAssertEqual(presentedMessage(answerID, in: model)?.feedback, .like)
        XCTAssertEqual(client.feedbackRequests.map(\.feedback), [.like, nil])
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

    @MainActor
    func testReopenedChatWhoseLastRunFailedShowsOneFailureCaptionAndNoBubble() async throws {
        let history = try decodeHydration(threadId: "thread-a", messages: [
            [
                "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
                "content": ["kind": "markdown", "text": "What is my balance?"],
                "createdAt": "2026-07-22T00:00:01.000Z"
            ],
            [
                "id": "answer", "threadId": "thread-a", "role": "assistant", "status": "complete",
                "content": ["kind": "markdown", "text": "You hold 5 TON."],
                "createdAt": "2026-07-22T00:00:02.000Z"
            ],
            [
                "id": "second-question", "threadId": "thread-a", "role": "user", "status": "complete",
                "content": ["kind": "markdown", "text": "And in dollars?"],
                "createdAt": "2026-07-22T00:00:03.000Z"
            ],
            [
                "id": "failed", "threadId": "thread-a", "role": "assistant", "status": "error",
                "error": ["code": "network_error", "retryable": true],
                "createdAt": "2026-07-22T00:00:04.000Z"
            ]
        ])
        let client = FakeAgentV2Client(hydrationResult: history)
        let model = AgentV2Model(client: client, thread: history.thread)
        await model.waitForInitialLoad()
        forgetChatReadState(threadId: history.thread.id)
        let controller = AgentVC(model: model)
        let navigation = UINavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigation)
        defer {
            window.isHidden = true
            navigation.setViewControllers([], animated: false)
            model.stop()
        }

        let messages = model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { !$0.isDateTimeSystemMessage }
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(messages.map(\.isFailureCaption), [false, false, false, true])
        let failure = try XCTUnwrap(messages.last)
        XCTAssertEqual(failure.text, lang("$agent_connection_lost"))
        XCTAssertTrue(failure.controls.isEmpty)

        let collection = try XCTUnwrap(findDescendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        let failureIndexPath = IndexPath(item: try XCTUnwrap(model.itemIDs.firstIndex(of: failure.id)), section: 0)
        for _ in 0..<100 where collection.cellForItem(at: failureIndexPath) == nil {
            window.layoutIfNeeded()
            await Task.yield()
        }
        let caption = try XCTUnwrap(collection.cellForItem(at: failureIndexPath) as? AgentSystemMessageCell)
        let captionText = try XCTUnwrap(findDescendants(of: caption).first { $0.accessibilityIdentifier == "agent_message_failure" })
        XCTAssertFalse(captionText.isHidden)
        XCTAssertEqual(captionText.accessibilityLabel, lang("$agent_connection_lost"))
        let bubbles = collection.visibleCells.compactMap { $0 as? AgentMessageCell }
        XCTAssertEqual(bubbles.count, 3)
    }

    @MainActor
    func testRunFailureItsSavedAnswerAlsoCarriesShowsOneCaptionWithItsRetry() async throws {
        let question: [String: Any] = [
            "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "What is my balance?"],
            "createdAt": "2026-07-22T00:00:01.000Z"
        ]
        let initialHydration = try decodeHydration(threadId: "thread-a", messages: [])
        let failedHydration = try decodeHydration(threadId: "thread-a", messages: [question, [
            "id": "message-a", "threadId": "thread-a", "role": "assistant", "status": "error",
            "error": ["code": "rate_limited", "retryable": true],
            "createdAt": "2026-07-22T00:00:02.000Z"
        ]])
        let client = FakeAgentV2Client(
            hydrationResult: initialHydration,
            hydrationResults: [initialHydration, failedHydration],
            shouldCompleteRun: true
        )
        client.runResultState = .failed
        let model = AgentV2Model(client: client, thread: initialHydration.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let runFailed = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: JSONSerialization.data(withJSONObject: [
            "type": "agentV2",
            "update": [
                "kind": "runFailed", "clientRunId": "client-thread-a", "runId": "run-thread-a", "threadId": "thread-a",
                "messageId": "message-a", "code": "rate_limited", "retryable": true
            ]
        ])).update
        client.startRunObserver = { [weak coordinator] in
            coordinator?.walletCore(event: .agentV2(runFailed))
        }

        model.send(text: "What is my balance?")
        await waitForHydrationRequest(client, count: 2)
        for _ in 0..<100 where !coordinator.messages.contains(where: { $0.error != nil }) {
            await Task.yield()
        }

        // The failed answer and the run's failure are one failure, shown once with its retry
        XCTAssertEqual(coordinator.messages.last?.error?.code, .rateLimited)
        XCTAssertTrue(coordinator.isRunFailure)
        let answers = model.itemIDs.compactMap { presentedMessage($0, in: model) }.filter { $0.role == .assistant }
        XCTAssertEqual(answers.map(\.isFailureCaption), [true])
        XCTAssertEqual(answers.map(\.text), [AgentV2Copy.error(.rateLimited)])
        XCTAssertEqual(answers.first?.controls.map(\.id), ["retry-limit"])
    }

    @MainActor
    func testLeavingStreamingChatKeepsUnreadAnswerAcrossRestart() async throws {
        let suite = "AgentV2ContractTests.ReadState.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initialHistory = try decodeRatedConversation(answerFeedback: nil)
        var hydration = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(initialHistory)) as? [String: Any])
        var thread = try XCTUnwrap(hydration["thread"] as? [String: Any])
        thread["messageCount"] = 10
        hydration["thread"] = thread
        hydration["nextCursor"] = "older"
        let history = try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: JSONSerialization.data(withJSONObject: hydration))
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let readState = AgentThreadReadState(userDefaults: defaults)
        readState.chatDidAppear(threadId: history.thread.id)
        readState.chatDidDisappear(threadId: history.thread.id, seenMessageCount: model.seenMessageCount)
        let unchanged = AgentThreadReadState(userDefaults: defaults)
        unchanged.observe([history.thread], answeringThreadIds: [])
        XCTAssertEqual(model.seenMessageCount, 10)
        XCTAssertFalse(unchanged.isUnread(history.thread))

        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let started = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runStarted", "clientRunId": "client-thread-a", "runId": "run-thread-a",
            "threadId": history.thread.id, "threadRevision": history.thread.revision + 1
        ]))
        let delta = try decodeUpdate(kind: "textDelta", threadId: history.thread.id, messageId: "new-answer", delta: "Working")
        client.startRunObserver = { [weak coordinator] in
            coordinator?.walletCore(event: .agentV2(started))
            coordinator?.walletCore(event: .agentV2(delta))
        }
        unchanged.chatDidAppear(threadId: history.thread.id)
        model.send(text: "Another question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        XCTAssertEqual(model.seenMessageCount, 11)
        unchanged.chatDidDisappear(threadId: history.thread.id, seenMessageCount: model.seenMessageCount)

        thread["messageCount"] = 12
        let completed = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: thread))
        let restarted = AgentThreadReadState(userDefaults: defaults)
        restarted.observe([completed], answeringThreadIds: [])
        XCTAssertTrue(restarted.isUnread(completed))
    }

    @MainActor
    func testAdmittedRegenerationRestoresTheServerAnswerAfterCancellationOrFailure() async throws {
        for kind in ["runCancelled", "runFailed"] {
            let history = try decodeRatedConversation(answerFeedback: nil)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            client.blocksRunStart = true
            let model = AgentV2Model(client: client, thread: history.thread)
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
            defer {
                model.stop()
                client.resumeRunStart()
            }
            await model.waitForInitialLoad()
            let answerID = try XCTUnwrap(presentedMessageID(in: model, role: .assistant))
            let started = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
                "kind": "runStarted", "clientRunId": "client-thread-a", "runId": "run-thread-a",
                "threadId": history.thread.id, "threadRevision": history.thread.revision + 1
            ]))
            client.startRunObserver = { [weak coordinator] in coordinator?.walletCore(event: .agentV2(started)) }

            model.regenerateMessage(answerID)
            XCTAssertNil(model.message(for: answerID))
            XCTAssertEqual(model.seenMessageCount, 1)
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            XCTAssertEqual(client.startedCommands.first?.input, .regenerate(targetAssistantMessageId: "answer"))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: kind, threadId: history.thread.id, messageId: "replacement",
                code: kind == "runFailed" ? .internalError : nil
            )))
            try await waitForDiscussionUI { client.hydrationRequestCount == 2 && model.message(for: answerID) != nil }

            XCTAssertEqual(model.message(for: answerID)?.text, "You hold 5 TON.")
            XCTAssertFalse(model.hasActiveRun)
            XCTAssertFalse(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
        }
    }

    @MainActor
    func testStopTakesThePlaceOfSendWhileAnAnswerIsWrittenAndStopsItOnce() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history)
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        await model.waitForInitialLoad()
        let chat = AgentVC(model: model)
        let window = makeKeyWindow(showing: chat)
        defer {
            window.isHidden = true
            model.stop()
            client.resumeRunStart()
        }
        window.layoutIfNeeded()
        let buttons = findDescendants(of: window).compactMap { $0 as? UIButton }
        let send = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "agent_send" })
        // Stop is the microphone's circle, which turns into it while an answer is being written
        let stop = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "agent_microphone" })
        XCTAssertEqual(stop.accessibilityLabel, lang("$agent_dictation_start"))
        XCTAssertFalse(stop.isHidden)

        model.send(text: "Next question")
        XCTAssertTrue(model.hasActiveRun)
        XCTAssertFalse(stop.isHidden)
        XCTAssertEqual(stop.accessibilityLabel, lang("$agent_stop_answer"))
        XCTAssertEqual(stop.accessibilityIdentifier, "agent_stop")
        XCTAssertTrue(send.isHidden)
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let started = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runStarted", "clientRunId": "client-thread-a", "runId": "run-thread-a",
            "threadId": "thread-a", "threadRevision": history.thread.revision + 1
        ]))
        coordinator.walletCore(event: .agentV2(started))
        coordinator.walletCore(event: .agentV2(try decodeUpdate(kind: "messageStarted", threadId: "thread-a", messageId: "partial")))
        coordinator.walletCore(event: .agentV2(try decodeUpdate(
            kind: "textDelta", threadId: "thread-a", messageId: "partial", delta: "You hold"
        )))
        coordinator.walletCore(event: .agentV2(try decodeFollowupsUpdate(threadId: "thread-a", messageId: "partial")))
        coordinator.walletCore(event: .agentV2(try decodeUpdate(kind: "messageContentEnded", threadId: "thread-a", messageId: "partial")))
        XCTAssertEqual(stop.accessibilityLabel, lang("$agent_stop_answer"))

        tap(stop)
        XCTAssertFalse(model.hasActiveRun)
        XCTAssertTrue(model.canSendMessage(draftText: "Another question"))
        XCTAssertFalse(stop.isHidden)
        XCTAssertEqual(stop.accessibilityLabel, lang("$agent_dictation_start"))
        // The microphone again, which a tap doesn't stop with
        tap(stop)
        try await waitForDiscussionUI { !client.stoppedThreadIds.isEmpty }
        // A second stop would follow the first one's call
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(client.stoppedThreadIds, ["thread-a"])

        let answerID = try XCTUnwrap(model.itemIDs.last { presentedMessage($0, in: model)?.role == .assistant })
        let answer = try XCTUnwrap(presentedMessage(answerID, in: model))
        XCTAssertEqual(answer.text, "You hold")
        XCTAssertFalse(answer.isStreaming)
        XCTAssertFalse(answer.canRate)
        XCTAssertFalse(answer.controls.contains { $0.kind == .followup })
    }

    /// Questions sent while an answer is written, as Android queues them: each shows at once as the user's bubble at
    /// the chat's end, below the answer's typing row, and they go once each, after the answer ends, first in, first
    /// out, one run at a time. An edit doesn't wait, and a question that waits has nothing stored to edit.
    @MainActor
    func testQuestionsSentDuringAnAnswerWaitAtTheEndAndGoOnceInOrder() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let userTexts = {
            model.itemIDs.compactMap { self.presentedMessage($0, in: model) }.filter { $0.role == .user }.map(\.text)
        }
        let getIndex = { (text: String) in
            model.itemIDs.firstIndex { self.presentedMessage($0, in: model)?.text == text }
        }
        let getTypingIndex = {
            model.itemIDs.firstIndex { if case .typingIndicator? = model.item(for: $0) { return true }; return false }
        }
        let storedQuestionID = try XCTUnwrap(model.itemIDs.first { presentedMessage($0, in: model)?.text == "What is my balance?" })
        XCTAssertTrue(model.canEditMessage(storedQuestionID))

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        XCTAssertFalse(model.canEditMessage(storedQuestionID), "An answer is running, with nothing queued yet")
        XCTAssertTrue(model.canStopAnswer)
        XCTAssertTrue(model.canSendMessage(draftText: "Second question"), "A question can be sent during the answer")
        XCTAssertFalse(model.canSendMessage(draftText: "Edited question", isEditing: true), "An edit doesn't wait")
        model.send(text: "Second question")
        model.send(text: "Third question")
        XCTAssertEqual(Array(userTexts().suffix(3)), ["First question", "Second question", "Third question"], "At once")
        XCTAssertEqual(model.itemIDs.last.flatMap { presentedMessage($0, in: model) }?.text, "Third question", "At the chat's end")
        XCTAssertLessThan(try XCTUnwrap(getTypingIndex()), try XCTUnwrap(getIndex("Second question")), "Below the typing row")
        let waitingID = try XCTUnwrap(model.itemIDs.first { presentedMessage($0, in: model)?.text == "Second question" })
        XCTAssertFalse(model.canEditMessage(waitingID))
        XCTAssertFalse(model.canEditMessage(storedQuestionID), "Questions wait behind the answer")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.count, 1, "They wait for the answer")

        client.resumeRunStart()
        client.blocksRunStart = true
        try await waitForDiscussionUI { client.startedCommands.count == 2 }
        // The second question's typing row comes under it, above the third, which still waits last
        XCTAssertEqual(model.itemIDs.last.flatMap { presentedMessage($0, in: model) }?.text, "Third question")
        let typingIndex = try XCTUnwrap(getTypingIndex())
        XCTAssertLessThan(try XCTUnwrap(getIndex("Second question")), typingIndex)
        XCTAssertLessThan(typingIndex, try XCTUnwrap(getIndex("Third question")))
        client.resumeRunStart()
        client.blocksRunStart = true
        try await waitForDiscussionUI { client.startedCommands.count == 3 }
        client.resumeRunStart()
        try await waitForDiscussionUI { !model.hasActiveRun }
        XCTAssertTrue(model.canEditMessage(storedQuestionID), "The chat is free again")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(
            client.startedCommands.map(\.input),
            [.append(text: "First question"), .append(text: "Second question"), .append(text: "Third question")],
            "Once each, in order"
        )
    }

    /// A stop while a question waits sends it at once, once. Stop stays, and a repeated tap, which is for the answer it
    /// stopped, doesn't stop that question's run until the run has its id.
    @MainActor
    func testStopSendsTheWaitingQuestionAtOnceAndOnlyOnce() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.clientRunIds = ["first-run", "second-run"]
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.send(text: "Second question")
        model.stopAnswer()
        XCTAssertTrue(model.hasActiveRun, "The waiting question went at once")
        XCTAssertEqual(coordinator.activeRun?.clientRunId, "second-run")
        XCTAssertTrue(model.canStopAnswer, "Stop stays")
        model.stopAnswer()
        XCTAssertTrue(model.hasActiveRun, "A repeated tap doesn't stop it before its run has its id")
        // The stopped run's start comes back, and the waiting question's run starts
        client.resumeRunStart()
        client.blocksRunStart = true
        try await waitForDiscussionUI { client.startedCommands.count == 2 && !client.stoppedThreadIds.isEmpty }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.map(\.input), [.append(text: "First question"), .append(text: "Second question")])
        XCTAssertEqual(client.stoppedThreadIds, ["thread-a"], "Stopped once")

        coordinator.walletCore(event: .agentV2(try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runStarted", "clientRunId": "second-run", "runId": "run-second",
            "threadId": "thread-a", "threadRevision": history.thread.revision + 1
        ]))))
        XCTAssertEqual(coordinator.activeRun?.runId, "run-second")
        model.stopAnswer()
        XCTAssertFalse(model.hasActiveRun, "Once the run has its id, Stop stops it")
        try await waitForDiscussionUI { client.stoppedThreadIds.count == 2 }
    }

    /// A question that waits stays one row of the chat as it goes and gets its answer, after an answer that ends or one
    /// that is stopped: through the run that sends it, the server naming its message and the thread read after its
    /// answer, the row never leaves the chat or comes back under another id, which would show its bubble anew
    @MainActor
    func testAWaitingQuestionStaysOneRowAsItGoesAndGetsItsAnswer() async throws {
        let question = newsPostMessage(id: "question", text: "What is my balance?", threadId: "thread-a")
        let answer = newsPostMessage(id: "answer", text: "You hold 5 TON.", role: "assistant", threadId: "thread-a")
        let firstQuestion = newsPostMessage(id: "first-question", text: "First question", threadId: "thread-a")
        let firstAnswer = newsPostMessage(id: "first-answer", text: "First answer", role: "assistant", threadId: "thread-a")
        let secondQuestion = newsPostMessage(id: "second-question", text: "Second question", threadId: "thread-a")
        let secondAnswer = newsPostMessage(id: "second-answer", text: "Second answer", role: "assistant", threadId: "thread-a")
        for isAnswerStopped in [false, true] {
            let firstRun = [question, answer, firstQuestion] + (isAnswerStopped ? [] : [firstAnswer])
            let firstHistory = try decodeHydration(threadId: "thread-a", messages: firstRun)
            let secondHistory = try decodeHydration(threadId: "thread-a", messages: firstRun + [secondQuestion, secondAnswer])
            let history = try decodeRatedConversation(answerFeedback: nil)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            client.clientRunIds = ["first-run", "second-run"]
            client.blocksRunStart = true
            // Each run's question gets its stored id, and the thread read after the run has the run's answer
            client.startRunObserver = { [weak client] in
                guard let client else { return }
                let isFirstRun = client.startedCommands.count == 1
                client.runInputMessageId = isFirstRun ? "first-question" : "second-question"
                client.setHydrationResult(isFirstRun ? firstHistory : secondHistory)
            }
            let model = AgentV2Model(client: client, thread: history.thread)
            let rows = AgentRowPresenceRecorder(model: model)
            defer {
                model.stop()
                client.resumeRunStart()
            }
            await model.waitForInitialLoad()

            model.send(text: "First question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            model.send(text: "Second question")
            let waitingID = try XCTUnwrap(model.itemIDs.last)
            XCTAssertEqual(presentedMessage(waitingID, in: model)?.text, "Second question")
            XCTAssertEqual(model.trailingItemIDs, [waitingID], "It waits")
            rows.watchedID = waitingID

            if isAnswerStopped {
                model.stopAnswer()
            }
            client.resumeRunStart()
            client.blocksRunStart = true
            try await waitForDiscussionUI { client.startedCommands.count == 2 }
            XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
            XCTAssertTrue(model.trailingItemIDs.isEmpty, "It went")
            client.resumeRunStart()
            try await waitForDiscussionUI {
                !model.hasActiveRun && model.itemIDs.contains { presentedMessage($0, in: model)?.text == "Second answer" }
            }

            let label = isAnswerStopped ? "After a stopped answer" : "After an answer"
            XCTAssertGreaterThan(rows.changeCount, 0)
            XCTAssertEqual(rows.missingCount, 0, "\(label): the row never left the chat")
            let shownRows = model.itemIDs.filter { presentedMessage($0, in: model)?.role != .system }
            let index = try XCTUnwrap(shownRows.firstIndex(of: waitingID), "\(label): the same row")
            XCTAssertEqual(presentedMessage(waitingID, in: model)?.text, "Second question")
            XCTAssertEqual(
                shownRows.dropFirst(index + 1).first.flatMap { presentedMessage($0, in: model) }?.text,
                "Second answer",
                "\(label): its answer follows it"
            )
        }
    }

    @MainActor
    func testDeletingTheChatPreventsARunWaitingForHostContextFromStarting() async throws {
        let thread = try decodeNewsThread(id: "news-thread", eventId: 307, headline: "News", messageCount: 0)
        let history = try decodeHydration(threadId: thread.id, messages: [], thread: thread)
        for shouldFailDeletion in [false, true] {
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHostContextAttempt: 1)
            if shouldFailDeletion { client.threadDeletionError = FakeAgentV2ClientError.unavailable }
            let model = AgentV2Model(client: client, thread: thread)
            model.retainPresentation()
            defer {
                model.stop()
                client.resumeBlockedHostContextUpdate()
                client.beforeThreadDeletion = nil
            }
            try await waitForHostContextUpdate(client)
            try await waitForDiscussionUI { model.canSendMessage(draftText: "Question") }

            model.send(text: "Question")
            XCTAssertTrue(model.hasActiveRun)
            for _ in 0..<20 { await Task.yield() }
            client.beforeThreadDeletion = { @MainActor [weak client] in
                client?.resumeBlockedHostContextUpdate()
                await model.waitForInitialLoad()
                for _ in 0..<20 { await Task.yield() }
                XCTAssertEqual(client?.startedCommands.count, 0, "A run waiting for its context doesn't start during deletion")
            }
            XCTAssertTrue(model.beginChatDeletion())
            do {
                try await model.deleteChat()
                XCTAssertFalse(shouldFailDeletion)
            } catch {
                XCTAssertTrue(shouldFailDeletion)
            }

            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(client.deletedThreadIds, [thread.id])
            XCTAssertTrue(client.startedCommands.isEmpty)
            XCTAssertFalse(model.hasActiveRun)
            if shouldFailDeletion {
                XCTAssertTrue(model.canSendMessage(draftText: "Next question"))
            }
        }
    }

    @MainActor
    func testQueuedQuestionsWaitUntilEveryHoldIsReleased() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.send(text: "Second question")
        model.holdQueuedQuestions()
        model.holdQueuedQuestions()
        model.releaseQueuedQuestions()
        client.resumeRunStart()
        try await waitForDiscussionUI { !model.hasActiveRun }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.count, 1, "Releasing one hold leaves the other in place")
        XCTAssertTrue(model.hasQueuedQuestions)

        model.releaseQueuedQuestions()
        try await waitForDiscussionUI { client.startedCommands.count == 2 }
        XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
    }

    /// Deleting the chat holds its waiting questions until success; a failed deletion lets them go on
    @MainActor
    func testDeletingTheChatDropsItsWaitingQuestions() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        for shouldFailDeletion in [false, true] {
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            client.blocksRunStart = true
            if shouldFailDeletion { client.threadDeletionError = FakeAgentV2ClientError.unavailable }
            let model = AgentV2Model(client: client, thread: history.thread)
            let preloader = AgentPreloader(client: client)
            preloader.keepRecent(model)
            model.retainPresentation()
            defer {
                preloader.setWalletReady(false)
                model.stop()
                client.resumeRunStart()
                client.beforeThreadDeletion = nil
            }
            await model.waitForInitialLoad()

            model.send(text: "First question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            model.send(text: "Second question")
            client.beforeThreadDeletion = { @MainActor [weak client] in
                client?.resumeRunStart()
                try? await self.waitForDiscussionUI { !model.hasActiveRun }
                for _ in 0..<20 { await Task.yield() }
                XCTAssertEqual(client?.startedCommands.count, 1, "The waiting question stays held during deletion")
                XCTAssertTrue(model.hasQueuedQuestions)
            }
            XCTAssertTrue(model.beginChatDeletion())
            // The chat closes before the deletion request finishes
            model.releasePresentation()
            do {
                try await model.deleteChat()
                XCTAssertFalse(shouldFailDeletion)
            } catch {
                XCTAssertTrue(shouldFailDeletion)
            }
            if shouldFailDeletion {
                try await waitForDiscussionUI { client.startedCommands.count == 2 }
                XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
            } else {
                for _ in 0..<20 { await Task.yield() }
                XCTAssertEqual(client.startedCommands.count, 1, "The waiting question doesn't go")
                XCTAssertFalse(model.hasQueuedQuestions)
            }
        }
    }

    /// Deleting a chat from the list holds its waiting questions until the server deletes it, then drops them
    @MainActor
    func testDeletingAChatLeftAnsweringFromTheListDropsItsWaitingQuestions() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let model = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        preloader.keepRecent(model)
        defer {
            model.stop()
            client.resumeRunStart()
            client.beforeThreadDeletion = nil
        }
        await model.waitForInitialLoad()

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.send(text: "Second question")
        var startedCountDuringDeletion: Int?
        var shownTextsDuringDeletion: [String] = []
        client.beforeThreadDeletion = { @MainActor [weak client] in
            // The answer ends while the server deletes the thread
            client?.resumeRunStart()
            try? await self.waitForDiscussionUI { !model.hasActiveRun }
            for _ in 0..<20 { await Task.yield() }
            startedCountDuringDeletion = client?.startedCommands.count
            shownTextsDuringDeletion = model.itemIDs.compactMap { model.message(for: $0)?.text }
        }
        await AgentThreadListModel(client: client, preloader: preloader).delete(history.thread)

        XCTAssertEqual(client.deletedThreadIds, [history.thread.id])
        XCTAssertEqual(startedCountDuringDeletion, 1, "The waiting question doesn't go")
        XCTAssertTrue(shownTextsDuringDeletion.contains("Second question"))
        XCTAssertFalse(model.hasQueuedQuestions)
        XCTAssertFalse(model.itemIDs.contains { model.message(for: $0)?.text == "Second question" })
    }

    /// A chat left while it answers, which stays loaded as a recent chat, keeps its queue: the question that waits goes
    /// once the answer ends
    @MainActor
    func testLeavingTheChatKeepsItsQueueRunning() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let otherHistories = try (1...8).map { index in
            try decodeHydration(threadId: "other-\(index)", messages: [])
        }
        let client = FakeAgentV2Client(hydrationResults: [history] + otherHistories + [history], shouldCompleteRun: true)
        client.blocksRunStart = true
        let preloader = AgentPreloader(client: client)
        let model = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
        preloader.keepRecent(model)
        // The chat on screen holds its model, as `AgentVC` does
        model.retainPresentation()
        defer {
            preloader.setWalletReady(false)
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.send(text: "Second question")
        // The chat leaves the screen
        model.releasePresentation()
        for history in otherHistories {
            let otherModel = try XCTUnwrap(preloader.acquireModel(thread: history.thread))
            await otherModel.waitForInitialLoad()
            preloader.keepRecent(otherModel)
        }
        XCTAssertTrue(preloader.model(threadId: history.thread.id) === model, "Queued questions outlive the recent chat limit")
        XCTAssertNotNil(preloader.model(threadId: otherHistories[0].thread.id), "The eight recent chats stay loaded too")

        client.resumeRunStart()
        client.blocksRunStart = true
        try await waitForDiscussionUI { client.startedCommands.count == 2 }
        XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
        let latestModel = try XCTUnwrap(preloader.model(threadId: try XCTUnwrap(otherHistories.last).thread.id))
        preloader.keepRecent(latestModel)
        XCTAssertTrue(preloader.model(threadId: history.thread.id) === model, "The last queued answer is still running")

        client.resumeRunStart()
        try await waitForDiscussionUI { !model.hasActiveRun }
        preloader.keepRecent(latestModel)
        XCTAssertNil(preloader.model(threadId: history.thread.id), "The idle chat is released at the next trim")
        XCTAssertFalse(model.isReadyForPresentation)
    }

    /// Clearing the chat cancels the answer being written and drops the questions that wait for it
    @MainActor
    func testClearingTheChatCancelsTheAnswerAndDropsItsWaitingQuestions() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.send(text: "Second question")
        XCTAssertTrue(model.canClearChat, "An answer being written doesn't keep the chat from clearing")
        model.clearChat(animated: false)
        XCTAssertFalse(model.hasActiveRun, "The answer is cancelled")
        client.resumeRunStart()
        try await waitForDiscussionUI {
            client.requestOrder.contains("clearThread") && model.canSendMessage(draftText: "Next question")
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.startedCommands.count, 1, "The waiting question doesn't go")
        XCTAssertEqual(client.stoppedThreadIds, ["thread-a"])
        XCTAssertFalse(model.itemIDs.contains { presentedMessage($0, in: model)?.role == .user })
    }

    /// A limit holds the questions that wait, and takes no more. Once it resets, the question it held back goes first,
    /// by itself, as the same run its Retry sends, and the questions behind it follow.
    @MainActor
    func testALimitHoldsTheQueueAndTheQuestionItHeldBackGoesFirstOnceItResets() async throws {
        let history = try decodeHydration(threadId: "thread-a", messages: [
            newsPostMessage(id: "question", text: "What is my balance?", threadId: "thread-a")
        ], nextCursor: "older")
        let olderHistory = try decodeHydration(threadId: "thread-a", messages: [
            newsPostMessage(id: "older-question", text: "Earlier question", threadId: "thread-a")
        ], thread: history.thread)
        let client = FakeAgentV2Client(
            hydrationResults: [history, history, olderHistory, history], shouldCompleteRun: true,
            retryResultState: .completed, blockedHydrationAttempt: 3
        )
        client.clientRunIds = ["first-run", "second-run"]
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
            client.resumeBlockedHydration()
            client.startRunObserver = nil
        }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let storedQuestionID = try XCTUnwrap(presentedMessageID(in: model, role: .user))

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.send(text: "Second question")
        let resetAt = Date().addingTimeInterval(1.5).timeIntervalSince1970 * 1_000
        coordinator.walletCore(event: .agentV2(try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runFailed", "clientRunId": "first-run", "threadId": "thread-a",
            "code": "rate_limited", "retryable": true, "resetAt": resetAt
        ]))))
        var retriedBeforeQueuedStart: [String]?
        client.startRunObserver = { [weak client] in
            retriedBeforeQueuedStart = client?.retriedClientRunIds
        }
        client.runResultState = .failed
        client.resumeRunStart()
        try await waitForDiscussionUI { !model.hasActiveRun && client.hydrationRequestCount == 2 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(model.isInputBlockedByLimit)
        XCTAssertEqual(client.startedCommands.count, 1, "The waiting question doesn't meet the limit")
        XCTAssertTrue(client.retriedClientRunIds.isEmpty)
        XCTAssertFalse(model.canSendMessage(draftText: "Third question"), "Nothing waits while the limit holds")
        XCTAssertEqual(model.itemIDs.last.flatMap { presentedMessage($0, in: model) }?.text, "Second question")
        XCTAssertFalse(model.hasActiveRun)
        XCTAssertFalse(model.canEditMessage(storedQuestionID), "Questions wait while no answer runs")

        let observer = AgentV2CoordinatorObserverSpy()
        coordinator.addObserver(observer)
        let historyLoad = Task { await model.loadOlderMessages() }
        try await waitForDiscussionUI { client.hydrationRequestCount == 3 }
        try await waitForDiscussionUI { !model.isInputBlockedByLimit && !observer.changes.isEmpty }
        XCTAssertTrue(client.retriedClientRunIds.isEmpty, "The reset arrived while older history still loads")
        XCTAssertEqual(client.startedCommands.count, 1)
        client.resumeBlockedHydration()
        let didLoad = await historyLoad.value
        XCTAssertTrue(didLoad)

        try await waitForDiscussionUI { client.startedCommands.count == 2 }
        XCTAssertEqual(retriedBeforeQueuedStart, ["first-run"], "The held question went first, as the same run")
        XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
    }

    /// A wallet switch fails the questions that wait, as failed sends that stay last with one failure after them, which
    /// a history load keeps. They don't go once the answer ends; Retry asks them again for the new wallet.
    @MainActor
    func testAWalletSwitchFailsTheWaitingQuestionsAndRetryAsksThemForTheNewWallet() async throws {
        // The host context reads the active account and its saved addresses from their stores
        try await withDependencies {
            $0.accountStore = .makePreview(
                accounts: ["wallet-a", "wallet-b"].map { Self.makeWalletAccount(id: $0) },
                selectedAccountId: "wallet-a"
            )
            $0[SavedAddressesStore.self] = .liveValue
        } operation: {
            let history = try decodeRatedConversation(answerFeedback: nil)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            client.blocksRunStart = true
            var accountID: String? = "wallet-a"
            let model = AgentV2Model(client: client, thread: history.thread, activeAccount: { accountID.map { Self.makeWalletAccount(id: $0) } })
            defer {
                model.stop()
                client.resumeRunStart()
            }
            await model.waitForInitialLoad()
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
            let getLastMessages = { (count: Int) in
                Array(model.itemIDs.compactMap { self.presentedMessage($0, in: model) }.suffix(count))
            }

            model.send(text: "First question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            model.send(text: "Second question")
            accountID = "wallet-b"
            coordinator.walletCore(event: .agentV2(try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
                "kind": "walletAuthorityChanged", "preservesActiveRuns": true
            ]))))
            let failed = getLastMessages(2)
            XCTAssertEqual(failed.first?.text, "Second question")
            XCTAssertEqual(failed.last?.isFailureCaption, true)
            XCTAssertEqual(failed.last?.text, lang("$agent_error_generic"))
            XCTAssertEqual(failed.last?.controls.map(\.id), ["retry-failed-questions"])
            XCTAssertTrue(model.hasActiveRun, "The answer goes on")

            client.resumeRunStart()
            try await waitForDiscussionUI { !model.hasActiveRun && client.hydrationRequestCount == 2 }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(client.startedCommands.count, 1, "The failed question doesn't go for the new wallet")
            XCTAssertEqual(getLastMessages(2).map(\.text), ["Second question", lang("$agent_error_generic")], "A load keeps them")

            let failureID = try XCTUnwrap(getLastMessages(1).first?.id)
            model.performControl(messageID: failureID, controlID: "retry-failed-questions")
            try await waitForDiscussionUI { client.startedCommands.count == 2 }
            XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
            XCTAssertNil(model.message(for: failureID))
        }
    }

    /// A later switch adds the questions that wait then to the same failure, and its Retry, also while an answer is
    /// written, makes them all wait again in order, for the current wallet, behind the answer
    @MainActor
    func testALaterSwitchJoinsTheFailureWhoseRetryQueuesItsQuestionsWhileAnAnswerRuns() async throws {
        // The host context reads the active account and its saved addresses from their stores
        try await withDependencies {
            $0.accountStore = .makePreview(
                accounts: ["wallet-a", "wallet-b"].map { Self.makeWalletAccount(id: $0) },
                selectedAccountId: "wallet-a"
            )
            $0[SavedAddressesStore.self] = .liveValue
        } operation: {
            let history = try decodeRatedConversation(answerFeedback: nil)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
            client.blocksRunStart = true
            var accountID: String? = "wallet-a"
            let model = AgentV2Model(client: client, thread: history.thread, activeAccount: { accountID.map { Self.makeWalletAccount(id: $0) } })
            defer {
                model.stop()
                client.resumeRunStart()
            }
            await model.waitForInitialLoad()
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
            let getLastTexts = { (count: Int) in
                Array(model.itemIDs.compactMap { self.presentedMessage($0, in: model)?.text }.suffix(count))
            }
            let switchWallet = { (id: String) in
                accountID = id
                coordinator.walletCore(event: .agentV2(try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
                    "kind": "walletAuthorityChanged", "preservesActiveRuns": true
                ]))))
            }
            let failure = lang("$agent_error_generic")

            model.send(text: "First question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            model.send(text: "Second question")
            try switchWallet("wallet-b")
            model.send(text: "Third question")
            XCTAssertEqual(getLastTexts(3), ["Second question", failure, "Third question"], "The failed ones, their failure, the queue")
            try switchWallet("wallet-a")
            XCTAssertEqual(getLastTexts(3), ["Second question", "Third question", failure], "One failure after them all")
            XCTAssertEqual(model.itemIDs.filter { presentedMessage($0, in: model)?.text == failure }.count, 1)

            let failureID = try XCTUnwrap(model.itemIDs.last)
            model.performControl(messageID: failureID, controlID: "retry-failed-questions")
            XCTAssertEqual(getLastTexts(2), ["Second question", "Third question"], "They wait again, behind the answer")
            XCTAssertTrue(model.hasActiveRun)

            client.resumeRunStart()
            client.blocksRunStart = true
            try await waitForDiscussionUI { client.startedCommands.count == 2 }
            client.resumeRunStart()
            client.blocksRunStart = true
            try await waitForDiscussionUI { client.startedCommands.count == 3 }
            XCTAssertEqual(
                client.startedCommands.map(\.input),
                [.append(text: "First question"), .append(text: "Second question"), .append(text: "Third question")]
            )
        }
    }

    /// The wallet's authority published again for the same wallet, as after its chains change, fails nothing: the
    /// question that waits goes once the authority is published
    @MainActor
    func testTheSameWalletsAuthorityPublishedAgainKeepsTheQuestionWaitingUntilItIsPublished() async throws {
        // The host context reads the active account and its saved addresses from their stores
        try await withDependencies {
            $0.accountStore = .makePreview(
                accounts: ["wallet-a", "wallet-b"].map { Self.makeWalletAccount(id: $0) },
                selectedAccountId: "wallet-a"
            )
            $0[SavedAddressesStore.self] = .liveValue
        } operation: {
            let history = try decodeRatedConversation(answerFeedback: nil)
            let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true, blockedHostContextAttempt: 2)
            client.blocksRunStart = true
            let model = AgentV2Model(client: client, thread: history.thread, activeAccount: { Self.makeWalletAccount(id: "wallet-a") })
            defer {
                model.stop()
                client.resumeRunStart()
                client.resumeBlockedHostContextUpdate()
            }
            await model.waitForInitialLoad()
            XCTAssertEqual(client.hostContextUpdateCount, 1)
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
            let provider = try XCTUnwrap(
                Mirror(reflecting: coordinator).children.first { $0.label == "hostContextProvider" }?.value as? AgentV2HostContextProvider
            )

            model.send(text: "First question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            model.send(text: "Second question")
            provider.walletCore(event: .accountChanged(accountId: "wallet-a", isNew: false))
            try await waitForDiscussionUI { client.hostContextUpdateCount == 2 }
            client.resumeRunStart()
            try await waitForDiscussionUI { !model.hasActiveRun }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(client.startedCommands.count, 1, "It waits for the authority")
            XCTAssertEqual(model.itemIDs.last.flatMap { presentedMessage($0, in: model) }?.text, "Second question")
            XCTAssertFalse(model.itemIDs.contains { presentedMessage($0, in: model)?.text == lang("$agent_error_generic") })

            client.resumeBlockedHostContextUpdate()
            try await waitForDiscussionUI { client.startedCommands.count == 2 }
            XCTAssertEqual(client.startedCommands.last?.input, .append(text: "Second question"))
        }
    }

    /// Tells the chats' host contexts that the user chose another wallet, inside the test's dependencies
    @MainActor
    private func notifyAccountChanged(to accountId: String, in models: [AgentV2Model]) throws {
        for model in models {
            let coordinator = try XCTUnwrap(
                Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator
            )
            let provider = try XCTUnwrap(
                Mirror(reflecting: coordinator).children.first { $0.label == "hostContextProvider" }?.value as? AgentV2HostContextProvider
            )
            provider.walletCore(event: .accountChanged(accountId: accountId, isNew: false))
        }
    }

    private static func makeWalletAccount(id: String) -> MAccount {
        MAccount(id: id, title: "Wallet", type: .mnemonic, byChain: [.ton: .init(address: "ton")])
    }

    @MainActor
    func testRunSentRightAfterAStopIgnoresTheStoppedRunsLateUpdates() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history, shouldCompleteRun: true)
        client.clientRunIds = ["first-run", "second-run"]
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        // The fake's run result names `run-thread-a` as the server's run
        let serverRunIds = ["first-run": "run-old", "second-run": "run-thread-a"]
        func deliver(_ kind: String, run: String, _ fields: [String: Any] = [:]) throws {
            let update = fields.merging([
                "kind": kind, "clientRunId": run, "runId": serverRunIds[run]!, "threadId": "thread-a"
            ]) { $1 }
            coordinator.walletCore(event: .agentV2(try JSONDecoder().decode(
                ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: update)
            )))
        }

        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.stopAnswer()
        client.resumeRunStart()
        client.blocksRunStart = true
        model.send(text: "Second question")
        try await waitForDiscussionUI { client.startedCommands.count == 2 }
        XCTAssertEqual(client.startedCommands.map(\.clientRunId), ["first-run", "second-run"])

        try deliver("runStarted", run: "first-run", ["threadRevision": 3])
        try deliver("messageStarted", run: "first-run", ["messageId": "late-answer", "contentKind": "markdown"])
        try deliver("textDelta", run: "first-run", ["messageId": "late-answer", "delta": "Old"])
        try deliver("runCancelled", run: "first-run")
        XCTAssertTrue(model.hasActiveRun)
        XCTAssertEqual(coordinator.activeRun?.clientRunId, "second-run")
        XCTAssertNil(coordinator.activeRun?.runId)

        try deliver("runStarted", run: "second-run", ["threadRevision": 3])
        try deliver("messageStarted", run: "second-run", ["messageId": "new-answer", "contentKind": "markdown"])
        try deliver("textDelta", run: "second-run", ["messageId": "new-answer", "delta": "New answer"])
        try deliver("messageCompleted", run: "second-run", ["messageId": "new-answer", "finishReason": "complete"])
        XCTAssertFalse(coordinator.messages.contains { $0.id == "late-answer" })
        XCTAssertEqual(coordinator.messages.last?.text, "New answer")
        XCTAssertEqual(coordinator.messages.last?.status, .complete)

        client.resumeRunStart()
        try await waitForDiscussionUI { !model.hasActiveRun }
        XCTAssertEqual(client.stoppedThreadIds, ["thread-a"])
        XCTAssertEqual(coordinator.activeRun?.runId, "run-thread-a")
    }

    @MainActor
    func testStoppedAnswerShowsOnlyWithContentLiveAndAfterTheSavedThreadReloads() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let stoppedHistory = try decodeHydration(threadId: "thread-a", messages: [
            ["id": "empty-question", "threadId": "thread-a", "role": "user", "status": "complete",
             "content": ["kind": "markdown", "text": "First"], "createdAt": "2026-07-22T00:00:01.000Z"],
            ["id": "empty-answer", "threadId": "thread-a", "role": "assistant", "status": "cancelled",
             "content": ["kind": "markdown", "text": ""], "createdAt": "2026-07-22T00:00:02.000Z"],
            ["id": "partial-question", "threadId": "thread-a", "role": "user", "status": "complete",
             "content": ["kind": "markdown", "text": "Second"], "createdAt": "2026-07-22T00:00:03.000Z"],
            ["id": "partial-answer", "threadId": "thread-a", "role": "assistant", "status": "cancelled",
             "content": ["kind": "markdown", "text": "Saved part"], "createdAt": "2026-07-22T00:00:04.000Z",
             "followups": [["id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "More?"]]],
        ], thread: try makeThread(history.thread, revision: history.thread.revision + 1))
        let client = FakeAgentV2Client(hydrationResults: [history, stoppedHistory])
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let assistantTexts = {
            model.itemIDs.compactMap { self.presentedMessage($0, in: model) }.filter { $0.role == .assistant }.map(\.text)
        }

        model.send(text: "Next question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        coordinator.walletCore(event: .agentV2(try decodeUpdate(kind: "messageStarted", threadId: "thread-a", messageId: "empty")))
        model.stopAnswer()
        XCTAssertEqual(coordinator.messages.first { $0.id == "empty" }?.status, .cancelled)
        XCTAssertEqual(assistantTexts(), ["You hold 5 TON."])

        // A thread no newer than at the stop comes before the server cancels the run
        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: "thread-a", thread: history.thread)))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(client.hydrationRequestCount, 1)
        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: "thread-a", thread: stoppedHistory.thread)))
        try await waitForDiscussionUI { client.hydrationRequestCount == 2 && assistantTexts() == ["Saved part"] }
        let answer = try XCTUnwrap(model.itemIDs.compactMap { presentedMessage($0, in: model) }.last)
        XCTAssertEqual(answer.text, "Saved part")
        XCTAssertFalse(answer.canRate)
        XCTAssertTrue(answer.controls.isEmpty)
    }

    /// A stopped answer the server saved with less text than it showed, here none, keeps its shown text after the
    /// reload, without suggestions or a rating
    @MainActor
    func testStoppedAnswerKeepsItsShownTextWhenTheReloadBringsLess() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let stoppedThread = try makeThread(history.thread, revision: history.thread.revision + 1)
        let stoppedHistory = try decodeHydration(threadId: "thread-a", messages: [
            ["id": "next-question", "threadId": "thread-a", "role": "user", "status": "complete",
             "content": ["kind": "markdown", "text": "Next question"], "createdAt": "2026-07-22T00:00:01.000Z"],
            ["id": "partial", "threadId": "thread-a", "role": "assistant", "status": "cancelled",
             "content": ["kind": "markdown", "text": ""], "createdAt": "2026-07-22T00:00:02.000Z"],
        ], thread: stoppedThread)
        let client = FakeAgentV2Client(hydrationResults: [history, stoppedHistory])
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        let lastAnswer = {
            model.itemIDs.compactMap { self.presentedMessage($0, in: model) }.last { $0.role == .assistant }
        }

        model.send(text: "Next question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        coordinator.walletCore(event: .agentV2(try decodeUpdate(kind: "messageStarted", threadId: "thread-a", messageId: "partial")))
        coordinator.walletCore(event: .agentV2(try decodeUpdate(
            kind: "textDelta", threadId: "thread-a", messageId: "partial", delta: "You hold"
        )))
        model.stopAnswer()
        XCTAssertEqual(lastAnswer()?.text, "You hold", "Live, the answer keeps what it showed")

        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: "thread-a", thread: stoppedThread)))
        try await waitForDiscussionUI { client.hydrationRequestCount == 2 }
        for _ in 0..<20 { await Task.yield() }
        let answer = try XCTUnwrap(lastAnswer(), "The stopped answer stays after the reload")
        XCTAssertEqual(answer.text, "You hold")
        XCTAssertFalse(answer.canRate)
        XCTAssertFalse(answer.controls.contains { $0.kind == .followup })
        XCTAssertEqual(coordinator.messages.first { $0.id == "partial" }?.status, .cancelled)
        XCTAssertTrue(coordinator.messages.contains { $0.id == "next-question" }, "The rest is the server's")
    }

    /// A stopped answer outside the newest page keeps its shown text once an older page brings it: over a shorter server
    /// copy, after its question when the server left it out, and once only when the conversation shows it already. A
    /// server copy with as much text replaces it.
    @MainActor
    func testStoppedAnswerOnAnOlderPageKeepsItsShownText() async throws {
        enum Case: CaseIterable { case shorterCopy, leftOut, alreadyShown, fullCopy }
        let question: [String: Any] = [
            "id": "next-question", "threadId": "thread-a", "role": "user", "status": "complete",
            "content": ["kind": "markdown", "text": "Next question"], "createdAt": "2026-07-22T00:00:01.000Z"
        ]
        func answer(_ text: String) -> [String: Any] {
            ["id": "partial", "threadId": "thread-a", "role": "assistant", "status": "cancelled",
             "content": ["kind": "markdown", "text": text], "createdAt": "2026-07-22T00:00:02.000Z"]
        }
        let laterMessages: [[String: Any]] = [
            ["id": "later-question", "threadId": "thread-a", "role": "user", "status": "complete",
             "content": ["kind": "markdown", "text": "Later question"], "createdAt": "2099-01-01T00:00:01.000Z"],
            ["id": "later-answer", "threadId": "thread-a", "role": "assistant", "status": "complete",
             "content": ["kind": "markdown", "text": "Later answer"], "createdAt": "2099-01-01T00:00:02.000Z"],
        ]
        for testCase in Case.allCases {
            let history = try decodeRatedConversation(answerFeedback: nil)
            let stoppedThread = try makeThread(history.thread, revision: history.thread.revision + 1)
            let newestPage = try decodeHydration(
                threadId: "thread-a",
                messages: (testCase == .alreadyShown ? [answer("")] : []) + laterMessages,
                nextCursor: "older",
                thread: stoppedThread
            )
            let olderMessages: [[String: Any]] = switch testCase {
            case .shorterCopy: [question, answer("")]
            case .leftOut, .alreadyShown: [question]
            case .fullCopy: [question, answer("You hold 5 TON")]
            }
            let olderPage = try decodeHydration(threadId: "thread-a", messages: olderMessages, thread: stoppedThread)
            let client = FakeAgentV2Client(hydrationResults: [history, newestPage, olderPage])
            client.blocksRunStart = true
            let model = AgentV2Model(client: client, thread: history.thread)
            defer {
                model.stop()
                client.resumeRunStart()
            }
            await model.waitForInitialLoad()
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)

            model.send(text: "Next question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            coordinator.walletCore(event: .agentV2(try decodeUpdate(kind: "messageStarted", threadId: "thread-a", messageId: "partial")))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "textDelta", threadId: "thread-a", messageId: "partial", delta: "You hold"
            )))
            model.stopAnswer()
            coordinator.walletCore(event: .agentV2(.threadChanged(threadId: "thread-a", thread: stoppedThread)))
            try await waitForDiscussionUI { client.hydrationRequestCount == 2 }
            for _ in 0..<20 { await Task.yield() }

            let didLoad = await coordinator.loadOlderMessages()
            XCTAssertTrue(didLoad, "\(testCase)")
            XCTAssertEqual(
                coordinator.messages.map(\.id),
                ["next-question", "partial", "later-question", "later-answer"],
                "\(testCase)"
            )
            XCTAssertEqual(
                coordinator.messages.first { $0.id == "partial" }?.text,
                testCase == .fullCopy ? "You hold 5 TON" : "You hold",
                "\(testCase)"
            )
        }
    }

    /// An edit or a regeneration replaces the stopped answer on the server, so the next history load shows the
    /// server's answer even when it is shorter than the stopped one
    @MainActor
    func testStoppedAnswerIsGoneAfterARegenerationOrAnEdit() async throws {
        for isEdit in [false, true] {
            let history = try decodeRatedConversation(answerFeedback: nil)
            let replacedHistory = try decodeHydration(threadId: "thread-a", messages: [
                ["id": "next-question", "threadId": "thread-a", "role": "user", "status": "complete",
                 "content": ["kind": "markdown", "text": "Next question"], "createdAt": "2026-07-22T00:00:01.000Z"],
                ["id": "partial", "threadId": "thread-a", "role": "assistant", "status": "complete",
                 "content": ["kind": "markdown", "text": "New"], "createdAt": "2026-07-22T00:00:02.000Z"],
            ], thread: try makeThread(history.thread, revision: history.thread.revision + 2))
            let client = FakeAgentV2Client(hydrationResults: [history, replacedHistory], shouldCompleteRun: true)
            client.blocksRunStart = true
            let model = AgentV2Model(client: client, thread: history.thread)
            defer {
                model.stop()
                client.resumeRunStart()
            }
            await model.waitForInitialLoad()
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)

            model.send(text: "Next question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            coordinator.walletCore(event: .agentV2(try decodeUpdate(kind: "messageStarted", threadId: "thread-a", messageId: "partial")))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "textDelta", threadId: "thread-a", messageId: "partial", delta: "You hold"
            )))
            model.stopAnswer()
            client.resumeRunStart()
            let questionId = try XCTUnwrap(coordinator.messages.last { $0.role == .user }?.id)
            XCTAssertTrue(coordinator.send(
                input: isEdit
                    ? .edit(targetUserMessageId: questionId, text: "Next question")
                    : .regenerate(targetAssistantMessageId: "partial"),
                entryPoint: nil
            ))

            try await waitForDiscussionUI { client.hydrationRequestCount == 2 }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(
                coordinator.messages.filter { $0.role == .assistant }.map(\.text),
                ["New"],
                isEdit ? "After an edit" : "After a regeneration"
            )
        }
    }

    /// An edit or a regeneration the server rejects before admitting its run leaves the stopped answer, so the history
    /// load after the failure keeps the text it showed
    @MainActor
    func testStoppedAnswerStaysAfterARejectedRegenerationOrEdit() async throws {
        for isEdit in [false, true] {
            let history = try decodeRatedConversation(answerFeedback: nil)
            let savedHistory = try decodeHydration(threadId: "thread-a", messages: [
                ["id": "next-question", "threadId": "thread-a", "role": "user", "status": "complete",
                 "content": ["kind": "markdown", "text": "Next question"], "createdAt": "2026-07-22T00:00:01.000Z"],
                ["id": "partial", "threadId": "thread-a", "role": "assistant", "status": "cancelled",
                 "content": ["kind": "markdown", "text": ""], "createdAt": "2026-07-22T00:00:02.000Z"],
            ], thread: try makeThread(history.thread, revision: history.thread.revision + 1))
            let client = FakeAgentV2Client(hydrationResults: [history, savedHistory])
            client.blocksRunStart = true
            let model = AgentV2Model(client: client, thread: history.thread)
            defer {
                model.stop()
                client.resumeRunStart()
            }
            await model.waitForInitialLoad()
            let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)

            model.send(text: "Next question")
            try await waitForDiscussionUI { client.startedCommands.count == 1 }
            coordinator.walletCore(event: .agentV2(try decodeUpdate(kind: "messageStarted", threadId: "thread-a", messageId: "partial")))
            coordinator.walletCore(event: .agentV2(try decodeUpdate(
                kind: "textDelta", threadId: "thread-a", messageId: "partial", delta: "You hold"
            )))
            model.stopAnswer()
            client.resumeRunStart()
            let questionId = try XCTUnwrap(coordinator.messages.last { $0.role == .user }?.id)
            XCTAssertTrue(coordinator.send(
                input: isEdit
                    ? .edit(targetUserMessageId: questionId, text: "Next question")
                    : .regenerate(targetAssistantMessageId: "partial"),
                entryPoint: nil
            ))

            try await waitForDiscussionUI { client.hydrationRequestCount == 2 && coordinator.activeRun?.isRunning != true }
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(
                coordinator.messages.first { $0.id == "partial" }?.text,
                "You hold",
                isEdit ? "After a rejected edit" : "After a rejected regeneration"
            )
        }
    }

    @MainActor
    func testRunSentBeforeTheSavedThreadLoadsKeepsItsMessages() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let savedThread = try makeThread(history.thread, revision: history.thread.revision + 1)
        let client = FakeAgentV2Client(hydrationResults: [
            history, try decodeHydration(threadId: "thread-a", messages: [], thread: savedThread)
        ])
        client.blocksRunStart = true
        let model = AgentV2Model(client: client, thread: history.thread)
        defer {
            model.stop()
            client.resumeRunStart()
        }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        model.send(text: "First question")
        try await waitForDiscussionUI { client.startedCommands.count == 1 }
        model.stopAnswer()
        client.resumeRunStart()
        client.blocksRunStart = true

        coordinator.walletCore(event: .agentV2(.threadChanged(threadId: "thread-a", thread: savedThread)))
        model.send(text: "Second question")
        try await waitForDiscussionUI { client.startedCommands.count == 2 }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(client.hydrationRequestCount, 1)
        XCTAssertTrue(model.hasActiveRun)
        XCTAssertEqual(coordinator.messages.last?.text, "Second question")
    }

    @MainActor
    func testRegenerationKeepsTheTimelineWhenTheCoordinatorCannotStartARun() async throws {
        let history = try decodeRatedConversation(answerFeedback: nil)
        let client = FakeAgentV2Client(hydrationResult: history)
        let model = AgentV2Model(client: client, thread: history.thread)
        defer { model.stop() }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        coordinator.stop()
        let answerID = try XCTUnwrap(presentedMessageID(in: model, role: .assistant))
        let itemIDs = model.itemIDs.filter { model.message(for: $0)?.isDateTimeSystemMessage != true }
        let texts = itemIDs.compactMap { model.message(for: $0)?.text }

        model.regenerateMessage(answerID)

        let regeneratedItemIDs = model.itemIDs.filter { model.message(for: $0)?.isDateTimeSystemMessage != true }
        XCTAssertEqual(regeneratedItemIDs, itemIDs)
        XCTAssertEqual(regeneratedItemIDs.compactMap { model.message(for: $0)?.text }, texts)
        XCTAssertFalse(model.itemIDs.contains { if case .typingIndicator? = model.item(for: $0) { return true }; return false })
        XCTAssertTrue(client.startedCommands.isEmpty)
    }

    private func decodeUpdate(
        kind: String,
        threadId: String,
        messageId: String,
        delta: String? = nil,
        contentKind: ApiAgentV2ContentKind = .markdown,
        code: ApiAgentV2ErrorCode? = nil,
        finishReason: String = "complete"
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
        if kind == "messageCompleted" { update["finishReason"] = finishReason }
        if let code {
            update["code"] = code.rawValue
            update["retryable"] = false
        }
        let data = try JSONSerialization.data(withJSONObject: ["type": "agentV2", "update": update])
        return try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data).update
    }

    private func makeThread(
        _ thread: ApiAgentV2ThreadSummary,
        revision: Int,
        support: ApiAgentV2ThreadSupport? = nil
    ) throws -> ApiAgentV2ThreadSummary {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)) as? [String: Any])
        object["revision"] = revision
        if let support {
            object["support"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(support))
        }
        return try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// Runs the button's touch-up actions, which `sendActions` leaves to an application the tests don't run
    @MainActor
    private func tap(_ button: UIButton) {
        for target in button.allTargets {
            for action in button.actions(forTarget: target, forControlEvent: .touchUpInside) ?? [] {
                (target as? NSObject)?.perform(NSSelectorFromString(action), with: button)
            }
        }
    }

    private func decodeFollowupsUpdate(threadId: String, messageId: String) throws -> ApiAgentV2ClientUpdate {
        try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "followupsAvailable", "clientRunId": "client-\(threadId)", "runId": "run-\(threadId)",
            "threadId": threadId, "messageId": messageId,
            "items": [["id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "More?"]]
        ]))
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
        nextCursor: String? = nil,
        thread: ApiAgentV2ThreadSummary? = nil
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
        if let thread {
            hydration["thread"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread))
        }
        let data = try JSONSerialization.data(withJSONObject: hydration)
        return try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: data)
    }

    private func newsPostMessage(
        id: String,
        text: String,
        role: String = "user",
        threadId: String = "news-thread",
        newsPost: Bool? = nil,
        followups: [[String: String]]? = nil
    ) -> [String: Any] {
        var message: [String: Any] = [
            "id": id, "threadId": threadId, "role": role, "status": "complete",
            "content": ["kind": "markdown", "text": text], "createdAt": "2026-10-20T10:00:01.000Z"
        ]
        message["newsPost"] = newsPost
        message["followups"] = followups
        return message
    }

    private func decodeNewsThread(
        id: String,
        eventId: Int,
        headline: String,
        messageCount: Int,
        isCleared: Bool = false,
        body: String? = nil,
        sources: [ApiAgentV2NewsFeedItem.Source]? = nil
    ) throws -> ApiAgentV2ThreadSummary {
        let thread = try decodeHydration(threadId: id, messages: []).thread
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)) as? [String: Any])
        object["messageCount"] = messageCount
        object["news"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ApiAgentV2ThreadNewsCard(
            eventId: eventId, headline: headline, excerpt: nil, imageUrl: nil,
            publishedAt: "2026-10-20T10:00:00.000Z", source: nil, body: body, sources: sources
        )))
        if isCleared { object["clearedAt"] = "2026-10-20T11:00:00.000Z" }
        return try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: object))
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

    private func decodeRatedConversation(answerFeedback: String?) throws -> ApiAgentV2ThreadHydration {
        var answer: [String: Any] = [
            "id": "answer", "threadId": "thread-a", "role": "assistant", "status": "complete",
            "content": ["kind": "markdown", "text": "You hold 5 TON."],
            "createdAt": "2026-07-22T00:00:02.000Z"
        ]
        answer["feedback"] = answerFeedback
        return try decodeHydration(threadId: "thread-a", messages: [
            [
                "id": "question", "threadId": "thread-a", "role": "user", "status": "complete",
                "content": ["kind": "markdown", "text": "What is my balance?"],
                "createdAt": "2026-07-22T00:00:01.000Z"
            ],
            answer
        ])
    }

    @MainActor
    private func presentedMessageID(in model: AgentV2Model, role: AgentMessage.Role) -> AgentItemID? {
        model.itemIDs.first { presentedMessage($0, in: model)?.role == role }
    }

    @MainActor
    private func presentedMessage(_ id: AgentItemID, in model: AgentV2Model) -> AgentMessage? {
        guard case .message(let message)? = model.item(for: id) else { return nil }
        return message
    }

    @MainActor
    private func waitForFeedbackRequest(_ client: FakeAgentV2Client, count: Int) async {
        for _ in 0..<100 {
            guard client.feedbackRequests.count < count else { return }
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

/// Takes the model's changes in place of a chat, and counts those that leave the row `watchedID` out of the timeline
@MainActor
private final class AgentRowPresenceRecorder: AgentModelDelegate {
    var watchedID: AgentItemID?
    private(set) var changeCount = 0
    private(set) var missingCount = 0
    private weak var model: AgentModel?

    init(model: AgentModel) {
        self.model = model
        model.delegate = self
    }

    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID]) {
        record()
    }

    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool) {
        record()
    }

    func agentModelDidUpdateHints(animated: Bool) {}

    private func record() {
        guard let watchedID, let model else { return }
        changeCount += 1
        if !model.itemIDs.contains(watchedID) {
            missingCount += 1
        }
    }
}

@MainActor
private final class AgentV2CoordinatorObserverSpy: AgentV2CoordinatorObserver {
    private(set) var changes: [AgentV2CoordinatorChange] = []

    func agentV2CoordinatorDidChange(_ coordinator: AgentV2Coordinator, change: AgentV2CoordinatorChange) {
        changes.append(change)
    }
}

@MainActor
private final class AgentThreadBridgeWebView: WKWebView {
    struct Call {
        let method: String
        let arguments: [Any]
    }

    var response: String? = "{}"
    private(set) var calls: [Call] = []

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)? = nil
    ) {
        completionHandler?(nil, nil)
    }

    override func __callAsyncJavaScript(
        _ functionBody: String,
        arguments: [String: Any]?,
        inFrame frame: WKFrameInfo?,
        in contentWorld: WKContentWorld,
        completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)?
    ) {
        if let method = arguments?["methodName"] as? String,
           let argumentsString = arguments?["argsString"] as? String,
           let decoded = try? JSONSerialization.jsonObject(with: Data(argumentsString.utf8)) as? [Any] {
            calls.append(Call(method: method, arguments: decoded))
        }
        completionHandler?(response, nil)
    }
}

private enum FakeAgentV2ClientError: Error {
    case unavailable
}

@MainActor
final class FakeAgentV2Client: AgentV2Client, AgentThreadListClient {
    var defaultThreadError: ApiAgentV2MutationError?
    var hintsResult: ApiAgentV2HintsResponse?
    private(set) var hintsRequestCount = 0
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
    private(set) var deletedThreadIds: [String] = []
    var threadDeletionError: Error?
    var beforeThreadDeletion: (() async -> Void)?
    private(set) var retriedClientRunIds: [String] = []
    private(set) var hostContextUpdateCount = 0
    private(set) var cancelledHostContextUpdateCount = 0
    private(set) var hydrationRequestCount = 0
    var hydrationError: Error?
    private(set) var cancelledHydrationRequestCount = 0
    private(set) var hydratedThreadIds: [String] = []
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
    var runResultRunId: String? = "run-thread-a"
    var runInputMessageId: String?
    var runStartError: Error?
    var blocksRunStart = false
    private var runStartContinuation: CheckedContinuation<Void, Never>?
    func resumeRunStart() {
        blocksRunStart = false
        runStartContinuation?.resume()
        runStartContinuation = nil
    }

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
    var consentError: Error?
    func consent() async throws -> Bool {
        if let consentError { throw consentError }
        return hasConsent
    }
    var isConsentKnownGiven = false
    func forgetKnownConsent() {
        isConsentKnownGiven = false
    }
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
    func resumeClear() {
        blocksClear = false
        clearContinuation?.resume()
        clearContinuation = nil
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
        if Task.isCancelled { cancelledHostContextUpdateCount += 1 }
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
        hintsRequestCount += 1
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
    var availabilityResult: ApiAgentV2AvailabilityState?
    var userQuotaResult: ApiAgentV2UserQuota?
    private var statusContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var completedStatusRequests = Set<String>()
    private(set) var cancelledStatusRequests = Set<String>()
    func loadAvailability() async {
        await loadStatus("availability")
        if let availabilityResult {
            WalletCoreData.notify(event: .agentV2(.availabilityChanged(availabilityResult)))
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        completedStatusRequests.insert("availability")
    }
    func loadUserQuota() async {
        await loadStatus("userQuota")
        if let userQuotaResult {
            WalletCoreData.notify(event: .agentV2(.userQuotaChanged(userQuotaResult)))
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        completedStatusRequests.insert("userQuota")
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
    var threadListResult: ApiAgentV2ThreadListResponse?
    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        guard let threadListResult else { throw FakeAgentV2ClientError.unavailable }
        return threadListResult
    }
    func cachedThreads() async -> [ApiAgentV2ThreadListItem]? { nil }
    var createdThreadIsNew = true
    var createdThread: ApiAgentV2ThreadSummary?
    private(set) var newsThreadRequests: [ApiAgentV2ThreadNewsRequest] = []
    var threadCreationError: Error?
    var blocksThreadCreation = false
    private(set) var cancelledThreadCreationCount = 0
    private var threadCreationContinuation: CheckedContinuation<Void, Never>?
    func resumeThreadCreation() {
        blocksThreadCreation = false
        threadCreationContinuation?.resume()
        threadCreationContinuation = nil
    }
    func createThread() async throws -> ApiAgentV2ThreadCreateResponse {
        requestOrder.append("createThread")
        if blocksThreadCreation {
            await withCheckedContinuation { threadCreationContinuation = $0 }
        }
        if Task.isCancelled { cancelledThreadCreationCount += 1 }
        if let threadCreationError { throw threadCreationError }
        let thread = createdThread ?? hydrationResult?.thread ?? makeThread(id: defaultThreadId)
        return try JSONDecoder().decode(
            ApiAgentV2ThreadCreateResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "protocolVersion": 3,
                "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)),
                "created": createdThreadIsNew
            ])
        )
    }
    var digestThreadRequests: [ApiAgentV2ThreadDigestRequest] = []
    func createThread(digest: ApiAgentV2ThreadDigestRequest) async throws -> ApiAgentV2ThreadCreateResponse {
        digestThreadRequests.append(digest)
        return try await createThread()
    }
    func createThread(news: ApiAgentV2ThreadNewsRequest) async throws -> ApiAgentV2ThreadCreateResponse {
        newsThreadRequests.append(news)
        return try await createThread()
    }
    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse {
        throw FakeAgentV2ClientError.unavailable
    }
    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        deletedThreadIds.append(id)
        await beforeThreadDeletion?()
        if let threadDeletionError { throw threadDeletionError }
        return try JSONDecoder().decode(
            ApiAgentV2ThreadDeleteResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "protocolVersion": 3, "threadId": id, "duplicate": false
            ])
        )
    }
    func messages(threadId: String, cursor: String?, limit: Int) async throws -> ApiAgentV2ThreadHydration {
        requestOrder.append("messages")
        hydrationRequestCount += 1
        hydratedThreadIds.append(threadId)
        let attempt = hydrationRequestCount
        let result = hydrationResults.isEmpty
            ? hydrationResult
            : hydrationResults[min(attempt - 1, hydrationResults.count - 1)]
        if attempt == blockedHydrationAttempt {
            await withCheckedContinuation { continuation in
                blockedHydrationContinuation = continuation
            }
        }
        if Task.isCancelled { cancelledHydrationRequestCount += 1 }
        if let hydrationError { throw hydrationError }
        guard let result else { throw FakeAgentV2ClientError.unavailable }
        return result
    }
    func cachedMessages(threadId: String) async -> ApiAgentV2CachedMessages? { nil }
    /// The ids of the next runs; after them every run is `client-<defaultThreadId>`
    var clientRunIds: [String] = []
    func makeClientRunId() -> String {
        clientRunIds.isEmpty ? "client-\(defaultThreadId)" : clientRunIds.removeFirst()
    }
    func startRun(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult {
        startedCommands.append(command)
        startRunObserver?()
        if blocksRunStart {
            await withCheckedContinuation { runStartContinuation = $0 }
        }
        if let runStartError { throw runStartError }
        guard shouldCompleteRun else { throw FakeAgentV2ClientError.unavailable }
        var result: [String: Any] = [
            "clientRunId": command.clientRunId,
            "state": runResultState.rawValue
        ]
        result["runId"] = runResultRunId
        result["inputMessageId"] = runInputMessageId
        return try JSONDecoder().decode(
            ApiAgentV2RunResult.self,
            from: JSONSerialization.data(withJSONObject: result)
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
    private(set) var stoppedThreadIds: [String] = []
    func stopRun(threadId: String) async {
        stoppedThreadIds.append(threadId)
    }
    var blocksClear = false
    var clearError: Error?
    private var clearContinuation: CheckedContinuation<Void, Never>?
    func clearThread(
        id: String,
        revision: Int
    ) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse> {
        requestOrder.append("clearThread")
        if blocksClear {
            await withCheckedContinuation { clearContinuation = $0 }
        }
        if let clearError { throw clearError }
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
    func transcribeAgentV2Audio(_ request: ApiAgentV2TranscriptionRequest) async throws -> ApiAgentV2TranscriptionResponse {
        throw FakeAgentV2ClientError.unavailable
    }
    private(set) var feedbackRequests: [(messageId: String, feedback: ApiAgentV2AnswerFeedback?)] = []
    private var feedbackContinuations: [CheckedContinuation<Result<ApiAgentV2AnswerFeedback?, Error>, Never>] = []
    func setMessageFeedback(
        threadId: String,
        messageId: String,
        feedback: ApiAgentV2AnswerFeedback?
    ) async throws -> ApiAgentV2AnswerFeedback? {
        feedbackRequests.append((messageId, feedback))
        return try await withCheckedContinuation { feedbackContinuations.append($0) }.get()
    }
    func settleFeedbackRequest(at index: Int, with result: Result<ApiAgentV2AnswerFeedback?, Error>) {
        feedbackContinuations[index].resume(returning: result)
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

/// Pushes without the animation, so a test sees the chat laid out at its place at once
private final class ListQuestionTestNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: false)
    }
}
