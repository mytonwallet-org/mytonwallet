package org.mytonwallet.app_air.uicomponents.commonViews

import android.graphics.Canvas
import android.graphics.Paint
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.firstGrapheme
import org.mytonwallet.app_air.walletcore.models.MAccount

/**
 * Generates an abbreviation from a name or address.
 * Takes first graphemes of up to 2 words from the name, or first 2 characters of address as fallback.
 */
fun generateAbbreviation(name: String?, address: String): String {
    return name?.takeIf { it.isNotBlank() }?.let { n ->
        n.trim()
            .split("\\s+".toRegex())
            .filter { it.isNotEmpty() }
            .take(2)
            .joinToString("") { part -> part.firstGrapheme().uppercase() }
    } ?: address.take(2)
}

/**
 * Generates an abbreviation from an account name or address.
 */
val MAccount.abbreviation: String
    get() = generateAbbreviation(name, firstAddress ?: "")

/**
 * Helper object for rendering account avatar text.
 */
object AccountAvatarRenderer {

    /**
     * Creates a Paint configured for avatar text rendering with the rounded Nunito font.
     */
    fun createTextPaint(textSize: Float): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.textSize = textSize
        typeface = WFont.NunitoExtraBold.typeface
        color = WColor.White.color
        textAlign = Paint.Align.CENTER
    }

    /**
     * Returns the appropriate text size in dp for a given view size.
     * Matches iOS behavior with scaled sizes for different avatar dimensions.
     */
    fun getTextSizeForViewSize(viewSizePx: Int): Float = when {
        viewSizePx >= 80.dp -> 38f.dp
        viewSizePx >= 40.dp -> 16f.dp
        else -> 14f.dp
    }

    /**
     * Draws centered text on a canvas at the specified position.
     */
    fun drawCenteredText(
        canvas: Canvas,
        text: String,
        centerX: Float,
        centerY: Float,
        paint: Paint
    ) {
        if (text.isEmpty()) return
        val adjustedY = centerY - (paint.descent() + paint.ascent()) / 2f
        canvas.drawText(text, centerX, adjustedY, paint)
    }

    /**
     * Updates the paint color for theme changes.
     */
    fun updatePaintTheme(paint: Paint) {
        paint.color = WColor.White.color
    }
}

