//
//  ApiToken.swift
//  WalletCore
//
//  Created by Sina on 3/26/24.
//

import Foundation
import WalletContext
import OrderedCollections

public struct ApiToken: Equatable, Hashable, Codable, Sendable {
    
    public let slug: String
    
    public var name: String
    public var symbol: String
    public var decimals: Int
    public var chain: ApiChain = .ton
    public var type: ApiTokenType?
    public var tokenAddress: String?
    public var image: String?
    public var isPopular: Bool?
    public var keywords: [String]?
    public var cmcSlug: String?
    public var color: String?
    public var isGaslessEnabled: Bool?
    public var isStarsEnabled: Bool?
    public var isTiny: Bool?
    public var customPayloadApiUrl: String?
    public var codeHash: String?
    public var label: String?
    
    /* Means the token is fetched from the backend by default and already includes price
    and other details (`ApiTokenDetails`), so no separate requests are needed. */
    public var isFromBackend: Bool?

    public var priceUsd: Double?
    public var percentChange24h: Double?

    public init(slug: String, name: String, symbol: String, decimals: Int, chain: ApiChain, tokenAddress: String? = nil, image: String? = nil, isPopular: Bool? = nil, keywords: [String]? = nil, cmcSlug: String? = nil, color: String? = nil, isGaslessEnabled: Bool? = nil, isStarsEnabled: Bool? = nil, isTiny: Bool? = nil, customPayloadApiUrl: String? = nil, codeHash: String? = nil, label: String? = nil, isFromBackend: Bool? = nil, priceUsd: Double? = nil, percentChange24h: Double? = nil) {
        self.slug = slug
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.chain = chain
        self.tokenAddress = tokenAddress
        self.image = image
        self.isPopular = isPopular
        self.keywords = keywords
        self.cmcSlug = cmcSlug
        self.color = color
        self.isGaslessEnabled = isGaslessEnabled
        self.isStarsEnabled = isStarsEnabled
        self.isTiny = isTiny
        self.customPayloadApiUrl = customPayloadApiUrl
        self.codeHash = codeHash
        self.label = label
        self.isFromBackend = isFromBackend
        self.priceUsd = priceUsd
        self.percentChange24h = percentChange24h
    }

    enum CodingKeys: CodingKey {
        case slug
        case name
        case symbol
        case decimals
        case chain
        case tokenAddress
        case image
        case isPopular
        case keywords
        case cmcSlug
        case color
        case isGaslessEnabled
        case isStarsEnabled
        case isTiny
        case customPayloadApiUrl
        case codeHash
        case label
        case priceUsd
        case percentChange24h
        
        // support for ApiSwapAsset
        case blockchain
        
