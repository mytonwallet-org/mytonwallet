package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import androidx.constraintlayout.widget.ConstraintSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class LinedCenteredTitleView(context: Context) :
    WCell(context, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)),
    WThemedView {
    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(17f, WFont.Medium)
        lbl.maxLines = 1
        lbl.setTextColor(WColor.PrimaryText)
        lbl
    }

    private val leftLineView = WBaseView(context)
    private val rightLineView = WBaseView(context)

    var lineColor: WColor? = null
        set(value) {
            field = value
            updateTheme()
        }

    init {
        addView(leftLineView, LayoutParams(60.dp, 1.dp).apply {
            rightMargin = 12.dp
        })
        addView(rightLineView, LayoutParams(60.dp, 1.dp).apply {
            leftMargin = 12.dp
        })
        addView(titleLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        setConstraints {
            toLeft(leftLineView)
            toCenterY(leftLineView)
            leftToRight(titleLabel, leftLineView)
            toCenterY(titleLabel)
            leftToRight(rightLineView, titleLabel)
            toRight(rightLineView)
            toCenterY(rightLineView)
            createHorizontalChain(
                ConstraintSet.PARENT_ID, ConstraintSet.LEFT,
                ConstraintSet.PARENT_ID, ConstraintSet.RIGHT,
                intArrayOf(leftLineView.id, titleLabel.id, rightLineView.id),
                null,
                ConstraintSet.CHAIN_PACKED
            )
        }
    }

    override fun updateTheme() {
        val color = lineColor?.color?.colorWithAlpha(51)
            ?: (if (ThemeManager.isDark) WColor.Separator else WColor.GroupedBackground).color
        leftLineView.setBackgroundColor(color, 1f)
        rightLineView.setBackgroundColor(color, 1f)
    }

    fun configure(title: String, topPadding: Int, bottomPadding: Int) {
        setPadding(0, topPadding, 0, bottomPadding)
        titleLabel.text = title
        updateTheme()
    }

    fun configureText(font: WFont, color: WColor) {
        titleLabel.setStyle(17f, font)
        titleLabel.setTextColor(color)
    }

}
