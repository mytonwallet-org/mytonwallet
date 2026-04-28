
import Foundation
import WalletContext


public final class ExplorerHelper {
    
    private init() {}
    
    public static func viewTransactionUrl(network: ApiNetwork, chain: ApiChain, txHash: String) -> URL {
        var url = URL(string: SHORT_UNIVERSAL_URL)!.appending(components: "tx", chain.rawValue, txHash)
        if network == .testnet {
            url.append(queryItems: [URLQueryItem(name: "testnet", value: "true")])
        }
        return url
    }

    public static func viewNftUrl(network: ApiNetwork, nftAddress: String) -> URL {
        var url = URL(string: SHORT_UNIVERSAL_URL)!.appending(components: "nft", nftAddress)
        if network == .testnet {
            url.append(queryItems: [URLQueryItem(name: "testnet", value: "true")])
        }
        return url
    }

    public static func addressUrl(chain: ApiChain, address: String) -> URL {
        let network = AccountStore.activeNetwork
        if let explorer = selectedExplorerConfig(for: chain),
           let baseUrl = explorer.baseUrl[network] {
            let param = baseUrl.param ?? ""
            let str = explorer.address
                .replacing("{base}", with: baseUrl.url)
                .replacing("{address}", with: address)
                + param
            return URL(string: str)!
        }
        let str = chain.explorer.address
            .replacing("{base}", with: chain.explorer.baseUrl[network]!.url)
            .replacing("{address}", with: address)
            + (chain.explorer.baseUrl[network]!.param ?? "")
        return URL(string: str)!
    }
    
    public static func txUrl(chain: ApiChain, txHash: String) -> URL {
        let network = AccountStore.activeNetwork
        var txHash = txHash
        if let explorer = selectedExplorerConfig(for: chain),
           let baseUrl = explorer.baseUrl[network] {
            if explorer.doConvertHashFromBase64 {
                txHash = txHash.base64ToHex
            }
            let param = baseUrl.param ?? ""
            let str = explorer.transaction
                .replacing("{base}", with: baseUrl.url)
                .replacing("{hash}", with: txHash)
                + param
            return URL(string: str)!
        }
        if chain.explorer.doConvertHashFromBase64 {
            txHash = txHash.base64ToHex
        }
        let str = chain.explorer.transaction
            .replacing("{base}", with: chain.explorer.baseUrl[network]!.url)
            .replacing("{hash}", with: txHash)
            + (chain.explorer.baseUrl[network]!.param ?? "")
        return URL(string: str)!
    }

    public static func nftUrl(_ nft: ApiNft) -> URL {
        if nft.chain == .ton {
            return URL(string: "https://getgems.io/collection/\(nft.collectionAddress ?? "")/\(nft.address)")!
        }
        return explorerNftUrl(nft)
    }

    public static func tonscanNftUrl(_ nft: ApiNft) -> URL {
        if nft.chain != .ton {
            return addressUrl(chain: nft.chain, address: nft.address)
        }
        return URL(string: "https://tonscan.org/nft/\(nft.address)")!
    }

    public static func explorerNftUrl(_ nft: ApiNft, explorerId: String? = nil) -> URL {
        let chain = nft.chain
        let network = AccountStore.activeNetwork
        let explorers = availableExplorers(for: chain)
        let explorerById: ExplorerConfig? = if let explorerId {
            explorers.first(where: { $0.id == explorerId })
        } else {
            nil
        }
        let explorer = explorerById ?? selectedExplorerConfig(for: chain)
        if let explorer, let baseUrl = explorer.baseUrl[network], let nftPath = explorer.nft {
            let param = baseUrl.param ?? ""
            let str = nftPath
                .replacing("{base}", with: baseUrl.url)
                .replacing("{address}", with: nft.address)
                + param
            return URL(string: str)!
        }
        return addressUrl(chain: chain, address: nft.address)
    }

    public static func marketplaceNftWebsite(_ nft: ApiNft, marketplaceId: String? = nil) -> Website? {
        let chain = nft.chain
        let network = AccountStore.activeNetwork
        let marketplaces = availableMarketplaces(for: chain)
        let marketplace = if let marketplaceId {
            marketplaces.first(where: { $0.id == marketplaceId })
        } else {
            marketplaces.first
        }
        guard let marketplace,
              let baseUrl = marketplace.baseUrl[network],
              !baseUrl.url.isEmpty else {
            return nil
        }
        let str = marketplace.nft
            .replacing("{base}", with: baseUrl.url)
            .replacing("{chain}", with: chain.rawValue)
            .replacing("{address}", with: nft.address)
            + (baseUrl.param ?? "")
        guard let url = URL(string: str) else {
            return nil
        }
        return Website(title: marketplace.name, address: url)
    }
    
    public static func getgemsNftCollectionUrl(collectionAddress: String) -> URL? {
        guard let collectionAddress = collectionAddress.nilIfEmpty else {
            return nil
        }
        return URL(string: "https://getgems.io/collection/\(collectionAddress)")
    }
    
