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

    /// The day as the chat names it, "Today" or the month and day, with the year for another year, and the time
    static func formatChatDate(for timestamp: Date) -> (date: String, time: String) {
        let locale = LocalizationSupport.shared.locale
        let now = Date()
        let dateText: String
        if now.isInSameDay(as: timestamp) {
            dateText = lang("Today")
        } else if now.isInSameYear(as: timestamp) {
            dateText = timestamp.formatted(.localizedDateTime.month(.wide).day())
        } else {
            dateText = timestamp.formatted(.localizedDateTime.year(.defaultDigits).month(.wide).day())
        }
        return (dateText, Self.formattedTime(timestamp, locale: locale))
    }
}
