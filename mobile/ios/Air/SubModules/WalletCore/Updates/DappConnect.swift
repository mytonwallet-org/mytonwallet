
import WalletContext


extension ApiUpdate {
    public struct DappConnect: Equatable, Hashable, Codable, Sendable {
        public var type = "dappConnect"
        public enum MultichainResolution: String, Equatable, Hashable, Codable, Sendable {
            case switchedAccount = "switched-account"
            case needsNewWallet = "needs-new-wallet"
        }
        public let identifier: String?
        public let promiseId: String
        public let accountId: String
        public let dapp: ApiDapp
        public struct Permissions: Equatable, Hashable, Codable, Sendable {
            public let address: Bool
            public let proof: Bool
        }
        public let permissions: Permissions
        public let proof: ApiTonConnectProof?
        public let multichainResolution: MultichainResolution?
    }
}

#if DEBUG
extension  ApiUpdate.DappConnect {
    public static let sample = ApiUpdate.DappConnect(
        identifier: "identifier",
        promiseId: "promiseId",
        accountId: "2-mainnet",
        dapp: .sample,
        permissions: ApiUpdate.DappConnect.Permissions(address: true, proof: true),
        proof: ApiTonConnectProof(timestamp: 1717171717, domain: "domain", payload: "payload"),
        multichainResolution: nil,
    )
}
#endif
