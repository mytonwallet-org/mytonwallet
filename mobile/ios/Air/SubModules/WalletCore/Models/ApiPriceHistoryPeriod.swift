
import Foundation
import WalletContext

public enum ApiPriceHistoryPeriod: String, CaseIterable, Equatable, Hashable, Codable, Sendable {
    case day = "1D"
    case week = "7D"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "ALL"
    
    public var localized: String {
        switch self {
        case .day:
            lang("D")
        case .week:
            lang("W")
        case .month:
            lang("M")
        case .threeMonths:
            lang("3M")
        case .year:
            lang("Y")
        case .all:
            lang("All")
        }
    }
}
