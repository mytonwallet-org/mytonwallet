import ContextMenuKit
import XCTest
import UIKit
@testable import UIAgent
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class AgentRegenerateTests: XCTestCase {
    func testMessageMenuItemsFollowRoleStreamingAndActionAvailability() {
        _ = WalletResourcesBundle.bundle.load()
        var invoked: [String] = []
        func actions(
            _ message: AgentMessage,
            canEdit: Bool = true,
            canRegenerate: Bool,
            canReportProblem: Bool
        ) -> [ContextMenuAction] {
            AgentMessageMenuItems.makeItems(
                for: message,
                copyText: "Visible copy text",
                canEdit: canEdit,
                canRegenerate: canRegenerate,
                canReportProblem: canReportProblem,
                edit: { invoked.append("edit") },
                regenerate: { invoked.append("regenerate") },
                reportProblem: { invoked.append("report") }
            ).compactMap { item in
                guard case .action(let action) = item else { return nil }
                return action
            }
        }
        let question = AgentMessage(role: .user, text: "Question", isStreaming: false)
        var answer = AgentMessage(role: .assistant, text: "Answer", isStreaming: false)
        let questionActions = actions(question, canRegenerate: true, canReportProblem: true)
        XCTAssertEqual(questionActions.map(\.title), [lang("Copy"), lang("Edit")])
        questionActions[1].handler?()
        // A question that waits for the answer, or one a wallet switch failed, has nothing stored to edit
        XCTAssertEqual(actions(question, canEdit: false, canRegenerate: true, canReportProblem: true).map(\.title), [lang("Copy")])
        let answerActions = actions(answer, canRegenerate: true, canReportProblem: true)
        XCTAssertEqual(answerActions.map(\.title), [lang("Copy"), lang("Regenerate"), lang("Report a Problem")])
        answerActions[1].handler?()
        answerActions[2].handler?()
        XCTAssertEqual(invoked, ["edit", "regenerate", "report"])
        XCTAssertEqual(actions(answer, canRegenerate: false, canReportProblem: true).map(\.title), [lang("Copy"), lang("Report a Problem")])
        XCTAssertEqual(actions(answer, canRegenerate: true, canReportProblem: false).map(\.title), [lang("Copy"), lang("Regenerate")])
        answer.isStreaming = true
        XCTAssertEqual(actions(answer, canRegenerate: false, canReportProblem: true).map(\.title), [lang("Copy")])
    }

    func testMessageCopyTextIncludesSupplementaryErrorAndOmitsEmptyParts() {
        var message = AgentMessage(role: .assistant, text: "Answer", isStreaming: false)
        XCTAssertEqual(AgentMessageMenuItems.copyText(for: message), "Answer")
        message.supplementaryErrorText = " \nService unavailable\n "
        XCTAssertEqual(AgentMessageMenuItems.copyText(for: message), "Answer\n\nService unavailable")
        message.text = ""
        XCTAssertEqual(AgentMessageMenuItems.copyText(for: message), "Service unavailable")
        message.supplementaryErrorText = " \n "
        XCTAssertNil(AgentMessageMenuItems.copyText(for: message))
    }

    func testAnswerMenuRegeneratesTheAnswerAndQuestionMenuDoesNot() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let backend = RegenerateTestBackend()
        let model = AgentModel(backend: backend)
        let question = AgentMessage(role: .user, text: "How do swaps work?", isStreaming: false)
        let answer = AgentMessage(role: .assistant, text: "A swap exchanges one token for another.", isStreaming: false)
        backend.regeneratableMessageIDs = [answer.id]
        backend.context?.replaceTimeline(with: [.message(question), .message(answer)], animated: false)
        let controller = AgentVC(model: model)
        let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
        defer { window.isHidden = true }
        let collectionView = try XCTUnwrap(findDescendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        for _ in 0..<100 where collectionView.visibleCells.compactMap({ $0 as? AgentMessageCell }).count < 2 {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        let cells = collectionView.visibleCells
            .compactMap { $0 as? AgentMessageCell }
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(cells.count, 2)

        let questionMenu = try XCTUnwrap(cells[0].contextMenuConfigurationProvider?())
        XCTAssertNil(regenerateAction(in: questionMenu))
        let answerMenu = try XCTUnwrap(cells[1].contextMenuConfigurationProvider?())
        let regenerate = try XCTUnwrap(regenerateAction(in: answerMenu))

        regenerate.handler?()
        XCTAssertEqual(backend.regeneratedMessageIDs, [answer.id])

        backend.regeneratableMessageIDs = []
        let busyMenu = try XCTUnwrap(cells[1].contextMenuConfigurationProvider?())
        XCTAssertNil(regenerateAction(in: busyMenu))
    }

    func testRegenerateReportsTheRowsItTakesOutIncludingDateLinesLeftWithNothingUnderThem() {
        _ = WalletResourcesBundle.bundle.load()
        let backend = RegenerateTestBackend()
        let model = AgentModel(backend: backend)
        let conversation = Conversation(start: Date(timeIntervalSince1970: 1_800_000_000))
        backend.regeneratableMessageIDs = [conversation.answer.id]
        backend.replacedItemIDs = conversation.replacedByRegeneratingAnswer
        backend.context?.replaceTimeline(with: conversation.items, animated: false)

        // A date line heads each question, as an hour passes between them
        XCTAssertEqual(model.itemIDs.count, 6)
        let laterDateLineID = model.itemIDs[3]
        XCTAssertNotEqual(laterDateLineID, conversation.followUp.id)
        XCTAssertEqual(
            model.getItemIDsRemovedByRegenerating(conversation.answer.id),
            [conversation.answer.id, laterDateLineID, conversation.followUp.id, conversation.followUpAnswer.id]
        )

        backend.regeneratableMessageIDs = []
        XCTAssertEqual(model.getItemIDsRemovedByRegenerating(conversation.answer.id), [])
    }

    func testRegeneratedRowsDissolveOverTheMessagesAndLeaveNoCellHidden() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let backend = RegenerateTestBackend()
        let model = AgentModel(backend: backend)
        let conversation = Conversation(start: Date())
        backend.regeneratableMessageIDs = [conversation.answer.id]
        backend.replacedItemIDs = conversation.replacedByRegeneratingAnswer
        backend.context?.replaceTimeline(with: conversation.items, animated: false)
        let controller = AgentVC(model: model)
        let window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
        defer { window.isHidden = true }
        let collectionView = try XCTUnwrap(findDescendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        for _ in 0..<100 where collectionView.visibleCells.compactMap({ $0 as? AgentMessageCell }).count < 4 {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        let messageCells = collectionView.visibleCells
            .compactMap { $0 as? AgentMessageCell }
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(messageCells.count, 4)
        let dissolvedCells = Array(messageCells.dropFirst())
        let answerCell = try XCTUnwrap(dissolvedCells.first)
        let menu = try XCTUnwrap(answerCell.contextMenuConfigurationProvider?())
        try XCTUnwrap(regenerateAction(in: menu)).handler?()

        XCTAssertEqual(backend.regeneratedMessageIDs, [conversation.answer.id])
        XCTAssertEqual(model.itemIDs.count, 3)
        // The rows dissolve right above the messages, under the composer and the header
        let dissolveView = try XCTUnwrap(findDescendants(of: controller.view).compactMap { $0 as? AgentMessageDissolveView }.first)
        let chatViews = try XCTUnwrap(collectionView.superview).subviews
        XCTAssertEqual(chatViews.firstIndex(of: dissolveView), chatViews.firstIndex(of: collectionView).map { $0 + 1 })
        XCTAssertFalse(dissolveView.subviews.isEmpty)
        // Neither the cells on screen nor those the removed rows left for reuse keep their content hidden
        for _ in 0..<100 where findCells(in: collectionView).contains(where: { $0.contentView.isHidden }) {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        XCTAssertTrue(findCells(in: collectionView).allSatisfy { !$0.contentView.isHidden })

        let newMessages = (0..<6).map { index in
            AgentMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "Message \(index)", isStreaming: false)
        }
        backend.context?.replaceTimeline(with: [.message(conversation.question)] + newMessages.map { .message($0) }, animated: false)
        for _ in 0..<100 where collectionView.visibleCells.compactMap({ $0 as? AgentMessageCell }).count < 7 {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        // New messages take the cells of the rows that dissolved, and show in them
        let reusedCells = dissolvedCells.filter { cell in collectionView.visibleCells.contains { $0 === cell } }
        XCTAssertFalse(reusedCells.isEmpty)
        XCTAssertTrue(reusedCells.allSatisfy { !$0.contentView.isHidden })
        XCTAssertTrue(findCells(in: collectionView).allSatisfy { !$0.contentView.isHidden })
    }

    private func findCells(in collectionView: UICollectionView) -> [UICollectionViewCell] {
        collectionView.visibleCells + collectionView.subviews.compactMap { $0 as? UICollectionViewCell }
    }

    private func regenerateAction(in configuration: ContextMenuConfiguration) -> ContextMenuAction? {
        configuration.rootPage.items.compactMap { item -> ContextMenuAction? in
            guard case .action(let action) = item, action.title == lang("Regenerate") else { return nil }
            return action
        }.first
    }
}

/// A question and its answer, then, an hour later, a follow-up question and its answer
private struct Conversation {
    let question: AgentMessage
    let answer: AgentMessage
    let followUp: AgentMessage
    let followUpAnswer: AgentMessage

    init(start: Date) {
        question = AgentMessage(role: .user, text: "How do swaps work?", isStreaming: false, timestamp: start)
        answer = AgentMessage(
            role: .assistant,
            text: "A swap exchanges one token for another.",
            isStreaming: false,
            timestamp: start.addingTimeInterval(60)
        )
        followUp = AgentMessage(
            role: .user,
            text: "And staking?",
            isStreaming: false,
            timestamp: start.addingTimeInterval(3600)
        )
        followUpAnswer = AgentMessage(
            role: .assistant,
            text: "Staking earns a reward for locking tokens.",
            isStreaming: false,
            timestamp: start.addingTimeInterval(3660)
        )
    }

    var items: [AgentTimelineItem] {
        [.message(question), .message(answer), .message(followUp), .message(followUpAnswer)]
    }

    /// What the Agent V2 backend takes out when the first answer is asked for again
    var replacedByRegeneratingAnswer: [AgentItemID] {
        [answer.id, followUp.id, followUpAnswer.id]
    }
}

@MainActor
private final class RegenerateTestBackend: AgentBackend {
    var context: AgentBackendContext?
    var regeneratableMessageIDs: Set<AgentItemID> = []
    var regeneratedMessageIDs: [AgentItemID] = []
    /// The items Regenerate takes out, which it removes and replaces with a typing indicator as the Agent V2 backend does
    var replacedItemIDs: [AgentItemID] = []

    func attach(to context: AgentBackendContext) { self.context = context }
    func detach() { context = nil }
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
    func didSendUserMessage(
        _ text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?
    ) {}
    func clearConversation() {}

    func canRegenerateMessage(messageID: AgentItemID) -> Bool {
        regeneratableMessageIDs.contains(messageID)
    }

    func getItemIDsRemovedByRegenerating(messageID: AgentItemID) -> [AgentItemID] {
        replacedItemIDs
    }

    func regenerateMessage(messageID: AgentItemID) {
        regeneratedMessageIDs.append(messageID)
        guard let context, !replacedItemIDs.isEmpty else { return }
        for itemID in replacedItemIDs {
            context.removeItem(id: itemID, animated: false)
        }
        context.append(.typingIndicator(AgentTypingIndicator()), animated: true)
    }
}
