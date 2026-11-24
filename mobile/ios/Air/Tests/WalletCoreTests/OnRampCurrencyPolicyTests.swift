import Foundation
import Testing
import WalletCoreTypes
@testable import WalletCore

@Suite("On-Ramp Currency Policy", .serialized)
final class OnRampCurrencyPolicyTests {

    // Every test bundle shares the preferences of the test runner, so a config left here limits the suites run next
    deinit {
        ConfigStore.shared.clean()
        _ = ConfigStore.shared.config
    }

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

    @Test(arguments: [
        (#"["cardOnRamp"]"#, [MBaseCurrency.RUB]),
        (#"["rubOnRamp"]"#, [.USD, .EUR]),
        (#"["cardOnRamp", "rubOnRamp"]"#, []),
        (#"[]"#, [.USD, .EUR, .RUB]),
    ])
    func `the list of restricted features closes card and ruble buying apart`(
        restricted: String, offered: [MBaseCurrency]
    ) throws {
        ConfigStore.shared.isLimitedOverride = nil
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"], "restrictedFeatures": \#(restricted)}"#)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton) == offered)
    }

    @Test
    func `an account has nothing to buy on once both ways to buy are restricted`() throws {
        ConfigStore.shared.isLimitedOverride = nil
        let account = MAccount(id: "1-mainnet", title: nil, type: .mnemonic, byChain: [.ton: .init(address: "ton")])
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"], "restrictedFeatures": []}"#)
        #expect(OnRampCurrencyPolicy.defaultChain(for: account) == .ton)
        try setConfig(json: #"{"allowedOnOffRampCurrencies": ["usd", "eur", "rub"], "restrictedFeatures": ["cardOnRamp", "rubOnRamp"]}"#)
        #expect(OnRampCurrencyPolicy.defaultChain(for: account) == nil)
    }

    @Test(arguments: [
        (#"{"isLimited": true, "allowedOnOffRampCurrencies": ["usd", "eur", "rub"]}"#, [MBaseCurrency]()),
        (#"{"isLimited": true, "isSwapAndOnRampLimited": false, "allowedOnOffRampCurrencies": ["usd", "eur", "rub"]}"#,
         [.USD, .EUR, .RUB]),
    ])
    func `without the list the older limit flags decide what can be bought`(json: String, offered: [MBaseCurrency]) throws {
        ConfigStore.shared.isLimitedOverride = nil
        try setConfig(json: json)
        #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ton) == offered)
    }
}