        // legacy
        case quote
        case minterAddress
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.slug, forKey: .slug)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.symbol, forKey: .symbol)
        try container.encode(self.decimals, forKey: .decimals)
        try container.encode(self.chain, forKey: .chain)
        try container.encodeIfPresent(self.tokenAddress, forKey: .tokenAddress)
        try container.encodeIfPresent(self.image, forKey: .image)
        try container.encodeIfPresent(self.isPopular, forKey: .isPopular)
        try container.encodeIfPresent(self.keywords, forKey: .keywords)
        try container.encodeIfPresent(self.cmcSlug, forKey: .cmcSlug)
        try container.encodeIfPresent(self.color, forKey: .color)
        try container.encodeIfPresent(self.isGaslessEnabled, forKey: .isGaslessEnabled)
        try container.encodeIfPresent(self.isStarsEnabled, forKey: .isStarsEnabled)
        try container.encodeIfPresent(self.isTiny, forKey: .isTiny)
        try container.encodeIfPresent(self.customPayloadApiUrl, forKey: .customPayloadApiUrl)
        try container.encodeIfPresent(self.codeHash, forKey: .codeHash)
        try container.encodeIfPresent(self.label, forKey: .label)
        try container.encodeIfPresent(self.priceUsd, forKey: .priceUsd)
        try container.encodeIfPresent(self.percentChange24h, forKey: .percentChange24h)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.name = try container.decode(String.self, forKey: .name)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.decimals = try container.decode(Int.self, forKey: .decimals)
        
        if let chain = try? container.decodeIfPresent(ApiChain.self, forKey: .chain) {
            self.chain = chain
        } else if let blockchain = try? container.decodeIfPresent(ApiChain.self, forKey: .blockchain) {
            self.chain = blockchain
        } else {
            self.chain = FALLBACK_CHAIN
        }
        
        var tokenAddress = try container.decodeIfPresent(String.self, forKey: .tokenAddress)
        if tokenAddress == nil {
            tokenAddress = try? container.decodeIfPresent(String.self, forKey: .minterAddress)
        }
        self.tokenAddress = tokenAddress
        
        self.image = try container.decodeIfPresent(String.self, forKey: .image)
        self.isPopular = try container.decodeIfPresent(Bool.self, forKey: .isPopular)
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords)
        self.cmcSlug = try container.decodeIfPresent(String.self, forKey: .cmcSlug)
        self.color = try container.decodeIfPresent(String.self, forKey: .color)
        self.isGaslessEnabled = try container.decodeIfPresent(Bool.self, forKey: .isGaslessEnabled)
        self.isStarsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isStarsEnabled)
        self.isTiny = try container.decodeIfPresent(Bool.self, forKey: .isTiny)
        self.customPayloadApiUrl = try container.decodeIfPresent(String.self, forKey: .customPayloadApiUrl)
        self.codeHash = try container.decodeIfPresent(String.self, forKey: .codeHash)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        
        var quote = try? container.decodeIfPresent(ApiTokenPrice.self, forKey: .quote)
        if quote == nil {
            do {
                let priceUsd = try container.decode(Double.self, forKey: .priceUsd)
                let percentChange24h = try? container.decode(Double.self, forKey: .percentChange24h)
                quote = ApiTokenPrice(priceUsd: priceUsd, percentChange24h: percentChange24h)
            } catch {
            }
        }
        self.priceUsd = quote?.priceUsd
        self.percentChange24h = quote?.percentChange24h
    }
    
    public init(any: Any) throws {
        let dict = try (any as? [String: Any]).orThrow()
        self.slug = try (dict["slug"] as? String).orThrow()
        self.name = try (dict["name"] as? String).orThrow()
        self.symbol = try (dict["symbol"] as? String).orThrow()
        self.decimals = try (dict["decimals"] as? Int).orThrow()
        if let chainRaw = dict["chain"] as? String, let chain = ApiChain(rawValue: chainRaw) {
            self.chain = chain
        } else if let blockchainRaw = dict["blockchain"] as? String, let blockchain = ApiChain(rawValue: blockchainRaw) {
            self.chain = blockchain
        } else {
            self.chain = FALLBACK_CHAIN
        }
        self.type = (dict["type"] as? String).flatMap(ApiTokenType.init)
        self.tokenAddress = dict["tokenAddress"] as? String
        self.image = dict["image"] as? String
        self.isPopular = dict["isPopular"] as? Bool
        self.keywords = dict["keywords"] as? [String]
        self.cmcSlug = dict["cmcSlug"] as? String
        self.color = dict["color"] as? String
        self.isGaslessEnabled = dict["isGaslessEnabled"] as? Bool
        self.isStarsEnabled = dict["isStarsEnabled"] as? Bool
        self.isTiny = dict["isTiny"] as? Bool
        self.customPayloadApiUrl = dict["customPayloadApiUrl"] as? String
        self.codeHash = dict["codeHash"] as? String
        self.label = dict["label"] as? String
        self.isFromBackend = dict["isFromBackend"] as? Bool
        self.priceUsd = dict["priceUsd"] as? Double
        self.percentChange24h = dict["percentChange24h"] as? Double
    }
}

extension ApiToken: Identifiable {
    public var id: String { slug }
}

public enum ApiTokenType: String, Equatable, Hashable, Codable, Sendable {
    case lp_token = "lp_token"
}

extension ApiToken {
    public var price: Double? {
        return priceUsd.flatMap { $0 * TokenStore.baseCurrencyRate }
    }
}

