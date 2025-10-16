package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class HeaderCell(
    context: Context,
    startMargin: Float = 20f,
) : WCell(context), WThemedView {

    private var titleColor: Int = WColor.PrimaryText.color
    private var topRounding: Float = 0f

    val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            isSelected = true
        }
    }

    init {
        layoutParams.apply {
            height = 48.dp
        }
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            setHorizontalBias(titleLabel.id, 0f)
            toCenterX(titleLabel, startMargin)
            toTop(titleLabel, 17f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            topRounding,
            0f
        )
        titleLabel.setTextColor(titleColor)
    }

    fun configure(title: String, titleColor: Int? = null, topRounding: Float = 0f) {
        this.topRounding = topRounding
        titleLabel.text = title
        if (titleColor != null) {
            this.titleColor = titleColor
            titleLabel.setTextColor(titleColor)
        }
        updateTheme()
    }

}
