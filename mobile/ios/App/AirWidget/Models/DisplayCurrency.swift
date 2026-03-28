import Foundation

extension MBaseCurrency {
    public var nameStringResource: LocalizedStringResource {
        switch self {
        case .USD:
            return "US Dollar"
        case .EUR:
            return "Euro"
        case .RUB:
            return "Russian Ruble"
        case .CNY:
            return "Chinese Yuan"
        case .BTC:
            return "Bitcoin"
        case .TON:
            return "Toncoin"
        }
    }
}
