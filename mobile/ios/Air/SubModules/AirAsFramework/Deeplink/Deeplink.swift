
import Foundation
import UIInAppBrowser
import WalletCore
import WalletContext

enum Deeplink {
    case tonConnect2(requestLink: String)
    case walletConnect(requestLink: String)
    case invoice(address: String, amount: BigInt?, comment: String?, binaryPayload: String?, token: String?, jetton: String?, stateInit: String?)
    case swap(from: String?, to: String?, amountIn: Double?)
    case buyWithCard
    case sell(Sell)
    case stake
    case url(config: InAppBrowserPageConfig)
    case switchToClassic
    case transfer
    case receive
    case explore(siteHost: String?)
    case tokenSlug(slug: String)
    case tokenAddress(chain: ApiChain, tokenAddress: String)
    case transaction(chain: ApiChain, txId: String)
    case nftAddress(nftAddress: String)
    case view(addressOrDomainByChain: [String: String])
}

extension Deeplink {
    var isAllowedFromExploreSearchBar: Bool {
        switch self {
        case .switchToClassic, .url:
            false
        default:
            true
        }
    }
}