    public static func tonscanNftCollectionUrl(collectionAddress: String) -> URL? {
        guard let collectionAddress = collectionAddress.nilIfEmpty else {
            return nil
        }
        return URL(string: "https://tonscan.org/nft/\(collectionAddress)")
    }

    public static func nftCollectionUrl(_ nft: ApiNft) -> URL {
        guard let collectionAddress = nft.collectionAddress?.nilIfEmpty else {
            return explorerNftUrl(nft)
        }
        if nft.chain == .ton {
            guard let url = getgemsNftCollectionUrl(collectionAddress: collectionAddress) else {
                assertionFailure("Unable to create collection url for \(collectionAddress)")
                return explorerNftUrl(nft)
            }
            return url
        }
        let network = AccountStore.activeNetwork
        if let explorer = selectedExplorerConfig(for: nft.chain),
           let baseUrl = explorer.baseUrl[network],
           let nftCollectionPath = explorer.nftCollection {
            let param = baseUrl.param ?? ""
            let str = nftCollectionPath
                .replacing("{base}", with: baseUrl.url)
                .replacing("{address}", with: collectionAddress)
                + param
            return URL(string: str)!
        }
        return addressUrl(chain: nft.chain, address: collectionAddress)
    }

    public static func nftCollectionUrl(_ collection: NftCollection) -> URL? {
        if collection.chain == .ton {
            return getgemsNftCollectionUrl(collectionAddress: collection.address)
        }
        let network = AccountStore.activeNetwork
        if let explorer = selectedExplorerConfig(for: collection.chain),
           let baseUrl = explorer.baseUrl[network],
           let nftCollectionPath = explorer.nftCollection {
            let str = nftCollectionPath
                .replacing("{base}", with: baseUrl.url)
                .replacing("{address}", with: collection.address)
                + (baseUrl.param ?? "")
            return URL(string: str)
        }
        return addressUrl(chain: collection.chain, address: collection.address)
    }
    
    public static func tonDnsManagementUrl(_ nft: ApiNft) -> URL? {
        if nft.collectionAddress == ApiNft.TON_DNS_COLLECTION_ADDRESS, let baseName = nft.name?.components(separatedBy: ".").first {
            return URL(string: "https://dns.ton.org/#\(baseName)")!
        }
        return nil
    }
    
    public static func tokenUrl(token: ApiToken) -> URL {
        guard let tokenAddress = token.tokenAddress?.nilIfEmpty else {
            return URL(string: "https://coinmarketcap.com/currencies/\(token.cmcSlug ?? "")/")!
        }
        let network = AccountStore.activeNetwork
        let chain = token.chain
        if let explorer = selectedExplorerConfig(for: chain),
           let baseUrl = explorer.baseUrl[network] {
            let param = baseUrl.param ?? ""
            let str = explorer.token
                .replacing("{base}", with: baseUrl.url)
                .replacing("{address}", with: tokenAddress)
                + param
            return URL(string: str)!
        }
        let str = chain.explorer.token
            .replacing("{base}", with: chain.explorer.baseUrl[network]!.url)
            .replacing("{address}", with: tokenAddress)
            + (chain.explorer.baseUrl[network]!.param ?? "")
        return URL(string: str)!
    }
    
    public struct Website {
        public var title: String
        public var address: URL
    }
    
    public static func websitesForToken(_ token: ApiToken) -> [Website] {
        var websites: [Website] = []
        if let cmcSlug = token.cmcSlug?.nilIfEmpty,
           let url = URL(string: "https://coinmarketcap.com/currencies/\(cmcSlug)") {
            websites.append(Website(title: "CoinMarketCap", address: url))
        }
        if let url = websiteSearchURL(base: "https://www.coingecko.com/en/search", queryItemName: "query", query: token.name.lowercased()) {
            websites.append(Website(title: "CoinGecko", address: url))
        }
        if let url = websiteSearchURL(base: "https://www.geckoterminal.com/", queryItemName: "q", query: token.symbol.lowercased()) {
            websites.append(Website(title: "GeckoTerminal", address: url))
        }
        if let url = websiteSearchURL(base: "https://dexscreener.com/search", queryItemName: "q", query: token.name.lowercased()) {
            websites.append(Website(title: "DEX Screener", address: url))
        }
        return websites
    }

    private static func websiteSearchURL(base: String, queryItemName: String, query: String) -> URL? {
        guard let query = query.nilIfEmpty else { return nil }
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [URLQueryItem(name: queryItemName, value: query)]
        return components.url
    }

