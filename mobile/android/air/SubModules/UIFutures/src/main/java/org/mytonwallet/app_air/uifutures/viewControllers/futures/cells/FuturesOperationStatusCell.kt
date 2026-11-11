package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.futuresOperationMessage
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.futuresOperationTitle
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOperation

/** Opens the status of an order that blocks new ones. */
@SuppressLint("ViewConstructor")
class FuturesOperationStatusCell(context: Context, private val onSelect: () -> Unit) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private val titleLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
    }

    private val messageLabel = WLabel(context).apply {
        setStyle(14f)
    }

    private val cardView = WView(context).apply {
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(messageLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(titleLabel, 14f)
            toCenterX(titleLabel, 20f)
            topToBottom(messageLabel, titleLabel, 4f)
            toCenterX(messageLabel, 20f)
            toBottom(messageLabel, 14f)
        }
        setOnClickListener { onSelect() }
    }

    init {
        addView(cardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(cardView)
        }
        updateTheme()
    }

    fun configure(operation: MApiPerpsOperation) {
        setCardPadding(ViewConstants.GAP.dp)
        titleLabel.text = futuresOperationTitle(operation)
        messageLabel.text = futuresOperationMessage(operation)
        updateTheme()
    }

    override fun updateTheme() {
        cardView.setPositionsCardBackground(isFirst = true, isLast = true)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        messageLabel.setTextColor(WColor.SecondaryText.color)
    }
}
