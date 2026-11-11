package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresPaymentSymbol
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsBalanceWithdrawal
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class FuturesBalanceWithdrawalCell(context: Context, private val onWithdraw: () -> Unit) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private var canWithdraw = false
    private var isPreparing = false

    private val iconView = WCustomImageView(context)

    private val balanceLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
    }

    private val detailLabel = WLabel(context).apply {
        setStyle(14f)
        setSingleLine()
    }

    private val withdrawLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        text = LocaleController.getString("PerpsWithdraw")
        setTextColor(WColor.Tint)
        isTinted = true
        setPadding(12.dp, 0, 12.dp, 0)
        gravity = Gravity.CENTER
    }

    private val progressDrawable = RoundProgressDrawable(sizeDp = 16f, strokeWidthDp = 1.5f)

    // The arc's stroke runs past the drawable's bounds
    private val progressView = AppCompatImageView(context).apply {
        setPadding(2.dp)
        setImageDrawable(progressDrawable)
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        visibility = GONE
    }

    private val withdrawButton = FrameLayout(context).apply {
        id = generateViewId()
        addView(withdrawLabel, FrameLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        addView(
            progressView,
            FrameLayout.LayoutParams(PROGRESS_SIZE.dp, PROGRESS_SIZE.dp, Gravity.CENTER)
        )
        setOnClickListener { withdraw() }
    }

    private val cardView = WView(context).apply {
        addView(iconView, LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp))
        addView(balanceLabel, LayoutParams(0, WRAP_CONTENT))
        addView(detailLabel, LayoutParams(0, WRAP_CONTENT))
        addView(withdrawButton, LayoutParams(WRAP_CONTENT, BUTTON_HEIGHT.dp))
        setConstraints {
            toCenterY(iconView)
            toStart(iconView, 12f)
            toTop(balanceLabel, 9f)
            startToEnd(balanceLabel, iconView, 12f)
            endToStart(balanceLabel, withdrawButton, 10f)
            toBottom(detailLabel, 7f)
            startToStart(detailLabel, balanceLabel)
            endToStart(detailLabel, withdrawButton, 10f)
            toCenterY(withdrawButton)
            toEnd(withdrawButton, 12f)
        }
        setOnClickListener { withdraw() }
    }

    init {
        addView(cardView, LayoutParams(MATCH_PARENT, ROW_HEIGHT.dp))
        setConstraints {
            allEdges(cardView)
        }
        updateTheme()
    }

    fun configure(
        withdrawal: MApiPerpsBalanceWithdrawal,
        canWithdraw: Boolean,
        isPreparing: Boolean
    ) {
        setCardPadding(ViewConstants.GAP.dp)
        this.canWithdraw = canWithdraw
        this.isPreparing = isPreparing
        withdrawLabel.isInvisible = isPreparing
        progressView.isVisible = isPreparing
        TokenStore.getToken(PERPS_PAYMENT_TOKEN_SLUG)?.let(iconView::setAsset)
            ?: iconView.clear()
        balanceLabel.text = withdrawal.balance.toDoubleOrNull()?.toUsdString() ?: withdrawal.balance
        detailLabel.text = "${LocaleController.getString("PerpsAvailable")} · $futuresPaymentSymbol"
        withdrawButton.alpha = if (canWithdraw) 1f else DISABLED_ALPHA
        updateTheme()
    }

    override fun updateTheme() {
        cardView.setPositionsCardBackground(isFirst = true, isLast = true)
        balanceLabel.setTextColor(WColor.PrimaryText.color)
        detailLabel.setTextColor(WColor.SecondaryText.color)
        withdrawButton.setBackgroundColor(WColor.Tint.color.colorWithAlpha(25), 15f.dp)
        progressDrawable.color = WColor.Tint.color
    }

    private fun withdraw() {
        if (canWithdraw && !isPreparing) onWithdraw()
    }

    private companion object {
        const val ICON_SIZE = 44

        const val ROW_HEIGHT = 58
        const val BUTTON_HEIGHT = 30
        const val DISABLED_ALPHA = 0.5f
        const val PROGRESS_SIZE = 20
    }
}
