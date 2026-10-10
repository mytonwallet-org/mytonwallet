import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletResources

@MainActor
final class AgentSuggestionTests: XCTestCase {
    private let followup = AgentMessageControl(id: "followup:next", title: "Tell me more", isEnabled: true, kind: .followup)
    private let action = AgentMessageControl(id: "action:open", title: "Open Portfolio", isEnabled: true)

    func testDefaultSuggestionsOnlyAppearBeforeTheFirstMessageAndAfterClearing() {
        let backend = SuggestionTestBackend()
        let model = BaseAgentModel(backend: backend)
        let hint = AgentHint(id: "hint:swaps", title: "How swaps work", subtitle: "Learn", prompt: "Explain swaps")
        backend.context?.setHints([hint], animated: false)
        XCTAssertEqual(model.visibleHints, [hint])

        model.send(text: hint.prompt, source: .hint(id: hint.id, catalogVersion: nil))
        XCTAssertEqual(backend.sentTexts, [hint.prompt])
        XCTAssertTrue(model.visibleHints.isEmpty)
        backend.context?.setHints([hint], animated: false)
        XCTAssertTrue(model.visibleHints.isEmpty, "Refreshing suggestions must not overlay an existing conversation")

        model.clearChat(animated: false)
        XCTAssertEqual(model.visibleHints, [hint])

        model.setTimeline([
            .message(AgentMessage(role: .user, text: "Earlier question", isStreaming: false)),
            .message(response())
        ], animated: false)
        XCTAssertTrue(model.visibleHints.isEmpty, "Opening chat history must not show the default suggestions")
    }

    func testHistoryOnlyShowsFollowupsOnTheLastAssistantMessage() {
        let model = BaseAgentModel(backend: SuggestionTestBackend())
        let first = response()
        let last = response()
        model.setTimeline([.message(first), .message(last)], animated: false)
        XCTAssertEqual(controls(model, first.id), [action])
        XCTAssertEqual(controls(model, last.id), [action, followup])

        let user = AgentMessage(role: .user, text: "Another question", isStreaming: false)
        model.setTimeline([.message(first), .message(last), .message(user)], animated: false)
        XCTAssertEqual(controls(model, last.id), [action])
    }

    func testEverySendSourceHidesFollowupsAndReconfiguresThePreviousResponse() {
        for source in [AgentBackendSendSource.composer, .hint(id: "hint", catalogVersion: nil),
                       .followup(messageID: "message", followupID: "next")] {
            let backend = SuggestionTestBackend()
            let model = BaseAgentModel(backend: backend)
            let delegate = SuggestionTestDelegate()
            model.delegate = delegate
            let message = response()
            model.setTimeline([.message(message)], animated: false)
            delegate.reconfiguredIDs = []

            model.send(text: "Next question", source: source)

            XCTAssertEqual(controls(model, message.id), [action])
            XCTAssertTrue(delegate.reconfiguredIDs.contains(message.id))
            XCTAssertEqual(backend.sentTexts, ["Next question"])
            backend.context?.updateMessage(message, animated: false, scrollToBottom: false)
            XCTAssertEqual(controls(model, message.id), [action], "A late backend update must not restore old followups")
            model.performControl(messageID: message.id, controlID: followup.id)
            XCTAssertTrue(backend.performedControls.isEmpty)
            model.performControl(messageID: message.id, controlID: action.id)
            XCTAssertEqual(backend.performedControls, [action.id])
        }
    }

    func testAResponseWithoutFollowupsDoesNotReviveEarlierSuggestions() {
        let model = BaseAgentModel(backend: SuggestionTestBackend())
        let first = response()
        let last = AgentMessage(role: .assistant, text: "Done", isStreaming: false)
        model.setTimeline([.message(first), .message(last)], animated: false)
        XCTAssertEqual(controls(model, first.id), [action])
        XCTAssertEqual(controls(model, last.id), [])
    }

    func testFollowupPillsUseTheSharedButtonAndDoNotWidenTheBubble() {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        let message = AgentMessage(role: .assistant, text: "Done", isStreaming: false, controls: [
            AgentMessageControl(id: "followup:wide", title: "Learn how to keep my wallet safe", isEnabled: true, kind: .followup)
        ])
        cell.configure(with: message, onURLTap: { _ in })
        cell.layoutIfNeeded()
        let suggestions = descendants(of: cell).compactMap { $0 as? AgentSuggestionButton }
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.bounds.height, 40)
        XCTAssertEqual(suggestions.first?.accessibilityLabel, "Learn how to keep my wallet safe")
        let bubble = descendants(of: cell).compactMap { $0 as? AgentBubbleBackgroundView }.first!
        XCTAssertLessThan(bubble.bounds.width, suggestions[0].bounds.width)

