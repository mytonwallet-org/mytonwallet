import Foundation
import Testing
@testable import WalletCore

@Suite("Dapp metadata decoding")
struct ApiDappTests {
    @Test(arguments: [
        ("", nil),
        (#", "iconUrl": null"#, nil),
        (#", "iconUrl": "https://app.ens.domains/icon.png""#, "https://app.ens.domains/icon.png"),
    ] as [(String, String?)])
    func connectionAcceptsOptionalIcon(iconField: String, expectedIcon: String?) throws {
        let json = """
        {
            "type": "dappConnect",
            "promiseId": "connect-ens",
            "accountId": "0-mainnet",
            "dapp": {
                "protocolType": "walletConnect",
                "url": "https://app.ens.domains",
                "name": "ENS"\(iconField)
            },
            "permissions": {"address": true, "proof": false}
        }
        """

        let update = try JSONDecoder().decode(ApiUpdate.DappConnect.self, from: Data(json.utf8))

        #expect(update.dapp.name == "ENS")
        #expect(update.dapp.iconUrl == expectedIcon)

        let encoded = try JSONEncoder().encode(update.dapp)
        let stored = try JSONDecoder().decode(ApiDapp.self, from: encoded)
        #expect(stored == update.dapp)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["iconUrl"] as? String == expectedIcon)
        if expectedIcon == nil {
            #expect(fields["iconUrl"] == nil)
        }
    }
}
