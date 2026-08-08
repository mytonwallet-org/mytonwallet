import Foundation
import Testing
import WalletCoreTypes
@testable import WalletCore

@Suite("On-Ramp Currency Policy", .serialized)
struct OnRampCurrencyPolicyTests {

    private func setConfig(json: String?) throws {
        if let json {
            ConfigStore.shared.config = try JSONDecoder().decode(ApiUpdate.UpdateConfig.self, from: Data(json.utf8))
        } else {
            ConfigStore.shared.config = nil
        }
    }

    @Test
    func `absent config falls back to the licensed currencies only`() throws {
        try setConfig(json: nil)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton) == [.USD, .EUR])
    }

    @Test
    func `config without the field falls back to the licensed currencies only`() throws {
        try setConfig(json: #"{"isLimited": false}"#)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton) == [.USD, .EUR])
    }

    @Test
    func `allowed list with rub restores the full baseline on ton`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"]}"#)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton) == [.USD, .EUR, .RUB])
    }

    /// The ruble link buys GRAM and carries the TON address, so spending rubles from any other chain would
    /// deliver an asset the user did not pick. Every chain has to stay out, not only the ones known today.
    @Test
    func `rub is never offered off ton regardless of the allowed list`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"]}"#)
        for chain in ApiChain.allCases where !chain.config.canBuyWithCardInRussia {
            #expect(OnRampCurrencyPolicy.supportedCurrencies(for: chain) == [.USD, .EUR])
        }
        #expect(ApiChain.allCases.filter(\.config.canBuyWithCardInRussia) == [.ton])
    }

    @Test
    func `empty allowed list yields no currencies`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": []}"#)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton).isEmpty)
    }

    @Test
    func `malformed allowed list decodes as nil and stays fail closed`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": "rub"}"#)
        #expect(ConfigStore.shared.config?.allowedOnOffRampCurrencies == nil)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton) == [.USD, .EUR])
    }

    @Test
    func `narrowing a previously wider config takes effect immediately`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"]}"#)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton).contains(.RUB))
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur"]}"#)
        #expect(!OnRampCurrencyPolicy.supportedCurrencies(for: .ton).contains(.RUB))
    }

    @Test
    func `preferred currency takes the first offered preference`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"]}"#)
        #expect(OnRampCurrencyPolicy.preferredCurrency(for: .ton, preferences: [.RUB, .USD]) == .RUB)
    }

    @Test
    func `preferred currency skips a preference the config withdrew`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur"]}"#)
        #expect(OnRampCurrencyPolicy.preferredCurrency(for: .ton, preferences: [.RUB, .EUR]) == .EUR)
    }

    @Test
    func `preferred currency never answers outside the offered set`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["eur"]}"#)
        #expect(OnRampCurrencyPolicy.preferredCurrency(for: .ton, preferences: [.USD]) == .EUR)
    }

    @Test
    func `preferred currency answers nothing when nothing is offered`() throws {
        try setConfig(json: #"{"allowedOnOffRampCurrencies": []}"#)
        #expect(OnRampCurrencyPolicy.preferredCurrency(for: .ton, preferences: [.USD, .EUR]) == nil)
    }

    @Test
    func `the cached copy of the config carries no ramp allowlist`() throws {
        let config = try JSONDecoder().decode(
            ApiUpdate.UpdateConfig.self,
            from: Data(#"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"], "countryCode": "RU"}"#.utf8)
        )
        #expect(config.allowedOnOffRampCurrencies == ["usd", "eur", "rub"])

        let cacheable = ConfigStore.cacheableConfig(config)
        #expect(cacheable.allowedOnOffRampCurrencies == nil)
        // The rest of the config still has to survive a restart
        #expect(cacheable.countryCode == "RU")
    }

    @Test
    func `a restored config cannot resurrect a withdrawn currency`() throws {
        let fetched = try JSONDecoder().decode(
            ApiUpdate.UpdateConfig.self,
            from: Data(#"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"]}"#.utf8)
        )
        let roundTripped = try JSONDecoder().decode(
            ApiUpdate.UpdateConfig.self,
            from: JSONEncoder().encode(ConfigStore.cacheableConfig(fetched))
        )

        ConfigStore.shared.config = roundTripped
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton) == [.USD, .EUR])
    }
}
