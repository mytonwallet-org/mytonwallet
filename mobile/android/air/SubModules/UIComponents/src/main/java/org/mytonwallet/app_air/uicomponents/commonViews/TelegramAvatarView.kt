package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.view.View
import org.mytonwallet.app_air.walletbasecontext.utils.firstGrapheme
import org.mytonwallet.app_air.walletcore.models.AccountMfa

/**
 * Renders a Telegram-style initials-on-gradient avatar.
 *
 * Mirrors Telegram's native `AvatarDrawable` algorithm: picks one of 7 vertical
 * linear gradients via `abs(userId % 7)` and draws the first grapheme of the user's
 * name in white, matching the look of the server-side `t.me/i/userpic/...` SVG
 * placeholder. Used when the Telegram API returns no photo (avatarUrl is a `.svg`
 * placeholder) so we don't need an SVG decoder for a single client-renderable case.
 */
@SuppressLint("ViewConstructor")
class TelegramAvatarView(
    context: Context,
    user: AccountMfa.User,
) : View(context) {

    companion object {
        // Telegram's in-app avatar palette (Theme.keys_avatar_background[1..2]).
        // Order matters: index = abs(userId % gradients.size).
        private val GRADIENTS: Array<IntArray> = arrayOf(
            intArrayOf(0xFFFF845E.toInt(), 0xFFD45246.toInt()), // Red
            intArrayOf(0xFFFEBB5B.toInt(), 0xFFF68136.toInt()), // Orange
            intArrayOf(0xFFB694F9.toInt(), 0xFF6C61DF.toInt()), // Violet
            intArrayOf(0xFF9AD164.toInt(), 0xFF46BA43.toInt()), // Green
            intArrayOf(0xFF53EDD6.toInt(), 0xFF28C9B7.toInt()), // Cyan
            intArrayOf(0xFF5BCBE3.toInt(), 0xFF408ACF.toInt()), // Blue
            intArrayOf(0xFFFF8AAC.toInt(), 0xFFD95574.toInt()), // Pink
        )
    }

    private val initial: String = firstInitial(user.name)
    private val gradient: IntArray = pickGradient(user)

    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        // Telegram's SVG uses `font: 600 44px ...` on a 100×100 viewBox — i.e. text
        // height ~44% of avatar diameter. Use 0.44 * width at draw time, with a
        // semi-bold typeface to match.
        typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
    }
    private val ovalRect = RectF()

    private fun pickGradient(user: AccountMfa.User): IntArray {
        val key = user.id?.takeIf { it.isNotEmpty() }
            ?: user.username?.takeIf { it.isNotEmpty() }
            ?: user.name
        // Match Telegram: numeric ids → abs(id mod N). Fall back to char-sum for
        // non-numeric seeds so we still get a deterministic gradient.
        val index = key.toLongOrNull()
            ?.let { (kotlin.math.abs(it) % GRADIENTS.size).toInt() }
            ?: ((key.sumOf { it.code }.toLong() % GRADIENTS.size).toInt())
        return GRADIENTS[index]
    }

    private fun firstInitial(name: String): String =
        name.trim().firstGrapheme().uppercase()

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        ovalRect.set(0f, 0f, w, h)
        backgroundPaint.shader = LinearGradient(
            0f, 0f, 0f, h, gradient[0], gradient[1], Shader.TileMode.CLAMP,
        )
        canvas.drawOval(ovalRect, backgroundPaint)

        if (initial.isEmpty()) return

        textPaint.textSize = w * 0.44f
        val baselineY = h / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(initial, w / 2f, baselineY, textPaint)
    }
}
