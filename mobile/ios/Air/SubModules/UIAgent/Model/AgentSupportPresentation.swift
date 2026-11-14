import WalletContext
import WalletCore

/// What live support changes in the chat, as Classic shows it: the authors over the answers once an operator has
/// joined, the header's subtitle and the field's placeholder while support has the chat, and the chat list's label
@MainActor
enum AgentSupportPresentation {
    /// The label of a chat with support in the chat list: bright while an operator is in it, muted while it waits
    enum LabelStyle: Equatable {
        case active
        case muted
    }

    /// An operator has joined the chat: a reply of theirs or the line of their joining is in it
    static func checkAuthorsShown(in messages: [AgentV2NativeMessage]) -> Bool {
        messages.contains { $0.role == .operator || $0.supportEvent?.isOperatorJoined == true }
    }

    /// The chat's support as its list row knows it, without the operator's name
    static func getState(for support: ApiAgentV2ThreadSupport?) -> AgentSupportState {
        switch support?.state {
        case .waiting?: .waiting
        case .operator?: .operator(nil)
        case .closed?: .closed
        case nil: .none
        }
    }

    static func getSubtitle(for state: AgentSupportState) -> String? {
        switch state {
        case .waiting:
            lang("$agent_support_waiting")
        case .operator(let author?):
            L10n.agentSupportWithOperator(name: author.name)
        case .operator(nil):
            lang("$agent_support_label")
        case .none, .closed:
            nil
        }
    }

    static func getComposerPlaceholder(for state: AgentSupportState) -> String {
        state.isActive ? lang("$agent_support_placeholder") : lang("Ask anything")
    }

    static func getLabelStyle(for support: ApiAgentV2ThreadSupport?) -> LabelStyle? {
        switch support?.state {
        case .operator?: .active
        case .waiting?: .muted
        case .closed?, nil: nil
        }
    }
}
