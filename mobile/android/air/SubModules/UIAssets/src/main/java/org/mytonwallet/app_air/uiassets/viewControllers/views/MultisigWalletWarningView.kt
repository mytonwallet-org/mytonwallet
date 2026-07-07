package org.mytonwallet.app_air.uiassets.viewControllers.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.method.LinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent

@SuppressLint("ViewConstructor")
class MultisigWalletWarningView(context: Context) :
    WAlertLabel(context, alertColor = WColor.Red.color, coloredText = true),
    WThemedView {

    companion object {
        private fun helpUrl(): String {
            val ctx = ApplicationContextHolder.applicationContext
            val resId = if (WGlobalStorage.getLangCode() == "ru") BaseR.string.app_help_scam_url_ru
            else BaseR.string.app_help_scam_url_en
            return ctx.getString(resId).ifEmpty { ctx.getString(BaseR.string.app_help_scam_url_en) }
        }
    }

    init {
        movementMethod = LinkMovementMethod.getInstance()
        configure()
    }

    private fun configure() {
        val appName = ApplicationContextHolder.applicationContext
            .getString(BaseR.string.app_locale_name_key)
        val url = helpUrl()
        val link = LocaleController.getString("\$multisig_warning_link")
        val linkSpannable = SpannableStringBuilder(link).apply {
            setSpan(
                WClickableSpan(url) {
                    if (url.isNotEmpty())
                        WalletCore.notifyEvent(WalletEvent.OpenUrl(url))
                },
                0, length,
                SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        val body = LocaleController.getSpannableStringWithKeyValues(
            "\$multisig_warning_text",
            listOf(
                Pair("%app_name%", appName),
                Pair("%multisig_warning_link%", linkSpannable)
            )
        ).toProcessedSpannableStringBuilder()

        text = SpannableStringBuilder(
            LocaleController.getString("Multisig Wallet Detected").toProcessedSpannableStringBuilder()
        ).apply {
            setSpan(
                android.text.style.StyleSpan(android.graphics.Typeface.BOLD),
                0, length,
                SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            append("\n")
            append(body)
        }
    }

    override fun updateTheme() {
        setLinkTextColor(WColor.Red.color)
        highlightColor = WColor.Tint.color
        configure()
    }
}