package org.mytonwallet.app_air.uitransaction.viewControllers.transaction

import android.content.Context
import android.net.Uri
import android.text.method.LinkMovementMethod
import android.text.style.URLSpan
import android.util.Patterns
import android.widget.LinearLayout
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uiinappbrowser.span.InAppBrowserUrlSpan
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.SpanHelpers
import org.mytonwallet.app_air.walletcore.moshi.ApiSwapStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexTransactionStatus as CexStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

internal class CexActivityDetailsFooter(context: Context) : LinearLayout(context) {
    private val statusLabel = WLabel(context).apply { setStyle(14f, WFont.Regular) }
    private val supportLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        movementMethod = LinkMovementMethod.getInstance()
    }

    init {
        id = generateViewId()
        orientation = VERTICAL
        setPaddingDp(20, 0, 20, 0)
        addView(statusLabel, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        addView(supportLabel, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        statusLabel.isGone = true
        supportLabel.isGone = true
    }

    fun configure(swap: MApiTransaction.Swap?, now: Long = System.currentTimeMillis()): Long? {
        val cex = swap?.cex
        if (cex == null) {
            statusLabel.isGone = true
            supportLabel.isGone = true
            setPaddingDp(20, 0, 20, 0)
            return null
        }
        val deadline = swap.timestamp + 3 * 60 * 60 * 1000L
        val expiredWaiting = now >= deadline &&
            cex.status in
            listOf(CexStatus.NEW, CexStatus.WAITING)
        val status = when {
            expiredWaiting -> CexStatus.EXPIRED

            cex.status != null -> cex.status

            else -> when (swap.status) {
                ApiSwapStatus.PENDING, ApiSwapStatus.PENDING_TRUSTED -> CexStatus.NEW
                ApiSwapStatus.EXPIRED -> CexStatus.EXPIRED
                ApiSwapStatus.FAILED -> CexStatus.FAILED
                ApiSwapStatus.COMPLETED, ApiSwapStatus.CONFIRMED -> CexStatus.FINISHED
            }
        }
        val messageKey = when (status) {
            CexStatus.NEW, CexStatus.WAITING,
            CexStatus.CONFIRMING, CexStatus.EXCHANGING,
            CexStatus.SENDING ->
                "Swaps like this usually take a few minutes. In rare cases, up to two hours."

            CexStatus.EXPIRED, CexStatus.OVERDUE ->
                "You have not sent the coins to the specified address."

            CexStatus.REFUNDED ->
                "Exchange failed and coins were refunded to your wallet."

            else -> null
        }
        statusLabel.text = messageKey?.let(LocaleController::getString)
        statusLabel.isGone = messageKey == null
        statusLabel.setTextColor(
            if (status in listOf(
                    CexStatus.EXPIRED,
                    CexStatus.OVERDUE,
                    CexStatus.REFUNDED
                )
            ) {
                WColor.Red.color
            } else {
                WColor.SecondaryText.color
            }
        )
        val supportUrl = cex.supportUrl?.trim()?.takeIf {
            val uri = Uri.parse(it)
            uri.scheme?.lowercase() in listOf("http", "https") && !uri.host.isNullOrEmpty()
        }
        val email = cex.supportEmail?.trim()?.takeIf {
            Patterns.EMAIL_ADDRESS.matcher(it).matches()
        }
        val emailUrl = email?.let { "mailto:${Uri.encode(it, "@")}" }
        val provider = cex.providerName?.takeIf { it.isNotEmpty() }
        val showSupport = status?.isFinished != true &&
            (status == CexStatus.HOLD || now >= deadline) &&
            provider != null && (supportUrl != null || emailUrl != null)
        supportLabel.isGone = !showSupport
        if (showSupport) {
            val label = LocaleController.getString("\$swap_cex_provider_support")
                .replace("%provider%", provider.orEmpty())
            val key = when {
                status == CexStatus.HOLD && email != null ->
                    "\$swap_cex_hold_support_footer_email"

                status == CexStatus.HOLD -> "\$swap_cex_hold_support_footer"

                email != null -> "\$swap_cex_support_footer_email"

                else -> "\$swap_cex_support_footer"
            }
            supportLabel.text = LocaleController.getSpannableStringWithKeyValues(
                key,
                listOf(
                    "%support%" to SpanHelpers.buildSpannable(
                        label,
                        supportUrl?.let { InAppBrowserUrlSpan(it, null) } ?: URLSpan(emailUrl)
                    ),
                    "%email%" to
                        (email?.let { SpanHelpers.buildSpannable(it, URLSpan(emailUrl)) } ?: "")
                )
            )
        }
        supportLabel.setTextColor(WColor.SecondaryText.color)
        supportLabel.setLinkTextColor(WColor.Tint.color)
        (supportLabel.layoutParams as LayoutParams).topMargin = if (messageKey != null) 8.dp else 0
        val hasContent = messageKey != null || showSupport
        setPaddingDp(20, if (hasContent) 12 else 0, 20, if (hasContent) 16 else 0)
        return deadline.takeIf { status?.isFinished != true && now < it }
    }
}
