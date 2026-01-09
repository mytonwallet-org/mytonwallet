//
//  BadgeHelper.swift
//  MyTonWalletAir
//
//  Created by nikstar on 24.06.2025.
//

import WalletCore
import WalletContext

public enum BadgeContent {
    case staking(StakingBadgeContent)
    case chain(ApiChain)
}

func getBadgeContent(accountContext: AccountContext, slug: String, isStaking: Bool) -> BadgeContent? {
    if let stakingBadge = accountContext.getStakingBadgeContent(tokenSlug: slug, isStaking: isStaking) {
        return .staking(stakingBadge)
    } else if let chain = accountContext.account.supportedChains.first(where: { $0.usdtSlug[accountContext.account.network] == slug }) {
        return .chain(chain)
    }
    return nil
}
