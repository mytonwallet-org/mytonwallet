package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.content.Context
import android.text.InputType
import android.text.TextUtils
import android.text.method.DigitsKeyListener
import android.view.Gravity
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAmountEditText
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WTokenMaxButton
import org.mytonwallet.app_air.uicomponents.widgets.WTokenSymbolIconView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

class SwapAssetInputView(context: Context) : WCell(context), WThemedView {
    private val leftTopLabel = WLabel(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END

        setStyle(16f, WFont.Regular)
        setLineHeight(24f)
    }

    private val rightTopButton = WTokenMaxButton(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, 24.dp)
    }

    val assetView = WTokenSymbolIconView(context).apply {
        id = generateViewId()
        drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18
        )
        defaultSymbol = LocaleController.getString("Select Token")
        layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
    }

    val amountEditText = WAmountEditText(context).apply {
        id = generateViewId()
        hint = "0"
        layoutParams = LayoutParams(0, 48.dp)
        gravity = Gravity.CENTER_VERTICAL or
            (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
        inputType = InputType.TYPE_NUMBER_FLAG_DECIMAL
        keyListener = DigitsKeyListener.getInstance("0123456789.,")
        isHorizontalFadingEdgeEnabled = true
        setSingleLine()
        setHorizontallyScrolling(true)
        setPaddingLocalized(0, 0, 20.dp, 0)
        setOnFocusChangeListener { _, hasFocus ->
            if (!hasFocus) {
                setSelection(0)
                scrollTo(0, 0)
            }
        }
    }

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
            forceSeparator = true
        }
    }

    enum class Mode {
        SELL, BUY
    }

    init {
        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 96.dp)
        clipChildren = false

        addView(leftTopLabel)
        addView(rightTopButton)
        addView(assetView)
        addView(this.amountEditText)

        setConstraints {
            toStart(leftTopLabel, 20f)
            endToStart(leftTopLabel, rightTopButton)
            toTop(leftTopLabel, 16f)

            startToEnd(rightTopButton, leftTopLabel, 6f)
            centerYToCenterY(rightTopButton, leftTopLabel)
            toEnd(rightTopButton, 14f)

            toStart(this@SwapAssetInputView.amountEditText, 20f)
            centerYToCenterY(this@SwapAssetInputView.amountEditText, assetView)
            endToStart(this@SwapAssetInputView.amountEditText, assetView)

            startToEnd(assetView, this@SwapAssetInputView.amountEditText, 8f)
            toBottom(assetView, 14f)
            toEnd(assetView, 20f)
        }
        updateTheme()
    }

    private var mode = Mode.SELL
    fun setMode(mode: Mode) {
        this.mode = mode
        if (mode == Mode.SELL) {
            leftTopLabel.text = LocaleController.getString("You sell")
            rightTopButton.visibility = VISIBLE
        } else {
            leftTopLabel.text = LocaleController.getString("You buy")
            rightTopButton.visibility = GONE
        }
        updateTheme()
    }

    private var currentAsset: IApiToken? = null

    fun setAsset(asset: IApiToken?) {
        if (currentAsset?.slug == asset?.slug) {
            return
        }

        currentAsset = asset
        assetView.setAsset(asset, showChain = true)
        asset?.let {
            amountEditText.amountTextWatcher.decimals = it.decimals
            amountEditText.amountTextWatcher.afterTextChanged(amountEditText.text)
        } ?: run {
            amountEditText.amountTextWatcher.decimals = null
            amountEditText.text?.clear()
        }
    }

    fun setBalance(subtitle: String?) {
        rightTopButton.setAmount(subtitle)
    }

    fun setOnMaxBalanceClickListener(onClickListener: OnClickListener?) {
        rightTopButton.setOnClickListener(onClickListener)
    }

    override fun updateTheme() {
        if (mode == Mode.SELL) {
            setBackgroundColor(WColor.Background.color, ViewConstants.TOOLBAR_RADIUS.dp, 0f)
        } else {
            setBackgroundColor(WColor.Background.color, 0f, ViewConstants.BLOCK_RADIUS.dp)
        }
        separatorBackgroundDrawable.invalidateSelf()
        leftTopLabel.setTextColor(WColor.SecondaryText.color)
        rightTopButton.background = ViewHelpers.roundedRippleDrawable(
            null, WColor.tintRippleColor, 8f.dp
        )
    }
}
