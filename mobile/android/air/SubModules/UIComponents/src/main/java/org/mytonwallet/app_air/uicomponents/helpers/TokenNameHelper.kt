package org.mytonwallet.app_air.uicomponents.helpers

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance

object TokenNameHelper {

    fun getTokenName(token: MToken, tokenBalance: MTokenBalance): String {
        if (!tokenBalance.isVirtualStakingRow) {
            return token.name
        }

        val baseName = when (tokenBalance.token) {
            USDE_SLUG -> "Ethena"
            else -> token.name
        }

        return LocaleController.getStringWithKeyValues(
            "%token% Staking",
            listOf(Pair("%token%", baseName))
        )
    }
}
