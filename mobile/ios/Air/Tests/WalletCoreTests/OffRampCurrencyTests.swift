import Foundation
import Testing
import WalletCoreTypes
@testable import WalletCore

// The enclosing suite serializes tests that mutate `ConfigStore.shared`
extension OnRampCurrencyPolicyTests {
    @Suite("Off-Ramp Currencies")
    struct OffRampCurrencyTests {
        @Test(arguments: [
            #"{"countryCode":"ES","allowedOnOffRampCurrencies":["usd","eur"]}"#,
            #"{"countryCode":"ES","allowedOnOffRampCurrencies":["USD","EUR","RUB"]}"#,
            #"{"countryCode":"ES"}"#,
        ])
        func `Spain offers EUR payouts while buying still supports USD`(json: String) throws {
            let previousConfig = ConfigStore.shared.config
            defer { ConfigStore.shared.config = previousConfig }
            ConfigStore.shared.config = try JSONDecoder().decode(ApiUpdate.UpdateConfig.self, from: Data(json.utf8))

            #expect(Moonpay.Offramp.supportedCurrencies == [.EUR])
            #expect(OnRampCurrencyPolicy.supportedCurrencies(for: .ethereum) == [.USD, .EUR])
        }

        @Test
        func `an unavailable config keeps selling on EUR`() {
            let previousConfig = ConfigStore.shared.config
            defer { ConfigStore.shared.config = previousConfig }
            ConfigStore.shared.config = nil

            #expect(Moonpay.Offramp.supportedCurrencies == [.EUR])
        }

        @Test(arguments: [
            #"{"allowedOnOffRampCurrencies":[]}"#,
            #"{"allowedOnOffRampCurrencies":["usd","rub"]}"#,
        ])
        func `a withdrawn payout currency leaves no checkout currency`(json: String) throws {
            let previousConfig = ConfigStore.shared.config
            defer { ConfigStore.shared.config = previousConfig }
            ConfigStore.shared.config = try JSONDecoder().decode(ApiUpdate.UpdateConfig.self, from: Data(json.utf8))

            #expect(Moonpay.Offramp.supportedCurrencies.isEmpty)
        }
    }
}
