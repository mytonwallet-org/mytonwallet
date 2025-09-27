package org.mytonwallet.app_air.uistake.staking.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.InputType
import android.text.TextUtils
import android.text.method.DigitsKeyListener
import android.view.Gravity
import android.widget.LinearLayout
import androidx.core.content.ContextCompat
import androidx.core.widget.doOnTextChanged
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAmountEditText
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WTokenMaxButton
import org.mytonwallet.app_air.uicomponents.widgets.WTokenSymbolIconView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.MToken
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class StakeInputView(
    context: Context,
    layoutParams: LayoutParams = LayoutParams(
        LayoutParams.MATCH_CONSTRAINT,
        LayoutParams.WRAP_CONTENT
    ),
    onClickEquivalentLabel: (() -> Unit)? = null,
    onClickMaxBalanceButton: (() -> Unit)? = null,
) : WView(context), WThemedView {

    private val amountTitleLabel = WLabel(context).apply {
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        text =
            LocaleController.getString("Amount")

        setTextColor(WColor.PrimaryText.color)
        setStyle(16f, WFont.Medium)
        setLineHeight(24f)
    }

    private val maxBalanceButton = WTokenMaxButton(context).apply {
        this.id = generateViewId()
        setPaddingDp(6, 0, 6, 0)

        setOnClickListener { onClickMaxBalanceButton?.invoke() }
    }

    private val tokenSymbolView = WTokenSymbolIconView(context).apply {
        id = generateViewId()
    }

    val amountEditText = WAmountEditText(context).apply {
        id = generateViewId()
        hint = "0"
        isSingleLine = true
        gravity = Gravity.CENTER_VERTICAL or
            (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
        inputType = InputType.TYPE_NUMBER_FLAG_DECIMAL
        keyListener = DigitsKeyListener.getInstance("0123456789.,")
        textSize = 22f
        setPaddingLocalized(0, 0, 15.dp, 0)
    }

    private val equivalentAmountLabel = WLabel(context).apply {
        id = generateViewId()
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        setTextColor(WColor.SecondaryText.color)
        setStyle(14f, WFont.Regular)
        setLineHeight(20f)

        setOnClickListener { onClickEquivalentLabel?.invoke() }
    }

    private val switchCurrencyIcon: WImageView by lazy {
        val icon = WImageView(context)
        icon.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                R.drawable.ic_switch_24
            )?.apply {
                setTint(WColor.SecondaryText.color)
            }
        )
        icon.setOnClickListener { onClickEquivalentLabel?.invoke() }
        icon
    }

    val feeLabel = WLabel(context).apply {
        setPadding(0, 4.dp, 0, 0)
        setTextColor(WColor.SecondaryText.color)
        setStyle(14f, WFont.Regular)
    }

    override fun setupViews() {
        super.setupViews()

        layoutParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 136.dp)

        addView(amountTitleLabel, LayoutParams(0, LayoutParams.WRAP_CONTENT))
        addView(maxBalanceButton, LayoutParams(LayoutParams.WRAP_CONTENT, 20.dp))
        addView(amountEditText, LayoutParams(0, 28.dp))
        addView(tokenSymbolView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        addView(equivalentAmountLabel, LayoutParams(LayoutParams.WRAP_CONTENT, 20.dp))
        addView(switchCurrencyIcon, LayoutParams(16.dp, 16.dp))
        addView(feeLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))

        setConstraints {

            toStart(amountTitleLabel, 20f)
            toTop(amountTitleLabel, 16.5f)
            endToStart(amountTitleLabel, maxBalanceButton, 10f)

            startToEnd(maxBalanceButton, amountTitleLabel)
            topToTop(maxBalanceButton, amountTitleLabel, 2f)
            bottomToBottom(maxBalanceButton, amountTitleLabel)
            toEndPx(maxBalanceButton, 19.5f.dp.roundToInt() - 6)

            toStart(amountEditText, 20f)
            centerYToCenterY(amountEditText, tokenSymbolView)
            endToStart(amountEditText, tokenSymbolView, 10f)

            startToEnd(tokenSymbolView, amountEditText)
            topToBottom(tokenSymbolView, maxBalanceButton, 14f)
            toEnd(tokenSymbolView, 20f)

            toStart(equivalentAmountLabel, 20f)
            toBottom(equivalentAmountLabel, 16f)

            startToEnd(switchCurrencyIcon, equivalentAmountLabel)
            centerYToCenterY(switchCurrencyIcon, equivalentAmountLabel)

            toEnd(feeLabel, 20f)
            centerYToCenterY(feeLabel, equivalentAmountLabel)
        }
    }

    fun setOnAmountInputListener(listener: (CharSequence?) -> Unit) {
        this.amountEditText.doOnTextChanged { text, _, _, _ ->
            listener.invoke(text)
        }
    }

    fun setAmount(text: CharSequence) {
        amountEditText.setText(text)
    }

    fun getEquivalentLabel() = equivalentAmountLabel

    fun setMaxBalance(balance: String) {
        maxBalanceButton.setAmount(balance)
    }

    private var currentAsset: MToken? = null

    fun setAsset(asset: MToken?) {
        if (currentAsset?.slug == asset?.slug) {
            return
        }

        currentAsset = asset
        asset?.let {
            if (asset.slug == TONCOIN_SLUG || asset.slug == STAKE_SLUG)
                tokenSymbolView.setTonAsset(false)
            else tokenSymbolView.setAsset(asset, false)
            amountEditText.amountTextWatcher.decimals = it.decimals
            amountEditText.amountTextWatcher.afterTextChanged(amountEditText.text)
        } ?: run {
            amountEditText.amountTextWatcher.decimals = null
            amountEditText.text?.clear()
        }

        // TODO remove in
    }

    fun setShowingBaseCurrency(isShowingBaseCurrency: Boolean) {
        tokenSymbolView.setBaseCurrIndicatorEnabled(isShowingBaseCurrency)
    }

    fun setAssetAsBaseCurrency(baseCurrencyDecimal: Int, text: CharSequence) {
        amountEditText.amountTextWatcher.decimals = baseCurrencyDecimal
        amountEditText.setText(text)
        // TODO add in
    }

    override fun updateTheme() {
        amountTitleLabel.setTextColor(WColor.PrimaryText.color)
        equivalentAmountLabel.setTextColor(WColor.SecondaryText.color)
        feeLabel.setTextColor(WColor.SecondaryText.color)
        switchCurrencyIcon.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                R.drawable.ic_switch_24
            )?.apply {
                setTint(WColor.SecondaryText.color)
            }
        )
    }

}
