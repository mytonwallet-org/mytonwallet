import Foundation
import Testing
@testable import WalletCore

// Nested under the on-ramp suite so its `.serialized` trait covers both: they write the same shared ConfigStore.
extension OnRampCurrencyPolicyTests {
@Suite("Config Store Swap Restriction")
struct ConfigStoreSwapRestrictionTests {

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
        #expect(ConfigStore.shared.shouldRestrictSwapsAndOnRamp == false)
        #expect(ConfigStore.shared.shouldRestrictSell)
        #expect(ConfigStore.shared.shouldRestrictBuyNfts)
        #expect(ConfigStore.shared.shouldRestrictSites)
    }

    @Test
    func `a backend without the field keeps swaps on isLimited`() throws {
        try setConfig(json: #"{"isLimited": true}"#)
        #expect(ConfigStore.shared.shouldRestrictSwapsAndOnRamp)
    }

    @Test
    func `a malformed field reads as absent`() throws {
        try setConfig(json: #"{"isLimited": true, "isSwapAndOnRampLimited": "no"}"#)
        #expect(ConfigStore.shared.shouldRestrictSwapsAndOnRamp)
    }

    @Test
    func `the debug override still limits swaps`() throws {
        try setConfig(json: #"{"isLimited": false, "isSwapAndOnRampLimited": false}"#)
        ConfigStore.shared.isLimitedOverride = true
        defer { ConfigStore.shared.isLimitedOverride = nil }
        #expect(ConfigStore.shared.shouldRestrictSwapsAndOnRamp)
    }
}
}
