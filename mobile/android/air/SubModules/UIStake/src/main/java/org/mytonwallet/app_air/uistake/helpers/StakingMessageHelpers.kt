package org.mytonwallet.app_air.uistake.helpers

import android.text.Spannable
import android.text.style.ForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

class StakingMessageHelpers {
    companion object {
        fun whyStakingIsSafeDescription(tokenSlug: String): CharSequence? {
            val spannable = LocaleController.getString(
                when (tokenSlug) {
                    TONCOIN_SLUG ->
                        LocaleController.getString("\$safe_staking_description1") + "\n\n" +
                            LocaleController.getStringWithKeyValues(
                                "\$safe_staking_description2",
                                listOf(
                                    Pair("%chain%", MBlockchain.ton.displayName),
                                )
                            ) + "\n\n" +
                            LocaleController.getString("\$safe_staking_description3")

                    MYCOIN_SLUG ->
                        (LocaleController.getString("\$safe_staking_description_jetton1") + "\n\n" +
                            LocaleController.getString("\$safe_staking_description_jetton2"))
                            .replace("%jvault_link%", "JVault")

                    USDE_SLUG ->
                        LocaleController.getString("\$safe_staking_ethena_description1") + "\n\n" +
                            LocaleController.getString("\$safe_staking_ethena_description2") + "\n\n" +
                            LocaleController.getString("\$safe_staking_ethena_description3")

                    else -> return null
                }
            ).toProcessedSpannableStringBuilder()

            val jvaultRegex = Regex("JVault")
            val matches = jvaultRegex.findAll(spannable)
            for (match in matches) {
                val start = match.range.first
                val end = match.range.last + 1

                spannable.setSpan(
                    ForegroundColorSpan(WColor.Tint.color),
                    start,
                    end,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                val jVaultURL = "https://jvault.xyz"
                spannable.setSpan(
                    WClickableSpan(jVaultURL) {
                        WalletCore.notifyEvent(WalletEvent.OpenUrl(jVaultURL))
                    },
                    start,
                    end,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }

            return spannable
        }
    }
}
