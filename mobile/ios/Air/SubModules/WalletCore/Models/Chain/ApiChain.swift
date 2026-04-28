import UIKit
import WalletContext

public let FALLBACK_CHAIN: ApiChain = .ton

@dynamicMemberLookup
public enum ApiChain: Equatable, Hashable, Codable, Sendable, CaseIterable {
    case ton
    case tron
    case solana
    case ethereum
    case base
    case bnb
//    case polygon
    case arbitrum
//    case monad
//    case avalanche
    case hyperliquid
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
        case "ethereum":
            self = .ethereum
        case "base":
            self = .base
        case "bnb":
            self = .bnb
//        case "polygon":
//            self = .polygon
        case "arbitrum":
            self = .arbitrum
//        case "monad":
//            self = .monad
//        case "avalanche":
//            self = .avalanche
        case "hyperliquid":
            self = .hyperliquid
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
        case .ethereum:
            "ethereum"
        case .base:
            "base"
        case .bnb:
            "bnb"
//        case .polygon:
//            "polygon"
        case .arbitrum:
            "arbitrum"
//        case .monad:
//            "monad"
//        case .avalanche:
//            "avalanche"
        case .hyperliquid:
            "hyperliquid"
        case .other(let rawValue):
            rawValue
        }
    }

    public var isSupported: Bool {
        isSupportedChain(self)
    }

    public static let allCases: [ApiChain] = getSupportedChains()
    
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
    ApiChain.allCases.first {
        $0.nativeToken.slug == tokenSlug
    }
}

// MARK: - ChainConfig extensions

public extension ApiChain {
    static let viewAccountEvmParam = "evm"

    static var evmChains: [ApiChain] {
        allCases.filter(\.isEvm)
    }

    var isEvm: Bool {
        config.chainStandard == .ethereum
    }

    var isOnrampSupported: Bool {
        guard isSupported, config.isOnRampSupported else { return false }
        return config.canBuyWithCardInRussia || ConfigStore.shared.config?.countryCode != "RU"
    }

    var isOfframpSupported: Bool {
        guard isSupported else { return false }
        return config.isOffRampSupported
    }

    var isOnchainSwapSupported: Bool {
        switch self {
        case .ton: true
        default: false
        }
    }
    
    var isSendToSelfAllowed: Bool {
        switch self {
        case .ton: true
        default: false
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
        case .bnb:
            "BEP-20"
        case .ethereum, .base:
            "ERC-20"
        case /*.polygon,*/ .arbitrum, /*.monad, .avalanche,*/ .hyperliquid:
            "ERC-20"
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
        default:
            return Gas(
                maxSwap: nil,
                maxTransfer: 0,
                maxTransferToken: 0,
            )
        }
    }
}
