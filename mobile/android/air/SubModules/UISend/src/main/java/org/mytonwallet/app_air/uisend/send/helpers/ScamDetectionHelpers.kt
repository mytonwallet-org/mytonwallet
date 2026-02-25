package org.mytonwallet.app_air.uisend.send.helpers

import android.text.Spannable
import android.text.style.ForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.TRON_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

class ScamDetectionHelpers {
    companion object {
        const val HOUR = 60 * 60 * 1000

        fun shouldShowSeedPhraseScamWarning(
            transferTokenChain: MBlockchain
        ): Boolean {
            val account = AccountStore.activeAccount ?: return false

            // Only check for recently imported accounts (within 1 hour)
            val importedAt = account.importedAt
            if (importedAt == null || System.currentTimeMillis() - importedAt > HOUR) {
                return false
            }

            // Only show when trying to transfer TRON tokens
            if (transferTokenChain != MBlockchain.tron) {
                return false
            }

            // Check if account has TRON tokens (like USDT)
            val hasTronTokens = BalanceStore.getBalances(account.accountId)?.any { balance ->
                if (balance.key == TRON_USDT_SLUG)
                    return@any true
                val token = TokenStore.getToken(balance.key) ?: return false
                return@any (token.slug != TRON_SLUG && token.mBlockchain == MBlockchain.tron && balance.value > BigInteger.ZERO)
            } ?: false

            return hasTronTokens
        }

        private val HELP_CENTER_SEED_SCAM_URL = mapOf(
            "en" to "https://help.mytonwallet.io/intro/scams/leaked-seed-phrases",
            "ru" to "https://help.mytonwallet.io/ru/baza-znanii/moshennichestvo-i-skamy/slitye-sid-frazy"
        )

        fun scamWarningMessage(): CharSequence {
            val helpCenterString = LocaleController.getString("Help Center")
            val spannable =
                LocaleController.getString("\$seed_phrase_scam_warning")
                    .replace("%help_center_link%", helpCenterString)
                    .toProcessedSpannableStringBuilder()

            val helpCenterRegex = Regex(helpCenterString)
            val matches = helpCenterRegex.findAll(spannable)
            for (match in matches) {
                val start = match.range.first
                val end = match.range.last + 1

                spannable.setSpan(
                    ForegroundColorSpan(WColor.Tint.color),
                    start,
                    end,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                val helpCenterUrl = HELP_CENTER_SEED_SCAM_URL[WGlobalStorage.getLangCode()]
                    ?: HELP_CENTER_SEED_SCAM_URL["en"]!!
                spannable.setSpan(
                    WClickableSpan(helpCenterUrl) {
                        WalletCore.notifyEvent(WalletEvent.OpenUrl(helpCenterUrl))
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
