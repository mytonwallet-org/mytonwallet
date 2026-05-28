
import Foundation
import WalletContext
import WalletCore

extension MBaseCurrency {
    public var nameStringResource: LocalizedStringResource {
        switch self {
        case .USD:
            return LocalizedStringResource("US Dollar", bundle: LocalizationSupport.shared.bundle)
        case .EUR:
            return LocalizedStringResource("Euro", bundle: LocalizationSupport.shared.bundle)
        case .RUB:
            return LocalizedStringResource("Russian Ruble", bundle: LocalizationSupport.shared.bundle)
        case .CNY:
            return LocalizedStringResource("Chinese Yuan", bundle: LocalizationSupport.shared.bundle)
        case .BTC:
            return LocalizedStringResource("Bitcoin", bundle: LocalizationSupport.shared.bundle)
        case .TON:
            return LocalizedStringResource("Toncoin", bundle: LocalizationSupport.shared.bundle)
        }
    }
}
