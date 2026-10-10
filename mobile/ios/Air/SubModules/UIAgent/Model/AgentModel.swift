import Foundation
import WalletContext

class AgentModel: BaseAgentModel {
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
        return (dateText, Self.formattedTime(timestamp, locale: locale))
    }
}
