import Foundation
import UIComponents
import WalletContext
import WalletCore

@MainActor
final class AgentV2ActionExecutor {
    private let coordinator: AgentV2Coordinator

    init(coordinator: AgentV2Coordinator) {
        self.coordinator = coordinator
    }

    func perform(_ action: AgentV2NativeAction, messageId: String) {
        Task { [weak self, coordinator] in
            guard let resolved = await coordinator.resolveAction(
                messageId: messageId,
                actionId: action.id
            ) else {
                self?.showUnavailableAction()
                return
            }
            await self?.perform(resolved)
        }
    }

    private func perform(_ resolved: AgentV2Coordinator.ResolvedAction) async {
        guard AccountStore.account?.id == resolved.accountId,
              AccountStore.accountsById[resolved.accountId] != nil else {
            showUnavailableAction()
            return
        }
        let action = resolved.value
        let accountContext = AccountContext(accountId: resolved.accountId)
        switch action.kind {
        case .openReceive:
            let chain = action.chain.flatMap(ApiChain.init(rawValue:))
            AppActions.showReceive(accountContext: accountContext, chain: chain)
        case .openStaking:
            guard let tokenSlug = action.tokenSlug else { return }
            let prefilledAmount: StakePrefilledAmount?
            switch action.stakeAmount?.kind {
            case .exact:
                prefilledAmount = action.stakeAmount?.value.map(StakePrefilledAmount.exact)
            case .all:
                prefilledAmount = .all
            case nil:
                prefilledAmount = nil
            }
            AppActions.showEarn(
                accountContext: accountContext,
                tokenSlug: tokenSlug,
                prefilledAmount: prefilledAmount
            )
        case .openSwap:
            guard accountContext.account.supportsSwap,
                  let parameters = Self.resolveSwapParameters(action, swapAssets: TokenStore.swapAssets) else {
                showUnavailableAction()
                return
            }
            await AppActions.showSwap(
                accountContext: accountContext,
                defaultSellingToken: parameters.sellingToken,
                defaultBuyingToken: parameters.buyingToken,
                defaultSellingAmount: parameters.sellingAmount,
                defaultBuyingAmount: parameters.buyingAmount,
                push: nil
            )
        case .openSend:
            guard let value = action.url,
                  let url = URL(string: value),
                  url.scheme == "mtw", url.host == "send" else {
                showUnavailableAction()
                return
            }
            let sendAccountContext = AccountContext(source: .current)
            if url.path.isEmpty || url.path == "/" {
                guard url.query == nil, url.fragment == nil else {
                    showUnavailableAction()
                    return
                }
                AppActions.showSendForm(accountContext: sendAccountContext, prefilledValues: .init())
            } else {
                guard let deeplink = Deeplink(url: url),
                      case .send(let chain, let address, let amount, let comment, let binaryPayload, let tokenSlug, let stateInit) = deeplink else {
                    showUnavailableAction()
                    return
                }
                // A link without `token` still names the network the resolver validated the recipient in
                AppActions.showSendForm(accountContext: sendAccountContext, prefilledValues: .init(
                    address: address, amount: amount, token: tokenSlug ?? chain.nativeToken.slug,
                    commentOrMemo: comment, binaryPayload: binaryPayload, stateInit: stateInit,
                    isMaxAmount: action.isMaxAmount
                ))
            }
        case .openPortfolio:
            AppActions.showPortfolio(accountContext: accountContext)
        case .openDapp:
            guard let url = action.url,
                  await AppActions.showExploreSite(siteUrl: url) else {
                showUnavailableAction()
                return
            }
        case .inactive:
            showUnavailableAction()
        }
    }

    static func resolveSwapParameters(
        _ action: ApiAgentV2ResolvedAction,
        swapAssets: [ApiToken]?
    ) -> (sellingToken: String?, buyingToken: String?, sellingAmount: Double?, buyingAmount: Double?)? {
        guard action.kind == .openSwap else { return nil }
        for slug in [action.tokenInSlug, action.tokenOutSlug].compactMap({ $0 }) {
            guard swapAssets?.contains(where: { $0.slug == slug }) == true else { return nil }
        }
        let amount: Double?
        if let rawAmount = action.swapAmount {
            guard let value = Double(rawAmount), value.isFinite, value > 0,
                  let side = action.amountSide,
                  (side == .source ? action.tokenInSlug : action.tokenOutSlug) != nil else { return nil }
            amount = value
        } else {
            guard action.amountSide == nil else { return nil }
            amount = nil
        }
        return (
            action.tokenInSlug,
            action.tokenOutSlug,
            action.amountSide == .source ? amount : nil,
            action.amountSide == .destination ? amount : nil
        )
    }

    private func showUnavailableAction() {
        AppActions.showToast(message: lang("This action is no longer available."))
    }
}