    public static func convertExplorerUrl(_ url: URL, toExplorerId: String) -> URL? {
        guard let explorerInfo = getExplorerByUrl(url) else {
            return nil
        }
        if explorerInfo.explorerId == toExplorerId {
            return url
        }
        let explorers = availableExplorers(for: explorerInfo.chain)
        guard let fromExplorer = explorers.first(where: { $0.id == explorerInfo.explorerId }),
              let toExplorer = explorers.first(where: { $0.id == toExplorerId }) else {
            return nil
        }
        let urlString = url.absoluteString
        let fromTestnetBase = fromExplorer.baseUrl[.testnet]?.url ?? ""
        let isTestnet = !fromTestnetBase.isEmpty && urlString.hasPrefix(fromTestnetBase)
        guard let fromBaseUrl = fromExplorer.baseUrl[isTestnet ? .testnet : .mainnet]?.url,
              let toBaseUrl = toExplorer.baseUrl[isTestnet ? .testnet : .mainnet]?.url else {
            return nil
        }
        let toParam = toExplorer.baseUrl[isTestnet ? .testnet : .mainnet]?.param ?? ""
        let pathAfterBase = String(urlString.dropFirst(fromBaseUrl.count))
        let patterns: [(from: String?, to: String?)] = [
            (fromExplorer.nftCollection, toExplorer.nftCollection),
            (fromExplorer.nft, toExplorer.nft),
            (fromExplorer.transaction, toExplorer.transaction),
            (fromExplorer.token, toExplorer.token),
            (fromExplorer.address, toExplorer.address),
        ]
        for pattern in patterns {
            guard let fromPattern = pattern.from, let toPattern = pattern.to else { continue }
            if let identifier = extractIdentifier(pathAfterBase, pattern: fromPattern) {
                return buildExplorerUrl(pattern: toPattern, baseUrl: toBaseUrl, identifier: identifier, param: toParam)
            }
        }
        return URL(string: toBaseUrl + pathAfterBase + toParam)
    }

    public static func selectedExplorerId(for chain: ApiChain) -> String {
        selectedExplorerConfig(for: chain)?.id ?? defaultExplorerId(for: chain)
    }

    public static func setSelectedExplorerId(_ explorerId: String, for chain: ApiChain) {
        AppStorageHelper.save(selectedExplorerId: explorerId, for: chain)
    }

    public static func selectedExplorerName(for chain: ApiChain) -> String {
        selectedExplorerConfig(for: chain)?.name ?? chain.explorer.name
    }

    public static func selectedExplorerMenuIconName(for chain: ApiChain) -> String {
        explorerMenuIconNames[selectedExplorerId(for: chain)] ?? "SendGlobe"
    }

    private typealias ExplorerConfig = ChainConfig.Explorer

    private static let explorerMenuIconNames = [
        "tonscan": "MenuTonscan26",
        "tonviewer": "MenuTonviewer26",
    ]

    private static func availableExplorers(for chain: ApiChain) -> [ExplorerConfig] {
        getAvailableExplorers(chain: chain)
    }

    private static func availableMarketplaces(for chain: ApiChain) -> [ChainConfig.Marketplace] {
        getAvailableMarketplaces(chain: chain)
    }

    private static func selectedExplorerConfig(for chain: ApiChain) -> ExplorerConfig? {
        let explorers = availableExplorers(for: chain)
        if let stored = AppStorageHelper.selectedExplorerId(for: chain),
           let explorer = explorers.first(where: { $0.id == stored }) {
            return explorer
        }
        if chain == .ton, let explorer = explorers.first(where: { $0.id == "tonscan" }) {
            return explorer
        }
        return explorers.first
    }

    private static func defaultExplorerId(for chain: ApiChain) -> String {
        if chain == .ton {
            return "tonscan"
        }
        return availableExplorers(for: chain).first?.id ?? "tonscan"
    }

    private static func getExplorerByUrl(_ url: URL) -> (chain: ApiChain, explorerId: String)? {
        guard let host = url.host?.lowercased() else { return nil }
        for chain in ApiChain.allCases {
            for explorer in availableExplorers(for: chain) {
                let mainnetHost = hostname(from: explorer.baseUrl[.mainnet]?.url ?? "")
                let testnetHost = hostname(from: explorer.baseUrl[.testnet]?.url ?? "")
                if let explorerId = explorer.id, host == mainnetHost || host == testnetHost {
                    return (chain, explorerId)
                }
            }
        }
        return nil
    }

    private static func hostname(from urlString: String) -> String? {
        URL(string: urlString)?.host?.lowercased()
    }

    private static func extractIdentifier(_ path: String, pattern: String) -> String? {
        let patternPath = pattern.replacingOccurrences(of: "{base}", with: "")
        let escapedPattern = NSRegularExpression.escapedPattern(for: patternPath)
        let regexPattern = escapedPattern
            .replacingOccurrences(of: "\\{address\\}", with: "([^?#/]+)")
            .replacingOccurrences(of: "\\{hash\\}", with: "([^?#/]+)")
        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)") else {
            return nil
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return String(path[matchRange])
    }

    private static func buildExplorerUrl(pattern: String, baseUrl: String, identifier: String, param: String) -> URL? {
        URL(string: pattern
            .replacingOccurrences(of: "{base}", with: baseUrl)
            .replacingOccurrences(of: "{address}", with: identifier)
            .replacingOccurrences(of: "{hash}", with: identifier)
        + param)
    }
}
