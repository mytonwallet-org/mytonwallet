package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

// In dp
private const val SIDE_INSET = 16f
private const val TITLE_GAP = 10f
private const val TITLE_TOP = 8f
private const val TITLE_BOTTOM = 4f

private const val LINE_ALPHA = 0x33000000

@SuppressLint("ViewConstructor")
internal class AgentUnreadDividerCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private val label = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setLineHeight(20f)
        gravity = Gravity.CENTER
        text = LocaleController.getString("\$agent_news_new")
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val leadingLine = View(context).apply { id = generateViewId() }
    private val trailingLine = View(context).apply { id = generateViewId() }

    init {
        addView(label, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(leadingLine, LayoutParams(0, 1.dp))
        addView(trailingLine, LayoutParams(0, 1.dp))
        setConstraints {
            toCenterX(label)
            toTop(label, TITLE_TOP)
            toBottom(label, TITLE_BOTTOM)
            toStart(leadingLine, SIDE_INSET)
            endToStart(leadingLine, label, TITLE_GAP)
            centerYToCenterY(leadingLine, label)
            startToEnd(trailingLine, label, TITLE_GAP)
            toEnd(trailingLine, SIDE_INSET)
            centerYToCenterY(trailingLine, label)
        }
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = label.text
        updateTheme()
    }

    override fun updateTheme() {
        label.setTextColor(WColor.Tint)
        val lineColor = (WColor.Tint.color and 0x00FFFFFF) or LINE_ALPHA
        leadingLine.setBackgroundColor(lineColor)
        trailingLine.setBackgroundColor(lineColor)
    }
}
