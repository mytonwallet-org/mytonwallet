import Foundation
import SwiftUI
import UIKit

let APP_GROUP_ID = "group.org.mytonwallet.app"
let SELF_PROTOCOL = "mtw://"

let TONCOIN_SLUG = "toncoin"
let TON_USDT_SLUG = "ton-eqcxe6mutq"
let TRX_SLUG = "trx"
let TRON_USDT_SLUG = "tron-tr7nhqjekq"
let SOLANA_SLUG = "sol"
let SOLANA_USDT_MAINNET_SLUG = "solana-es9vmfrzac"
let MYCOIN_SLUG = "ton-eqcfvnlrbn"
let STAKED_TON_SLUG = "ton-eqcqc6ehrj"
let STAKED_MYCOIN_SLUG = "ton-eqcbzvsfwq"
let TON_USDE_SLUG = "ton-eqaib6kmdf"
let TON_TSUSDE_SLUG = "ton-eqdq5uuyph"

let appGroupContainerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)
let widgetLocalizationBundle = Bundle.main

typealias ApiHistoryList = [[Double]]

func localized(_ keyAndDefault: String) -> LocalizedStringResource {
    LocalizedStringResource(String.LocalizationValue(keyAndDefault), bundle: widgetLocalizationBundle)
}

func lang(_ keyAndDefault: String) -> String {
    NSLocalizedString(keyAndDefault, bundle: widgetLocalizationBundle, comment: "")
}

public enum CompactRoundedWeight {
    case bold
    case semibold
}

public extension UIFont {
    class func compactRounded(ofSize size: CGFloat, weight: CompactRoundedWeight) -> UIFont {
        switch weight {
        case .bold:
            UIFont(name: "SFCompactRounded-Bold", size: size)!
        case .semibold:
            UIFont(name: "SFCompactRounded-Semibold", size: size)!
        }
    }
}

public extension Font {
    static func compactRounded(size: CGFloat, weight: CompactRoundedWeight) -> Font {
        Font(UIFont.compactRounded(ofSize: size, weight: weight))
    }
}

public enum BaseCurrencyFormatPreset {
    case baseCurrencyEquivalent
    case baseCurrencyPrice
}

public enum ApiChain: Equatable, Hashable, Codable, Sendable {
    case ton
    case tron
    case solana
    case other(String)

