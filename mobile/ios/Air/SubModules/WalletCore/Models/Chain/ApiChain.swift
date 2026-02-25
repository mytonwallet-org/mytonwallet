import UIKit
import WalletContext

public let FALLBACK_CHAIN: ApiChain = .ton

@dynamicMemberLookup
public enum ApiChain: Equatable, Hashable, Codable, Sendable, CaseIterable {
    case ton
    case tron
    case solana
    case other(String)

    public init?(rawValue: String) {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }
        switch rawValue {
        case "ton":
            self = .ton
        case "tron":
            self = .tron
        case "solana":
            self = .solana
        default:
            self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .ton:
            "ton"
        case .tron:
            "tron"
        case .solana:
            "solana"
        case .other(let rawValue):
            rawValue
        }
    }

    public var isSupported: Bool {
        switch self {
        case .ton, .tron, .solana:
            true
        case .other:
            false
        }
    }

    public static let allCases: [ApiChain] = [.ton, .tron, .solana]
    
    public var config: ChainConfig {
        getChainConfig(chain: self)
    }
    
    public subscript<V>(dynamicMember keyPath: KeyPath<ChainConfig, V>) -> V {
        config[keyPath: keyPath]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let chain = ApiChain(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ApiChain raw value cannot be empty")
        }
        self = chain
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public func getChainBySlug(_ tokenSlug: String) -> ApiChain? {
    let items = tokenSlug.split(separator: "-")
    if items.count == 1 {
        return getChainByNativeSlug(tokenSlug)
    }
    if items.count == 2 {
        guard let chain = ApiChain(rawValue: String(items[0])), chain.isSupported else { return nil }
        return chain
    }
    return nil
}

public func getChainByNativeSlug(_ tokenSlug: String) -> ApiChain? {
    switch tokenSlug {
    case ApiChain.ton.nativeToken.slug: .ton
    case ApiChain.tron.nativeToken.slug: .tron
    case ApiChain.solana.nativeToken.slug: .solana
    default: nil
    }
}

// MARK: - ChainConfig extensions

public extension ApiChain {
    var isOfframpSupported: Bool {
        switch self {
        case .solana, .other:
            false
        case .ton, .tron:
            true
        }
    }

    var isOnchainSwapSupported: Bool {
        switch self {
        case .ton: true
        case .tron: false
        case .solana: false
        case .other: false
        }
    }
    
    var isSendToSelfAllowed: Bool {
        switch self {
        case .ton: true
        case .tron: false
        case .solana: false
        case .other: false
        }
    }
    
    var usdtBadgeText: String {
        switch self {
        case .ton:
            "TON"
        case .tron:
            "TRC-20"
        case .solana:
            "Solana"
        case .other(let chain):
            chain.uppercased()
        }
    }
}

// MARK: - Helper methods

public extension ApiChain {
    var image: UIImage {
        UIImage(named: "chain_\(rawValue)", in: AirBundle, compatibleWith: nil)
            ?? UIImage(named: "chain_\(FALLBACK_CHAIN.rawValue)", in: AirBundle, compatibleWith: nil)!
    }

    func isValidAddressOrDomain(_ addressOrDomain: String) -> Bool {
        guard isSupported else { return false }
        return config.addressRegex.matches(addressOrDomain) || isValidDomain(addressOrDomain)
    }

    func isValidDomain(_ domain: String) -> Bool {
        guard isSupported else { return false }
        return config.isDnsSupported && DNSHelpers.isDnsDomain(domain)
    }
}

// MARK: - Gas

public extension ApiChain {
    struct Gas {
        public let maxSwap: BigInt?
        public let maxTransfer: BigInt
        public let maxTransferToken: BigInt
    }
    
    var gas: Gas {
        switch self {
        case .ton:
            return Gas(
                maxSwap: 400_000_000,
                maxTransfer: 15_000_000,
                maxTransferToken: 60_000_000,
            )
        case .tron:
            return Gas(
                maxSwap: nil,
                maxTransfer: 1_000_000,
                maxTransferToken: 30_000_000,
            )
        case .solana:
            return Gas(
                maxSwap: nil,
                maxTransfer: 0,
                maxTransferToken: 0,
            )
        case .other:
            return Gas(
                maxSwap: nil,
                maxTransfer: 0,
                maxTransferToken: 0,
            )
        }
    }
}
