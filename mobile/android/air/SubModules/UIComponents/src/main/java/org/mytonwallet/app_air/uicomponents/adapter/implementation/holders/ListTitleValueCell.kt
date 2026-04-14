package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.graphics.Color
import android.text.method.LinkMovementMethod
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

class ListTitleValueCell(context: Context) : FrameLayout(context), WThemedView {

    private val titleView = WLabel(context).apply {
        isSingleLine = true
        maxLines = 1
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setStyle(14f, WFont.DemiBold)
        setTextColor(WColor.Tint)
        movementMethod = LinkMovementMethod.getInstance()
        highlightColor = Color.TRANSPARENT
        useCustomEmoji = true
    }

    private val valueView = WLabel(context).apply {
        isSingleLine = true
        maxLines = 1
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
        useCustomEmoji = true
    }

    init {
        setPaddingDp(20f, 17f, 20f, 0f)
        layoutParams = ViewGroup.LayoutParams(LayoutParams.MATCH_PARENT, 40.dp)
        addView(
            titleView, LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.LEFT
            }
        )
        addView(
            valueView, LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.RIGHT
            }
        )
        updateTheme()
    }

    fun setTitle(text: CharSequence?) {
        titleView.text = text
    }

    fun setValue(text: CharSequence?) {
        valueView.text = text
    }

    override fun updateTheme() {
        titleView.updateTheme()
        valueView.updateTheme()
    }

    class Holder(parent: ViewGroup) :
        BaseListHolder<Item.ListTitleValue>(ListTitleValueCell(parent.context)) {

        private val cell = itemView as ListTitleValueCell

        override fun onBind(item: Item.ListTitleValue) {
            cell.setTitle(item.title)
            cell.setValue(item.value)

            cell.updateTheme()
        }
    }
}
