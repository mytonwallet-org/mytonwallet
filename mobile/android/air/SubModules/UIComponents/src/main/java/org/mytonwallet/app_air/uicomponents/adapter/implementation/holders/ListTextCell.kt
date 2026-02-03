package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

class ListTextCell(context: Context) : AppCompatTextView(context), WThemedView {
    init {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        isSingleLine = true
        maxLines = 1
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setPaddingDp(20f, 16f, 20f, 8f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = WFont.Medium.typeface
        gravity =
            if (LocaleController.isRTL)
                Gravity.RIGHT
            else
                Gravity.LEFT
        updateTheme()
    }

    var textColor: WColor? = null
    override fun updateTheme() {
        setTextColor(textColor?.color ?: WColor.PrimaryText.color)
    }

    class Holder(parent: ViewGroup) :
        BaseListHolder<Item.ListText>(ListTextCell(parent.context)) {
        private val view = itemView as ListTextCell
        override fun onBind(item: Item.ListText) {
            view.text = item.title
            val paddingDp = item.paddingDp
            view.setPaddingDp(paddingDp.left, paddingDp.top, paddingDp.right, paddingDp.bottom)
            view.gravity =
                item.gravity ?: if (LocaleController.isRTL)
                    Gravity.RIGHT
                else
                    Gravity.LEFT
            view.setTextSize(TypedValue.COMPLEX_UNIT_SP, item.textSize ?: 16f)
            view.textColor = item.textColor
            view.typeface = item.font ?: WFont.Medium.typeface
            view.updateTheme()
        }
    }
}
