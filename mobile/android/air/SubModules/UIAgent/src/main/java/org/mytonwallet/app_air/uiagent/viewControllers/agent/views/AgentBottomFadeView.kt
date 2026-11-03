package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentChatBackgroundColor
import org.mytonwallet.app_air.uicomponents.drawable.GradientShaderDrawable
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

private const val BOTTOM_ALPHA = 229

@SuppressLint("ViewConstructor")
internal class AgentBottomFadeView(context: Context) :
    View(context),
    WThemedView {
    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        updateTheme()
    }

    override fun updateTheme() {
        background = GradientShaderDrawable(
            intArrayOf(
                agentChatBackgroundColor.colorWithAlpha(0),
                agentChatBackgroundColor.colorWithAlpha(BOTTOM_ALPHA)
            ),
            floatArrayOf(0f, 1f)
        )
    }

    companion object {
        fun isShown(isWideLayout: Boolean): Boolean =
            isWideLayout || WGlobalStorage.isGradientNavigationBarActive()
    }
}
