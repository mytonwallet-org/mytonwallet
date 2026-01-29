
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
            let str = explorer.address
                .replacing("{base}", with: baseUrl)
                .replacing("{address}", with: address)
            return URL(string: str)!
        }
        let str = chain.explorer.address
            .replacing("{base}", with: chain.explorer.baseUrl[network]!)
            .replacing("{address}", with: address)
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
            let str = explorer.transaction
                .replacing("{base}", with: baseUrl)
                .replacing("{hash}", with: txHash)
            return URL(string: str)!
        }
        if chain.explorer.doConvertHashFromBase64 {
            txHash = txHash.base64ToHex
        }
        let str = chain.explorer.transaction
            .replacing("{base}", with: chain.explorer.baseUrl[network]!)
            .replacing("{hash}", with: txHash)
        return URL(string: str)!
    }

    public static func nftUrl(_ nft: ApiNft) -> URL {
        URL(string: "https://getgems.io/collection/\(nft.collectionAddress ?? "")/\(nft.address)")!
    }
    
    public static func tonscanNftUrl(_ nft: ApiNft) -> URL {
        return URL(string: "https://tonscan.org/nft/\(nft.address)")!
    }

    public static func explorerNftUrl(_ nft: ApiNft, explorerId: String? = nil) -> URL {
        let baseUrl = tonscanNftUrl(nft)
        let targetId = explorerId ?? selectedExplorerId(for: .ton)
        return convertExplorerUrl(baseUrl, toExplorerId: targetId) ?? baseUrl
    }
    
    public static func nftCollectionUrl(_ nft: ApiNft) -> URL {
        URL(string: "https://getgems.io/collection/\(nft.collectionAddress ?? "")")!
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
        let chain = token.chainValue
        if let explorer = selectedExplorerConfig(for: chain),
           let baseUrl = explorer.baseUrl[network] {
            let str = explorer.token
                .replacing("{base}", with: baseUrl)
                .replacing("{address}", with: tokenAddress)
            return URL(string: str)!
        }
        let str = chain.explorer.token
            .replacing("{base}", with: chain.explorer.baseUrl[network]!)
            .replacing("{address}", with: tokenAddress)
        return URL(string: str)!
    }
    
    public struct Website {
        public var title: String
        public var address: URL
    }
    
    public static func websitesForToken(_ token: ApiToken) -> [Website] {
        var websites: [Website] = []
        if let cmcSlug = token.cmcSlug {
            websites += Website(title: "CoinMarketCap", address: URL(string: "https://coinmarketcap.com/currencies/\(cmcSlug)")!)
        }
        websites += [
            Website(title: "CoinGecko", address: URL(string: "https://www.coingecko.com/coins/\(token.name.lowercased())")!),
            Website(title: "GeckoTerminal", address: URL(string: "https://www.geckoterminal.com/?q=\(token.symbol.lowercased())")!),
            Website(title: "DEX Screener", address: URL(string: "https://dexscreener.com/search?q=\(token.name.lowercased())")!),
        ]
        return websites
    }

    public static func convertExplorerUrl(_ url: URL, toExplorerId: String) -> URL? {
        guard let explorerInfo = getExplorerByUrl(url) else {
            return nil
        }
        if explorerInfo.explorerId == toExplorerId {
            return url
        }
        let explorers = getAvailableExplorers(explorerInfo.chain)
        guard let fromExplorer = explorers.first(where: { $0.id == explorerInfo.explorerId }),
              let toExplorer = explorers.first(where: { $0.id == toExplorerId }) else {
            return nil
        }
        let urlString = url.absoluteString
        let fromTestnetBase = fromExplorer.baseUrl[.testnet] ?? ""
        let isTestnet = !fromTestnetBase.isEmpty && urlString.hasPrefix(fromTestnetBase)
        guard let fromBaseUrl = fromExplorer.baseUrl[isTestnet ? .testnet : .mainnet],
              let toBaseUrl = toExplorer.baseUrl[isTestnet ? .testnet : .mainnet] else {
            return nil
        }
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
                return buildExplorerUrl(pattern: toPattern, baseUrl: toBaseUrl, identifier: identifier)
            }
        }
        return URL(string: toBaseUrl + pathAfterBase)
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
        if selectedExplorerId(for: chain) == "tonviewer" {
            return "MenuTonviewer26"
        }
        return "MenuTonscan26"
    }

    private struct ExplorerConfig {
        let id: String
        let name: String
        let baseUrl: [ApiNetwork: String]
        let address: String
        let token: String
        let transaction: String
        let nft: String?
        let nftCollection: String?
        let doConvertHashFromBase64: Bool
    }

    private static let explorerConfigsByChain: [ApiChain: [ExplorerConfig]] = [
        .ton: [
            ExplorerConfig(
                id: "tonscan",
                name: "Tonscan",
                baseUrl: [
                    .mainnet: "https://tonscan.org/",
                    .testnet: "https://testnet.tonscan.org/",
                ],
                address: "{base}address/{address}",
                token: "{base}jetton/{address}",
                transaction: "{base}tx/{hash}",
                nft: "{base}nft/{address}",
                nftCollection: "{base}collection/{address}",
                doConvertHashFromBase64: true
            ),
            ExplorerConfig(
                id: "tonviewer",
                name: "Tonviewer",
                baseUrl: [
                    .mainnet: "https://tonviewer.com/",
                    .testnet: "https://testnet.tonviewer.com/",
                ],
                address: "{base}{address}?address",
                token: "{base}{address}?jetton",
                transaction: "{base}transaction/{hash}",
                nft: "{base}{address}?nft",
                nftCollection: "{base}{address}?collection",
                doConvertHashFromBase64: true
            ),
        ],
        .tron: [
            ExplorerConfig(
                id: "tronscan",
                name: "Tronscan",
                baseUrl: [
                    .mainnet: "https://tronscan.org/#/",
                    .testnet: "https://shasta.tronscan.org/#/",
                ],
                address: "{base}address/{address}",
                token: "{base}token20/{address}",
                transaction: "{base}transaction/{hash}",
                nft: nil,
                nftCollection: nil,
                doConvertHashFromBase64: false
            ),
        ],
    ]

    private static func getAvailableExplorers(_ chain: ApiChain) -> [ExplorerConfig] {
        explorerConfigsByChain[chain] ?? []
    }

    private static func selectedExplorerConfig(for chain: ApiChain) -> ExplorerConfig? {
        let explorers = getAvailableExplorers(chain)
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
        return getAvailableExplorers(chain).first?.id ?? "tonscan"
    }

    private static func getExplorerByUrl(_ url: URL) -> (chain: ApiChain, explorerId: String)? {
        guard let host = url.host?.lowercased() else { return nil }
        for chain in ApiChain.allCases {
            for explorer in getAvailableExplorers(chain) {
                let mainnetHost = hostname(from: explorer.baseUrl[.mainnet] ?? "")
                let testnetHost = hostname(from: explorer.baseUrl[.testnet] ?? "")
                if host == mainnetHost || host == testnetHost {
                    return (chain, explorer.id)
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

    private static func buildExplorerUrl(pattern: String, baseUrl: String, identifier: String) -> URL? {
        URL(string: pattern
            .replacingOccurrences(of: "{base}", with: baseUrl)
            .replacingOccurrences(of: "{address}", with: identifier)
            .replacingOccurrences(of: "{hash}", with: identifier)
        )
    }
}
