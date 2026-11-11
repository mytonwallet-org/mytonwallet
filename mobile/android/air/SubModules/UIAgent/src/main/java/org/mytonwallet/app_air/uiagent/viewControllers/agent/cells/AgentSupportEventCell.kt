package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentSupportPlateColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

// In dp
private const val PLATE_TOP = 12f
private const val PLATE_BOTTOM = 4f
private const val PLATE_SIDE = 28f
private const val PLATE_RADIUS = 14f
private const val PLATE_HORIZONTAL_PADDING = 13
private const val PLATE_VERTICAL_PADDING = 7
private const val ICON_SIZE = 15
private const val GAP = 8

private const val TEXT_SIZE = 13f
private const val LINE_HEIGHT = 18f

/** A line in the middle of the chat about its handover to support, with the time it happened */
@SuppressLint("ViewConstructor")
internal class AgentSupportEventCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private val icon = ImageView(context).apply {
        setImageResource(R.drawable.ic_agent_support)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val textLabel = WLabel(context).apply {
        setStyle(TEXT_SIZE, WFont.Medium)
        setLineHeight(LINE_HEIGHT)
        isSingleLine = false
        maxLines = TEXT_MAX_LINES
        ellipsize = TextUtils.TruncateAt.END
        textAlignment = TEXT_ALIGNMENT_CENTER
    }
    private val timeLabel = WLabel(context).apply {
        setStyle(TEXT_SIZE)
        setLineHeight(LINE_HEIGHT)
        isSingleLine = true
    }
    private val plate = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(
            PLATE_HORIZONTAL_PADDING.dp,
            PLATE_VERTICAL_PADDING.dp,
            PLATE_HORIZONTAL_PADDING.dp,
            PLATE_VERTICAL_PADDING.dp
        )
        addView(icon, LinearLayout.LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp))
        addView(
            textLabel,
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { marginStart = GAP.dp }
        )
        addView(
            timeLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = GAP.dp }
        )
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        listOf(textLabel, timeLabel).forEach {
            it.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
    }

    init {
        addView(plate, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            constrainedWidth(plate.id, true)
            toTop(plate, PLATE_TOP)
            toBottom(plate, PLATE_BOTTOM)
            toCenterX(plate, PLATE_SIDE)
        }
        updateTheme()
    }

    fun configure(message: AgentMessage) {
        textLabel.text = message.text
        timeLabel.text = formatAgentChatTime(context, message.date)
        plate.contentDescription = "${message.text}, ${timeLabel.text}"
    }

    override fun updateTheme() {
        plate.setBackgroundColor(agentSupportPlateColor, PLATE_RADIUS.dp)
        icon.setColorFilter(WColor.Tint.color)
        textLabel.setTextColor(WColor.SecondaryText.color)
        timeLabel.setTextColor(WColor.SecondaryText.color)
    }

    private companion object {
        const val TEXT_MAX_LINES = 4
    }
}
