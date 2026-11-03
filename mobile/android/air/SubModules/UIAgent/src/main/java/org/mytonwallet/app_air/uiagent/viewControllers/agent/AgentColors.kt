package org.mytonwallet.app_air.uiagent.viewControllers.agent

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
