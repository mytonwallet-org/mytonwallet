import Foundation
import WalletContext

public enum Deeplink {
    case tonConnect2(requestLink: String)
    case walletConnect(requestLink: String)
    case agent
    case agentNews(eventId: Int)
    case agentDigest(id: String)
    case invoice(address: String, amount: BigInt?, comment: String?, binaryPayload: String?, token: String?, jetton: String?, stateInit: String?)
    case send(chain: ApiChain, address: String, amount: BigInt?, comment: String?, binaryPayload: String?, tokenSlug: String?, stateInit: String?)
    case swap(from: String?, to: String?, amountIn: Double?)
    case buyWithCard
    case sellOnCard
    case sell(Sell)
    case stake
    case multisend
    case portfolio
    case market
    case mintCard
    case url(url: URL, title: String?, injectDappConnect: Bool)
    case transfer
    case receive
    case explore(siteHost: String?)
    case tokenSlug(slug: String)
    case tokenAddress(chain: ApiChain, tokenAddress: String)
    case transaction(chain: ApiChain, txId: String)
    case nftAddress(nftAddress: String)
    case view(network: ApiNetwork, addressOrDomainByChain: [String: String])
    case settings(section: AppSettingsSection?)
    /// UI tests: `mtw://e2e-unlock?passcode=…&next=…`, parsed in DEBUG builds only.
    /// `next` is a link opened once the app is unlocked.
    case e2eUnlock(passcode: String, next: URL?)
}

public extension Deeplink {
    var isAllowedFromExploreSearchBar: Bool {
        switch self {
        case .url, .e2eUnlock:
            false
        default:
            true
        }
    }
}