extension ApiToken {
    
    public var chainId: String {
        chain.rawValue
    }
    
    public var isOnChain: Bool {
        AccountStore.account?.supports(chain: chain) ?? false
    }
    
    public var swapIdentifier: String {
        return symbol == "TON" ? "TON" : (tokenAddress?.nilIfEmpty ?? slug)
    }
    
    public var earnAvailable: Bool {
        return AccountStore.activeNetwork == .mainnet && EARN_AVAILABLE_SLUGS.contains(slug)
    }
    
    public var isNative: Bool {
        slug == nativeTokenSlug
    }
    
    public var nativeTokenSlug: String {
        chain.nativeToken.slug
    }

    public var isStakedToken: Bool {
        return STAKED_TOKEN_SLUGS.contains(slug)
    }
    
    /// assumes keyword is lowercased and trimmed
    public func matchesSearch(_ keyword: String) -> Bool {
        if keyword.isEmpty { return true }
        if name.lowercased().contains(keyword) { return true }
        if symbol.lowercased().contains(keyword) { return true }
        if let keywords, keywords.any({ $0.contains(keyword) }) {
            return true
        }
        return false
    }
    
    public var internalDeeplinkUrl: URL {
        URL(string: "\(SELF_PROTOCOL)token/\(slug)")!
    }
}

extension ApiToken {
    public var isPricelessToken: Bool {
        if let codeHash {
            return PRICELESS_TOKEN_HASHES.contains(codeHash)
        }
        return false
    }
}

extension ApiToken {
    /// initial StubTokenSlugs
    /// These are shown when account is created and there are no transactions yet.
    /// The order is defined as for displaying in UI.
    public static func defaultSlugs(forNetwork network: ApiNetwork, account: MAccount? = nil) -> OrderedSet<String> {
        if IS_GRAM_WALLET {
            return OrderedSet(defaultSlugs(for: .ton, network: network, account: nil))
        }

        if let account {
            let supportedChains = account.supportedChains
            if supportedChains.count == 1, let chain = supportedChains.first {
                return OrderedSet(defaultSlugs(for: chain, network: network, account: account))
            }
        }

        let slugs: [(ApiChain, String)] = [
            (.ethereum, ETH_SLUG),
            (.solana, SOLANA_SLUG),
            (.tron, TRX_SLUG),
            (.bnb, BNB_SLUG),
            (.ton, TONCOIN_SLUG),
            (.hyperliquid, HYPERLIQUID_SLUG),
        ]

        return OrderedSet(
            slugs.compactMap { chain, slug in
                if let account, !account.supports(chain: chain) {
                    return nil
                }
                return slug
            }
        )
    }

    private static func defaultSlugs(for chain: ApiChain, network: ApiNetwork, account: MAccount?) -> [String] {
        guard account?.supports(chain: chain) != false else {
            return []
        }

        var slugs = [chain.nativeToken.slug]
        if let stablecoinSlug = chain.usdtSlug[network]?.nilIfEmpty {
            slugs.append(stablecoinSlug)
        }
        return slugs
    }
}

private let TON_USDT_MAINNET_IMAGE = "https://imgproxy.mytonwallet.org/imgproxy/T3PB4s7oprNVaJkwqbGg54nexKE0zzKhcrPv8jcWYzU/rs:fill:200:200:1/g:no/aHR0cHM6Ly90ZXRoZXIudG8vaW1hZ2VzL2xvZ29DaXJjbGUucG5n.webp"
private let SOLANA_USDC_MAINNET_IMAGE = "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png"

extension ApiToken {
    
    public static let TONCOIN = ApiToken(
        slug: TONCOIN_SLUG,
        name: "Toncoin",
        symbol: "TON",
        decimals: 9,
        chain: .ton,
        cmcSlug: "toncoin"
    )

    public static let TRX = ApiToken(
        slug: TRX_SLUG,
        name: "TRON",
        symbol: "TRX",
        decimals: 6,
        chain: .tron,
        cmcSlug: "tron"
    )
    
