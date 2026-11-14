import Testing
@testable import UIAgent
import WalletCore

struct AgentV2MessageReplacementTests {
    @Test(arguments: [ApiAgentV2RunResultState.failed, .cancelled, .interrupted])
    func rejectedEditRestoresMessages(outcome: ApiAgentV2RunResultState) {
        var replacement = AgentV2MessageReplacement()
        replacement.beginEditing(targetNativeID: "question", messages: messages)
        replacement.sendEdit(targetNativeID: "question", text: "Edited question")

        #expect(replacement.ignoredNativeIDs == ["answer", "followup"])
        #expect(replacement.editedTextByNativeID == ["question": "Edited question"])
        #expect(replacement.runTerminated(outcome: outcome) == .restore)
        #expect(replacement.ignoredNativeIDs.isEmpty)
        #expect(replacement.editedTextByNativeID.isEmpty)
        #expect(replacement.runTerminated(outcome: outcome) == .none)
    }

    @Test
    func reconciledEditIsAdmittedAndKeepsItsReplacement() {
        var replacement = AgentV2MessageReplacement()
        replacement.beginEditing(targetNativeID: "question", messages: messages)
        replacement.sendEdit(targetNativeID: "question", text: "Edited question")

        replacement.reconcileMessageID(localID: "question", canonicalID: "canonical-question")

        #expect(replacement.editedTextByNativeID == ["canonical-question": "Edited question"])
        #expect(replacement.runTerminated(outcome: .failed) == .none)
        #expect(replacement.ignoredNativeIDs == ["answer", "followup"])
        #expect(replacement.editedTextByNativeID == ["canonical-question": "Edited question"])
    }

    @Test(arguments: [false, true])
    func failedRegenerationRestoresMessagesAndResyncsOnlyAfterAdmission(isAdmitted: Bool) {
        var replacement = AgentV2MessageReplacement()
        replacement.beginRegeneration(targetNativeID: "answer", replacedNativeIDs: ["answer", "followup"])
        replacement.admitRegeneration(runID: isAdmitted ? "run" : nil)

        #expect(replacement.ignoredNativeIDs == ["answer", "followup"])
        #expect(replacement.runTerminated(outcome: .failed) == (isAdmitted ? .restoreAndResync : .restore))
        #expect(replacement.ignoredNativeIDs.isEmpty)
        #expect(replacement.runTerminated(outcome: .failed) == .none)
    }

    @Test
    func completedRegenerationKeepsMessagesHiddenUntilPruning() {
        var replacement = AgentV2MessageReplacement()
        replacement.beginRegeneration(targetNativeID: "answer", replacedNativeIDs: ["answer", "followup"])
        replacement.admitRegeneration(runID: "run")

        #expect(replacement.runTerminated(outcome: .completed) == .none)
        #expect(replacement.ignoredNativeIDs == ["answer", "followup"])
    }

    @Test
    func regenerationThatDidNotStartRestoresMessages() {
        var replacement = AgentV2MessageReplacement()
        replacement.beginRegeneration(targetNativeID: "answer", replacedNativeIDs: ["answer", "followup"])

        #expect(replacement.regenerationDidNotStart() == .restore)
        #expect(replacement.ignoredNativeIDs.isEmpty)
        #expect(replacement.runTerminated(outcome: .failed) == .none)
    }

    @Test
    func pruningRemovedMessagesClearsPendingReplacements() {
        var replacement = AgentV2MessageReplacement()
        replacement.beginEditing(targetNativeID: "question", messages: messages)
        replacement.sendEdit(targetNativeID: "question", text: "Edited question")
        replacement.beginRegeneration(targetNativeID: "answer", replacedNativeIDs: ["answer", "followup"])

        replacement.prune(messages: [])

        #expect(replacement.ignoredNativeIDs.isEmpty)
        #expect(replacement.editedTextByNativeID.isEmpty)
        #expect(replacement.runTerminated(outcome: .failed) == .none)
    }

