import Foundation
import WalletContext

public enum HomeWalletVisibleTokensLimit: Int, CaseIterable, Equatable, Sendable {
    case top5 = 5
    case top10 = 10
    case top30 = 30

    public static let defaultValue: Self = .top5

    public init(storedValue: Int) {
        self = Self(rawValue: storedValue) ?? .defaultValue
    }

    public var title: String {
        switch self {
        case .top5:
            localizedIntegerDigits(in: lang("Top 5"))
        case .top10:
            localizedIntegerDigits(in: lang("Top 10"))
        case .top30:
            localizedIntegerDigits(in: lang("Top 30"))
        }
    }
}
