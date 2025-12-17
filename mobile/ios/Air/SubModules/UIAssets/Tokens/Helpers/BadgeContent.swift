//
//  BadgeHelper.swift
//  MyTonWalletAir
//
//  Created by nikstar on 24.06.2025.
//

import WalletCore
import WalletContext

public enum BadgeContent {
    case activeStaking(ApiYieldType, Double)
    case inactiveStaking(ApiYieldType, Double)
    case chain(ApiChain)
}

func badgeContent(accountId: String, slug: String, isStaking: Bool) -> BadgeContent? {
    lazy var stakingData = StakingStore.byId(accountId)
    lazy var balances = BalanceStore.getAccountBalances(accountId: accountId)
    if slug == TONCOIN_SLUG, let apy = stakingData?.tonState?.apy {
        let hasBalance = balances[STAKED_TON_SLUG] ?? 0 > 0
        if isStaking && hasBalance {
            return .activeStaking(.apy, apy)
        } else if !isStaking && !hasBalance {
            return .inactiveStaking(.apy, apy)
        }
    } else if slug == MYCOIN_SLUG, let apy = stakingData?.mycoinState?.apy {
        let hasBalance = balances[STAKED_MYCOIN_SLUG] ?? 0 > 0
        if isStaking && hasBalance {
            return .activeStaking(.apr, apy)
        } else if !isStaking && !hasBalance {
            return .inactiveStaking(.apr, apy)
        }
    } else if slug == TON_USDE_SLUG, let apy = stakingData?.ethenaState?.apy {
        let hasBalance = balances[TON_TSUSDE_SLUG] ?? 0 > 0
        if isStaking && hasBalance {
            return .activeStaking(.apy, apy)
        } else if !isStaking && !hasBalance {
            return .inactiveStaking(.apy, apy)
        }
    } else if (slug == TON_USDT_SLUG || slug == TRON_USDT_SLUG) && AccountStore.accountsById[accountId]?.isMultichain == true {
        return .chain(slug == TON_USDT_SLUG ? .ton : .tron)
    }
    return nil
}
