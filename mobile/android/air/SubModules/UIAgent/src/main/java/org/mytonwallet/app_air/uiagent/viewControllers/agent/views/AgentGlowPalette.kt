package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Color
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager

/**
 * The Agent's blue and violet, as iOS's `AgentGlowPalette` has them: the colours of the thinking glow's stretches and
 * lights. The glow lays the deep pair on dark, where it adds light, and the bright pair over light.
 */
internal object AgentGlowPalette {
    private val DEEP_BLUE = Color.rgb(5, 109, 205)
    private val DEEP_VIOLET = Color.rgb(144, 70, 203)
    private val BRIGHT_BLUE = Color.rgb(50, 158, 255)
    private val BRIGHT_VIOLET = Color.rgb(190, 118, 253)

    val glowBlue: Int
        get() = if (ThemeManager.isDark) DEEP_BLUE else BRIGHT_BLUE

    val glowViolet: Int
        get() = if (ThemeManager.isDark) DEEP_VIOLET else BRIGHT_VIOLET

    /**
     * Text in the Agent's colours takes the pair that stands out from the background: the deep one on light and the
     * bright one on dark, the other way round from the glow
     */
    val textBlue: Int
        get() = if (ThemeManager.isDark) BRIGHT_BLUE else DEEP_BLUE

    val textViolet: Int
        get() = if (ThemeManager.isDark) BRIGHT_VIOLET else DEEP_VIOLET
}
