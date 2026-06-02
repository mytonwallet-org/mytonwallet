package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ReplacementSpan
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat

/**
 * Builds the "Confirm with [TG icon] Telegram" title used across the MFA screens.
 * Replaces the literal " Telegram" word in the localised string with an inline
 * 32dp Telegram icon followed by the word.
 */
fun buildConfirmWithTelegramTitle(context: Context): CharSequence {
    val telegram = "Telegram"
    val full = "${LocaleController.getString("Confirm with")} $telegram"
    val idx = full.indexOf(telegram)
    if (idx < 0) return full
    val builder = SpannableStringBuilder(full)
    val drawable = context.getDrawableCompat(R.drawable.ic_tg_inline) ?: return full
    val iconSize = 32.dp
    val rightOffset = 2.dp
    drawable.setBounds(0, 0, iconSize, iconSize)
    drawable.setTint(WColor.PrimaryText.color)

    val span = object : ReplacementSpan() {
        override fun getSize(
            paint: Paint,
            text: CharSequence?,
            start: Int,
            end: Int,
            fm: Paint.FontMetricsInt?,
        ): Int = iconSize + rightOffset

        override fun draw(
            canvas: Canvas,
            text: CharSequence?,
            start: Int,
            end: Int,
            x: Float,
            top: Int,
            y: Int,
            bottom: Int,
            paint: Paint,
        ) {
            val centerY = (top + bottom) / 2f - iconSize / 2f
            canvas.save()
            canvas.translate(x, centerY)
            drawable.draw(canvas)
            canvas.restore()
        }
    }

    builder.insert(idx, " ")
    builder.setSpan(span, idx, idx + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    return builder
}