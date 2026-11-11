import Foundation
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

struct AgentMessage {
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
