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

func getBadgeContent(accountId: String, slug: String, isStaking: Bool) -> BadgeContent? {
    @AccountViewModel(accountId: accountId) var account
    if let stakingBadge = $account.getStakingBadgeContent(tokenSlug: slug, isStaking: isStaking) {
        return .staking(stakingBadge)
    } else if let chain = account.supportedChains.first(where: { $0.usdtSlug[account.network] == slug }) {
        return .chain(chain)
    }
    return nil
}
