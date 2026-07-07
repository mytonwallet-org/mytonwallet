package org.mytonwallet.app_air.uicomponents.helpers

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance

object TokenNameHelper {

    fun getTokenName(token: MToken, tokenBalance: MTokenBalance): String {
        if (!tokenBalance.isVirtualStakingRow) {
            return displayName(token)
        }

        val baseName = when (tokenBalance.token) {
            USDE_SLUG -> "Ethena"
            else -> displayName(token)
        }

        return LocaleController.getStringWithKeyValues(
            "%token% Staking",
            listOf(Pair("%token%", baseName))
        )
    }

    private fun displayName(token: MToken): String {
        val name = token.name
        if (!token.isRwaStock) return name
        val label = token.label?.trim()?.takeIf { it.isNotEmpty() } ?: return name

        val trimmedName = name.trim()
        val candidates = listOf(label, label.removeSuffix("s"), label.removeSuffix("S"))
            .filter { it.isNotEmpty() }
            .distinct()
        for (candidate in candidates) {
            val stripped = stripLabel(trimmedName, candidate).trim()
            if (stripped != trimmedName) return stripped.ifEmpty { name }
        }
        return name
    }

    private fun stripLabel(name: String, label: String): String {
        if (name.length > label.length) {
            if (name.endsWith(label, ignoreCase = true)) {
                return name.substring(0, name.length - label.length)
            }
            if (name.startsWith(label, ignoreCase = true)) {
                return name.substring(label.length)
            }
        }
        return name
    }
}
