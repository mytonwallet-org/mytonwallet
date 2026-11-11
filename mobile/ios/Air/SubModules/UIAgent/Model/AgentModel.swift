import Foundation
import WalletContext

class AgentModel: BaseAgentModel {
    var chatTitleText: String { lang("Agent") }
    var chatIcon: String? { nil }
    var chatTitle: String {
        if let chatIcon {
            return "\(chatIcon) \(chatTitleText)"
        }
        return chatTitleText
    }

    override func formattedDate(for timestamp: Date) -> (date: String, time: String) {
        Self.formatChatDate(for: timestamp)
    }

    /// The day as the chat's date lines name it, "Today", "Yesterday" or the day and month, with the year for another
    /// year, and the time on the device's clock
    static func formatChatDate(for timestamp: Date, relativeTo now: Date = .now) -> (date: String, time: String) {
        (
            AgentThreadDateFormatting.formatDay(for: timestamp, relativeTo: now),
            Self.formattedTime(timestamp, locale: LocalizationSupport.shared.locale)
        )
    }
}