    public static let SOLANA = ApiToken(
        slug: SOLANA_SLUG,
        name: "Solana",
        symbol: "SOL",
        decimals: 9,
        chain: .solana,
        cmcSlug: "solana"
    )

    public static let ETH = ApiToken(
        slug: ETH_SLUG,
        name: "Ethereum",
        symbol: "ETH",
        decimals: 18,
        chain: .ethereum
    )

    public static let BASE = ApiToken(
        slug: BASE_SLUG,
        name: "Base",
        symbol: "ETH",
        decimals: 18,
        chain: .base,
        label: "Base"
    )

    public static let BNB = ApiToken(
        slug: BNB_SLUG,
        name: "BNB",
        symbol: "BNB",
        decimals: 18,
        chain: .bnb
    )

//    public static let POLYGON = ApiToken(
//        slug: POLYGON_SLUG,
//        name: "Polygon",
//        symbol: "POL",
//        decimals: 18,
//        chain: .polygon
//    )

    public static let ARBITRUM = ApiToken(
        slug: ARBITRUM_SLUG,
        name: "Arbitrum",
        symbol: "ETH",
        decimals: 18,
        chain: .arbitrum,
        label: "Arbitrum"
    )

//    public static let MONAD = ApiToken(
//        slug: MONAD_SLUG,
//        name: "Monad",
//        symbol: "MON",
//        decimals: 18,
//        chain: .monad
//    )
//
//    public static let AVALANCHE = ApiToken(
//        slug: AVALANCHE_SLUG,
//        name: "Avalanche",
//        symbol: "AVAX",
//        decimals: 18,
//        chain: .avalanche
//    )

    public static let HYPERLIQUID = ApiToken(
        slug: HYPERLIQUID_SLUG,
        name: "Hyperliquid",
        symbol: "HYPE",
        decimals: 18,
        chain: .hyperliquid
    )

    public static let MYCOIN = ApiToken(
        slug: MYCOIN_SLUG,
        name: "MyTonWallet Coin",
        symbol: "MY",
        decimals: 9,
        chain: .ton
    )
    
    public static let TON_USDT = ApiToken(
        slug: TON_USDT_SLUG,
        name: "Tether USD",
        symbol: "USD₮",
        decimals: 6,
        chain: .ton,
        image: TON_USDT_MAINNET_IMAGE,
        label: "TON",
        priceUsd: 1
    )

    public static let TON_USDT_TESTNET = ApiToken(
        slug: TON_USDT_TESTNET_SLUG,
        name: "Tether USD",
        symbol: "USD₮",
        decimals: 6,
        chain: .ton,
        tokenAddress: "kQD0GKBM8ZbryVk2aESmzfU6b9b_8era_IkvBSELujFZPsyy",
        label: "TON",
        priceUsd: 1
    )

    public static let TRON_USDT = ApiToken(
        slug: TRON_USDT_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .tron,
        label: "TRC-20"
    )

    public static let TRON_USDT_TESTNET = ApiToken(
        slug: TRON_USDT_TESTNET_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .tron,
        tokenAddress: "TG3XXyExBkPp9nzdajDZsozEu4BkaSJozs",
        label: "TRC-20"
    )

    public static let SOLANA_USDT_MAINNET = ApiToken(
        slug: SOLANA_USDT_MAINNET_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .solana,
        tokenAddress: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
        image: TON_USDT_MAINNET_IMAGE,
        label: "SOL",
        priceUsd: 1
    )

    public static let SOLANA_USDC_MAINNET = ApiToken(
        slug: SOLANA_USDC_MAINNET_SLUG,
        name: "USD Coin",
        symbol: "USDC",
        decimals: 6,
        chain: .solana,
        tokenAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        image: SOLANA_USDC_MAINNET_IMAGE,
        label: "SOL",
        priceUsd: 1
    )

    public static let ETH_USDT_MAINNET = ApiToken(
        slug: ETH_USDT_MAINNET_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .ethereum,
        tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        image: TON_USDT_MAINNET_IMAGE,
        label: "ERC-20",
        priceUsd: 1
    )

