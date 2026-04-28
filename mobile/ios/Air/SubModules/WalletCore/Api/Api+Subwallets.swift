import Foundation
import WalletContext

extension Api {
    public static func getWalletVariants(
        accountId: String,
        page: Int,
        mnemonic: [String]
    ) async throws -> [ApiGroupedWalletVariant] {
        try await bridge.callApi(
            "getWalletVariants",
            accountId,
            page,
            mnemonic,
            decoding: [ApiGroupedWalletVariant].self
        )
    }

    internal static func createSubWallet(
        accountId: String,
        password: String
    ) async throws -> ApiCreateSubWalletResult {
        try await bridge.callApi("createSubWallet", accountId, password, decoding: ApiCreateSubWalletResult.self)
    }

    internal static func addSubWallet(
        accountId: String,
        byChain: [String: ApiSubWallet]
    ) async throws -> ApiAddSubWalletResult {
        try await bridge.callApi("addSubWallet", accountId, byChain, decoding: ApiAddSubWalletResult.self)
    }
}

public struct ApiDerivation: Equatable, Hashable, Codable, Sendable {
    public var path: String
    public var index: Int
    public var label: String?

    public init(path: String, index: Int, label: String? = nil) {
        self.path = path
        self.index = index
        self.label = label
    }
}

public struct ApiSubWallet: Equatable, Hashable, Codable, Sendable {
    public var address: String
    public var publicKey: String?
    public var version: ApiTonWalletVersion?
    public var isInitialized: Bool?
    public var derivation: ApiDerivation?

    public init(
        address: String,
        publicKey: String? = nil,
        version: ApiTonWalletVersion? = nil,
        isInitialized: Bool? = nil,
        derivation: ApiDerivation? = nil
    ) {
        self.address = address
        self.publicKey = publicKey
        self.version = version
        self.isInitialized = isInitialized
        self.derivation = derivation
    }
}

public struct ApiWalletVariant: Equatable, Hashable, Codable, Sendable {
    public enum Metadata: Equatable, Hashable, Codable, Sendable {
        case version(ApiTonWalletVersion)
        case path(path: String, label: String?)

        private enum CodingKeys: CodingKey {
            case type
            case version
            case path
            case label
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "version":
                self = .version(try container.decode(ApiTonWalletVersion.self, forKey: .version))
            case "path":
                self = .path(
                    path: try container.decode(String.self, forKey: .path),
                    label: try container.decodeIfPresent(String.self, forKey: .label)
                )
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported wallet variant metadata type")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .version(let version):
                try container.encode("version", forKey: .type)
                try container.encode(version, forKey: .version)
            case .path(let path, let label):
                try container.encode("path", forKey: .type)
                try container.encode(path, forKey: .path)
                try container.encodeIfPresent(label, forKey: .label)
            }
        }
    }

    public var chain: ApiChain
    public var wallet: ApiSubWallet
    public var balance: BigInt
    public var metadata: Metadata

    public init(chain: ApiChain, wallet: ApiSubWallet, balance: BigInt, metadata: Metadata) {
        self.chain = chain
        self.wallet = wallet
        self.balance = balance
        self.metadata = metadata
    }
}

public struct ApiGroupedWalletVariant: Equatable, Hashable, Codable, Sendable {
    public struct ChainEntry: Equatable, Hashable, Codable, Sendable {
        public var wallet: ApiSubWallet
        public var balance: BigInt
        public var hasDerivation: Bool

        public init(wallet: ApiSubWallet, balance: BigInt, hasDerivation: Bool) {
            self.wallet = wallet
            self.balance = balance
            self.hasDerivation = hasDerivation
        }
    }

    public var index: Int
    public var totalBalance: BigInt
    public var byChain: [String: ChainEntry]

    public init(index: Int, totalBalance: BigInt, byChain: [String: ChainEntry]) {
        self.index = index
        self.totalBalance = totalBalance
        self.byChain = byChain
    }

    public func entry(for chain: ApiChain) -> ChainEntry? {
        byChain[chain.rawValue]
    }
}

public struct ApiCreateSubWalletResult: Decodable, Sendable {
    public var isNew: Bool
    public var address: String?
    public var derivation: ApiDerivation?
    public var accountId: String
    public var byChain: [String: AccountChain]?
}

public struct ApiAddSubWalletResult: Decodable, Sendable {
    public var isNew: Bool
    public var address: String?
    public var accountId: String
    public var byChain: [String: AccountChain]?
}
