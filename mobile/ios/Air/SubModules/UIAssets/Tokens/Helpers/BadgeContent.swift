//
//  BadgeContent.swift
//
//  Created by nikstar on 24.06.2025.
//

import WalletCore
import WalletContext
import UIComponents

public enum BadgeContent {
    case staking(StakingBadgeContent)
    case chain(ApiChain)
    case tokenLabel(text: String, style: BadgeView.TokenLabelStyle)

    var isTokenLabel: Bool {
        if case .tokenLabel = self {
            return true
        }
        return false
    }
}

@MainActor func getBadgeContent(accountContext: AccountContext, slug: String, isStaking: Bool) -> BadgeContent? {
    if let stakingBadge = accountContext.getStakingBadgeContent(tokenSlug: slug, isStaking: isStaking) {
        return .staking(stakingBadge)
    } else if let token = TokenStore.getToken(slug: slug), let label = token.label?.nilIfEmpty {
        return .tokenLabel(text: label, style: token.isRwaStock ? .stock : .regular)
    } else if let chain = accountContext.account.supportedChains.first(where: { $0.usdtSlug[accountContext.account.network] == slug }) {
        return .chain(chain)
    }
    return nil
}
