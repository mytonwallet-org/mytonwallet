import Foundation
import Testing
import WalletCore

@Suite("ApiToken Localized Name Coding")
struct ApiTokenLocalizedNameCodingTests {
    @Test
    func `decodes and encodes localized name`() throws {
        let data = Data(
            #"{"slug":"usdt","name":"Tether USD","localizedName":"Тезер","symbol":"USDT","decimals":6,"chain":"ton"}"#.utf8
        )

        let token = try JSONDecoder().decode(ApiToken.self, from: data)
        #expect(token.localizedName == "Тезер")

        let encoded = try JSONEncoder().encode(token)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["localizedName"] as? String == "Тезер")
    }

    @Test
    func `decodes localized name from update dictionary`() throws {
        let token = try ApiToken(any: [
            "slug": "usdt",
            "name": "Tether USD",
            "localizedName": "Тезер",
            "symbol": "USDT",
            "decimals": 6,
            "chain": "ton",
        ])

        #expect(token.localizedName == "Тезер")
    }

    @Test
    func `decodes and reencodes cached token without localized name`() throws {
        let data = Data(
            #"{"slug":"usdt","name":"Tether USD","symbol":"USDT","decimals":6,"chain":"ton"}"#.utf8
        )

        let token = try JSONDecoder().decode(ApiToken.self, from: data)
        #expect(token.localizedName == nil)

        let encoded = try JSONEncoder().encode(token)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["localizedName"] == nil)
    }
}
