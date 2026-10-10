package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Paint
import android.text.TextPaint
import android.util.TypedValue
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import kotlin.math.ceil
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WCell

@SuppressLint("ViewConstructor")
class SearchChatHintCell(context: Context, private val onTap: (AgentHint) -> Unit) :
    WCell(context) {

    companion object {
        private const val HINT_START_PADDING = 16
        private const val HINT_END_PADDING = 2
        private const val HINT_CONTENT_HORIZONTAL_PADDING = 32
        private const val CELL_HORIZONTAL_PADDING =
            HINT_START_PADDING + HINT_END_PADDING + HINT_CONTENT_HORIZONTAL_PADDING
        const val SECTION_END_SPACING = HINT_START_PADDING - HINT_END_PADDING
        private val hintMeasurePaint = TextPaint(Paint.ANTI_ALIAS_FLAG)

        fun hintCellWidths(context: Context, hints: List<AgentHint>): List<Int> {
            hintMeasurePaint.apply {
                textSize = TypedValue.applyDimension(
                    TypedValue.COMPLEX_UNIT_SP,
                    16f,
                    context.resources.displayMetrics
                )
                typeface = WFont.Medium.typeface
            }
            return hints.map { hint ->
                ceil(hintMeasurePaint.measureText(hint.title)).toInt() + CELL_HORIZONTAL_PADDING.dp
            }
        }
    }

    private var hint: AgentHint? = null
    private val hintView = WAgentHintView(
        context,
        "",
        showsIcon = false,
        titleMaxLines = 1
    ) {
        hint?.let(onTap)
    }

    override fun setupViews() {
        super.setupViews()

        addView(
            hintView,
            LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
                constrainedWidth = true
            }
        )
        setConstraints {
            setHorizontalBias(hintView.id, 0f)
            toStart(hintView, HINT_START_PADDING.toFloat())
            toEnd(hintView, HINT_END_PADDING.toFloat())
            centerYToCenterY(hintView, this@SearchChatHintCell)
        }
    }

    fun configure(hint: AgentHint) {
        this.hint = hint
        hintView.setTitle(hint.title)
        hintView.updateTheme()
    }
}
