import Foundation
import WalletContext

public enum Deeplink {
    case tonConnect2(requestLink: String)
    case walletConnect(requestLink: String)
    case agent
    case invoice(address: String, amount: BigInt?, comment: String?, binaryPayload: String?, token: String?, jetton: String?, stateInit: String?)
    case send(chain: ApiChain, address: String, amount: BigInt?, comment: String?, binaryPayload: String?, tokenSlug: String?, stateInit: String?)
    case swap(from: String?, to: String?, amountIn: Double?)
    case buyWithCard
    case sell(Sell)
    case stake
    case portfolio
    case url(url: URL, title: String?, injectDappConnect: Bool)
    case switchToClassic
    case transfer
    case receive
    case explore(siteHost: String?)
    case tokenSlug(slug: String)
    case tokenAddress(chain: ApiChain, tokenAddress: String)
    case transaction(chain: ApiChain, txId: String)
    case nftAddress(nftAddress: String)
    case view(network: ApiNetwork, addressOrDomainByChain: [String: String])
    case settings(section: AppSettingsSection?)
}

public extension Deeplink {
    var isAllowedFromExploreSearchBar: Bool {
        switch self {
        case .switchToClassic, .url:
            false
        default:
            true
        }
    }
}
