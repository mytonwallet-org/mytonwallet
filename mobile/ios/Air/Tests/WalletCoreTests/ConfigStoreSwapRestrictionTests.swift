import Foundation
import Testing
@testable import WalletCore

// Nested under the on-ramp suite so its `.serialized` trait covers both: they write the same shared ConfigStore.
extension OnRampCurrencyPolicyTests {
@Suite("Config Store Swap Restriction")
final class ConfigStoreSwapRestrictionTests {

    deinit {
        ConfigStore.shared.clean()
        _ = ConfigStore.shared.config
    }

    @Test(arguments: [
        (#"{"isAgentSupportEnabled": true}"#, true as Bool?),
        (#"{"isAgentSupportEnabled": false}"#, false as Bool?),
        (#"{}"#, nil as Bool?),
        (#"{"isAgentSupportEnabled": "true"}"#, nil as Bool?),
        (#"{"isAgentSupportEnabled": 1}"#, nil as Bool?),
    ])
    func `agent support accepts only booleans and survives config caching`(json: String, isEnabled: Bool?) throws {
        let config = try JSONDecoder().decode(ApiUpdate.UpdateConfig.self, from: Data(json.utf8))
        #expect(config.isAgentSupportEnabled == isEnabled)

        let restored = try JSONDecoder().decode(
            ApiUpdate.UpdateConfig.self,
            from: JSONEncoder().encode(ConfigStore.cacheableConfig(config))
        )
        #expect(restored.isAgentSupportEnabled == isEnabled)
    }

    private func setConfig(json: String) throws {
        ConfigStore.shared.isLimitedOverride = nil
        ConfigStore.shared.config = try JSONDecoder().decode(ApiUpdate.UpdateConfig.self, from: Data(json.utf8))
    }

    @Test
    func `the narrower field opens swaps and on-ramp while every other limit stays`() throws {
        try setConfig(json: #"{"isLimited": true, "isSwapAndOnRampLimited": false}"#)
        #expect(ConfigStore.shared.isRestricted(.dexSwap) == false)
        #expect(ConfigStore.shared.shouldRestrictSell)
        #expect(ConfigStore.shared.shouldRestrictBuyNfts)
        #expect(ConfigStore.shared.shouldRestrictSites)
    }

    @Test
    func `a backend without the field keeps swaps on isLimited`() throws {
        try setConfig(json: #"{"isLimited": true}"#)
        #expect(ConfigStore.shared.isRestricted(.dexSwap))
    }

    @Test
    func `a malformed field reads as absent`() throws {
        try setConfig(json: #"{"isLimited": true, "isSwapAndOnRampLimited": "no"}"#)
        #expect(ConfigStore.shared.isRestricted(.dexSwap))
    }

    @Test
    func `the debug override still limits swaps`() throws {
        try setConfig(json: #"{"isLimited": false, "isSwapAndOnRampLimited": false}"#)
        ConfigStore.shared.isLimitedOverride = true
        defer { ConfigStore.shared.isLimitedOverride = nil }
        #expect(ConfigStore.shared.isRestricted(.dexSwap))
    }

    @Test
    func `the list decides each feature on its own`() throws {
        try setConfig(json: #"{"isLimited": true, "isSwapAndOnRampLimited": true, "restrictedFeatures": ["dexSwap", "offRamp"]}"#)
        #expect(ConfigStore.shared.isRestricted(.dexSwap))
        #expect(ConfigStore.shared.isRestricted(.offRamp))
        #expect(!ConfigStore.shared.isRestricted(.cexSwap))
        #expect(!ConfigStore.shared.isRestricted(.nftPurchase))
        #expect(!ConfigStore.shared.shouldRestrictSwaps)
        #expect(ConfigStore.shared.shouldRestrictSell)
        #expect(!ConfigStore.shared.shouldRestrictBuyNfts)
        #expect(!ConfigStore.shared.shouldRestrictSites)
    }

    @Test
    func `the swap entry closes only when all three swap kinds are restricted`() throws {
        try setConfig(json: #"{"isLimited": false, "restrictedFeatures": ["dexSwap", "crossChainSwap"]}"#)
        #expect(!ConfigStore.shared.shouldRestrictSwaps)
        try setConfig(json: #"{"isLimited": false, "restrictedFeatures": ["dexSwap", "crossChainSwap", "cexSwap"]}"#)
        #expect(ConfigStore.shared.shouldRestrictSwaps)
    }

    @Test
    func `the buy entry closes only when both ways to buy are restricted`() throws {
        try setConfig(json: #"{"isLimited": false, "restrictedFeatures": ["cardOnRamp"]}"#)
        #expect(!ConfigStore.shared.shouldRestrictOnRamp)
        try setConfig(json: #"{"isLimited": false, "restrictedFeatures": ["cardOnRamp", "rubOnRamp"]}"#)
        #expect(ConfigStore.shared.shouldRestrictOnRamp)
    }

    @Test
    func `an empty list opens everything whatever the old flags say`() throws {
        try setConfig(json: #"{"isLimited": true, "isSwapAndOnRampLimited": true, "restrictedFeatures": []}"#)
        for feature in RestrictedFeature.allCases { #expect(!ConfigStore.shared.isRestricted(feature)) }
    }

    @Test
    func `without the list the old flags decide`() throws {
        try setConfig(json: #"{"isLimited": true, "isSwapAndOnRampLimited": false}"#)
        #expect(!ConfigStore.shared.isRestricted(.dexSwap))
        #expect(!ConfigStore.shared.isRestricted(.cardOnRamp))
        #expect(ConfigStore.shared.isRestricted(.offRamp))
        #expect(ConfigStore.shared.isRestricted(.nftPurchase))
        #expect(ConfigStore.shared.isRestricted(.exploreSites))
    }

    @Test(arguments: [#""all""#, #"[1, 2]"#, #"{"dexSwap": true}"#])
    func `a malformed list reads as absent`(value: String) throws {
        try setConfig(json: #"{"isLimited": true, "restrictedFeatures": \#(value)}"#)
        #expect(ConfigStore.shared.isRestricted(.exploreSites))
        #expect(ConfigStore.shared.isRestricted(.dexSwap))
    }

    @Test
    func `an unknown name in the list is ignored`() throws {
        try setConfig(json: #"{"isLimited": false, "restrictedFeatures": ["staking", "cexSwap"]}"#)
        #expect(ConfigStore.shared.isRestricted(.cexSwap))
        #expect(!ConfigStore.shared.isRestricted(.dexSwap))
    }

    @Test
    func `the list survives config caching`() throws {
        let config = try JSONDecoder().decode(
            ApiUpdate.UpdateConfig.self,
            from: Data(#"{"restrictedFeatures": ["offRamp"]}"#.utf8)
        )
        #expect(ConfigStore.cacheableConfig(config).restrictedFeatures == ["offRamp"])
    }

    @Test
    func `the debug override closes and opens every feature`() throws {
        try setConfig(json: #"{"isLimited": false, "restrictedFeatures": []}"#)
        ConfigStore.shared.isLimitedOverride = true
        defer { ConfigStore.shared.isLimitedOverride = nil }
        for feature in RestrictedFeature.allCases { #expect(ConfigStore.shared.isRestricted(feature)) }
        ConfigStore.shared.isLimitedOverride = false
        for feature in RestrictedFeature.allCases { #expect(!ConfigStore.shared.isRestricted(feature)) }
    }
}
}
