
import Foundation
import WalletContext


public final class ExplorerHelper {
    
    private init() {}
    
    
    public static func addressUrl(chain: ApiChain, address: String) -> URL {
        let isMainnet = AccountStore.activeNetwork == .mainnet
        let str: String
        switch chain {
        case .ton:
            let domain = isMainnet ? "tonscan.org" : "testnet.tonscan.org"
            str = "https://\(domain)/address/\(address)"
        case .tron:
            str = "\(isMainnet ? "https://tronscan.org/#/address/" : "https://shasta.tronscan.org/#/address/")\(address)"
        }
        return URL(string: str)!
    }
    
    public static func txUrl(chain: ApiChain, txHash: String) -> URL {
        let isMainnet = AccountStore.activeNetwork == .mainnet
        let str: String
        switch chain {
        case .ton:
            let domain = isMainnet ? "tonscan.org" : "testnet.tonscan.org"
            str = "https://\(domain)/tx/\(txHash.base64ToHex ?? "")"
        case .tron:
            str = "\(isMainnet ? "https://tronscan.org/#/transaction/" : "https://shasta.tronscan.org/#/transaction/")\(txHash)"
        }
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
    
    public static func explorerUrlForToken(_ token: ApiToken) -> URL {
        if token.tokenAddress?.isEmpty ?? true {
            return URL(string: "https://coinmarketcap.com/currencies/\(token.cmcSlug!)/")!
        }

        let isMainnet = AccountStore.activeNetwork == .mainnet
        let chain = ApiChain(rawValue: token.chain) ?? ApiChain.ton
        switch chain {
        case .ton:
            let domain = isMainnet ? "https://tonscan.org" : "https://testnet.tonscan.org"
            return URL(string: "\(domain)/jetton/\(token.tokenAddress ?? "")")!
        case .tron:
            let domain = isMainnet ? "https://tronscan.org/#" : "https://shasta.tronscan.org/#"
            return URL(string: "\(domain)/token20/\(token.tokenAddress ?? "")")!
        }
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
