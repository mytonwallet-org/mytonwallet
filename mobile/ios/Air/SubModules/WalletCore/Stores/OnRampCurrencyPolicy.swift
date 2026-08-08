//
//  OnRampCurrencyPolicy.swift
//  WalletCore
//

import Foundation
import WalletCoreTypes

/// Which buy-with-card currencies the iOS surface may offer: the hardcoded baseline narrowed by
/// the server-sent allowlist. Without a fetched config only the licensed currencies are offered,
/// so a stale or unreachable config can never resurrect the RUB ramp; an empty list means no
/// currencies at all, and callers must hide or refuse the entry point instead of falling back.
public enum OnRampCurrencyPolicy {

    public static let baselineCurrencies: [MBaseCurrency] = [.USD, .EUR, .RUB]
    public static let noConfigCurrencies: [MBaseCurrency] = [.USD, .EUR]

    public static func supportedCurrencies(for chain: ApiChain) -> [MBaseCurrency] {
        let configAllowed: [MBaseCurrency]
        if let allowed = ConfigStore.shared.config?.allowedOnOffRampCurrencies {
            configAllowed = allowed.compactMap { MBaseCurrency(rawValue: $0.uppercased()) }
        } else {
            configAllowed = noConfigCurrencies
        }
        // The ruble link buys GRAM and carries the TON address, so the chain config is asked which chains that
        // provider serves; naming the ones it does not would hand the ruble to every chain added later
        let isRubSupported = chain.config.canBuyWithCardInRussia
        return baselineCurrencies.filter { configAllowed.contains($0) && ($0 != .RUB || isRubSupported) }
    }

    /// The chain an entry point that carries no chain of its own ends up buying on: the account's first chain the
    /// ramp actually serves. Answering with the first chain outright would offer a button whose tap then refuses,
    /// so the gate and the screen both read this. Nil means the account has nothing to buy on.
    public static func defaultChain(for account: MAccount) -> ApiChain? {
        ApiChain.allCases.first {
            account.supports(chain: $0) && $0.isOnrampSupported && !supportedCurrencies(for: $0).isEmpty
        }
    }

    /// Which currency a surface starts on: the first listed preference still offered, or the first offered
    /// currency when no preference survives. Nil means nothing is offered and the caller must refuse the
    /// entry point - naming a currency of its own here is what lets the app offer one the server withdrew.
    public static func preferredCurrency(for chain: ApiChain, preferences: [MBaseCurrency]) -> MBaseCurrency? {
        let supported = supportedCurrencies(for: chain)
        return preferences.first { supported.contains($0) } ?? supported.first
    }
}
