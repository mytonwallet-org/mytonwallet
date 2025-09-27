package org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews

import android.content.Context
import android.util.TypedValue
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class TotalCurrencyAmountView(
    context: Context
) : AppCompatTextView(context), WThemedView {

    init {
        setPaddingDp(20, 8, 20, 16)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 28f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        typeface = WFont.Medium.typeface
        updateTheme()
    }

    override fun updateTheme() {
        setTextColor(WColor.PrimaryText.color)
    }

    class Holder(parent: ViewGroup) :
        BaseListHolder<TonConnectItem.CurrencyAmount>(TotalCurrencyAmountView(parent.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
        }) {
        private val view: AppCompatTextView = itemView as AppCompatTextView
        override fun onBind(item: TonConnectItem.CurrencyAmount) {
            view.text = item.text
        }
    }
}