    init?(rawValue: String) {
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

    var rawValue: String {
        switch self {
        case .ton:
            return "ton"
        case .tron:
            return "tron"
        case .solana:
            return "solana"
        case .other(let rawValue):
            return rawValue
        }
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

public struct ApiToken: Equatable, Hashable, Codable, Sendable, Identifiable {
    let slug: String
    var name: String
    var symbol: String
    var decimals: Int
    var chain: ApiChain = .ton
    var tokenAddress: String?
    var image: String?
    var isPopular: Bool?
    var keywords: [String]?
    var cmcSlug: String?
    var color: String?
    var isGaslessEnabled: Bool?
    var isStarsEnabled: Bool?
    var isTiny: Bool?
    var customPayloadApiUrl: String?
    var codeHash: String?
    var priceUsd: Double?
    var percentChange24h: Double?

    public var id: String { slug }

    var internalDeeplinkUrl: URL {
        URL(string: "\(SELF_PROTOCOL)token/\(slug)")!
    }

    var percentChange24hRounded: Double? {
        percentChange24h?.rounded(decimals: 2)
    }

    func matchesSearch(_ keyword: String) -> Bool {
        if keyword.isEmpty {
            return true
        }
        if name.lowercased().contains(keyword) {
            return true
        }
        if symbol.lowercased().contains(keyword) {
            return true
        }
        return keywords?.contains(where: { $0.lowercased().contains(keyword) }) == true
    }

    private enum CodingKeys: CodingKey {
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
        case blockchain
        case quote
        case minterAddress
    }

    init(
        slug: String,
        name: String,
        symbol: String,
        decimals: Int,
        chain: ApiChain,
        tokenAddress: String? = nil,
        image: String? = nil,
        isPopular: Bool? = nil,
        keywords: [String]? = nil,
        cmcSlug: String? = nil,
        color: String? = nil,
        isGaslessEnabled: Bool? = nil,
        isStarsEnabled: Bool? = nil,
        isTiny: Bool? = nil,
        customPayloadApiUrl: String? = nil,
        codeHash: String? = nil,
        priceUsd: Double? = nil,
        percentChange24h: Double? = nil
    ) {
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
        self.priceUsd = priceUsd
        self.percentChange24h = percentChange24h
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        decimals = try container.decode(Int.self, forKey: .decimals)

        if let chain = try container.decodeIfPresent(ApiChain.self, forKey: .chain) {
            self.chain = chain
        } else if let blockchain = try container.decodeIfPresent(ApiChain.self, forKey: .blockchain) {
            self.chain = blockchain
        } else {
            self.chain = .ton
        }

        tokenAddress = try container.decodeIfPresent(String.self, forKey: .tokenAddress)
            ?? (try container.decodeIfPresent(String.self, forKey: .minterAddress))
        image = try container.decodeIfPresent(String.self, forKey: .image)
        isPopular = try container.decodeIfPresent(Bool.self, forKey: .isPopular)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords)
        cmcSlug = try container.decodeIfPresent(String.self, forKey: .cmcSlug)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        isGaslessEnabled = try container.decodeIfPresent(Bool.self, forKey: .isGaslessEnabled)
        isStarsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isStarsEnabled)
        isTiny = try container.decodeIfPresent(Bool.self, forKey: .isTiny)
        customPayloadApiUrl = try container.decodeIfPresent(String.self, forKey: .customPayloadApiUrl)
        codeHash = try container.decodeIfPresent(String.self, forKey: .codeHash)

        if let priceUsd = try container.decodeIfPresent(Double.self, forKey: .priceUsd) {
            self.priceUsd = priceUsd
            self.percentChange24h = try container.decodeIfPresent(Double.self, forKey: .percentChange24h)
        } else if let quote = try container.decodeIfPresent(ApiTokenPrice.self, forKey: .quote) {
            self.priceUsd = quote.priceUsd
            self.percentChange24h = quote.percentChange24h
        } else {
            self.priceUsd = nil
            self.percentChange24h = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(name, forKey: .name)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(decimals, forKey: .decimals)
        try container.encode(chain, forKey: .chain)
        try container.encodeIfPresent(tokenAddress, forKey: .tokenAddress)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(isPopular, forKey: .isPopular)
        try container.encodeIfPresent(keywords, forKey: .keywords)
        try container.encodeIfPresent(cmcSlug, forKey: .cmcSlug)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(isGaslessEnabled, forKey: .isGaslessEnabled)
        try container.encodeIfPresent(isStarsEnabled, forKey: .isStarsEnabled)
        try container.encodeIfPresent(isTiny, forKey: .isTiny)
        try container.encodeIfPresent(customPayloadApiUrl, forKey: .customPayloadApiUrl)
        try container.encodeIfPresent(codeHash, forKey: .codeHash)
        try container.encodeIfPresent(priceUsd, forKey: .priceUsd)
        try container.encodeIfPresent(percentChange24h, forKey: .percentChange24h)
    }
}

struct ApiTokenPrice: Equatable, Hashable, Codable, Sendable {
    var priceUsd: Double
    var percentChange24h: Double?
}

extension ApiToken {
    static let TONCOIN = ApiToken(
        slug: TONCOIN_SLUG,
        name: "Toncoin",
        symbol: "TON",
        decimals: 9,
        chain: .ton,
        isPopular: true,
        cmcSlug: "toncoin"
    )

    static let TRX = ApiToken(
        slug: TRX_SLUG,
        name: "TRON",
        symbol: "TRX",
        decimals: 6,
        chain: .tron,
        isPopular: true,
        cmcSlug: "tron"
    )

    static let SOLANA = ApiToken(
        slug: SOLANA_SLUG,
        name: "Solana",
        symbol: "SOL",
        decimals: 9,
        chain: .solana,
        isPopular: true,
        cmcSlug: "solana"
    )

    static let MYCOIN = ApiToken(
        slug: MYCOIN_SLUG,
        name: "MyTonWallet Coin",
        symbol: "MY",
        decimals: 9,
        chain: .ton
    )

    static let TON_USDT = ApiToken(
        slug: TON_USDT_SLUG,
        name: "Tether USD",
        symbol: "USD₮",
        decimals: 6,
        chain: .ton,
        isPopular: true
    )

    static let TRON_USDT = ApiToken(
        slug: TRON_USDT_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .tron,
        isPopular: true
    )

    static let SOLANA_USDT_MAINNET = ApiToken(
        slug: SOLANA_USDT_MAINNET_SLUG,
        name: "Tether USD",
        symbol: "USDT",
        decimals: 6,
        chain: .solana,
        tokenAddress: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
        isPopular: true
    )

    static let STAKED_TON = ApiToken(
        slug: STAKED_TON_SLUG,
        name: "Staked Toncoin",
        symbol: "STAKED",
        decimals: 9,
        chain: .ton
    )

    static let STAKED_MYCOIN = ApiToken(
        slug: STAKED_MYCOIN_SLUG,
        name: "Staked MyTonWallet Coin",
        symbol: "stMY",
        decimals: 9,
        chain: .ton
    )

    static let TON_USDE = ApiToken(
        slug: TON_USDE_SLUG,
        name: "Ethena USDe",
        symbol: "USDe",
        decimals: 6,
        chain: .ton,
        tokenAddress: "EQAIb6KmdfdDR7CN1GBqVJuP25iCnLKCvBlJ07Evuu2dzP5f",
        image: "https://imgproxy.toncenter.com/binMwUmcnFtjvgjp4wSEbsECXwfXUwbPkhVvsvpubNw/pr:small/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvVVNEZS5wbmc"
    )

    static let TON_TSUSDE = ApiToken(
        slug: TON_TSUSDE_SLUG,
        name: "Ethena tsUSDe",
        symbol: "tsUSDe",
        decimals: 6,
        chain: .ton,
        tokenAddress: "EQDQ5UUyPHrLcQJlPAczd_fjxn8SLrlNQwolBznxCdSlfQwr",
        image: "https://cache.tonapi.io/imgproxy/vGZJ7erwsWPo7DpVG_V7ygNn7VGs0szZXcNLHB_l0ms/rs:fill:200:200:1/g:no/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvdHNVU0RlLnBuZw.webp"
    )

    static let defaultTokens: [String: ApiToken] = [
        TONCOIN_SLUG: .TONCOIN,
        TRX_SLUG: .TRX,
        SOLANA_SLUG: .SOLANA,
        MYCOIN_SLUG: .MYCOIN,
        TON_USDE_SLUG: .TON_USDE,
        STAKED_TON_SLUG: .STAKED_TON,
        STAKED_MYCOIN_SLUG: .STAKED_MYCOIN,
        TON_TSUSDE_SLUG: .TON_TSUSDE,
        TON_USDT_SLUG: .TON_USDT,
        TRON_USDT_SLUG: .TRON_USDT,
        SOLANA_USDT_MAINNET_SLUG: .SOLANA_USDT_MAINNET,
    ]
}

public enum MBaseCurrency: String, Equatable, Hashable, Codable, Sendable, Identifiable, CaseIterable {
    case USD
    case EUR
    case RUB
    case CNY
    case BTC
    case TON

    var sign: String {
        switch self {
        case .USD:
            return "$"
        case .EUR:
            return "EUR"
        case .RUB:
            return "RUB"
        case .CNY:
            return "CNY"
        case .BTC:
            return "BTC"
        case .TON:
            return "TON"
        }
    }

    var decimalsCount: Int {
        switch self {
        case .USD, .EUR, .RUB, .CNY:
            return 6
        case .BTC:
            return 8
        case .TON:
            return 9
        }
    }

    var preferredDecimals: Int? {
        switch self {
        case .USD, .EUR, .RUB, .CNY:
            return 2
        case .BTC, .TON:
            return nil
        }
    }

    var fallbackExchangeRate: Double {
        switch self {
        case .USD:
            return 1.0
        case .EUR:
            return 1.0 / 1.1
        case .RUB:
            return 80.0
        case .CNY:
            return 7.2
        case .BTC:
            return 1.0 / 100_000.0
        case .TON:
            return 1.0 / 3.0
        }
    }

    public var id: Self { self }
}

public struct MDouble: Equatable, Hashable, Codable, Sendable, Comparable {
    let value: Double

    init(_ value: Double) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else {
            value = Double(try container.decode(String.self)) ?? 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func < (lhs: MDouble, rhs: MDouble) -> Bool {
        lhs.value < rhs.value
    }
}

public struct BaseCurrencyAmount: Equatable, Hashable, Sendable {
    let doubleValue: Double
    let baseCurrency: MBaseCurrency

    static func fromDouble(_ doubleValue: Double, _ baseCurrency: MBaseCurrency) -> BaseCurrencyAmount {
        BaseCurrencyAmount(doubleValue: doubleValue, baseCurrency: baseCurrency)
    }

    func formatted(_ preset: BaseCurrencyFormatPreset, showPlus: Bool = false, showMinus: Bool = true) -> String {
        let absValue = abs(doubleValue)
        let maxFractionDigits: Int

        switch preset {
        case .baseCurrencyEquivalent:
            if absValue >= 10_000 {
                maxFractionDigits = 0
            } else if absValue >= 1 {
                maxFractionDigits = baseCurrency.preferredDecimals ?? 2
            } else if absValue >= 0.01 {
                maxFractionDigits = 4
            } else {
                maxFractionDigits = min(baseCurrency.decimalsCount, 6)
            }
        case .baseCurrencyPrice:
            if absValue < 0.000005 {
                maxFractionDigits = min(baseCurrency.decimalsCount, 8)
            } else if absValue < 0.00005 {
                maxFractionDigits = min(baseCurrency.decimalsCount, 6)
            } else if absValue < 0.05 {
                maxFractionDigits = min(baseCurrency.decimalsCount, 4)
            } else if absValue < 10_000 {
                maxFractionDigits = min(baseCurrency.decimalsCount, 2)
            } else {
                maxFractionDigits = 0
            }
        }

        return formatBaseCurrencyValue(
            doubleValue,
            currency: baseCurrency,
            maxFractionDigits: maxFractionDigits,
            showPlus: showPlus,
            showMinus: showMinus
        )
    }
}

actor SharedCache {
    var tokens: [String: ApiToken] = ApiToken.defaultTokens
    var baseCurrency: MBaseCurrency = .USD
    var rates: [String: MDouble] = [:]

    private struct Snapshot: Codable, Sendable {
        var tokens: [String: ApiToken]
        var baseCurrency: MBaseCurrency
        var rates: [String: MDouble]
    }

    private let url = appGroupContainerUrl?.appending(component: "cache.json")

    init() {
        Task { await loadFromDisk() }
    }

    func reload() {
        loadFromDisk()
    }

    func setTokens(_ tokens: [String: ApiToken]) {
        self.tokens = tokens
        persist()
    }

    func setBaseCurrency(_ baseCurrency: MBaseCurrency) {
        self.baseCurrency = baseCurrency
        persist()
    }

    func setRates(_ rates: [String: MDouble]) {
        self.rates = rates
        persist()
    }

    private func loadFromDisk() {
        guard let url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        tokens = snapshot.tokens.isEmpty ? ApiToken.defaultTokens : snapshot.tokens
        baseCurrency = snapshot.baseCurrency
        rates = snapshot.rates
    }

    private func persist() {
        guard let url else { return }
        let snapshot = Snapshot(tokens: tokens, baseCurrency: baseCurrency, rates: rates)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

actor SharedStore {
    private let cache: SharedCache

    init(cache: SharedCache = SharedCache()) {
        self.cache = cache
    }

    func reloadCache() async {
        await cache.reload()
    }

    func baseCurrency() async -> MBaseCurrency {
        await cache.baseCurrency
    }

    func tokensDictionary(tryRemote: Bool) async -> [String: ApiToken] {
        var tokens = await cache.tokens

        if tokens.count < 20 || tryRemote {
            do {
                let url = URL(string: "https://api.mytonwallet.org/assets")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let remoteTokens = try JSONDecoder().decode([ApiToken].self, from: data).dictionaryByKey(\.slug)
                tokens = ApiToken.defaultTokens.merging(remoteTokens) { _, new in new }
                await cache.setTokens(tokens)
            } catch {
            }
        }

        return tokens.isEmpty ? ApiToken.defaultTokens : tokens
    }

    func ratesDictionary() async -> [String: MDouble] {
        await cache.rates
    }
}

func formatPercent(_ value: Double, decimals: Int = 2, showPlus: Bool = true, showMinus: Bool = true) -> String {
    let value = (value * 100).rounded(decimals: decimals)
    let number = abs(value)

    if showPlus && value > 0 {
        return "+\(number)%"
    }
    if showMinus && value < 0 {
        return "-\(number)%"
    }
    return "\(number)%"
}

private func formatBaseCurrencyValue(
    _ value: Double,
    currency: MBaseCurrency,
    maxFractionDigits: Int,
    showPlus: Bool,
    showMinus: Bool
) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maxFractionDigits
    formatter.groupingSeparator = formatter.groupingSeparator ?? " "

    let number = formatter.string(from: NSNumber(value: abs(value))) ?? "0"
    let signedNumber: String

    if showPlus && value > 0 {
        signedNumber = "+\(number)"
    } else if showMinus && value < 0 {
        signedNumber = "-\(number)"
    } else {
        signedNumber = number
    }

    if currency.sign.count > 1 || currency == .RUB {
        return "\(signedNumber) \(currency.sign)"
    }

    return "\(currency.sign)\(signedNumber)"
}

extension Sequence {
    func dictionaryByKey<Key: Hashable>(_ keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        Dictionary(uniqueKeysWithValues: map { ($0[keyPath: keyPath], $0) })
    }
}

extension Double {
    func rounded(decimals: Int) -> Double {
        let multiplier = pow(10.0, Double(decimals))
        return (self * multiplier).rounded() / multiplier
    }
}

extension Optional where Wrapped == Double {
    var nilIfZero: Wrapped? {
        guard let value = self, value != 0 else {
            return nil
        }
        return value
    }
}

extension UIColor {
    convenience init(hex hexString: String) {
        let hex = hexString
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        var intValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&intValue)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        switch hex.count {
        case 3:
            alpha = 255
            red = (intValue >> 8) * 17
            green = (intValue >> 4 & 0xF) * 17
            blue = (intValue & 0xF) * 17
        case 6:
            alpha = 255
            red = intValue >> 16
            green = intValue >> 8 & 0xFF
            blue = intValue & 0xFF
        case 8:
            alpha = intValue >> 24
            red = intValue >> 16 & 0xFF
            green = intValue >> 8 & 0xFF
            blue = intValue & 0xFF
        default:
            alpha = 255
            red = 0
            green = 0
            blue = 0
        }

        self.init(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
