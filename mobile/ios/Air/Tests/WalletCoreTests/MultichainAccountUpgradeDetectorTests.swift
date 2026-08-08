import CryptoKit
import Foundation
import Testing
@testable import WalletCore
import WalletCoreTypes

@Suite("Multichain Account Upgrade Detection")
struct MultichainAccountUpgradeDetectorTests {
    private static let backendAuthMessage = Data("MyTonWallet_AuthToken_n6i0k4w8pb".utf8)

    @Test
    func `fully upgraded accounts skip SDK preparation`() throws {
        let fixture = try makeStoredAccount()

        #expect(
            !MultichainAccountUpgradeDetector.needsSDKPreparation(
                nativeAccountsById: [fixture.nativeAccount.id: fixture.nativeAccount],
                storedAccountsJSON: fixture.json
            )
        )
    }

    @Test
    func `legacy TON accounts do not require multichain wallets`() throws {
        let fixture = try makeStoredAccount(accountType: "ton")

        #expect(
            !MultichainAccountUpgradeDetector.needsSDKPreparation(
                nativeAccountsById: [fixture.nativeAccount.id: fixture.nativeAccount],
                storedAccountsJSON: fixture.json
            )
        )
    }

    @Test
    func `missing supported chain requires SDK preparation`() throws {
        let missingChain = try #require(
            getSupportedChains().first { $0.multiWalletSupport != nil && $0 != .ton }
        )
        let fixture = try makeStoredAccount(removingChain: missingChain)

        #expect(
            MultichainAccountUpgradeDetector.needsSDKPreparation(
                nativeAccountsById: [fixture.nativeAccount.id: fixture.nativeAccount],
                storedAccountsJSON: fixture.json
            )
        )
    }

    @Test
    func `missing backend auth token requires SDK preparation`() throws {
        let fixture = try makeStoredAccount(includeAuthToken: false)

        #expect(
            MultichainAccountUpgradeDetector.needsSDKPreparation(
                nativeAccountsById: [fixture.nativeAccount.id: fixture.nativeAccount],
                storedAccountsJSON: fixture.json
            )
        )
    }

    @Test
    func `invalid backend auth token requires SDK preparation`() throws {
        let fixture = try makeStoredAccount(authTokenOverride: Data(repeating: 0, count: 64).base64EncodedString())

        #expect(
            MultichainAccountUpgradeDetector.needsSDKPreparation(
                nativeAccountsById: [fixture.nativeAccount.id: fixture.nativeAccount],
                storedAccountsJSON: fixture.json
            )
        )
    }

    @Test
    func `missing local storage is conservative for encrypted accounts`() {
        let account = makeNativeAccount()

        #expect(
            MultichainAccountUpgradeDetector.needsSDKPreparation(
                nativeAccountsById: [account.id: account],
                storedAccountsJSON: nil
            )
        )
    }

    @Test
    func `accounts without encrypted secrets skip SDK preparation`() {
        let account = MAccount(
            id: "view-mainnet",
            title: nil,
            type: .view,
            byChain: [.ton: AccountChain(address: "EQview")]
        )

        #expect(
            !MultichainAccountUpgradeDetector.needsSDKPreparation(
                nativeAccountsById: [account.id: account],
                storedAccountsJSON: nil
            )
        )
    }

    private func makeStoredAccount(
        accountType: String = "bip39",
        removingChain: ApiChain? = nil,
        includeAuthToken: Bool = true,
        authTokenOverride: String? = nil
    ) throws -> (nativeAccount: MAccount, json: String) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation.hexString
        let signature = try privateKey.signature(for: Self.backendAuthMessage).base64EncodedString()
        let authToken = authTokenOverride ?? signature

        let includedChains = accountType == "bip39" ? getSupportedChains() : [.ton]
        var byChain = Dictionary(
            uniqueKeysWithValues: includedChains
                .filter { $0.multiWalletSupport != nil && $0 != removingChain }
                .map { chain in
                    (
                        chain.rawValue,
                        [
                            "address": "\(chain.rawValue)-address",
                            "derivation": [
                                "path": "m/44'/0'/0'",
                                "index": 0,
                            ],
                        ] as [String: Any]
                    )
                }
        )
        var tonWallet = byChain[ApiChain.ton.rawValue] ?? [
            "address": "EQtest",
            "derivation": [
                "path": "m/44'/607'/0'",
                "index": 0,
            ],
        ]
        tonWallet["publicKey"] = publicKey
        if includeAuthToken {
            tonWallet["authToken"] = authToken
        }
        byChain[ApiChain.ton.rawValue] = tonWallet

        let account = makeNativeAccount()
        let data = try JSONSerialization.data(withJSONObject: [
            account.id: [
                "type": accountType,
                "byChain": byChain,
            ],
        ])
        return (account, try #require(String(data: data, encoding: .utf8)))
    }

    private func makeNativeAccount() -> MAccount {
        MAccount(
            id: "account-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: [.ton: AccountChain(address: "EQtest")]
        )
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
