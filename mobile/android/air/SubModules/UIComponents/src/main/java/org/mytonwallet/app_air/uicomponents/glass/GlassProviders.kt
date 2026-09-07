package org.mytonwallet.app_air.uicomponents.glass

import android.graphics.Color
import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.blur3.compat.Blur3Colors
import org.mytonwallet.app_air.blur3.compat.Blur3Settings
import org.mytonwallet.app_air.blur3.drawable.color.BlurredBackgroundColorProvider
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * Colors for one glass surface. Telegram's `BlurredBackgroundColorProviderThemed`: the panel color
 * at the glass alpha, a white specular rim when the panel is light and a faint one when it is
 * dark, a shadow only on light panels. Rim and shadow can be switched off for flat surfaces.
 *
 * Call [updateColors] after a theme change; the drawable caches these values.
 */
class GlassProvider(
    private val panelColor: () -> Int,
    private val panelAlpha: () -> Float = { defaultAlpha() },
    val rim: Boolean = true,
    val shadow: Boolean = true
) : BlurredBackgroundColorProvider {

    /** The same rim, shadow and alpha over a different panel color. */
    fun withColor(color: Int): GlassProvider = GlassProvider({ color }, panelAlpha, rim, shadow)

    private var backgroundColor = 0
    private var shadowColor = 0
    private var strokeColorTop = 0
    private var strokeColorBottom = 0

    init {
        updateColors()
    }

    /** True when the panel itself reads as dark, regardless of the app theme. */
    val isDark: Boolean
        get() = Blur3Colors.computePerceivedBrightness(panelColor()) < DARK_BRIGHTNESS

    fun updateColors() {
        val color = panelColor()
        backgroundColor = if (Blur3Settings.isBlurEnabled()) {
            Blur3Colors.multAlpha(color, panelAlpha())
        } else if (Color.alpha(color) == 0) {
            color
        } else {
            ColorUtils.setAlphaComponent(color, 255)
        }
        val dark = isDark
        strokeColorTop = if (!rim) {
            0
        } else if (dark) {
            RIM_TOP_DARK
        } else {
            RIM_LIGHT
        }
        strokeColorBottom = if (!rim) {
            0
        } else if (dark) {
            RIM_BOTTOM_DARK
        } else {
            RIM_LIGHT
        }
        shadowColor = if (!shadow || dark) 0 else SHADOW_LIGHT
    }

    override fun getShadowColor(): Int = shadowColor

    override fun getBackgroundColor(): Int = backgroundColor

    override fun getStrokeColorTop(): Int = strokeColorTop

    override fun getStrokeColorBottom(): Int = strokeColorBottom

    companion object {
        const val DARK_BRIGHTNESS = 0.721f
        const val RIM_LIGHT = 0xFFFFFFFF.toInt()
        const val RIM_TOP_DARK = 0x28FFFFFF
        const val RIM_BOTTOM_DARK = 0x14FFFFFF
        const val SHADOW_LIGHT = 0x20000000

        fun defaultAlpha(): Float = if (Blur3Settings.isLiquidGlassEnabled()) 0.85f else 0.76f
    }
}

/** Telegram's `shadow()` preset: no fill, only the rim (dark theme) and a soft shadow. */
class ShadowOnlyProvider : BlurredBackgroundColorProvider {
    override fun getShadowColor(): Int = if (ThemeManager.isDark) 0x04FFFFFF else 0x30000000

    override fun getBackgroundColor(): Int = Color.TRANSPARENT

    override fun getStrokeColorTop(): Int = if (ThemeManager.isDark) 0x28FFFFFF else 0

    override fun getStrokeColorBottom(): Int = if (ThemeManager.isDark) 0x14FFFFFF else 0
}

object GlassProviders {
    /** A floating pill (search bar, tab bar, avatar, toast). */
    fun pill(color: WColor): GlassProvider = GlassProvider({ color.color })

    fun pill(color: Int): GlassProvider = GlassProvider({ color })

    /** A composer-like input; Telegram lifts the light-theme alpha to 216/255. */
    fun composer(color: WColor): GlassProvider = GlassProvider(
        panelColor = { color.color },
        panelAlpha = {
            if (ThemeManager.isDark) GlassProvider.defaultAlpha() else COMPOSER_LIGHT_ALPHA
        }
    )

    /** A flat blurred surface with no rim or shadow (shelves, backdrops). */
    fun plain(color: WColor, alpha: Float? = null): GlassProvider = GlassProvider(
        panelColor = { color.color },
        panelAlpha = { alpha ?: GlassProvider.defaultAlpha() },
        rim = false,
        shadow = false
    )

    fun plain(color: Int, alpha: Float? = null): GlassProvider = GlassProvider(
        panelColor = { color },
        panelAlpha = { alpha ?: GlassProvider.defaultAlpha() },
        rim = false,
        shadow = false
    )

    fun shadowOnly(): BlurredBackgroundColorProvider = ShadowOnlyProvider()

    /** The pre-port look: the color at [alpha]/255, no rim, solid when blur is off. */
    fun legacy(color: WColor, alpha: Int = LEGACY_ALPHA, shadow: Boolean = false): GlassProvider =
        GlassProvider(
            panelColor = { color.color },
            panelAlpha = { alpha / 255f },
            rim = false,
            shadow = shadow
        )

    private const val LEGACY_ALPHA = 204

    private const val COMPOSER_LIGHT_ALPHA = 216 / 255f
}
