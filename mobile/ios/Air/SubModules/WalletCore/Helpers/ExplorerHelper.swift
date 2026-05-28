
import Foundation
import WalletContext


public final class ExplorerHelper {
    
    private init() {}
    
    
    public static func addressUrl(chain: ApiChain, address: String) -> URL {
        let network = AccountStore.activeNetwork
        let str = chain.explorer.address
            .replacing("{base}", with: chain.explorer.baseUrl[network]!)
            .replacing("{address}", with: address)
        return URL(string: str)!
    }
    
    public static func txUrl(chain: ApiChain, txHash: String) -> URL {
        let network = AccountStore.activeNetwork
        var txHash = txHash
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
}
