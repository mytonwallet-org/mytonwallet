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
            dateText = timestamp.formatted(.localizedDateTime.month(.wide).day())
        } else {
            dateText = timestamp.formatted(.localizedDateTime.year(.defaultDigits).month(.wide).day())
        }
        return (dateText, Self.formattedTime(timestamp, locale: locale))
    }
}
