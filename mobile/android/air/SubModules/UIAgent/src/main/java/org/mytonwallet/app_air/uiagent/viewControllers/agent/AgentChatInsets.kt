package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uicomponents.base.WViewController

// In dp

internal const val AGENT_MESSAGE_BOTTOM_GAP = 12

/** Compensates the field's 8 dp top inset and the bubble's 6 dp bottom inset */
internal const val AGENT_COMPOSER_LIST_GAP = -2

internal const val AGENT_COMPOSER_FIELD_TOP = 8

internal const val AGENT_SCROLL_BUTTON_GAP = 4
internal const val AGENT_SCROLL_BUTTON_END = 16

internal const val AGENT_BOTTOM_FADE_EXTRA = 4

internal const val AGENT_LIST_TOP_INSET = 8

/** In px, including the status bar */
internal fun WViewController.agentHeaderBottom(): Int {
    val bar = navigationBar
    return bar?.height?.takeIf { it > 0 } ?: bar?.calculatedMinHeight ?: 0
}
