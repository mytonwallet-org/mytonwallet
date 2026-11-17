//
//  BadgeContent.swift
//
//  Created by nikstar on 24.06.2025.
//

import WalletCore
import WalletContext
import UIComponents

public enum BadgeContent: Equatable {
    case staking(StakingBadgeContent)
    case tokenLabel(text: String, style: BadgeView.TokenLabelStyle)

    var isTokenLabel: Bool {
        if case .tokenLabel = self {
            return true
        }
        return false
    }
}

@MainActor func getBadgeContent(
    slug: String,
    stakingBadge: StakingBadgeContent?
) -> BadgeContent? {
    if let stakingBadge {
        return .staking(stakingBadge)
    } else if let token = TokenStore.getToken(slug: slug), let label = token.badgeLabel {
        return .tokenLabel(text: label, style: token.isRwaStock ? .stock : .regular)
    }
    return nil
}
