package org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.setCardPadding
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.pnlColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition

@SuppressLint("ViewConstructor")
class FuturesPositionDetailsCell(
    context: Context,
    private val onShowInfo: (title: String, text: String) -> Unit
) : WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private val rowsView = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
    }

    init {
        addView(rowsView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(rowsView)
        }
    }

    fun configure(position: MApiPerpsNativePosition) {
        setCardPadding(ViewConstants.GAP.dp)
        rowsView.removeAllViews()
        val rows = rows(position)
        rows.forEachIndexed { index, row ->
            row.setLast(index == rows.lastIndex)
            rowsView.addView(row)
        }
        updateTheme()
    }

    private fun rows(position: MApiPerpsNativePosition): List<KeyValueRowView> = listOf(
        row(
            "Invested",
            position.invested.toUsdString(),
            hintKey = "\$perps_invested_hint",
            isSensitiveData = true
        ),
        row(
            "Entry Price",
            position.entryPrice?.toPriceString() ?: EMPTY_VALUE,
            hintKey = "\$perps_entry_price_hint"
        ),
        row(
            "Liquidation Price",
            position.liquidationPrice?.toPriceString() ?: EMPTY_VALUE,
            hintKey = "\$perps_liquidation_price_hint"
        ),
        row(
            "Position Size",
            "~${position.positionValue.toUsdString()} · ${
                position.sizeAmount.toString(8, "", 8, smartDecimals = true)
            } ${position.symbol}",
            hintKey = "\$perps_position_size_details_hint",
            isSensitiveData = true
        ),
        row(
            "Funding Payments",
            fundingText(position.fundingReceived),
            hintKey = "\$perps_funding_payments_hint",
            isSensitiveData = true
        )
    )

    private fun row(
        key: String,
        value: CharSequence,
        hintKey: String,
        isSensitiveData: Boolean = false
    ) = KeyValueRowView(context, LocaleController.getString(key), value).apply {
        this.isSensitiveData = isSensitiveData
        setHint { onShowInfo(this.key, LocaleController.getString(hintKey)) }
    }

    private fun fundingText(fundingReceived: Double?): CharSequence {
        val received = fundingReceived ?: return EMPTY_VALUE
        val amount = abs(received)
        if (amount <= MAX_HIDDEN_USD) return 0.0.toUsdString()
        val text = received.toUsdString(
            showPositiveSign = true,
            decimals = if (amount < 0.01) SUB_CENT_DECIMALS else 2
        )
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(pnlColor(received)),
                0,
                text.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    override fun updateTheme() {
        rowsView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            clipToBounds = true
        )
    }

    private companion object {
        const val EMPTY_VALUE = "—"
        const val MAX_HIDDEN_USD = 0.001
        const val SUB_CENT_DECIMALS = 3
    }
}
