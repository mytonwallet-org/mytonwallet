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

func badgeContent(slug: String, isStaking: Bool) -> BadgeContent? {
    if slug == TONCOIN_SLUG, let apy = BalanceStore.currentAccountStakingData?.tonState?.apy {
        let hasBalance = BalanceStore.currentAccountBalances[STAKED_TON_SLUG] ?? 0 > 0
        if isStaking && hasBalance {
            return .activeStaking(.apy, apy)
        } else if !isStaking && !hasBalance {
            return .inactiveStaking(.apy, apy)
        }
    } else if slug == MYCOIN_SLUG, let apy = BalanceStore.currentAccountStakingData?.mycoinState?.apy {
        let hasBalance = BalanceStore.currentAccountBalances[STAKED_MYCOIN_SLUG] ?? 0 > 0
        if isStaking && hasBalance {
            return .activeStaking(.apr, apy)
        } else if !isStaking && !hasBalance {
            return .inactiveStaking(.apr, apy)
        }
    } else if slug == TON_USDE_SLUG, let apy = BalanceStore.currentAccountStakingData?.ethenaState?.apy {
        let hasBalance = BalanceStore.currentAccountBalances[TON_TSUSDE_SLUG] ?? 0 > 0
        if isStaking && hasBalance {
            return .activeStaking(.apy, apy)
        } else if !isStaking && !hasBalance {
            return .inactiveStaking(.apy, apy)
        }
    } else if AccountStore.account?.isMultichain == true && (slug == TON_USDT_SLUG || slug == TRON_USDT_SLUG) {
        return .chain(slug == TON_USDT_SLUG ? .ton : .tron)
    }
    return nil
}
