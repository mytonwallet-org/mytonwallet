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
    
    /* Means the token is fetched from the backend by default and already includes price
    and other details (`ApiTokenDetails`), so no separate requests are needed. */
    public var isFromBackend: Bool?

    public var priceUsd: Double?
    public var percentChange24h: Double?

    public init(slug: String, name: String, symbol: String, decimals: Int, chain: ApiChain, tokenAddress: String? = nil, image: String? = nil, isPopular: Bool? = nil, keywords: [String]? = nil, cmcSlug: String? = nil, color: String? = nil, isGaslessEnabled: Bool? = nil, isStarsEnabled: Bool? = nil, isTiny: Bool? = nil, customPayloadApiUrl: String? = nil, codeHash: String? = nil, isFromBackend: Bool? = nil, priceUsd: Double? = nil, percentChange24h: Double? = nil) {
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
    /// initialStubTokenSlugs
    /// These are shown when account is created and there are no transactions yet.
    private static let DEFAULT_SLUGS: OrderedSet<String> = [TONCOIN_SLUG, TON_USDT_SLUG, TRX_SLUG, TRON_USDT_SLUG, SOLANA_SLUG, SOLANA_USDT_MAINNET_SLUG]
    private static let DEFAULT_TESTNET_SLUGS: OrderedSet<String> = [TONCOIN_SLUG, TRX_SLUG, TRON_USDT_TESTNET_SLUG, SOLANA_SLUG]
    
    /// These are shown when account is created and there are no transactions yet.
    public static func defaultSlugs(forNetwork network: ApiNetwork) -> OrderedSet<String> {
        switch network {
        case .mainnet: DEFAULT_SLUGS
        case .testnet: DEFAULT_TESTNET_SLUGS
        }
    }
}

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
        chain: .ton
    )

    public static let TRON_USDT = ApiToken(
        slug: TRON_USDT_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .tron
    )

    public static let SOLANA_USDT_MAINNET = ApiToken(
        slug: SOLANA_USDT_MAINNET_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .solana,
        tokenAddress: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
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
