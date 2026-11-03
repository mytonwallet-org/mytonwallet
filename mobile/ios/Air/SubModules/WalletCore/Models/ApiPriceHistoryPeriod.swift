
import Foundation
import WalletContext

public enum ApiPriceHistoryPeriod: String, CaseIterable, Equatable, Hashable, Codable, Sendable {
    case day = "1D"
    case week = "7D"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "ALL"
    
    /// A cached chart whose newest point is older than this is not shown.
    public var maxCacheAge: TimeInterval {
        switch self {
        case .day:
            3 * 3600
        case .week:
            24 * 3600
        case .month:
            4 * 86400
        case .threeMonths:
            12 * 86400
        case .year, .all:
            45 * 86400
        }
    }

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
