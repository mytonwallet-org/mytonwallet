import Foundation
import WalletContext
import WalletCore

typealias AgentItemID = UUID

enum AgentTimelineItem {
    case message(AgentMessage)
    case typingIndicator(AgentTypingIndicator)

    var id: AgentItemID {
        switch self {
        case .message(let message):
            message.id
        case .typingIndicator(let indicator):
            indicator.id
        }
    }
}

struct AgentHint: Decodable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let prompt: String
    let catalogVersion: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        prompt: String,
        catalogVersion: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.prompt = prompt
        self.catalogVersion = catalogVersion
    }
}

extension AgentHint {
    private static let supportRequestID = "client.supportRequest"

    /// Contact Support, which the client adds after the server's suggestions
    static var supportRequest: AgentHint {
        AgentHint(id: supportRequestID, title: lang("$agent_support_contact"), subtitle: "", prompt: "")
    }

    var isSupportRequest: Bool {
        id == Self.supportRequestID
    }
}

struct AgentMessageControl: Hashable {
    enum Kind: Hashable {
        case action
        case followup
    }

    let id: String
    let title: String
    let isEnabled: Bool
    var kind: Kind = .action
}

enum AgentMessageRenderingPolicy: Equatable {
    case classic
    case agentV2Safe

    var markdownProfile: AgentMessageMarkdownProfile {
        switch self {
        case .classic:
            .legacy
        case .agentV2Safe:
            .agentMarkdownV1
        }
    }

    var allowsLinks: Bool {
        switch self {
        case .classic:
            true
        case .agentV2Safe:
            false
        }
    }
}

enum AgentSupportState: Equatable, Sendable {
    case none
    case waiting
    case `operator`(ApiAgentV2OperatorAuthor?)
    case closed

    var isActive: Bool {
        switch self {
        case .waiting, .operator: true
        case .none, .closed: false
        }
    }
}

enum AgentSupportEvent: Equatable, Sendable {
    case supportRequested
    case operatorJoined(ApiAgentV2OperatorAuthor)
    case supportClosed(ApiAgentV2SupportClosedReason)

    var text: String {
        switch self {
        case .supportRequested: lang("$agent_support_requested")
        case .operatorJoined(let author): L10n.agentSupportOperatorJoined(name: author.name)
        case .supportClosed(.operator): lang("$agent_support_closed_operator")
        case .supportClosed(.inactivity): lang("$agent_support_closed_inactivity")
        }
    }

    var isOperatorJoined: Bool {
        if case .operatorJoined = self { return true }
        return false
    }
}

struct AgentMessage {
    enum Author: Equatable, Sendable {
        case user
        case agent
        case `operator`(ApiAgentV2OperatorAuthor)
    }

    enum Role: String {
        case assistant
        case system
        case user
    }

    enum SystemStyle {
        case dateTime(date: String, time: String)
        /// A News day's capsule, naming the day alone, as the feed's posts show their own times
        case day
        /// A failure the chat shows as a caption, with its controls as links after the text
        case failure
    }

    let id: AgentItemID
    let role: Role
    var author: Author
    var supportEvent: AgentSupportEvent? = nil
    var isPlainText = false
    var isEditingDisabled = false
    /// The author shows over the answer, as in a chat an operator has joined
    var shouldShowAuthor = false
    var answerBlocks: [AgentMessageBlock]? = nil
    var text: String
    var timestamp: Date
    var isStreaming: Bool
    var responseLanguage: String? = nil
    var semanticContent: ApiAgentV2SemanticContent? = nil
    var controls: [AgentMessageControl] = []
    var renderingPolicy: AgentMessageRenderingPolicy = .classic
    var supplementaryErrorText: String? = nil
    var systemStyle: SystemStyle? = nil
    /// The answer is stored as complete, so the user can rate it
    var canRate = false
    var feedback: ApiAgentV2AnswerFeedback? = nil
    var newsPost = false

    init(
        id: AgentItemID = UUID(),
        role: Role,
        text: String,
        isStreaming: Bool,
        responseLanguage: String? = nil,
        semanticContent: ApiAgentV2SemanticContent? = nil,
        controls: [AgentMessageControl] = [],
        newsPost: Bool = false,
        renderingPolicy: AgentMessageRenderingPolicy = .classic,
        supplementaryErrorText: String? = nil,
        systemStyle: SystemStyle? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        author = role == .user ? .user : .agent
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.responseLanguage = responseLanguage
        self.semanticContent = semanticContent
        self.controls = controls
        self.renderingPolicy = renderingPolicy
        self.supplementaryErrorText = supplementaryErrorText
        self.systemStyle = systemStyle
        self.newsPost = newsPost
    }

    var isDateTimeSystemMessage: Bool {
        if case .dateTime? = systemStyle {
            return true
        }
        return false
    }

    /// A line that heads the rows of a date, which VoiceOver finds as a heading
    var isDateLine: Bool {
        switch systemStyle {
        case .dateTime?, .day?:
            true
        case .failure?, nil:
            false
        }
    }

    /// A News day, which shows as Telegram's date bubble
    var isDayCapsule: Bool {
        if case .day? = systemStyle {
            return true
        }
        return false
    }

    var isFailureCaption: Bool {
        if case .failure? = systemStyle {
            return true
        }
        return false
    }

}

struct AgentTypingIndicator {
    let id: AgentItemID = UUID()
}
