import ContextMenuKit
import UIComponents
import WalletContext
import WalletCore

private let walletTokenMenuStyle = ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)

@MainActor
final class WalletTokenActions {
    private let accountContext: AccountContext
    private let isInModal: Bool

    init(accountContext: AccountContext, isInModal: Bool) {
        self.accountContext = accountContext
        self.isInModal = isInModal
    }

    func open(_ walletToken: MTokenBalance) {
        let slug = walletToken.tokenSlug
        if walletToken.isStaking || accountContext.stakingData?.byStakedSlug(slug) != nil {
            goToStakedPage(slug: slug)
        } else {
            guard let token = TokenStore.tokens[slug] else {
                return Log.shared.error("Token \(slug) not found")
            }
            AppActions.showToken(accountSource: accountContext.source, token: token, isInModal: isInModal)
        }
    }

    private func stakingBaseSlug(for slug: String) -> String? {
        accountContext.stakingData?.byTokenSlug(slug)?.tokenSlug
    }

    private func goToStakedPage(slug: String) {
        AppActions.showEarn(accountContext: accountContext, tokenSlug: stakingBaseSlug(for: slug))
    }

    private func showEarnForToken(slug: String, isStaking: Bool) {
        if isStaking {
            goToStakedPage(slug: slug)
        } else {
            AppActions.showEarn(accountContext: accountContext, tokenSlug: slug)
        }
    }

    func makeContextMenuConfiguration(walletToken: MTokenBalance) -> ContextMenuConfiguration? {
        let tokenSlug = walletToken.tokenSlug
        let matchedStakingState = accountContext.stakingData?.byTokenSlug(tokenSlug)
        let isStakingPosition = walletToken.isStaking || accountContext.stakingData?.byStakedSlug(tokenSlug) != nil
        let stakingState = isStakingPosition ? matchedStakingState : nil
        let baseSlug = stakingState?.tokenSlug ?? tokenSlug
        guard let token = TokenStore.getToken(slug: tokenSlug) ?? TokenStore.getToken(slug: baseSlug) else {
            return nil
        }
        let account = accountContext.account
        let accountID = account.id
        let isViewMode = account.isView
        let isServiceToken = token.type == .lp_token || token.isStakedToken || token.isPricelessToken
        let isSwapAvailable = account.supportsSwap && (TokenStore.swapAssets?.contains(where: { $0.slug == token.slug }) ?? false)

        let canBeClaimed = stakingState.map { getStakingStateStatus(state: $0) == .readyToClaim } ?? false
        let hasUnclaimedRewards = stakingState?.type == .jetton ? (stakingState?.unclaimedRewards ?? 0) > 0 : false
        let isStakingAvailable = !isStakingPosition && accountContext.isEarnAvailable(forTokenSlug: token.slug)
        let isStakingToken = isStakingPosition

        var primaryItems: [ContextMenuItem] = []
        var secondaryItems: [ContextMenuItem] = []

        if !isViewMode {
            if let stakingState {
                if baseSlug != MYCOIN_SLUG {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Stake More"),
                            icon: .system("arrow.up"),
                            handler: { [weak self] in
                                self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                            }
                        )
                    ))
                }
                if stakingState.type != .ethena || !canBeClaimed {
                    let title = stakingState.type == .ethena ? lang("Request Unstaking") : lang("Unstake")
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: title,
                            icon: .system("arrow.down"),
                            handler: { [weak self] in
                                self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                            }
                        )
                    ))
                }
                if canBeClaimed || hasUnclaimedRewards {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Claim Rewards"),
                            icon: .system("bubbles.and.sparkles"),
                            handler: { [weak self] in
                                self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                            }
                        )
                    ))
                }
            } else {
                if !isServiceToken {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Fund"),
                            icon: .system("plus"),
                            handler: { [weak self] in
                                guard let self else { return }
                                AppActions.showReceive(
                                    accountContext: accountContext,
                                    chain: token.chain,
                                    buyingToken: token.slug
                                )
                            }
                        )
                    ))
                }
                primaryItems.append(.action(
                    ContextMenuAction(
                        title: lang("Send"),
                        icon: .system("arrow.up"),
                        handler: { [weak self] in
                            guard let self else { return }
                            AppActions.showSend(accountContext: accountContext, prefilledValues: .init(token: token.slug))
                        }
                    )
                ))
                if isSwapAvailable {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Swap"),
                            icon: .system("arrow.left.arrow.right"),
                            handler: { [weak self] in
                                guard let self else { return }
                                Task { [accountContext] in
                                    await AppActions.showSwap(
                                        accountContext: accountContext,
                                        defaultSellingToken: token.slug,
                                        defaultBuyingToken: nil,
                                        defaultSellingAmount: nil,
                                        push: nil
                                    )
                                }
                            }
                        )
                    ))
                }
                if isStakingAvailable {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Stake"),
                            icon: .system("cylinder.split.1x2"),
                            handler: { [weak self] in
                                guard let self else { return }
                                AppActions.showEarn(accountContext: accountContext, tokenSlug: token.slug)
                            }
                        )
                    ))
                }
            }
        }

        let assetsAndActivityData = AssetsAndActivityDataStore.data(accountId: accountID) ?? .empty
        let isStaking = walletToken.isStaking
        switch assetsAndActivityData.isTokenPinned(slug: walletToken.tokenSlug, isStaked: walletToken.isStaking) {
        case .pinned:
            secondaryItems.append(.action(
                ContextMenuAction(
                    title: lang("Unpin"),
                    icon: .system("pin.slash"),
                    handler: {
                        AssetsAndActivityDataStore.update(accountId: accountID, update: { settings in
                            settings.saveTokenPinning(slug: tokenSlug, isStaking: isStaking, isPinned: false)
                        })
                    }
                )
            ))
        case .notPinned:
            secondaryItems.append(.action(
                ContextMenuAction(
                    title: lang("Pin"),
                    icon: .system("pin"),
                    handler: {
                        AssetsAndActivityDataStore.update(accountId: accountID, update: { settings in
                            settings.saveTokenPinning(slug: tokenSlug, isStaking: isStaking, isPinned: true)
                        })
                    }
                )
            ))
        }

        secondaryItems.append(.action(
            ContextMenuAction(
                title: lang("Manage Assets"),
                icon: .airBundle("MenuManageAssets26"),
                handler: {
                    AppActions.showAssetsAndActivity()
                }
            )
        ))

        var items = primaryItems
        if !items.isEmpty, !secondaryItems.isEmpty {
            items.append(.separator)
        }
        items.append(contentsOf: secondaryItems)

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .defaultBlurred(),
            style: walletTokenMenuStyle
        )
    }
}
