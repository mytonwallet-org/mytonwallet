package org.mytonwallet.app_air.uiagent.viewControllers.agent

import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * The chat's background. Incoming bubbles stand out from it as on iOS: lighter in the dark theme, where the chat
 * takes the darker secondary background, and darker in the light one.
 */
internal val agentChatBackgroundColor: Int
    get() = if (ThemeManager.isDark) WColor.SecondaryBackground.color else WColor.Background.color

/** The fill of incoming bubbles, News posts and cards, the other color of the chat's pair */
internal val agentIncomingBubbleColor: Int
    get() = if (ThemeManager.isDark) WColor.Background.color else WColor.SecondaryBackground.color

/** An operator's reply: the incoming bubble in the green tint of support */
internal val agentOperatorBubbleColor: Int
    get() = ColorUtils.blendARGB(
        agentIncomingBubbleColor,
        WColor.Green.color,
        OPERATOR_BUBBLE_GREEN
    )

/** The plate of a line about support in the chat, and of the muted support label in the chat list */
internal val agentSupportPlateColor: Int
    get() = withAlpha(WColor.SecondaryText.color, SUPPORT_PLATE_ALPHA)

/** The support badge's text: the green of support, deep enough to read on its own tint in both themes */
internal val agentSupportBadgeTextColor: Int
    get() = ColorUtils.blendARGB(
        WColor.PrimaryText.color,
        WColor.Green.color,
        SUPPORT_BADGE_TEXT_GREEN
    )

internal val agentSupportBadgeColor: Int
    get() = withAlpha(WColor.Green.color, SUPPORT_BADGE_ALPHA)

/** The label of a chat an operator is in, in the chat list */
internal val agentSupportActiveLabelColor: Int
    get() = withAlpha(WColor.Tint.color, SUPPORT_ACTIVE_LABEL_ALPHA)

/** Behind an operator's initial while their photo is missing, the same in both themes */
internal const val AGENT_OPERATOR_INITIAL_COLOR = 0xFFD9895B.toInt()

/**
 * The reaction cloud: the message menu's own colour in the light theme, and in the dark one, where the menu's colour is
 * the answer's and shadows hardly show, a grey lighter than the answer it rides over
 */
internal val agentReactionFillColor: Int
    get() = if (ThemeManager.isDark) WColor.TrinaryBackground.color else WColor.Background.color

/** The circle behind an answer's reaction in the cloud: one neutral shade over the cloud for every reaction */
internal val agentReactionSelectionColor: Int
    get() = if (ThemeManager.isDark) {
        withAlpha(WHITE, REACTION_SELECTION_DARK_ALPHA)
    } else {
        withAlpha(BLACK, REACTION_SELECTION_LIGHT_ALPHA)
    }

/** Code in answers takes the accent, the color links take */
internal val agentCodeColor: Int
    get() = WColor.Tint.color

/** A table's header row over the bubble: darker by black in the light theme and lighter by white in the dark one */
internal val agentTableHeaderColor: Int
    get() = makeAgentTableColors(ThemeManager.isDark).header

/** The lines around and between a table's cells, over the bubble */
internal val agentTableBorderColor: Int
    get() = makeAgentTableColors(ThemeManager.isDark).border

internal data class AgentTableColors(val header: Int, val border: Int)

/** Telegram's grey table over an incoming bubble, as shades of black in the light theme and of white in the dark one */
internal fun makeAgentTableColors(isDark: Boolean): AgentTableColors {
    val shade = if (isDark) WHITE else BLACK
    return AgentTableColors(
        header = withAlpha(shade, TABLE_HEADER_ALPHA),
        border = withAlpha(shade, TABLE_BORDER_ALPHA)
    )
}

/** A code block's colors for the [accent] in the light or the dark theme, as Telegram draws its blue ones */
internal data class AgentCodeBlockColors(
    val background: Int,
    val bar: Int,
    val header: Int,
    val title: Int,
    val copyIcon: Int,
    val code: Int
) {
    companion object {
        fun make(accent: Int, isDark: Boolean) = AgentCodeBlockColors(
            background = if (isDark) {
                withAlpha(BLACK, CODE_DARK_BACKGROUND_ALPHA)
            } else {
                withAlpha(accent, CODE_BACKGROUND_ALPHA)
            },
            bar = withAlpha(accent, CODE_BAR_ALPHA),
            header = withAlpha(accent, CODE_HEADER_ALPHA),
            title = accent,
            copyIcon = withAlpha(accent, CODE_COPY_ICON_ALPHA),
            code = accent
        )
    }
}

private fun withAlpha(color: Int, alpha: Int): Int = (color and 0x00FFFFFF) or (alpha shl 24)

private const val BLACK = 0xFF000000.toInt()
private const val WHITE = 0xFFFFFFFF.toInt()

private const val OPERATOR_BUBBLE_GREEN = 0.13f
private const val SUPPORT_BADGE_TEXT_GREEN = 0.62f

// About 12 %, 16 % and 12 % of 255
private const val SUPPORT_PLATE_ALPHA = 31
private const val SUPPORT_BADGE_ALPHA = 41
private const val SUPPORT_ACTIVE_LABEL_ALPHA = 31

// About 5 % and 12 % of 255
private const val TABLE_HEADER_ALPHA = 13
private const val TABLE_BORDER_ALPHA = 31

// About 8 % and 12 % of 255
private const val REACTION_SELECTION_LIGHT_ALPHA = 20
private const val REACTION_SELECTION_DARK_ALPHA = 31

// 12 %, 75 %, 90 %, 30 % and 60 % of 255
private const val CODE_BACKGROUND_ALPHA = 31
private const val CODE_DARK_BACKGROUND_ALPHA = 191
private const val CODE_BAR_ALPHA = 230
private const val CODE_HEADER_ALPHA = 77
private const val CODE_COPY_ICON_ALPHA = 153