        cell.configure(with: AgentMessage(role: .assistant, text: "Next answer", isStreaming: false), onURLTap: { _ in })
        XCTAssertTrue(descendants(of: cell).compactMap { $0 as? AgentSuggestionButton }.isEmpty)
    }

    func testAnAnswerErrorWrapsOnlyAtTheBubbleWidth() {
        _ = WalletResourcesBundle.bundle.load()
        let error = "Agent could not complete the request. Please try again."
        for text in ["", "OK"] {
            let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 375, height: 300))
            cell.configure(with: AgentMessage(
                role: .assistant,
                text: text,
                isStreaming: false,
                renderingPolicy: .agentV2Safe,
                supplementaryErrorText: error
            ), onURLTap: { _ in })
            cell.layoutIfNeeded()
            let label = descendants(of: cell).compactMap { $0 as? UILabel }.first { $0.text == error }
            let bubble = descendants(of: cell).compactMap { $0 as? AgentBubbleBackgroundView }.first
            XCTAssertLessThanOrEqual(label?.bounds.height ?? .infinity, ceil((label?.font.lineHeight ?? 0) * 2) + 1, text)
            XCTAssertGreaterThan(bubble?.bounds.width ?? 0, 200, text)
        }
    }

    func testFollowupsAppearAfterStreamingRevealCompletes() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        host.view.addSubview(cell)
        var message = AgentMessage(role: .assistant, text: "Your wallet", isStreaming: true, renderingPolicy: .agentV2Safe)
        cell.configure(with: message, onURLTap: { _ in })
        cell.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        message.text = """
        **Your wallet, at a glance**

        You can review your assets, explore supported tokens, or learn how swaps work.

        A swap exchanges one token for another. Before you confirm, review the amount, network fee, and minimum amount you will receive.

        • Choose the token you want to exchange.
        • Select the token you want to receive.
        • Review the quote in your wallet.

        You stay in control of the final confirmation.
        """
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            message.text, textColor: .label, rendersMarkdown: true, detectsLinks: false,
            markdownProfile: message.renderingPolicy.markdownProfile
        )
        let layout = AgentStreamingTextLayout.make(attributedString: rendered, maxWidth: 334)
        XCTAssertGreaterThan(layout.size(forCharacterCount: layout.totalCharacterCount).width, layout.fullSize.width)
        cell.updateStreamingMessage(message)
        try await Task.sleep(for: .milliseconds(100))
        let completed = expectation(description: "Streaming reveal completed")
        completed.assertForOverFulfill = false
        cell.onStreamingRevealCompleted = { completed.fulfill() }
        message.isStreaming = false
        message.controls = [followup]
        cell.configure(with: message, onURLTap: { _ in })
        cell.layoutIfNeeded()
        await fulfillment(of: [completed], timeout: 5)
        let button = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentSuggestionButton }.first)
        XCTAssertFalse(button.superview!.isHidden)
    }

    private func response() -> AgentMessage {
        AgentMessage(role: .assistant, text: "Answer", isStreaming: false, controls: [action, followup])
    }

    private func controls(_ model: BaseAgentModel, _ id: AgentItemID) -> [AgentMessageControl] {
        guard case .message(let message) = model.item(for: id) else { return [] }
        return message.controls
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor
private final class SuggestionTestBackend: AgentBackend {
    var context: AgentBackendContext?
    var sentTexts: [String] = []
    var performedControls: [String] = []

    func attach(to context: AgentBackendContext) { self.context = context }
    func detach() { context = nil }
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
    func didSendUserMessage(_ text: String, userMessageID: AgentItemID, source: AgentBackendSendSource,
                            editContext: AgentBackendEditContext?) { sentTexts.append(text) }
    func clearConversation(completion: @escaping (Bool) -> Void) { completion(true) }
    func performControl(messageID: AgentItemID, controlID: String) { performedControls.append(controlID) }
}

@MainActor
private final class SuggestionTestDelegate: AgentModelDelegate {
    var reconfiguredIDs: [AgentItemID] = []
    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID]) {
        reconfiguredIDs += reconfigureItemIDs
    }
    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool) {}
    func agentModelDidUpdateHints(animated: Bool) {}
}
