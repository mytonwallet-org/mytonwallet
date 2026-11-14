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
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.widget.NestedScrollView
import androidx.transition.ChangeBounds
import androidx.transition.Fade
import androidx.transition.TransitionManager
import androidx.transition.TransitionSet
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
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
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapHint
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapEstimateDebugSummaryView
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapHintView
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
    private val onContinue: () -> Unit,
    private val onHintAction: (SwapHint) -> Unit
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
        setOnClickListener {
            model.toggleFeeCurrency()
            render()
        }
    }
    private val hintView = SwapHintView(context, topPadding = 8, messageTopMargin = 1) {
        shownHint?.let(onHintAction)
    }.apply {
        isVisible = false
    }
    private var shownHint: SwapHint? = null
    private var shownHintMessage: String? = null

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
    private val estimateDebugSummaryView = SwapEstimateDebugSummaryView(context).apply {
        isGone = true
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
        controlsContainer.addView(
            continueButton,
            LayoutParams(MATCH_PARENT, CONTROLS_HEIGHT.dp)
        )
        bottomPanel.addView(
            controlsContainer,
            LinearLayout.LayoutParams(MATCH_PARENT, CONTROLS_HEIGHT.dp).apply {
                setMargins(24.dp, 24.dp, 24.dp, CONTROLS_BOTTOM_MARGIN.dp)
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
        amountCard.addView(
            hintView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                setMargins(HINT_INSET.dp, 0, HINT_INSET.dp, 16.dp)
            }
        )
        content.addView(amountCard, LinearLayout.LayoutParams(MATCH_PARENT, 300.dp))
        content.addView(
            methodRow,
            LinearLayout.LayoutParams(MATCH_PARENT, METHOD_ROW_HEIGHT.dp).apply {
                setMargins(10.dp, METHOD_ROW_GAP.dp, 10.dp, METHOD_ROW_GAP.dp)
            }
        )
        content.addView(
            estimateDebugSummaryView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                setMargins(10.dp, 0, 10.dp, METHOD_ROW_GAP.dp)
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
        val contentWidth = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        val panelBottomPadding = max(16.dp, bottomInset)
        val footerHeight = cardFooterHeight(contentWidth)
        val extraHeight = max(0, footerHeight - DESIGN_FOOTER_HEIGHT.dp)
        val minCardHeight = topInset + CARD_MIN_CONTENT_HEIGHT.dp + extraHeight
        // Screens too short for the minimum card and keypad tighten the gaps around the controls.
        val isTight = height - panelBottomPadding - KEYPAD_MIN_HEIGHT.dp -
            panelChromeHeight(isTight = false) - methodRowSpace(isTight = false) <
            minCardHeight
        val cardTopPadding = if (isTight) 4.dp else 8.dp
        val compactCardHeight = topInset + max(
            CARD_COMPACT_CONTENT_HEIGHT.dp + extraHeight,
            cardTopPadding + 26.dp + 1.dp + COMPACT_AMOUNT_FIELD_HEIGHT.dp + footerHeight +
                footerBottomMargin(isTight, isCompact = true)
        )
        val panelChromeHeight = panelChromeHeight(isTight) + panelBottomPadding
        val methodRowGap = methodRowGap(isTight).dp
        val cardAndKeypadHeight = height - panelChromeHeight - methodRowSpace(isTight)
        val preferredKeypadHeight = TokenTradeKeypadView.preferredHeight

        // The card stops at its design height; taller screens give the rest to the keypad.
        // Short screens shrink the keypad to its minimum, then bring the card items closer down
        // to the compact card, then shrink the keypad to its compact minimum.
        fun layoutKeypad(cardExtraHeight: Int): Int {
            val maxCardHeight = topInset + CARD_MAX_CONTENT_HEIGHT.dp + cardExtraHeight
            val layoutMinCardHeight = topInset + CARD_MIN_CONTENT_HEIGHT.dp + cardExtraHeight
            return when {
                cardAndKeypadHeight - preferredKeypadHeight > maxCardHeight ->
                    cardAndKeypadHeight - maxCardHeight

                cardAndKeypadHeight - KEYPAD_MIN_HEIGHT.dp >= compactCardHeight -> min(
                    preferredKeypadHeight,
                    max(KEYPAD_MIN_HEIGHT.dp, cardAndKeypadHeight - layoutMinCardHeight)
                )

                else -> max(KEYPAD_COMPACT_MIN_HEIGHT.dp, cardAndKeypadHeight - compactCardHeight)
            }
        }

        // A taller footer takes the card's free space first, so a hint showing up doesn't
        // resize the keypad
        val designKeypadHeight = layoutKeypad(cardExtraHeight = 0)
        val isDesignLayout = cardAndKeypadHeight - designKeypadHeight >= minCardHeight
        val keypadHeight = if (isDesignLayout) designKeypadHeight else layoutKeypad(extraHeight)
        val layoutExtraHeight = if (isDesignLayout) 0 else extraHeight
        (keypad.layoutParams as LinearLayout.LayoutParams).height = keypadHeight
        (controlsContainer.layoutParams as LinearLayout.LayoutParams).topMargin =
            panelTopMargin(isTight).dp
        bottomPanel.setPadding(0, 0, 0, panelBottomPadding)
        (methodRow.layoutParams as LinearLayout.LayoutParams).apply {
            topMargin = methodRowGap
            bottomMargin = methodRowGap
        }
        (estimateDebugSummaryView.layoutParams as LinearLayout.LayoutParams).bottomMargin =
            methodRowGap
        val controlsHeight = panelChromeHeight + keypadHeight
        val cardHeight = max(compactCardHeight, cardAndKeypadHeight - keypadHeight)
        val isCompact = cardHeight - topInset - layoutExtraHeight < CARD_FULL_CONTENT_HEIGHT.dp
        (amountCard.layoutParams as LinearLayout.LayoutParams).height = cardHeight
        val amountFieldHeight =
            if (isCompact) COMPACT_AMOUNT_FIELD_HEIGHT.dp else AMOUNT_FIELD_HEIGHT.dp
        val footerBottomMargin = footerBottomMargin(isTight, isCompact)
        (feeLabel.layoutParams as LinearLayout.LayoutParams).bottomMargin =
            if (hintView.isVisible) FEE_HINT_GAP.dp else footerBottomMargin
        (hintView.layoutParams as LinearLayout.LayoutParams).bottomMargin = footerBottomMargin
        // Space above the pill is 78dp less than below the field; when that leaves less than
        // 48dp above the pill, the gap below is only 16dp larger.
        val freeHeight = max(
            0,
            cardHeight - topInset - cardTopPadding - 26.dp - 1.dp - amountFieldHeight -
                extraHeight
        )
        val topGap = ((freeHeight - 78.dp) / 2).takeIf { it >= 48.dp }
            ?: max(0, (freeHeight - 16.dp) / 2)
        (cardTopSpacer.layoutParams as LinearLayout.LayoutParams).height =
            topInset + cardTopPadding + topGap
        (amountField.layoutParams as LinearLayout.LayoutParams).height = amountFieldHeight
        (scrollView.layoutParams as LayoutParams).bottomMargin = controlsHeight
        // Unchanged measure specs would return cached sizes and skip the params set above
        scrollView.forceLayout()
        content.forceLayout()
        amountCard.forceLayout()
        bottomPanel.forceLayout()
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun cardFooterHeight(contentWidth: Int): Int {
        val feeHeight = feeLabel.heightAt(contentWidth - 48.dp)
        if (!hintView.isVisible) return feeHeight
        return feeHeight + FEE_HINT_GAP.dp + hintView.heightAt(contentWidth - 2 * HINT_INSET.dp)
    }

    private fun footerBottomMargin(isTight: Boolean, isCompact: Boolean) = when {
        isTight -> 8.dp
        hintView.isVisible -> 16.dp
        isCompact -> 12.dp
        else -> 22.dp
    }

    private fun View.heightAt(width: Int): Int {
        measure(
            MeasureSpec.makeMeasureSpec(max(0, width), MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        return measuredHeight
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
        estimateDebugSummaryView.updateTheme()
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
        feeLabel.isClickable = model.canToggleFeeCurrency
        // Kept while the next quote loads
        val message = model.hintMessage
        val hint = model.hint ?: shownHint?.takeIf { model.isLoading && message == null }
        if (hint != shownHint || message != shownHintMessage) {
            if (isLaidOut && WGlobalStorage.getAreAnimationsActive()) {
                val transition = TransitionSet()
                    .addTransition(ChangeBounds())
                    .addTransition(Fade())
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .setInterpolator(DecelerateInterpolator())
                // Another kind fades in place instead of resizing in view
                if (hint != null && shownHint != null && hint::class != shownHint!!::class) {
                    transition.excludeTarget(hintView, true)
                    transition.excludeChildren(hintView, true)
                    hintView.alpha = 0f
                    hintView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                }
                TransitionManager.beginDelayedTransition(this, transition)
            }
            shownHint = hint
            shownHintMessage = message
        }
        when {
            message != null -> hintView.configure("", message, "")
            hint != null -> configureHint(hint)
        }
        hintView.isVisible = hint != null || message != null

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

        val debugSummary = model.estimateDebugSummary
        if (!debugSummary.isNullOrEmpty()) {
            estimateDebugSummaryView.configure(debugSummary)
            estimateDebugSummaryView.isVisible = true
        } else {
            estimateDebugSummaryView.isGone = true
        }

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

    private fun configureHint(hint: SwapHint) {
        if (hint !is SwapHint.Intermediate || model.isBuying) {
            if (hint is SwapHint.Intermediate) {
                hintView.configure(
                    LocaleController.getString("Direct exchange unavailable"),
                    hint.message,
                    hint.actionTitle
                )
            } else {
                hintView.configure(hint)
            }
            return
        }
        val token = hint.token.symbol ?: ""
        hintView.configure(
            LocaleController.getString("Direct exchange unavailable"),
            LocaleController.getStringWithKeyValues(
                "To receive %buy_token%, first receive %token%, then exchange it for %buy_token%.",
                listOf("%buy_token%" to (hint.buyingToken.symbol ?: ""), "%token%" to token)
            ),
            LocaleController.getStringWithKeyValues("Receive %value%", listOf("%value%" to token))
        )
    }

    companion object {
        private const val METHOD_ROW_HEIGHT = 56
        private const val METHOD_ROW_GAP = 12

        // Card height below the top bars in the design (bottom at 390dp under 88dp of bars).
        private const val CARD_MAX_CONTENT_HEIGHT = 302
        private const val CARD_FULL_CONTENT_HEIGHT = 260
        private const val CARD_MIN_CONTENT_HEIGHT = 200
        private const val CARD_COMPACT_CONTENT_HEIGHT = 124
        private const val KEYPAD_MIN_HEIGHT = 240
        private const val KEYPAD_COMPACT_MIN_HEIGHT = 186
        private const val CONTROLS_HEIGHT = 52
        private const val CONTROLS_BOTTOM_MARGIN = 12
        private const val AMOUNT_FIELD_HEIGHT = 86
        private const val COMPACT_AMOUNT_FIELD_HEIGHT = 64

        // The design's one-line fee footer; taller footers grow the card.
        private const val DESIGN_FOOTER_HEIGHT = 20
        private const val FEE_HINT_GAP = 8
        private const val HINT_INSET = 16

        private fun methodRowGap(isTight: Boolean) = if (isTight) 8 else METHOD_ROW_GAP

        // Sums the per-view pixel sizes the layout uses, so content that fits does not overflow
        // by a rounding pixel.
        private fun methodRowSpace(isTight: Boolean) =
            METHOD_ROW_HEIGHT.dp + 2 * methodRowGap(isTight).dp

        private fun panelTopMargin(isTight: Boolean) = if (isTight) 12 else 24

        private fun panelChromeHeight(isTight: Boolean) =
            panelTopMargin(isTight).dp + CONTROLS_HEIGHT.dp + CONTROLS_BOTTOM_MARGIN.dp

        fun minimumHeight(topInset: Int, bottomInset: Int): Int =
            topInset + CARD_COMPACT_CONTENT_HEIGHT.dp + methodRowSpace(isTight = true) +
                panelChromeHeight(isTight = true) + max(16.dp, bottomInset) +
                KEYPAD_COMPACT_MIN_HEIGHT.dp
    }
}
