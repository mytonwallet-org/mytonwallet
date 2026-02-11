package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class HeaderCell(
    context: Context,
    private val startMargin: Float = 20f,
) : WCell(context), WThemedView {

    enum class TopRounding {
        FIRST_ITEM,
        NORMAL,
        ZERO
    }

    private var topRounding = TopRounding.ZERO
    private val topRoundingValue: Float
        get() {
            return when (topRounding) {
                TopRounding.FIRST_ITEM -> {
                    ViewConstants.TOOLBAR_RADIUS.dp
                }

                TopRounding.NORMAL -> {
                    ViewConstants.BLOCK_RADIUS.dp
                }

                TopRounding.ZERO -> {
                    0f
                }
            }
        }

    val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.DemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            isSelected = true
        }
    }

    override fun setupViews() {
        super.setupViews()

        layoutParams.apply {
            height = 40.dp
        }
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            constrainedWidth = true
        })
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
            topRoundingValue,
            0f
        )
        titleLabel.updateTheme()
    }

    fun configure(
        title: CharSequence,
        titleColor: WColor? = null,
        topRounding: TopRounding = TopRounding.ZERO
    ) {
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

    fun setTitle(title: CharSequence) {
        titleLabel.text = title
    }

    // Used in recycler-views not using custom rvAdapter
    class Holder(context: Context) :
        BaseListHolder<Item.ListTitle>(
            HeaderCell(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    WRAP_CONTENT
                )
            }) {
        private val view: HeaderCell = itemView as HeaderCell
        override fun onBind(item: Item.ListTitle) {
            view.configure(
                item.title, item.titleColor, item.topRounding,
            )
            view.setConstraints {
                toCenterX(view.titleLabel, item.startMargin)
            }
        }
    }
}
