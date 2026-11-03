package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.ViewCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

/** A section's title: Pinned, or the day of the chats under it */
@SuppressLint("ViewConstructor")
internal class AgentThreadSectionCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, AgentThreadSectionMetrics.HEIGHT.dp)),
    WThemedView {
    private val label = makeAgentThreadSectionLabel(context)

    init {
        addView(label, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(label, AgentThreadSectionMetrics.TEXT_INSET.toFloat())
            toEnd(label, AgentThreadSectionMetrics.TEXT_INSET.toFloat())
            toTop(label, AgentThreadSectionMetrics.TEXT_TOP.toFloat())
        }
        ViewCompat.setAccessibilityHeading(this, true)
        updateTheme()
    }

    /** Hides the title while the list draws it over the band under the top bar */
    var isTitleHidden = false
        set(value) {
            if (field == value) return
            field = value
            label.alpha = if (value) 0f else 1f
        }

    fun configure(title: String) {
        label.text = title
        contentDescription = title
        updateTheme()
    }

    override fun updateTheme() {
        label.setTextColor(WColor.Tint)
    }
}

internal fun makeAgentThreadSectionLabel(context: Context): WLabel = WLabel(context).apply {
    setStyle(AgentThreadSectionMetrics.TEXT_SIZE, WFont.Medium)
    setLineHeight(AgentThreadSectionMetrics.LINE_HEIGHT)
    isSingleLine = true
    ellipsize = TextUtils.TruncateAt.END
    textAlignment = View.TEXT_ALIGNMENT_VIEW_START
}

internal object AgentThreadSectionMetrics {
    const val HEIGHT = 40
    const val TEXT_INSET = 20
    const val TEXT_TOP = 14
    const val TEXT_SIZE = 14f
    const val LINE_HEIGHT = 24f
}