    @Test
    func pruningServerTextClearsTheMatchingOverride() {
        var replacement = AgentV2MessageReplacement()
        replacement.beginEditing(targetNativeID: "question", messages: [messages[0]])
        replacement.sendEdit(targetNativeID: "question", text: "Edited question")

        replacement.prune(messages: [message(id: "question", text: "Question")])
        #expect(replacement.editedTextByNativeID == ["question": "Edited question"])

        replacement.prune(messages: [message(id: "question", text: "Edited question")])

        #expect(replacement.editedTextByNativeID.isEmpty)
        #expect(replacement.runTerminated(outcome: .failed) == .none)
    }

    @Test
    func resetClearsAllReplacementState() {
        var replacement = AgentV2MessageReplacement()
        replacement.beginEditing(targetNativeID: "question", messages: messages)
        replacement.sendEdit(targetNativeID: "question", text: "Edited question")
        replacement.beginRegeneration(targetNativeID: "answer", replacedNativeIDs: ["answer", "followup"])
        replacement.admitRegeneration(runID: "run")

        replacement.reset()

        #expect(replacement.ignoredNativeIDs.isEmpty)
        #expect(replacement.editedTextByNativeID.isEmpty)
        #expect(replacement.runTerminated(outcome: .failed) == .none)
    }

    @Test
    func seenMessageCountSubtractsOnlyHiddenMessagesThatAreNotStreaming() {
        var replacement = AgentV2MessageReplacement()
        let messages = [
            message(id: "question", text: "Question"),
            message(id: "answer", text: "Answer", role: .assistant),
            message(id: "streaming-answer", text: "Partial answer", role: .assistant, status: .streaming),
        ]
        replacement.beginEditing(targetNativeID: "question", messages: messages)

        #expect(replacement.seenMessageCount(3, messages: messages) == 2)
        #expect(replacement.seenMessageCount(nil, messages: messages) == nil)
    }

    @Test
    func latestHistoryInsertsOperatorRepliesInServerOrderWithoutReplacingKnownMessages() {
        var conversation = AgentV2ConversationState()
        var answer = message(id: "answer", text: "Answer", role: .assistant)
        answer.feedback = .like
        conversation.replaceMessages([
            message(id: "older-page", text: "Older history"),
            answer,
            message(id: "later-question", text: "Later question"),
            message(id: "local-ios-question", text: "Unconfirmed question")
        ])
        let latest = [
            message(id: "answer", text: "Stored answer", role: .assistant),
            message(id: "late-operator", text: "Late reply", role: .operator),
            message(id: "later-question", text: "Later question"),
            message(id: "new-operator", text: "Latest reply", role: .operator)
        ]

        conversation.mergeLatestMessages(latest)
        conversation.mergeLatestMessages(latest)

        #expect(conversation.messages.map(\.id) == [
            "older-page", "answer", "late-operator", "later-question", "new-operator", "local-ios-question"
        ])
        #expect(conversation.messages.first { $0.id == "answer" } == answer)
    }

    @Test
    func latestHistoryWithoutAnOverlapKeepsOlderMessagesAndTheOptimisticTail() {
        var conversation = AgentV2ConversationState()
        conversation.replaceMessages([
            message(id: "older-page", text: "Older history"),
            message(id: "local-opening-question", text: "Unconfirmed question")
        ])

        conversation.mergeLatestMessages([
            message(id: "first-operator", text: "First reply", role: .operator),
            message(id: "second-operator", text: "Second reply", role: .operator)
        ])

        #expect(conversation.messages.map(\.id) == [
            "older-page", "first-operator", "second-operator", "local-opening-question"
        ])
    }

    private var messages: [AgentV2NativeMessage] {
        [
            message(id: "question", text: "Question"),
            message(id: "answer", text: "Answer", role: .assistant),
            message(id: "followup", text: "Follow-up"),
        ]
    }

    private func message(
        id: String,
        text: String,
        role: ApiAgentV2MessageRole = .user,
        status: AgentV2NativeMessageStatus = .complete
    ) -> AgentV2NativeMessage {
        AgentV2NativeMessage(id: id, threadId: "thread", role: role, text: text, status: status)
    }
}
