package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class AgentSystemMessageCell(context: Context) : WCell(
    context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)
) {
    private val label = WLabel(context).apply {
        setStyle(11f, WFont.Medium)
        setTextColor(WColor.SecondaryText.color)
        gravity = Gravity.CENTER
        maxLines = 2
        isSingleLine = false
        useCustomEmoji = true
    }

    init {
        addView(label)
        setConstraints {
            toTop(label, 4f)
            toBottom(label, 4f)
            toStart(label, 40f)
            toEnd(label, 40f)
        }
    }

    fun configure(message: AgentMessage) {
        label.text = message.text
    }
}
