
import WalletContext

extension ApiUpdate {
    public struct DappSignData: Equatable, Hashable, Decodable, Sendable {
        public var type = "dappSignData"
        public let promiseId: String
        public let accountId: String
        public let dapp: ApiDapp
        public let payloadToSign: SignDataPayload
    }
}
