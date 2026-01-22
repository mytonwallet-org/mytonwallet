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

    private var topRounding: Float = 0f

    val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.DemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            isSelected = true
        }
    }

    init {
        layoutParams.apply {
            height = 40.dp
        }
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            setHorizontalBias(titleLabel.id, 0f)
            toCenterX(titleLabel, startMargin)
            toTop(titleLabel, 16f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            topRounding,
            0f
        )
    }

    fun configure(title: String, titleColor: WColor? = null, topRounding: Float = 0f) {
        this.topRounding = topRounding
        titleLabel.text = title
        if (titleColor != null) {
            titleLabel.setTextColor(titleColor)
            titleLabel.isTinted = titleColor == WColor.Tint
        }
        updateTheme()
    }

    fun setTitleColor(color: Int) {
        titleLabel.setTextColor(color = null)
        titleLabel.setTextColor(color)
    }
}
