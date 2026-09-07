import Foundation
import WalletCore

enum SwapHint: Equatable {
    case receive(chain: ApiChain, hasAlternativeToken: Bool)
    case belowMinimum(chain: ApiChain)
    case intermediate(token: ApiToken, buyingToken: ApiToken)
    case external(providerName: String, url: URL)

    @MainActor
    static func fromBackend(_ hint: ApiSwapHint?, sellingToken: ApiToken?, buyingToken: ApiToken?) -> SwapHint? {
        guard let hint, let sellingToken, let buyingToken else { return nil }
        switch hint.type {
        case "intermediate":
            guard let slug = hint.token,
                  let token = TokenStore.getToken(slug: slug),
                  token.slug != sellingToken.slug, token.slug != buyingToken.slug else { return nil }
            return .intermediate(token: token, buyingToken: buyingToken)
        case "external":
            guard let providerName = hint.providerName, !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rawUrl = hint.url, let url = URL(string: rawUrl),
                  url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
            return .external(providerName: providerName, url: url)
        default:
            return nil
        }
    }

    @MainActor
    static func resolve(estimate: ApiSwapEstimateResponse?, accountContext: AccountContext, sellingToken: ApiToken?, buyingToken: ApiToken?) -> SwapHint? {
        if let hint = fromBackend(estimate?.hint, sellingToken: sellingToken, buyingToken: buyingToken) {
            return hint
        }
        guard let buyingToken, accountContext.account.supports(chain: buyingToken.chain) else { return nil }
        let balances = accountContext.balances
        if let sellingToken, accountContext.account.supports(chain: sellingToken.chain), case .cex(let estimate) = estimate,
           balances[sellingToken.slug, default: 0] < estimate.fromMin.bigintAmount(decimals: sellingToken.decimals) {
            return .belowMinimum(chain: buyingToken.chain)
        }
        if let sellingToken, sellingToken.slug != buyingToken.slug, balances[sellingToken.slug, default: 0] > 0 {
            return nil
        }
        let hasAlternativeToken = balances.contains { slug, balance in
            slug != buyingToken.slug && balance > 0 && TokenStore.getToken(slug: slug)?.type != .lp_token
        }
        return .receive(chain: buyingToken.chain, hasAlternativeToken: hasAlternativeToken)
    }
}
