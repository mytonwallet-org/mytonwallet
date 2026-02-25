
import WalletContext

extension ApiUpdate {
    public struct DappSignData: Equatable, Hashable, Decodable, Sendable {
        public var type = "dappSignData"
        public let promiseId: String
        public let accountId: String
        public let dapp: ApiDapp
        public let operationChain: ApiChain
        public let payloadToSign: SignDataPayload

        enum CodingKeys: CodingKey {
            case promiseId
            case accountId
            case dapp
            case operationChain
            case payloadToSign
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.promiseId = try container.decode(String.self, forKey: .promiseId)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.dapp = try container.decode(ApiDapp.self, forKey: .dapp)
            self.operationChain = (try? container.decodeIfPresent(ApiChain.self, forKey: .operationChain)) ?? FALLBACK_CHAIN
            self.payloadToSign = try container.decode(SignDataPayload.self, forKey: .payloadToSign)
        }
    }
}
