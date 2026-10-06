package org.mytonwallet.app_air.uiswap.screens.tokenTrade.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Matrix
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.isVisible
import androidx.core.widget.NestedScrollView
import kotlin.math.ceil
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.FiatCurrencyIconView
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.TokenTagHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeModel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class TokenTradeView(
    context: Context,
    private val model: TokenTradeModel,
    private val onSelectMethod: () -> Unit,
    private val onContinue: () -> Unit
) : FrameLayout(context),
    WThemedView {

    var topInset = 0
    var bottomInset = 0

    private val scrollView = NestedScrollView(context).apply {
        id = generateViewId()
        isVerticalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
    }
    private val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }

    private val amountCard = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val cardTopSpacer = View(context)
    private val conversionLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setSingleLine()
    }
    private val conversionIcon = ImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_switch_24)
        scaleType = ImageView.ScaleType.MATRIX
        imageMatrix = Matrix().apply {
            setScale(17f.dp / drawable.intrinsicWidth, 19.5f.dp / drawable.intrinsicHeight)
            postTranslate((-2.5f).dp, (-1.75f).dp)
        }
    }
    private val conversionPill = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(8.dp, 0, 8.dp, 0)
        contentDescription = LocaleController.getString("Switch Amount Currency")
        clipToOutline = true
        // Weighted so that the icon keeps its place while the pill's width animates
        addView(conversionLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, 1f))
        addView(
            conversionIcon,
            LinearLayout.LayoutParams(12.dp, 16.dp).apply { marginStart = 4.dp }
        )
        setOnClickListener {
            model.toggleUnit()
            render()
        }
    }
    val amountField = TokenTradeAmountField(context)
    private var displayedIsTokenAmount: Boolean? = null
    private var isRollingConversion = false
    private var conversionWidthAnimator: ValueAnimator? = null
    private val feeLabel = WLabel(context).apply {
        setStyle(14f)
        gravity = Gravity.END
        maxLines = 2
    }

    private val methodIconContainer = FrameLayout(context)
    private val methodTokenIcon = IconView(context, 28.dp, 12.dp)
    private val methodFiatIcon = FiatCurrencyIconView(context)
    private val methodTitle = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }
    private val methodAmount = WLabel(context).apply {
        setStyle(17f)
        setSingleLine()
    }
    private val methodSymbol = WLabel(context).apply {
        setStyle(17f)
        setSingleLine()
    }
    private val methodBadge = WLabel(context).apply {
        setStyle(10f, WFont.Medium)
        setPadding(3.dp, 0, 3.dp, 0)
        gravity = Gravity.CENTER
    }
    private val methodDropdown = ImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14)
        scaleType = ImageView.ScaleType.CENTER
    }
    private val methodRipple = WRippleDrawable.create((METHOD_ROW_HEIGHT / 2f).dp)
    private val methodRow = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPaddingRelative(14.dp, 0, 20.dp, 0)
        clipChildren = false
        background = methodRipple
        methodIconContainer.addView(methodTokenIcon, FrameLayout.LayoutParams(30.dp, 30.dp))
        methodIconContainer.addView(methodFiatIcon, FrameLayout.LayoutParams(28.dp, 28.dp))
        addView(methodIconContainer, LinearLayout.LayoutParams(28.dp, 28.dp))
        addView(
            methodTitle,
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { marginStart = 10.dp }
        )
        addView(
            methodAmount,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = 4.dp }
        )
        addView(
            methodSymbol,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = 4.dp }
        )
        addView(
            methodBadge,
            LinearLayout.LayoutParams(WRAP_CONTENT, 14.dp).apply { marginStart = 4.dp }
        )
        addView(
            methodDropdown,
            LinearLayout.LayoutParams(10.dp, 22.dp).apply { marginStart = 4.dp }
        )
        setOnClickListener { onSelectMethod() }
    }

    private val bottomPanel = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val controlsContainer = FrameLayout(context)
    private val percentRow = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
    private val percentButtons = listOf(25, 50, 100).map { percentage ->
        WLabel(context).apply {
            setStyle(17f, WFont.Medium)
            gravity = Gravity.CENTER
            text = "$percentage%"
            setOnClickListener {
                model.useFraction(percentage)
                render()
            }
        }
    }
    val continueButton = WButton(context).apply {
        buttonHeight = 52.dp
        setOnClickListener { onContinue() }
    }
    val keypad = TokenTradeKeypadView(
        context,
        onInsert = { amountField.insert(it) },
        onDelete = { amountField.deleteBackward() }
    )

    init {
        id = generateViewId()
        percentButtons.forEachIndexed { index, button ->
            percentRow.addView(
                button,
                LinearLayout.LayoutParams(0, MATCH_PARENT, 1f).apply {
                    if (index > 0) marginStart = 10.dp
                }
            )
        }
        controlsContainer.addView(percentRow, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        controlsContainer.addView(continueButton, LayoutParams(MATCH_PARENT, 52.dp))
        bottomPanel.addView(
            controlsContainer,
            LinearLayout.LayoutParams(MATCH_PARENT, 52.dp).apply {
                setMargins(24.dp, 24.dp, 24.dp, 12.dp)
            }
        )
        bottomPanel.addView(keypad, LinearLayout.LayoutParams(MATCH_PARENT, 256.dp))

        amountCard.addView(cardTopSpacer, LinearLayout.LayoutParams(MATCH_PARENT, 80.dp))
        amountCard.addView(
            conversionPill,
            LinearLayout.LayoutParams(WRAP_CONTENT, 26.dp).apply { marginStart = 24.dp }
        )
        amountCard.addView(
            amountField,
            LinearLayout.LayoutParams(MATCH_PARENT, 86.dp).apply {
                topMargin = 1.dp
                marginStart = 24.dp
                marginEnd = 4.dp
            }
        )
        amountCard.addView(View(context), LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        amountCard.addView(
            feeLabel,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                setMargins(24.dp, 0, 24.dp, 22.dp)
            }
        )
        content.addView(amountCard, LinearLayout.LayoutParams(MATCH_PARENT, 300.dp))
        content.addView(
            methodRow,
            LinearLayout.LayoutParams(MATCH_PARENT, METHOD_ROW_HEIGHT.dp).apply {
                setMargins(10.dp, METHOD_ROW_GAP.dp, 10.dp, METHOD_ROW_GAP.dp)
            }
        )
        scrollView.addView(content, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(scrollView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(bottomPanel, LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM))

        amountField.onChange = {
            model.userEditedInput(it)
            render()
        }
        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = MeasureSpec.getSize(heightMeasureSpec)
        val panelChromeHeight = 88.dp + max(16.dp, bottomInset)
        val methodRowSpace = (METHOD_ROW_HEIGHT + 2 * METHOD_ROW_GAP).dp
        var keypadHeight = TokenTradeKeypadView.preferredHeight
        val flexibleCardHeight = height - panelChromeHeight - keypadHeight - methodRowSpace
        // The card stops at its design height; taller screens give the rest to the keypad,
        // and short screens shrink the keypad before the card goes below its minimum.
        val maxCardHeight = topInset + CARD_MAX_CONTENT_HEIGHT.dp
        val minCardHeight = topInset + CARD_MIN_CONTENT_HEIGHT.dp
        if (flexibleCardHeight > maxCardHeight) {
            keypadHeight += flexibleCardHeight - maxCardHeight
        } else if (flexibleCardHeight < minCardHeight) {
            keypadHeight = max(
                KEYPAD_MIN_HEIGHT.dp,
                keypadHeight - (minCardHeight - flexibleCardHeight)
            )
        }
        (keypad.layoutParams as LinearLayout.LayoutParams).height = keypadHeight
        bottomPanel.setPadding(0, 0, 0, max(16.dp, bottomInset))
        val controlsHeight = panelChromeHeight + keypadHeight
        val contentHeight = max(0, height - controlsHeight)
        val cardHeight = max(minCardHeight, contentHeight - methodRowSpace)
        val isCompact = cardHeight - topInset < 260.dp
        (amountCard.layoutParams as LinearLayout.LayoutParams).height = cardHeight
        val amountFieldHeight = if (isCompact) 64.dp else 86.dp
        // Space above the pill is 78dp less than below the field; when that leaves less than
        // 48dp above the pill, the gap below is only 16dp larger.
        val freeHeight = max(
            0,
            cardHeight - topInset - 8.dp - 26.dp - 1.dp - amountFieldHeight
        )
        val topGap = ((freeHeight - 78.dp) / 2).takeIf { it >= 48.dp }
            ?: max(0, (freeHeight - 16.dp) / 2)
        (cardTopSpacer.layoutParams as LinearLayout.LayoutParams).height =
            topInset + 8.dp + topGap
        (amountField.layoutParams as LinearLayout.LayoutParams).height = amountFieldHeight
        (feeLabel.layoutParams as LinearLayout.LayoutParams).bottomMargin =
            if (isCompact) 12.dp else 22.dp
        (scrollView.layoutParams as LayoutParams).bottomMargin = controlsHeight
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.SecondaryBackground.color)
        amountCard.setBackgroundColor(WColor.Background.color, 0f, 28f.dp)
        bottomPanel.setBackgroundColor(WColor.Background.color, 32f.dp, 0f)
        methodRipple.backgroundColor = WColor.Background.color
        methodRipple.rippleColor = WColor.BackgroundRipple.color
        conversionPill.background = GradientDrawable().apply {
            cornerRadius = 13f.dp
            setColor(WColor.SecondaryText.color.colorWithAlpha(31))
        }
        conversionLabel.setTextColor(WColor.SecondaryText.color)
        conversionIcon.setColorFilter(WColor.SecondaryText.color)
        feeLabel.setTextColor(WColor.SecondaryText.color)
        methodTitle.setTextColor(WColor.PrimaryText.color)
        methodAmount.setTextColor(WColor.PrimaryText.color)
        methodSymbol.setTextColor(WColor.SecondaryText.color)
        methodBadge.setTextColor(WColor.SecondaryText.color)
        methodBadge.setBackgroundColor(WColor.SecondaryBackground.color, 4f.dp)
        methodDropdown.setColorFilter(WColor.SecondaryText.color)
        percentButtons.forEach {
            it.setTextColor(WColor.PrimaryText.color)
            it.background = WRippleDrawable.create(26f.dp).apply {
                backgroundColor = WColor.SecondaryBackground.color
                rippleColor = WColor.BackgroundRipple.color
            }
        }
        continueButton.customTint = (if (model.isBuying) WColor.Buy else WColor.Sell).color
        render()
    }

    // The old conversion rolls up out of the pill and the new one rolls in from below
    private fun rollConversionLabel() {
        val distance = conversionPill.height.toFloat()
        isRollingConversion = true
        animateConversionWidth(model.conversionText)
        conversionLabel.animate().cancel()
        conversionLabel.animate()
            .translationY(-distance)
            .setDuration(AnimationConstants.SUPER_QUICK_ANIMATION)
            .setInterpolator(CubicBezierInterpolator.EASE_IN)
            .withEndAction {
                isRollingConversion = false
                conversionLabel.text = model.conversionText
                conversionLabel.translationY = distance
                conversionLabel.animate()
                    .translationY(0f)
                    .setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_OUT_QUINT)
                    .withEndAction(null)
                    .start()
            }
            .start()
    }

    private fun animateConversionWidth(text: CharSequence?) {
        val targetWidth = conversionPill.paddingStart + conversionPill.paddingEnd +
            ceil(conversionLabel.paint.measureText(text?.toString() ?: "")).toInt() +
            (conversionIcon.layoutParams as LinearLayout.LayoutParams).let {
                it.width + it.marginStart
            }
        val layoutParams = conversionPill.layoutParams
        conversionWidthAnimator?.cancel()
        conversionWidthAnimator = ValueAnimator.ofInt(conversionPill.width, targetWidth).apply {
            duration = AnimationConstants.SUPER_QUICK_ANIMATION +
                AnimationConstants.VERY_VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                layoutParams.width = it.animatedValue as Int
                conversionPill.layoutParams = layoutParams
            }
            doOnEnd {
                if (conversionWidthAnimator !== it) return@doOnEnd
                conversionWidthAnimator = null
                layoutParams.width = WRAP_CONTENT
                conversionPill.layoutParams = layoutParams
            }
            start()
        }
    }

    fun render() {
        val switchesUnit = displayedIsTokenAmount.let { it != null && it != model.isTokenAmount }
        displayedIsTokenAmount = model.isTokenAmount
        if (switchesUnit && conversionPill.isLaidOut && WGlobalStorage.getAreAnimationsActive()) {
            rollConversionLabel()
        } else if (!isRollingConversion) {
            conversionLabel.text = model.conversionText
        }
        conversionLabel.alpha = if (model.isConversionAmountStale) 0.55f else 1f
        conversionPill.isEnabled = model.price > 0

        val symbol = model.token.symbol ?: ""
        amountField.contentDescription = LocaleController.getString("Amount") + ", " +
            if (model.isTokenAmount) symbol else model.currency.currencyCode
        amountField.configure(
            input = model.input,
            decimals = model.inputDecimals,
            prefix = if (model.isTokenAmount) "" else model.currency.sign,
            suffix = if (model.isTokenAmount) " $symbol" else "",
            hasAmount = model.hasAmount,
            switchesUnit = switchesUnit
        )
        val fee = model.feeText
        feeLabel.text = fee
        feeLabel.visibility = if (fee == null) INVISIBLE else VISIBLE

        val cardCurrency = model.cardCurrency
        methodFiatIcon.isVisible = cardCurrency != null
        methodTokenIcon.isVisible = cardCurrency == null
        if (cardCurrency != null) {
            methodFiatIcon.configure(cardCurrency)
        } else {
            methodTokenIcon.config(TokenStore.getToken(model.paymentToken?.slug), showChain = true)
        }
        methodTitle.text = LocaleController.getString(
            if (model.isBuying) "You Pay" else "You Receive"
        )
        val methodAmountText = model.methodAmountText
        methodAmount.text = methodAmountText
        methodAmount.isVisible = methodAmountText != null
        methodAmount.alpha = if (model.isMethodAmountStale) 0.55f else 1f
        methodSymbol.text = model.methodSymbol
        val badge = if (cardCurrency == null) {
            TokenTagHelper.staticTagText(model.paymentToken?.slug)
        } else {
            null
        }
        methodBadge.text = badge
        methodBadge.isVisible = badge != null

        val showsButton = model.hasAmount || (cardCurrency != null && model.isBuying)
        continueButton.isVisible = showsButton
        percentRow.isVisible = !showsButton
        if (showsButton) {
            val isLoading = model.isLoading
            continueButton.isLoading = isLoading
            if (!isLoading) {
                continueButton.isEnabled = model.canContinue
                continueButton.text = model.actionTitle
            }
        } else {
            val hasMaximum = (model.maximumTokenAmount?.signum() ?: 0) > 0
            percentButtons.forEach {
                it.isEnabled = hasMaximum
                it.alpha = if (hasMaximum) 1f else 0.5f
            }
        }
        keypad.setDeleteEnabled(model.input.text.isNotEmpty())
    }

    private companion object {
        const val METHOD_ROW_HEIGHT = 56
        const val METHOD_ROW_GAP = 12

        // Card height below the top bars in the design (bottom at 390dp under 88dp of bars).
        const val CARD_MAX_CONTENT_HEIGHT = 302
        const val CARD_MIN_CONTENT_HEIGHT = 200
        const val KEYPAD_MIN_HEIGHT = 240
    }
}
