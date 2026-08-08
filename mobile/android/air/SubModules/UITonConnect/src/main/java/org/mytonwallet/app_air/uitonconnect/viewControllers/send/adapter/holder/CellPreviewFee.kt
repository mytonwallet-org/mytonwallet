package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder

import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCounterButton
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat

class CellPreviewFee(context: Context) :
    WView(context),
    WThemedView {
    private val feeButton = WCounterButton(
        context,
        context.requireDrawableCompat(
            org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_24
        ).apply {
            layoutDirection = if (LocaleController.isRTL) {
                LAYOUT_DIRECTION_RTL
            } else {
                LAYOUT_DIRECTION_LTR
            }
        },
        true
    ).apply {
        id = generateViewId()
        isDrawableBeforeTextInRtl = true
    }

    init {
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, 40.dp)

        addView(feeButton, LayoutParams(WRAP_CONTENT, WCounterButton.HEIGHT.dp))

        setConstraints {
            toCenterY(feeButton)
            toEnd(feeButton, 6f)
        }

        updateTheme()
    }

    fun setOnFeeClickListener(listener: OnClickListener) {
        feeButton.setOnClickListener(listener)
    }

    fun configure(item: TonConnectItem.PreviewFee) {
        feeButton.shouldShowDrawable = item.feeDetails != null
        feeButton.setText(item.text.toString())
        feeButton.isClickable = item.feeDetails != null
    }

    override fun updateTheme() {
        feeButton.updateTheme()
    }

    class Holder(parent: ViewGroup, onClick: (TonConnectItem.PreviewFee) -> Unit) :
        BaseListHolder<TonConnectItem.PreviewFee>(CellPreviewFee(parent.context)) {

        private val cell = itemView as CellPreviewFee

        init {
            cell.setOnFeeClickListener {
                item?.let(onClick)
            }
        }

        override fun onBind(item: TonConnectItem.PreviewFee) {
            cell.configure(item)
            cell.updateTheme()
        }
    }
}
