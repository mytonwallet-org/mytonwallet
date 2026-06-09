import UIKit
import WalletContext
import WalletCoreTypes

public extension ApiChain {
    var isOnrampSupported: Bool {
        guard isSupported, config.isOnRampSupported else { return false }
        return config.canBuyWithCardInRussia || ConfigStore.shared.config?.countryCode != "RU"
    }

    var image: UIImage {
        UIImage(named: "chain_\(rawValue)", in: AirBundle, compatibleWith: nil)
            ?? UIImage(named: "chain_\(FALLBACK_CHAIN.rawValue)", in: AirBundle, compatibleWith: nil)!
    }

    func isValidAddressOrDomain(_ addressOrDomain: String) -> Bool {
        guard isSupported else { return false }
        return config.addressRegex.matches(addressOrDomain) || isValidDomain(addressOrDomain)
    }

    func isValidDomain(_ domain: String) -> Bool {
        guard isSupported else { return false }
        return config.isDnsSupported && DNSHelpers.isDnsDomain(domain)
    }
}
