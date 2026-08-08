import Foundation
import WalletContext
import WalletCore

class AgentModel: BaseAgentModel {
    
    private var currentAccountID: String? = AccountStore.accountId
    
    func checkAccountChanged(animated: Bool) {
        let newAccountID = AccountStore.accountId
        guard newAccountID != currentAccountID else { return }
        currentAccountID = newAccountID

        guard hasConversationMessages,
              let newAccountID,
              let account = AccountStore.accountsById[newAccountID] else {
            return
        }

        appendOrCoalesceAccountChangedMessage(for: account, animated: animated)
    }
    
    private func appendOrCoalesceAccountChangedMessage(for account: MAccount, animated: Bool) {
        var baseItems = baseTimelineItems
        let message = AgentMessage(
            role: .system,
            text: lang("Switched to %@", arg1: account.displayName),
            isStreaming: false,
            systemStyle: .accountChange
        )

        if case .message(let lastMessage)? = baseItems.last,
           lastMessage.isAccountChangeSystemMessage {
            baseItems[baseItems.count - 1] = .message(message)
        } else {
            baseItems.append(.message(message))
        }

        setTimeline(baseItems, animated: animated)
    }

    func handleAccountChangedEvent(animated: Bool = true) {
        guard isActive else { return }
        checkAccountChanged(animated: animated)
    }
    
    override func persistStableTimelineIfNeeded(messages: [AgentMessage]) {
        AgentStore.shared.saveHistory(messages: messages)
    }
    
    override func loadPersistedTimeline() -> [AgentTimelineItem] {
        AgentStore.shared.persistedTimelineItems()
    }

    override func formattedDate(for timestamp: Date) -> (date: String, time: String) {
        let locale = LocalizationSupport.shared.locale
        let now = Date()
        let dateText: String
        if now.isInSameDay(as: timestamp) {
            dateText = lang("Today")
        } else if now.isInSameYear(as: timestamp) {
            dateText = timestamp.formatted(.dateTime.month(.wide).day().locale(locale))
        } else {
            dateText = timestamp.formatted(.dateTime.year(.defaultDigits).month(.wide).day().locale(locale))
        }
        let timeText = timestamp.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .omitted))
                .minute()
                .locale(locale)
        )
        return (dateText, timeText)
    }
    
    static func makeBackend(kind: AgentBackendKind) -> AgentBackend {
        switch kind {
        case .testing:
            AgentTestingBackend()
        case .real:
            AgentRealBackend()
        case .local:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AgentStore.shared.isLocalBackendAvailable {
                AgentLocalBackend()
            } else {
                AgentRealBackend()
            }
            #else
            AgentRealBackend()
            #endif
        case .hybrid:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AgentStore.shared.isLocalBackendAvailable {
                AgentHybridBackend()
            } else {
                AgentRealBackend()
            }
            #else
            AgentRealBackend()
            #endif
        }
    }
}
