import Foundation

public enum AgentBackendKind: String, CaseIterable {
    case testing
    case real
    case local
    case hybrid
    
    static var menuOrder: [Self] { [.real, .local, .hybrid, .testing] }

    var menuTitle: String {
        switch self {
        case .testing:
            "Mock"
        case .real:
            "Live"
        case .local:
            "Local (On-Device)"
        case .hybrid:
            "Hybrid"
        }
    }
}

struct AgentBackendConversationMessage {
    enum Role {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

struct AgentBackendParsedMessage {
    let text: String
    let action: AgentMessageAction?
}

struct AgentBackendEditContext {
    let originalText: String
    let history: [AgentBackendConversationMessage]
}

enum AgentBackendMessages {
    static let unavailableMessage = "Agent backend is not configured yet."
    static let emptyResponseMessage = "The Agent returned an empty response."
    static let fallbackErrorMessage = "Something went wrong. Please try again."
}

@MainActor
protocol AgentBackend: AnyObject {
    var kind: AgentBackendKind { get }

    func attach(to context: AgentBackendContext)
    func detach()
    func loadHints(animated: Bool)
    func prepareForEditing(_ editContext: AgentBackendEditContext)
    func didSendUserMessage(_ text: String, editContext: AgentBackendEditContext?)
    func reset()
}

extension AgentBackend {
    private static var trailingMessageCharacters: CharacterSet {
        CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "\u{00A0}\u{200B}\u{200C}\u{200D}\u{FEFF}")
        )
    }

    static func parseMessage(_ rawText: String) -> AgentBackendParsedMessage {
        let trimmedText = rawText.trimmingCharacters(in: trailingMessageCharacters)
        guard let match = AgentActionLinkMatcher.deeplinkRegex.matches(
            in: trimmedText,
            options: [],
            range: NSRange(trimmedText.startIndex..., in: trimmedText)
        ).last else {
            return AgentBackendParsedMessage(text: trimmedText, action: nil)
        }

        guard let fullRange = Range(match.range(at: 0), in: trimmedText),
              let titleRange = Range(match.range(at: 1), in: trimmedText),
              let urlRange = Range(match.range(at: 2), in: trimmedText) else {
            return AgentBackendParsedMessage(text: trimmedText, action: nil)
        }

        let title = String(trimmedText[titleRange])
        let urlString = String(trimmedText[urlRange])
        guard let url = URL(string: urlString) else {
            return AgentBackendParsedMessage(text: trimmedText, action: nil)
        }

        var messageText = trimmedText
        messageText.removeSubrange(fullRange)
        messageText = messageText.trimmingCharacters(in: trailingMessageCharacters)

        return AgentBackendParsedMessage(
            text: messageText,
            action: AgentMessageAction(title: title, url: url)
        )
    }

    static func streamingFrames(for text: String) -> [String] {
        var frames: [String] = []
        var currentText = ""
        var charactersSinceFrame = 0

        for character in text {
            currentText.append(character)
            charactersSinceFrame += 1

            let shouldFlush = charactersSinceFrame >= streamingFlushThreshold(emittedCharacterCount: currentText.count)
                || character.isSentenceBoundary
                || character == "\n"
            if shouldFlush {
                frames.append(currentText)
                charactersSinceFrame = 0
            }
        }

        if frames.last != currentText {
            frames.append(currentText)
        }

        return frames
    }

    static func streamingDelay(frameIndex: Int, frame: String) -> Duration {
        let slowStartCharacterCount = 110
        let accelerationCharacterSpan = 320
        let baseMilliseconds = frame.last?.isSentenceBoundary == true ? 140.0 : 70.0
        let excess = max(0, frame.count - slowStartCharacterCount)
        let ramp = min(1.0, Double(excess) / Double(accelerationCharacterSpan))
        let factor = 1.0 - (0.7 * ramp)
        return .milliseconds(Int((baseMilliseconds * factor).rounded(.up)))
    }

    private static func streamingFlushThreshold(emittedCharacterCount: Int) -> Int {
        let slowStartCharacterCount = 110
        let initialFlushThreshold = 6
        let maxFlushThreshold = 40
        guard emittedCharacterCount > slowStartCharacterCount else {
            return initialFlushThreshold
        }
        let excess = emittedCharacterCount - slowStartCharacterCount
        return min(maxFlushThreshold, initialFlushThreshold + excess / 14)
    }
}

private extension Character {
    var isSentenceBoundary: Bool {
        self == "." || self == "!" || self == "?"
    }
}

@MainActor
final class AgentBackendContext {
    private let replaceTimelineHandler: ([AgentTimelineItem], Bool) -> Void
    private let setHintsHandler: ([AgentHint], Bool) -> Void
    private let replaceItemHandler: (AgentItemID, AgentTimelineItem, Bool) -> Void
    private let appendHandler: (AgentTimelineItem, Bool) -> Void
    private let removeHandler: (AgentItemID, Bool) -> Void
    private let updateMessageHandler: (AgentMessage, Bool, Bool) -> Void
    private let messageProvider: (AgentItemID) -> AgentMessage?
    private let itemIDsProvider: () -> [AgentItemID]

    init(
        replaceTimelineHandler: @escaping ([AgentTimelineItem], Bool) -> Void,
        setHintsHandler: @escaping ([AgentHint], Bool) -> Void,
        replaceItemHandler: @escaping (AgentItemID, AgentTimelineItem, Bool) -> Void,
        appendHandler: @escaping (AgentTimelineItem, Bool) -> Void,
        removeHandler: @escaping (AgentItemID, Bool) -> Void,
        updateMessageHandler: @escaping (AgentMessage, Bool, Bool) -> Void,
        messageProvider: @escaping (AgentItemID) -> AgentMessage?,
        itemIDsProvider: @escaping () -> [AgentItemID]
    ) {
        self.replaceTimelineHandler = replaceTimelineHandler
        self.setHintsHandler = setHintsHandler
        self.replaceItemHandler = replaceItemHandler
        self.appendHandler = appendHandler
        self.removeHandler = removeHandler
        self.updateMessageHandler = updateMessageHandler
        self.messageProvider = messageProvider
        self.itemIDsProvider = itemIDsProvider
    }

    var itemIDs: [AgentItemID] {
        itemIDsProvider()
    }

    func replaceTimeline(with items: [AgentTimelineItem], animated: Bool) {
        replaceTimelineHandler(items, animated)
    }

    func setHints(_ hints: [AgentHint], animated: Bool) {
        setHintsHandler(hints, animated)
    }

    func append(_ item: AgentTimelineItem, animated: Bool) {
        appendHandler(item, animated)
    }

    func replaceItem(id: AgentItemID, with item: AgentTimelineItem, animated: Bool) {
        replaceItemHandler(id, item, animated)
    }

    func removeItem(id: AgentItemID, animated: Bool) {
        removeHandler(id, animated)
    }

    func updateMessage(_ message: AgentMessage, animated: Bool, scrollToBottom: Bool) {
        updateMessageHandler(message, animated, scrollToBottom)
    }

    func message(for id: AgentItemID) -> AgentMessage? {
        messageProvider(id)
    }
}
