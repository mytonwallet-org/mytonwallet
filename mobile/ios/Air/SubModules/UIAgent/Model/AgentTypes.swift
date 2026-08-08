import Foundation

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
}

struct AgentMessage {
    enum Role: String {
        case assistant
        case system
        case user
    }

    enum SystemStyle {
        case dateTime(date: String, time: String)
        case accountChange
    }

    let id: AgentItemID
    let role: Role
    var text: String
    var timestamp: Date
    var isStreaming: Bool
    var action: AgentMessageAction? = nil
    var systemStyle: SystemStyle? = nil

    init(
        id: AgentItemID = UUID(),
        role: Role,
        text: String,
        isStreaming: Bool,
        action: AgentMessageAction? = nil,
        systemStyle: SystemStyle? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.action = action
        self.systemStyle = systemStyle
    }
    
    var isDateTimeSystemMessage: Bool {
        if case .dateTime? = systemStyle {
            return true
        }
        return false
    }

    var isAccountChangeSystemMessage: Bool {
        if case .accountChange? = systemStyle {
            return true
        }
        return false
    }
}

struct AgentMessageAction {
    let title: String
    let url: URL
}

struct AgentTypingIndicator {
    let id: AgentItemID = UUID()
}

