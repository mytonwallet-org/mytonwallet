package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Paint
import android.text.InputType
import android.text.TextPaint
import android.text.TextUtils
import android.text.method.DigitsKeyListener
import android.view.Gravity
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.drawable.counter.Counter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WAmountEditText
import org.mytonwallet.app_air.uicomponents.widgets.WCounterButton
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WTokenMaxButton
import org.mytonwallet.app_air.uicomponents.widgets.WTokenSymbolIconView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

@SuppressLint("ViewConstructor")
class TokenAmountInputView(
    context: Context,
    private val isFirstItem: Boolean,
) : WView(context), Counter.Callback, WThemedView {

    data class State(
        val title: String?,
        val token: IApiToken?,
        val balance: String?,
        val equivalent: String?,
        val subtitle: String?,
        val fiatMode: Boolean,

        val inputDecimal: Int,
        val inputSymbol: String?,
        val inputError: Boolean
    )

    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Regular.typeface
        textSize = 14f.dp
    }

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
        }
    }

    private val titleTextView = HeaderCell(context, 20f).apply {
        id = generateViewId()
        configure(
            title = LocaleController.getString("Amount"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val maxBalanceButton = WTokenMaxButton(context).apply {
        id = generateViewId()
        visibility = GONE
    }

    val tokenSelectorView = WTokenSymbolIconView(context).apply {
        id = generateViewId()
        drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18
        )
        defaultSymbol =
            LocaleController.getString("Select Token")
    }

    val amountEditText = WAmountEditText(context).apply {
        id = generateViewId()
        hint = "0"
        isSingleLine = true
        gravity = Gravity.CENTER_VERTICAL or
            (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
        inputType = InputType.TYPE_NUMBER_FLAG_DECIMAL
        keyListener = DigitsKeyListener.getInstance("0123456789.,")
        setPaddingLocalized(0, 0, 12.dp, 0)
    }

    private val equivalentTextView =
        WCounterButton(
            context,
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_switch_24
            )!!,
            false
        ).apply {
            id = generateViewId()
        }

    private val feeTextView =
        WCounterButton(
            context,
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_info_24
            )!!,
            true
        ).apply {
            id = generateViewId()
        }

    override fun setupViews() {
        super.setupViews()

        clipChildren = false
        addView(titleTextView, LayoutParams(0, LayoutParams.WRAP_CONTENT))
        addView(
            maxBalanceButton,
            LayoutParams(LayoutParams.WRAP_CONTENT, WTokenMaxButton.Companion.HEIGHT.dp)
        )
        addView(
            tokenSelectorView,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        )
        addView(amountEditText, LayoutParams(LayoutParams.MATCH_CONSTRAINT, 44.dp))
        addView(
            equivalentTextView,
            LayoutParams(LayoutParams.WRAP_CONTENT, WCounterButton.Companion.HEIGHT.dp)
        )
        addView(
            feeTextView,
            LayoutParams(LayoutParams.WRAP_CONTENT, WCounterButton.Companion.HEIGHT.dp)
        )

        setConstraints {
            toStart(titleTextView)
            toTop(titleTextView)
            endToStart(titleTextView, maxBalanceButton, 6f)
            toTop(maxBalanceButton, 16f)
            toEnd(maxBalanceButton, 20f - WTokenMaxButton.PADDING_HORIZONTAL)

            toStart(amountEditText, 20f)
            centerYToCenterY(amountEditText, tokenSelectorView)
            endToStart(amountEditText, tokenSelectorView)
            toEnd(tokenSelectorView, 16f)
            toTop(tokenSelectorView, 44f)

            topToBottom(equivalentTextView, tokenSelectorView, 12f)
            toStart(equivalentTextView, 20f - WCounterButton.PADDING_HORIZONTAL)
            toBottom(equivalentTextView, 16f)

            topToBottom(feeTextView, tokenSelectorView, 12f)
            toEnd(feeTextView, 20f - WCounterButton.PADDING_HORIZONTAL)
            toBottom(feeTextView, 16f)
        }

        updateTheme()
    }

    fun set(state: State, isFeeDetailed: Boolean) {
        titleTextView.setTitle(state.title ?: "")
        maxBalanceButton.setAmount(state.balance)
        tokenSelectorView.setAsset(state.token)
        tokenSelectorView.setBaseCurrIndicatorEnabled(state.fiatMode)
        amountEditText.amountTextWatcher.decimals = state.inputDecimal
        amountEditText.amountTextWatcher.afterTextChanged(amountEditText.text)
        amountEditText.setBaseCurrencySymbol(state.inputSymbol)
        amountEditText.isError.changeValue(state.inputError && isAttachedToWindow)

        var avail = measuredWidth - 40f.dp
        feeTextView.shouldShowDrawable = isFeeDetailed
        feeTextView.isClickable = isFeeDetailed
        if (state.subtitle.isNullOrEmpty() || measuredWidth == 0) {
            feeTextView.setText(state.subtitle)
        } else {
            if (avail > 0) {
                val text = TextUtils.ellipsize(
                    state.subtitle,
                    textPaint,
                    avail,
                    TextUtils.TruncateAt.END
                )?.toString()
                avail -= textPaint.measureText(text)
                avail -= 12f.dp // margin
                feeTextView.setText(text)
            } else {
                feeTextView.setText(null)
            }
        }

        if (state.equivalent.isNullOrEmpty() || measuredWidth == 0) {
            equivalentTextView.setText(state.equivalent)
        } else {
            avail -= 16f.dp // icon
            if (avail > 0) {
                val text = TextUtils.ellipsize(
                    state.equivalent,
                    textPaint,
                    avail,
                    TextUtils.TruncateAt.END
                )?.toString()
                avail -= textPaint.measureText(text)
                equivalentTextView.setText(text)
            } else {
                equivalentTextView.setText(null)
            }
        }
    }

    fun doOnEquivalentButtonClick(listener: (() -> Unit)?) {
        equivalentTextView.setOnClickListener {
            listener?.invoke()
        }
    }

    fun doOnFeeButtonClick(listener: (() -> Unit)?) {
        feeTextView.setOnClickListener {
            listener?.invoke()
        }
    }

    fun doOnMaxButtonClick(listener: (() -> Unit)?) {
        maxBalanceButton.setOnClickListener {
            listener?.invoke()
        }
        maxBalanceButton.visibility = VISIBLE
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            (if (isFirstItem) ViewConstants.TOOLBAR_RADIUS else ViewConstants.BLOCK_RADIUS).dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
    }

    override fun onCounterAppearanceChanged(counter: Counter, sizeChanged: Boolean) {
        invalidate()
    }
}
