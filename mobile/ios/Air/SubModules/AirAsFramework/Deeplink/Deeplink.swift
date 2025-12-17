
import Foundation
import UIInAppBrowser
import WalletCore
import WalletContext

enum Deeplink {
    case tonConnect2(requestLink: String)
    case invoice(address: String, amount: BigInt?, comment: String?, binaryPayload: String?, token: String?, jetton: String?, stateInit: String?)
    case swap(from: String?, to: String?, amountIn: Double?)
    case buyWithCard
    case stake
    case url(config: InAppBrowserPageVC.Config)
    case switchToClassic
    case transfer
    case receive
    case explore
    case tokenSlug(slug: String)
    case tokenAddress(chain: String, tokenAddress: String)
    case transaction(chain: ApiChain, txId: String)
    case view(addressOrDomainByChain: [String: String])
}
