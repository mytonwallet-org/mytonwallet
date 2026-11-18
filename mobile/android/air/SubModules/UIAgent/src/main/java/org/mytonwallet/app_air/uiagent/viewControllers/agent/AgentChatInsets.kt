package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

// In dp

internal const val AGENT_MESSAGE_BOTTOM_GAP = 12

/** Compensates the field's 8 dp top inset and the bubble's 6 dp bottom inset */
internal const val AGENT_COMPOSER_LIST_GAP = -2

internal const val AGENT_COMPOSER_FIELD_TOP = 8

/** The composer's space under its field */
internal const val AGENT_COMPOSER_FIELD_BOTTOM = 8

internal const val AGENT_SCROLL_BUTTON_GAP = 4
internal const val AGENT_SCROLL_BUTTON_END = 16

internal const val AGENT_BOTTOM_FADE_EXTRA = 4

internal const val AGENT_LIST_TOP_INSET = 8

/**
 * A sent question pinned under the header leaves the last line of the message above it in view: one line of an answer's
 * text, 22 dp, the bubble's 10 dp under it and the row's 6 dp under the bubble.
 */
internal const val AGENT_PIN_PREVIOUS_LINE = 38

// The idle field's bottom sits this far above the navigation bar, on the root toolbar's line as the list's field does,
// and the toolbar's extra gap higher without the gradient navigation bar
private const val FIELD_LINE_LIFT = 1
private const val FIELD_LINE_EXTRA = 7

/** In dp: how far above the navigation bar a chat's idle field's bottom rests, and the microphone's with it */
internal fun WViewController.agentFieldLine(): Int {
    if (window?.isWideLayout == true) return AGENT_COMPOSER_FIELD_BOTTOM
    val extra = if (WGlobalStorage.isGradientNavigationBarActive()) 0 else FIELD_LINE_EXTRA
    return FIELD_LINE_LIFT + extra
}

/** In px, including the status bar */
internal fun WViewController.agentHeaderBottom(): Int {
    val bar = navigationBar
    return bar?.height?.takeIf { it > 0 } ?: bar?.calculatedMinHeight ?: 0
}
