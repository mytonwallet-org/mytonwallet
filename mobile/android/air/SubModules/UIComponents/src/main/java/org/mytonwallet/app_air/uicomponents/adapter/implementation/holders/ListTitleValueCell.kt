package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.graphics.Color
import android.text.method.LinkMovementMethod
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ListTitleValueCell(context: Context) : FrameLayout(context), WThemedView {

    private val titleView = AppCompatTextView(context).apply {
        isSingleLine = true
        maxLines = 1
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        typeface = WFont.Medium.typeface
        movementMethod = LinkMovementMethod.getInstance()
        highlightColor = Color.TRANSPARENT
    }

    private val valueView = AppCompatTextView(context).apply {
        isSingleLine = true
        maxLines = 1
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        typeface = WFont.Regular.typeface
    }

    var textColor: WColor? = null
    var valueTextColor: WColor? = null

    init {
        setPaddingDp(20f, 16f, 20f, 8f)
        layoutParams = ViewGroup.LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT
        )
        addView(
            titleView, LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.LEFT or Gravity.CENTER_VERTICAL
            }
        )
        addView(
            valueView, LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.RIGHT or Gravity.CENTER_VERTICAL
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
        titleView.setTextColor(textColor?.color ?: WColor.PrimaryText.color)
        valueView.setTextColor(valueTextColor?.color ?: WColor.SecondaryText.color)
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
