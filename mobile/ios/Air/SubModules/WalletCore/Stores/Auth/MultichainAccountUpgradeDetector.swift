import CryptoKit
import Foundation
import WalletContext
import WalletCoreTypes

enum MultichainAccountUpgradeDetector {
    private static let backendAuthMessage = Data("MyTonWallet_AuthToken_n6i0k4w8pb".utf8)

    static func needsSDKPreparation(
        nativeAccountsById: [String: MAccount],
        storedAccountsJSON: String?
    ) -> Bool {
        let encryptedAccountIds = Set(
            nativeAccountsById.values
                .filter { $0.type.isStoredEncrypted }
                .map(\.id)
        )
        guard !encryptedAccountIds.isEmpty else {
            return false
        }
        guard let storedAccountsJSON,
              let data = storedAccountsJSON.data(using: .utf8),
              let storedAccounts = try? JSONDecoder().decode(
                [String: StoredAccount].self,
                from: data
              ) else {
            return true
        }

        return encryptedAccountIds.contains { accountId in
            guard let account = storedAccounts[accountId],
                  account.type == "bip39" || account.type == "ton" else {
                return true
            }
            return account.needsUpgrade
        }
    }

    private static func isBackendAuthTokenValid(_ authToken: String, publicKey: String) -> Bool {
        guard let signature = Data(base64Encoded: authToken),
              signature.count == 64,
              signature.base64EncodedString() == authToken,
              let publicKeyData = Data(hexString: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }

        return key.isValidSignature(signature, for: backendAuthMessage)
    }

    private struct StoredAccount: Decodable {
        let type: String
        let byChain: [String: StoredChain]

        var needsUpgrade: Bool {
            let hasMissingChains = type == "bip39" && getSupportedChains().contains { chain in
                chain.multiWalletSupport != nil && byChain[chain.rawValue]?.derivation == nil
            }

            let tonWallet = byChain[ApiChain.ton.rawValue]
            let hasMissingAuthToken: Bool
            if let publicKey = tonWallet?.publicKey, !publicKey.isEmpty {
                guard let authToken = tonWallet?.authToken, !authToken.isEmpty else {
                    return true
                }
                hasMissingAuthToken = !isBackendAuthTokenValid(authToken, publicKey: publicKey)
            } else {
                hasMissingAuthToken = false
            }

            return hasMissingChains || hasMissingAuthToken
        }
    }

    private struct StoredChain: Decodable {
        let derivation: ApiDerivation?
        let publicKey: String?
        let authToken: String?
    }
}