    public static let ETH_USDC_MAINNET = ApiToken(
        slug: ETH_USDC_MAINNET_SLUG,
        name: "USD Coin",
        symbol: "USDC",
        decimals: 6,
        chain: .ethereum,
        tokenAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        image: SOLANA_USDC_MAINNET_IMAGE,
        label: "ERC-20",
        priceUsd: 1
    )

    public static let BASE_USDT_MAINNET = ApiToken(
        slug: BASE_USDT_MAINNET_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .base,
        tokenAddress: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
        image: TON_USDT_MAINNET_IMAGE,
        label: "ERC-20",
        priceUsd: 1
    )

    public static let BASE_USDC_MAINNET = ApiToken(
        slug: BASE_USDC_MAINNET_SLUG,
        name: "USD Coin",
        symbol: "USDC",
        decimals: 6,
        chain: .base,
        tokenAddress: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        image: SOLANA_USDC_MAINNET_IMAGE,
        label: "ERC-20",
        priceUsd: 1
    )

    public static let BSC_USDT_MAINNET = ApiToken(
        slug: BSC_USDT_MAINNET_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .bnb,
        tokenAddress: "0x55d398326f99059ff775485246999027b3197955",
        image: TON_USDT_MAINNET_IMAGE,
        label: "BEP-20",
        priceUsd: 1
    )

//    public static let AVALANCHE_USDT_MAINNET = ApiToken(
//        slug: AVALANCHE_USDT_MAINNET_SLUG,
//        name: "Tether USD",
//        symbol: "USDT",
//        decimals: 6,
//        chain: .avalanche,
//        tokenAddress: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7",
//        image: TON_USDT_MAINNET_IMAGE,
//        label: "ERC-20",
//        priceUsd: 1
//    )

    public static let HYPERLIQUID_USDC_MAINNET = ApiToken(
        slug: HYPERLIQUID_USDC_MAINNET_SLUG,
        name: "USD Coin",
        symbol: "USDC",
        decimals: 6,
        chain: .hyperliquid,
        tokenAddress: "0xb88339CB7199b77E23DB6E890353E22632Ba630f",
        image: SOLANA_USDC_MAINNET_IMAGE,
        label: "ERC-20",
        priceUsd: 1
    )

    public static let STAKED_TON = ApiToken(
        slug: STAKED_TON_SLUG,
        name: "Staked Toncoin",
        symbol: "STAKED",
        decimals: 9,
        chain: .ton
    )

    public static let STAKED_MYCOIN = ApiToken(
        slug: STAKED_MYCOIN_SLUG,
        name: "Staked MyTonWallet Coin",
        symbol: "stMY",
        decimals: 9,
        chain: .ton
    )
    
    
    public static let TON_USDE = ApiToken(
        slug: TON_USDE_SLUG,
        name: "Ethena USDe",
        symbol: "USDe",
        decimals: 6,
        chain: .ton,
        tokenAddress: "EQAIb6KmdfdDR7CN1GBqVJuP25iCnLKCvBlJ07Evuu2dzP5f",
        image: "https://imgproxy.toncenter.com/binMwUmcnFtjvgjp4wSEbsECXwfXUwbPkhVvsvpubNw/pr:small/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvVVNEZS5wbmc"
    )
    
    public static let TON_TSUSDE = ApiToken(
        slug: TON_TSUSDE_SLUG,
        name: "Ethena tsUSDe",
        symbol: "tsUSDe",
        decimals: 6,
        chain: .ton,
        tokenAddress: "EQDQ5UUyPHrLcQJlPAczd_fjxn8SLrlNQwolBznxCdSlfQwr",
        image: "https://cache.tonapi.io/imgproxy/vGZJ7erwsWPo7DpVG_V7ygNn7VGs0szZXcNLHB_l0ms/rs:fill:200:200:1/g:no/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvdHNVU0RlLnBuZw.webp"
    )
}


// MARK: - ApiTokenPrice

public struct ApiTokenPrice: Equatable, Hashable, Codable, Sendable {
    public var priceUsd: Double
    public var percentChange24h: Double?
}

extension ApiToken {
    public var percentChange24hRounded: Double? {
        percentChange24h?.rounded(decimals: 2)
    }
}
