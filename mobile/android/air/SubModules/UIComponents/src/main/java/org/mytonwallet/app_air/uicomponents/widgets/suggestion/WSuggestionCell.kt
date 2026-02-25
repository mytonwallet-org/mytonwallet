package org.mytonwallet.app_air.uicomponents.widgets.suggestion

import android.content.Context
import android.graphics.Color
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

class WSuggestionCell(context: Context) : WCell(context, LayoutParams(WRAP_CONTENT, MATCH_PARENT)),
    WThemedView {

    private val ripple = WRippleDrawable.create(14f.dp)

    var onTap: ((text: String) -> Unit)? = null

    private var isPrimary = false

    private var suggestionsLength: Int = 0

    private val contentView: WView by lazy {
        WView(context).apply {
            background = ripple
        }
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(15f)
            maxLines = 1
        }
    }

    init {
        addView(contentView, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        contentView.addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints { allEdges(contentView) }
        contentView.setConstraints { allEdges(titleLabel) }

        setOnClickListener {
            onTap?.invoke(titleLabel.text.toString())
        }

        updateTheme()
        applySelection()
    }

    override fun updateTheme() {
        ripple.rippleColor = WColor.SecondaryBackground.color
        titleLabel.setTextColor(WColor.PrimaryText.color)
        applySelection()
    }

    fun configure(text: String, isPrimary: Boolean, suggestionsLength: Int) {
        titleLabel.text = text
        this.isPrimary = isPrimary
        this.suggestionsLength = suggestionsLength
        applySelection()
    }

    private fun applySelection() {
        if (isPrimary) {
            contentView.setPadding(6.dp, 6.dp, 6.dp, 6.dp)
            val isOneSuggestion = suggestionsLength == 1
            val primaryRightMargin = if (isOneSuggestion) 6.dp else 0.dp
            contentView.updateLayoutParams<MarginLayoutParams> {
                leftMargin = 6.dp
                topMargin = 6.dp
                rightMargin = primaryRightMargin
                bottomMargin = 6.dp
            }
            ripple.backgroundColor = WColor.PrimaryText.color.colorWithAlpha(15)
        } else {
            contentView.setPadding(6.dp, 12.dp, 6.dp, 12.dp)
            contentView.updateLayoutParams<MarginLayoutParams> {
                leftMargin = 0
                topMargin = 0
                rightMargin = 0
                bottomMargin = 0
            }
            ripple.backgroundColor = Color.TRANSPARENT
        }
    }
}
