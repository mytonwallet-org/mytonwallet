package org.mytonwallet.app_air.ledger.screens.ledgerWallets.cells

import android.content.Context
import android.text.SpannableStringBuilder
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isGone
import org.mytonwallet.app_air.ledger.screens.ledgerWallets.LedgerWalletsVC
import org.mytonwallet.app_air.uicomponents.drawable.CheckboxDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class LedgerWalletCell(
    context: Context,
) : WCell(context), WThemedView {

    private var item: LedgerWalletsVC.Item? = null
    var onTap: ((item: LedgerWalletsVC.Item) -> Unit)? = null

    private val checkboxDrawable = CheckboxDrawable {
        invalidate()
    }

    private val imageView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(checkboxDrawable)
    }

    private val topLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val bottomLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(14f)
        lbl
    }

    private val contentView = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(topLeftLabel)
        addView(bottomLeftLabel)
    }

    private val rightLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    init {
        layoutParams.apply {
            height = 60.dp
        }
        addView(imageView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(contentView)
        addView(rightLabel)
        setConstraints {
            toStart(imageView, 25f)
            toCenterY(imageView)
            toCenterY(contentView, 14f)
            toStart(contentView, 72f)
            toCenterY(rightLabel)
            toEnd(rightLabel, 20f)
        }

        setOnClickListener {
            item?.let {
                onTap?.invoke(it)
                checkboxDrawable.setChecked(it.isSelected, animated = true)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            0f
        )
        addRippleEffect(WColor.SecondaryBackground.color)
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        rightLabel.setTextColor(WColor.SecondaryText.color)
        checkboxDrawable.checkedColor = WColor.Tint.color
        checkboxDrawable.uncheckedColor = WColor.SecondaryText.color
    }

    fun configure(
        item: LedgerWalletsVC.Item,
    ) {
        val alpha = if (item.isAlreadyImported) 0.4f else 1f
        imageView.alpha = alpha
        topLeftLabel.alpha = alpha
        bottomLeftLabel.alpha = alpha
        rightLabel.alpha = alpha
        isEnabled = !item.isAlreadyImported

        this.item = item

        checkboxDrawable.setChecked(item.isSelected, animated = false)
        topLeftLabel.text =
            item.title ?: SpannableStringBuilder(
                item.wallet.wallet.address.formatStartEndAddress()
            ).apply {
                styleDots()
            }
        bottomLeftLabel.text =
            if (item.title != null) SpannableStringBuilder(
                item.wallet.wallet.address.formatStartEndAddress()
            ).apply {
                styleDots()
            } else null
        bottomLeftLabel.isGone = bottomLeftLabel.text.isNullOrEmpty()
        val toncoin = TokenStore.getToken(TONCOIN_SLUG)
        toncoin?.price?.let { price ->
            rightLabel.setAmount(
                amount = item.wallet.balance,
                decimals = toncoin.decimals,
                currency = toncoin.symbol,
                currencyDecimals = toncoin.decimals,
                smartDecimals = true
            )
        }

        updateTheme()
    }

}
