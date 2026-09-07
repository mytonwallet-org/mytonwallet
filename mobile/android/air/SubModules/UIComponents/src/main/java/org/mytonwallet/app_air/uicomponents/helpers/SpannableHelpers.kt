package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.MAccount

object SpannableHelpers {
    private const val ADDRESS_EDGE_LENGTH = 6

    /**
     * Renders [address] with its first and last [ADDRESS_EDGE_LENGTH] characters in [edgeColor]
     * and the middle in [middleColor]. Addresses too short to split stay entirely in [edgeColor].
     *
     * Colors resolve at draw time, so the result survives theme changes without being rebuilt.
     */
    fun addressSpan(
        address: String,
        font: WFont = WFont.Regular,
        edgeColor: WColor = WColor.PrimaryText,
        middleColor: WColor = WColor.SecondaryText
    ): CharSequence {
        val spannable = SpannableStringBuilder(address)
        spannable.setSpan(
            WTypefaceSpan(font.typeface),
            0,
            address.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        if (address.length <= 2 * ADDRESS_EDGE_LENGTH) {
            spannable.setSpan(
                WForegroundColorSpan(edgeColor),
                0,
                address.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            return spannable
        }
        spannable.setSpan(
            WForegroundColorSpan(edgeColor),
            0,
            ADDRESS_EDGE_LENGTH,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        spannable.setSpan(
            WForegroundColorSpan(middleColor),
            ADDRESS_EDGE_LENGTH,
            address.length - ADDRESS_EDGE_LENGTH,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        spannable.setSpan(
            WForegroundColorSpan(edgeColor),
            address.length - ADDRESS_EDGE_LENGTH,
            address.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        return spannable
    }

    fun encryptedCommentSpan(context: Context): SpannableStringBuilder {
        val builder = SpannableStringBuilder()
        context.getDrawableCompat(
            org.mytonwallet.app_air.icons.R.drawable.ic_lock
        )?.let { drawable ->
            drawable.mutate()
            drawable.setTint(Color.WHITE)
            val width = 16.dp
            val height = 16.dp
            drawable.setBounds(0, 0, width, height)
            val imageSpan = VerticalImageSpan(drawable)
            builder.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        builder.append(" ${LocaleController.getString("Encrypted Message")}")
        builder.setSpan(StyleSpan(Typeface.ITALIC), 0, builder.length, 0)
        return builder
    }

    private val walletEyeIcon = org.mytonwallet.app_air.icons.R.drawable.ic_wallet_eye
    private val walletLedgerIcon = org.mytonwallet.app_air.icons.R.drawable.ic_wallet_ledger
    private val walletTestnetIcon = org.mytonwallet.app_air.icons.R.drawable.ic_wallet_testnet

    fun accountBadgeIcons(account: MAccount): List<Int> = buildList {
        if (account.network.isTestnet) add(walletTestnetIcon)
        when (account.accountType) {
            MAccount.AccountType.VIEW -> add(walletEyeIcon)
            MAccount.AccountType.HARDWARE -> add(walletLedgerIcon)
            else -> {}
        }
    }

    fun accountBadgesSpan(
        context: Context,
        account: MAccount,
        badgeWidth: Int,
        spacing: Int,
        tint: Int
    ): SpannableStringBuilder {
        val builder = SpannableStringBuilder()
        accountBadgeIcons(account).forEachIndexed { index, resId ->
            val drawable = context.getDrawableCompat(resId)?.mutate() ?: return@forEachIndexed
            drawable.setTint(tint)
            val height =
                (badgeWidth * drawable.intrinsicHeight / drawable.intrinsicWidth.toFloat())
                    .roundToInt()
            drawable.setBounds(0, 0, badgeWidth, height)
            if (index > 0) {
                builder.append(" ", WSpacingSpan(spacing), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            builder.append(
                " ",
                VerticalImageSpan(
                    drawable,
                    verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                ),
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        return builder
    }
}
