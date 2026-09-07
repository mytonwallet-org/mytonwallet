
import WalletContext
import WalletCoreTypes

extension ApiUpdate {
    public struct DappSignData: Equatable, Hashable, Decodable, Sendable {
        public var type = "dappSignData"
        public let promiseId: String
        public let accountId: String
        public let dapp: ApiDapp
        public let operationChain: ApiChain
        public let payloadToSign: SignDataPayload
        public let parsedPayloadToSign: ParsedSignDataCellPreview?

        enum CodingKeys: CodingKey {
            case promiseId
            case accountId
            case dapp
            case operationChain
            case payloadToSign
            case parsedPayloadToSign
        }

        public struct ParsedSignDataCellPreview: Equatable, Hashable, Decodable, Sendable {
            public let title: String
            public let hash: String?
            public let bits: Int
            public let refs: Int
            public let fields: [ParsedSignDataCellField]
            public let error: String?
            public let isParsed: Bool
        }

        public struct ParsedSignDataCellField: Equatable, Hashable, Decodable, Sendable {
            public let label: String
            public let value: String
            public let depth: Int
            public let isMuted: Bool?
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.promiseId = try container.decode(String.self, forKey: .promiseId)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.dapp = try container.decode(ApiDapp.self, forKey: .dapp)
            self.operationChain = try container.decode(ApiChain.self, forKey: .operationChain)
            self.payloadToSign = try container.decode(SignDataPayload.self, forKey: .payloadToSign)
            self.parsedPayloadToSign = try container.decodeIfPresent(
                ParsedSignDataCellPreview.self,
                forKey: .parsedPayloadToSign
            )
        }
    }
}
