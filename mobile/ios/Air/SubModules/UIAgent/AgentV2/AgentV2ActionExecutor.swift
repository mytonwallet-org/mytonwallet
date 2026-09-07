import BigInt
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
            guard let tokenInSlug = action.tokenInSlug,
                  let tokenOutSlug = action.tokenOutSlug,
                  let rawAmount = action.swapAmount,
                  let amount = Double(rawAmount),
                  amount.isFinite,
                  amount > 0,
                  let amountSide = action.amountSide else { return }
            await AppActions.showSwap(
                accountContext: accountContext,
                defaultSellingToken: tokenInSlug,
                defaultBuyingToken: tokenOutSlug,
                defaultSellingAmount: amountSide == .source ? amount : nil,
                defaultBuyingAmount: amountSide == .destination ? amount : nil,
                push: nil
            )
        case .openSend:
            guard let tokenSlug = action.tokenSlug else { return }
            AppActions.showSend(
                accountContext: accountContext,
                prefilledValues: SendPrefilledValues(address: action.toAddress, token: tokenSlug)
            )
        case .reviewSend:
            guard let review = action.review,
                  let amount = BigInt(review.amountAtomic) else { return }
            AppActions.showSend(
                accountContext: accountContext,
                prefilledValues: SendPrefilledValues(
                    address: review.toAddress,
                    amount: amount,
                    token: review.tokenSlug,
                    commentOrMemo: review.comment
                )
            )
        case .openPortfolio:
            AppActions.showPortfolio(accountContext: accountContext)
        case .hideSpamAssets:
            guard let slugs = action.slugs,
                  !slugs.isEmpty else {
                showUnavailableAction()
                return
            }
            AssetsAndActivityDataStore.update(accountId: resolved.accountId) { settings in
                for slug in slugs {
                    settings.saveTokenHidden(slug: slug, isStaking: false, isHidden: true)
                }
            }
        case .openUrl:
            guard let value = action.url,
                  let url = URL(string: value),
                  url.scheme?.lowercased() == "https" else { return }
            AppActions.openInBrowser(url, title: nil, injectDappConnect: false)
        case .openToken:
            guard let chain = action.chain.flatMap(ApiChain.init(rawValue:)) else { return }
            if let tokenAddress = action.tokenAddress {
                AppActions.showTokenByAddress(chain: chain, tokenAddress: tokenAddress)
            } else if let slug = action.slug {
                AppActions.showTokenBySlug(slug)
            }
        case .openTransaction:
            guard let chain = action.chain.flatMap(ApiChain.init(rawValue:)),
                  let transactionRef = action.transactionRef else { return }
            AppActions.showActivityDetailsById(chain: chain, txId: transactionRef, showError: true)
        case .openAgent:
            AppActions.showAgent()
        case .inactive:
            showUnavailableAction()
        }
    }

    private func showUnavailableAction() {
        AppActions.showToast(message: lang("This action is no longer available."))
    }
}
