package org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Matrix
import android.graphics.drawable.GradientDrawable
import android.text.Spannable
import android.text.SpannableString
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.view.isVisible
import androidx.core.widget.NestedScrollView
import androidx.transition.ChangeBounds
import androidx.transition.Fade
import androidx.transition.TransitionManager
import androidx.transition.TransitionSet
import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WActivityImageView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.setOnMenuClickListener
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.STALE_ALPHA
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesAmountModel
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapHintView
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.views.TokenTradeAmountField
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.views.TokenTradeKeypadView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.stores.TokenStore

/** Amount card, payment row and keypad of the edit screen, laid out like the token trade screen. */
@SuppressLint("ViewConstructor")
class FuturesEditPositionView(
    context: Context,
    private val model: FuturesAmountModel,
    private val onLeverageTap: () -> Unit = {},
    private val onFundsHintAction: (tokenSlug: String) -> Unit = {},
    private val onFundingSelected: () -> Unit = {},
    private val onChange: () -> Unit,
    private val onReview: () -> Unit
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
        addView(conversionLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, 1f))
        addView(
            conversionIcon,
            LinearLayout.LayoutParams(12.dp, 16.dp).apply { marginStart = 4.dp }
        )
        setOnClickListener {
            model.toggleUnit()
            onChange()
        }
    }
    val amountField = TokenTradeAmountField(context).apply {
        if (model.isEditing) {
            onReset = {
                model.resetToCurrent()
                onChange()
            }
        }
    }
    private val currentLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        setSingleLine()
        setOnClickListener {
            model.resetToCurrent()
            onChange()
        }
    }

    /** Estimated values faded out until their estimate arrives. */
    private val fadedOutLabels = mutableSetOf<WLabel>()
    private val isEditing = model.isEditing
    private val liquidationLabel = WLabel(context).apply {
        setStyle(16f)
        setSingleLine()
    }
    private val leverageArrows = context.getDrawableCompat(
        org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
    )?.mutate()
    private val leverageLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        setSingleLine()
        val verticalPadding = 4.5f.dp.roundToInt()
        setPadding(12.dp, verticalPadding, 10.dp, verticalPadding)
        compoundDrawablePadding = 4.dp
        setCompoundDrawablesRelativeWithIntrinsicBounds(null, null, leverageArrows, null)
        setOnClickListener { onLeverageTap() }
    }
    private val positionSizeLabel = WLabel(context).apply {
        setStyle(16f)
        setSingleLine()
        gravity = Gravity.END
    }
    private val infoRow = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        if (isEditing) {
            addView(
                liquidationLabel,
                LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    marginStart = 8.dp
                }
            )
        } else {
            addView(leverageLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        addView(View(context), LinearLayout.LayoutParams(0, 0, 1f))
        addView(positionSizeLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    private data class Notice(
        val title: String,
        val message: String,
        val actionTitle: String,
        val isFunding: Boolean
    )

    private var shownNotice: Notice? = null
    private val fundsHintView = SwapHintView(context, topPadding = 8, messageTopMargin = 1) {
        model.fundsHint?.let { onFundsHintAction(it.tokenSlug) }
    }.apply {
        isVisible = false
    }

    private val paymentIcon = WActivityImageView(context, 28.dp).apply { chainSize = 12.dp }
    private val paymentTitle = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }
    private val paymentAmount = WLabel(context).apply {
        setStyle(17f)
        setSingleLine()
    }
    private val paymentSymbol = WLabel(context).apply {
        setStyle(17f)
        setSingleLine()
        compoundDrawablePadding = 4.dp
    }
    private val paymentArrows = context.getDrawableCompat(
        org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
    )?.mutate()
    private val paymentRow = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPaddingRelative(14.dp, 0, 20.dp, 0)
        setOnMenuClickListener { presentFundingMenu() }
        addView(paymentIcon, LinearLayout.LayoutParams(30.dp, 30.dp))
        addView(
            paymentTitle,
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { marginStart = 10.dp }
        )
        addView(
            paymentAmount,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = 4.dp }
        )
        addView(
            paymentSymbol,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = 4.dp }
        )
    }

    private val bottomPanel = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val controlsContainer = FrameLayout(context)
    private val changeRow = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
    private val changeButtons = model.quickChanges.map { percent ->
        WLabel(context).apply {
            setStyle(17f, WFont.Medium)
            gravity = Gravity.CENTER
            text = if (model.areQuickChangesRelative) {
                "${if (percent > 0) "+" else "−"}${abs(percent)}%"
            } else {
                "$percent%"
            }
            setOnClickListener {
                model.applyQuickChange(percent)
                onChange()
            }
        }
    }
    val reviewButton = WButton(context).apply {
        buttonHeight = 52.dp
        text = LocaleController.getString("Review")
        setOnClickListener { onReview() }
    }
    val keypad = TokenTradeKeypadView(
        context,
        onInsert = { amountField.insert(it) },
        onDelete = { amountField.deleteBackward() }
    )

    init {
        id = generateViewId()
        changeButtons.forEachIndexed { index, button ->
            changeRow.addView(
                button,
                LinearLayout.LayoutParams(0, MATCH_PARENT, 1f).apply {
                    if (index > 0) marginStart = 10.dp
                }
            )
        }
        controlsContainer.addView(changeRow, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        controlsContainer.addView(reviewButton, LayoutParams(MATCH_PARENT, CONTROLS_HEIGHT.dp))
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
        amountCard.addView(
            currentLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                setMargins(24.dp, CURRENT_TOP_MARGIN.dp, 24.dp, 0)
            }
        )
        amountCard.addView(View(context), LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        amountCard.addView(
            infoRow,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                setMargins(16.dp, 0, 24.dp, 22.dp)
            }
        )
        amountCard.addView(
            fundsHintView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                setMargins(16.dp, 0, 16.dp, 12.dp)
            }
        )
        content.addView(amountCard, LinearLayout.LayoutParams(MATCH_PARENT, 300.dp))
        content.addView(
            paymentRow,
            LinearLayout.LayoutParams(MATCH_PARENT, PAYMENT_ROW_HEIGHT.dp).apply {
                setMargins(10.dp, PAYMENT_ROW_GAP.dp, 10.dp, PAYMENT_ROW_GAP.dp)
            }
        )
        scrollView.addView(content, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(scrollView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(bottomPanel, LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM))

        amountField.onChange = {
            model.userEditedInput(it)
            onChange()
        }
        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = MeasureSpec.getSize(heightMeasureSpec)
        val contentWidth = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        val panelBottomPadding = max(16.dp, bottomInset)
        val footerHeight = cardFooterHeight(contentWidth)
        val currentHeight = if (currentLabel.visibility != GONE) {
            currentLabel.heightAt(contentWidth - 48.dp) + CURRENT_TOP_MARGIN.dp
        } else {
            0
        }
        val extraHeight = currentHeight + max(0, footerHeight - DESIGN_FOOTER_HEIGHT.dp)
        val minCardHeight = topInset + CARD_MIN_CONTENT_HEIGHT.dp + extraHeight
        // Tighten the gaps when the minimum card and keypad do not fit.
        val isTight = height - panelBottomPadding - KEYPAD_MIN_HEIGHT.dp -
            panelChromeHeight(isTight = false) - paymentRowSpace(isTight = false) <
            minCardHeight
        val cardTopPadding = if (isTight) 4.dp else 8.dp
        val compactCardHeight = topInset + max(
            CARD_COMPACT_CONTENT_HEIGHT.dp + extraHeight,
            cardTopPadding + 26.dp + 1.dp + COMPACT_AMOUNT_FIELD_HEIGHT.dp + currentHeight +
                footerHeight + footerBottomMargin(isTight, isCompact = true)
        )
        val panelChromeHeight = panelChromeHeight(isTight) + panelBottomPadding
        val paymentRowGap = paymentRowGap(isTight).dp
        val cardAndKeypadHeight = height - panelChromeHeight - paymentRowSpace(isTight)
        val liftOverFooter = if (isEditing) EDIT_FOOTER_LIFT.dp else 0
        val preferredKeypadHeight = TokenTradeKeypadView.preferredHeight

        // The keypad yields to a full-size amount, then to the minimum card, then to the compact one.
        fun layoutKeypad(cardExtraHeight: Int): KeypadLayout {
            val maxCardHeight = topInset + CARD_MAX_CONTENT_HEIGHT.dp + cardExtraHeight
            val layoutMinCardHeight = topInset + CARD_MIN_CONTENT_HEIGHT.dp + cardExtraHeight
            val fullCardHeight = topInset + CARD_FULL_CONTENT_HEIGHT.dp + cardExtraHeight
            val footerLift = if (cardAndKeypadHeight - KEYPAD_MIN_HEIGHT.dp >=
                fullCardHeight - liftOverFooter
            ) {
                liftOverFooter
            } else {
                0
            }
            val keypadHeight = when {
                cardAndKeypadHeight - preferredKeypadHeight > maxCardHeight - footerLift ->
                    cardAndKeypadHeight - maxCardHeight + footerLift

                footerLift > 0 ->
                    min(preferredKeypadHeight, cardAndKeypadHeight - fullCardHeight + footerLift)

                cardAndKeypadHeight - KEYPAD_MIN_HEIGHT.dp >= fullCardHeight ->
                    min(preferredKeypadHeight, cardAndKeypadHeight - fullCardHeight)

                cardAndKeypadHeight - KEYPAD_MIN_HEIGHT.dp >= compactCardHeight -> min(
                    preferredKeypadHeight,
                    max(KEYPAD_MIN_HEIGHT.dp, cardAndKeypadHeight - layoutMinCardHeight)
                )

                else -> max(KEYPAD_COMPACT_MIN_HEIGHT.dp, cardAndKeypadHeight - compactCardHeight)
            }
            return KeypadLayout(keypadHeight, footerLift, cardExtraHeight)
        }

        // A taller footer takes the card's free space first, so typing doesn't resize the keypad
        val designLayout = layoutKeypad(currentHeight)
        val (keypadHeight, footerLift, layoutExtraHeight) =
            if (cardAndKeypadHeight - designLayout.keypadHeight + designLayout.footerLift >=
                minCardHeight
            ) {
                designLayout
            } else {
                layoutKeypad(extraHeight)
            }
        (keypad.layoutParams as LinearLayout.LayoutParams).height = keypadHeight
        (controlsContainer.layoutParams as LinearLayout.LayoutParams).topMargin =
            panelTopMargin(isTight).dp
        bottomPanel.setPadding(0, 0, 0, panelBottomPadding)
        (paymentRow.layoutParams as LinearLayout.LayoutParams).apply {
            topMargin = paymentRowGap
            bottomMargin = paymentRowGap
        }
        val controlsHeight = panelChromeHeight + keypadHeight
        val cardHeight = max(compactCardHeight, cardAndKeypadHeight - keypadHeight)
        // Items are placed as in the card before the footer lift.
        val layoutCardHeight = cardHeight + footerLift
        val isCompact =
            layoutCardHeight - topInset - layoutExtraHeight < CARD_FULL_CONTENT_HEIGHT.dp
        (amountCard.layoutParams as LinearLayout.LayoutParams).height = cardHeight
        val amountFieldHeight = if (isCompact) COMPACT_AMOUNT_FIELD_HEIGHT.dp else 86.dp
        (cardFooter.layoutParams as LinearLayout.LayoutParams).bottomMargin =
            footerBottomMargin(isTight, isCompact)
        if (isShowingQuoteError) {
            (infoRow.layoutParams as LinearLayout.LayoutParams).bottomMargin = QUOTE_ERROR_GAP.dp
        }
        val freeHeight = max(
            0,
            layoutCardHeight - topInset - cardTopPadding - 26.dp - 1.dp - amountFieldHeight -
                extraHeight
        )
        val centeredTopGap = ((freeHeight - 78.dp) / 2).takeIf { it >= 48.dp }
            ?: max(0, (freeHeight - 16.dp) / 2)
        val topGap = max(0, centeredTopGap - TOP_GAP_REDUCTION.dp)
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

    private data class KeypadLayout(
        val keypadHeight: Int,
        val footerLift: Int,
        val extraHeight: Int
    )

    private val cardFooter: View
        get() = if (fundsHintView.isVisible) fundsHintView else infoRow

    private val isShowingQuoteError: Boolean
        get() = fundsHintView.isVisible && infoRow.isVisible

    private val noticeInset: Int
        get() = if (isShowingQuoteError) QUOTE_ERROR_INSET.dp else FUNDS_HINT_INSET.dp

    private fun cardFooterHeight(contentWidth: Int): Int {
        val infoHeight = if (infoRow.isVisible) infoRow.heightAt(contentWidth - 40.dp) else 0
        if (!fundsHintView.isVisible) return infoHeight
        val noticeHeight = fundsHintView.heightAt(contentWidth - 2 * noticeInset)
        if (!isShowingQuoteError) return noticeHeight
        return infoHeight + QUOTE_ERROR_GAP.dp + noticeHeight
    }

    private fun footerBottomMargin(isTight: Boolean, isCompact: Boolean) = when {
        isTight -> 8.dp
        fundsHintView.isVisible -> 16.dp
        isCompact -> 12.dp
        else -> 16.dp
    } + if (isEditing && !fundsHintView.isVisible) 6.dp else 0

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
        paymentRow.setBackgroundColor(WColor.Background.color, (PAYMENT_ROW_HEIGHT / 2f).dp)
        conversionPill.background = GradientDrawable().apply {
            cornerRadius = 13f.dp
            setColor(WColor.SecondaryText.color.colorWithAlpha(31))
        }
        conversionLabel.setTextColor(WColor.SecondaryText.color)
        conversionIcon.setColorFilter(WColor.SecondaryText.color)
        liquidationLabel.setTextColor(WColor.SecondaryText.color)
        leverageLabel.setTextColor(WColor.Tint.color)
        leverageLabel.setBackgroundColor(WColor.Tint.color.colorWithAlpha(26), 18f.dp)
        leverageArrows?.setTint(WColor.Tint.color)
        positionSizeLabel.setTextColor(WColor.SecondaryText.color)
        paymentAmount.setTextColor(WColor.PrimaryText.color)
        paymentSymbol.setTextColor(WColor.SecondaryText.color)
        paymentArrows?.setTint(WColor.SecondaryText.color)
        paymentIcon.updateTheme()
        changeButtons.forEach {
            it.setTextColor(WColor.PrimaryText.color)
            it.background = WRippleDrawable.create(26f.dp).apply {
                backgroundColor = WColor.SecondaryBackground.color
                rippleColor = WColor.BackgroundRipple.color
            }
        }
        render()
    }

    fun render() {
        conversionLabel.text = model.conversionText
        conversionPill.isEnabled = model.markPrice > 0
        amountField.configure(
            input = model.input,
            decimals = model.inputDecimals,
            prefix = if (model.isCoinAmount) "" else "$",
            suffix = if (model.isCoinAmount) " ${model.symbol}" else "",
            hasAmount = model.input.text.isNotEmpty(),
            isResettable = model.isChanged
        )

        val currentMargin = model.currentMarginText
        // Editing keeps the link's space, so the layout does not move when the amount changes.
        currentLabel.visibility = when {
            currentMargin != null -> VISIBLE
            isEditing -> INVISIBLE
            else -> GONE
        }
        currentLabel.text = currentMargin?.let(::currentText)

        val staleAlpha = if (model.isEstimating) STALE_ALPHA else 1f
        if (isEditing) {
            liquidationLabel.showIfKnown(model.liquidationPrice != null)
        } else {
            liquidationLabel.visibility = GONE
        }
        liquidationLabel.setEstimatedText(
            "${LocaleController.getString("Liquidation")} " +
                (model.liquidationPrice?.toPriceString() ?: EMPTY_VALUE),
            isLoading = model.isEstimating
        )
        leverageLabel.text = "${LocaleController.getString("Leverage")} ${model.leverage}x"
        leverageLabel.isEnabled = model.canSelectLeverage
        leverageLabel.alpha = if (model.canSelectLeverage) 1f else DISABLED_ALPHA
        val positionValue = model.positionValue
        positionSizeLabel.showIfKnown(positionValue != null && positionValue > 0)
        positionSizeLabel.setEstimatedText(
            "${LocaleController.getString("Position Size")} " +
                (positionValue?.toUsdString() ?: EMPTY_VALUE),
            isLoading = model.isEstimating
        )

        val paymentToken = TokenStore.getToken(model.paymentSlug ?: PERPS_PAYMENT_TOKEN_SLUG)
        // Reductions pay out to the wallet
        val isPaidFromBalance = model.isFundedFromBalance && model.canSelectFunding
        paymentIcon.set(
            paymentToken?.let { Content.of(it, showChain = true) }?.let {
                if (isPaidFromBalance) it.copy(subImageRes = MBlockchain.hyperliquid.icon) else it
            }
        )
        paymentRow.isClickable = model.canSelectFunding
        paymentSymbol.setCompoundDrawablesRelativeWithIntrinsicBounds(
            null,
            null,
            paymentArrows.takeIf { model.canSelectFunding },
            null
        )
        paymentTitle.text = model.paymentTitle
        paymentTitle.setTextColor(
            if (model.isPaymentTitleKnown) WColor.PrimaryText.color else WColor.SecondaryText.color
        )
        val amount = model.paymentAmount.takeIf { model.isChanged }
        paymentAmount.text = amount?.toString(
            PAYMENT_DISPLAY_DECIMALS,
            "",
            PAYMENT_DISPLAY_DECIMALS,
            smartDecimals = true
        )?.let { if (model.isPaymentEstimated) "≈ $it" else it }
        paymentAmount.isVisible = amount != null
        paymentAmount.alpha = staleAlpha
        paymentSymbol.text = model.paymentSymbol

        val fundsHint = model.fundsHint
        // Kept while the next quote loads
        val notice = fundsHint?.let { Notice(it.title, it.message, it.actionTitle, true) }
            ?: model.quoteError?.let { Notice("", it, "", false) }
            ?: shownNotice?.takeIf { model.isEstimating }
        if (notice != shownNotice) {
            if (isLaidOut && WGlobalStorage.getAreAnimationsActive()) {
                val transition = TransitionSet()
                    .addTransition(ChangeBounds())
                    .addTransition(Fade())
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .setInterpolator(DecelerateInterpolator())
                // Another kind fades in place, not sliding over the info row
                if (notice != null && shownNotice != null &&
                    notice.isFunding != shownNotice?.isFunding
                ) {
                    transition.excludeTarget(fundsHintView, true)
                    transition.excludeChildren(fundsHintView, true)
                    fundsHintView.alpha = 0f
                    fundsHintView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                }
                TransitionManager.beginDelayedTransition(this, transition)
            }
            shownNotice = notice
        }
        notice?.let { fundsHintView.configure(it.title, it.message, it.actionTitle) }
        fundsHintView.isVisible = notice != null
        infoRow.isVisible = notice?.isFunding != true
        (fundsHintView.layoutParams as LinearLayout.LayoutParams).apply {
            marginStart = noticeInset
            marginEnd = noticeInset
        }

        reviewButton.isVisible = model.isChanged || fundsHint != null
        changeRow.isVisible = !reviewButton.isVisible
        changeButtons.forEach {
            it.isEnabled = model.areQuickChangesEnabled
            it.alpha = if (model.areQuickChangesEnabled) 1f else DISABLED_ALPHA
        }
        if (fundsHint != null) {
            reviewButton.isLoading = false
            reviewButton.isEnabled = false
            reviewButton.text = fundsHint.buttonTitle
        } else if (model.isChanged) {
            val isLoading = model.isEstimating || model.isPreparingReview
            reviewButton.isLoading = isLoading
            if (!isLoading) {
                reviewButton.isEnabled = model.canReview
                reviewButton.text =
                    model.reviewBlocker ?: LocaleController.getString("Review")
            }
        }
        keypad.setDeleteEnabled(model.input.text.isNotEmpty())
    }

    private fun presentFundingMenu() {
        if (!model.canSelectFunding) return
        fun buildItem(isFromBalance: Boolean, chain: MBlockchain, balance: BigDecimal?) =
            WMenuPopup.Item(
                WMenuPopup.Item.Config.SelectableItem(
                    title = chain.displayName,
                    subtitle = balance?.let {
                        it.setScale(2, RoundingMode.DOWN).toDouble().toString(
                            2,
                            model.paymentSymbol,
                            2,
                            smartDecimals = true,
                            forceCurrencyToRight = true
                        )
                    },
                    isSelected = model.isFundedFromBalance == isFromBalance
                )
            ) {
                if (model.isFundedFromBalance != isFromBalance) {
                    model.selectFunding(isFromBalance)
                    onFundingSelected()
                }
            }
        WMenuPopup.present(
            paymentRow,
            listOf(
                buildItem(false, MBlockchain.arbitrum, model.walletBalance),
                buildItem(true, MBlockchain.hyperliquid, model.hyperliquidBalance)
            ),
            positioning = WMenuPopup.Positioning.ALIGNED,
            isAlignedToEnd = true,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout.fromView(
                paymentRow,
                roundRadius = (PAYMENT_ROW_HEIGHT / 2f).dp
            ),
            backdropStyle = WMenuPopup.BackdropStyle.Transparent
        )
    }

    /** Holds its place without a value; while an estimate loads, it keeps fading the old one. */
    private fun WLabel.showIfKnown(hasValue: Boolean) {
        if (!model.isEstimating) visibility = if (hasValue) VISIBLE else INVISIBLE
    }

    /** Fades the shown value out while an estimate loads and fades the new one in once it arrives. */
    private fun WLabel.setEstimatedText(text: CharSequence, isLoading: Boolean) {
        // A hidden label fades in once shown.
        if (!isVisible) {
            animate().cancel()
            alpha = 0f
            fadedOutLabels.add(this)
            this.text = text
            return
        }
        if (isLoading) {
            if (fadedOutLabels.add(this)) fadeOut(AnimationConstants.VERY_QUICK_ANIMATION)
            return
        }
        if (fadedOutLabels.remove(this)) {
            animate().cancel()
            this.text = text
            fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        } else {
            this.text = text
        }
    }

    private fun currentText(value: String): CharSequence {
        val text = "${LocaleController.getString("Current:")} $value"
        val start = text.indexOf(value).takeIf { it >= 0 } ?: return text
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(WColor.SecondaryText.color),
                0,
                start,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                ForegroundColorSpan(WColor.Tint.color),
                start,
                start + value.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    companion object {
        private const val DISABLED_ALPHA = 0.5f
        private const val PAYMENT_ROW_HEIGHT = 56
        private const val PAYMENT_ROW_GAP = 12
        private const val PAYMENT_DISPLAY_DECIMALS = 4
        private const val CURRENT_TOP_MARGIN = 12

        private const val COMPACT_AMOUNT_FIELD_HEIGHT = 64

        private const val TOP_GAP_REDUCTION = 21
        private const val FUNDS_HINT_INSET = 16
        private const val QUOTE_ERROR_INSET = 24
        private const val QUOTE_ERROR_GAP = 8
        private const val EDIT_FOOTER_LIFT = 26

        // The token trade card's fee line.
        private const val DESIGN_FOOTER_HEIGHT = 20

        private const val CARD_MAX_CONTENT_HEIGHT = 302
        private const val CARD_MIN_CONTENT_HEIGHT = 200

        private const val CARD_FULL_CONTENT_HEIGHT = 260
        private const val CARD_COMPACT_CONTENT_HEIGHT = 124
        private const val KEYPAD_MIN_HEIGHT = 240
        private const val KEYPAD_COMPACT_MIN_HEIGHT = 186
        private const val CONTROLS_HEIGHT = 52
        private const val CONTROLS_BOTTOM_MARGIN = 12
        private const val EMPTY_VALUE = "—"

        private fun paymentRowGap(isTight: Boolean) = if (isTight) 8 else PAYMENT_ROW_GAP

        private fun paymentRowSpace(isTight: Boolean) =
            PAYMENT_ROW_HEIGHT.dp + 2 * paymentRowGap(isTight).dp

        private fun panelTopMargin(isTight: Boolean) = if (isTight) 12 else 24

        private fun panelChromeHeight(isTight: Boolean) =
            panelTopMargin(isTight).dp + CONTROLS_HEIGHT.dp + CONTROLS_BOTTOM_MARGIN.dp

        private fun minimumHeight(topInset: Int, bottomInset: Int): Int =
            topInset + CARD_COMPACT_CONTENT_HEIGHT.dp + paymentRowSpace(isTight = true) +
                panelChromeHeight(isTight = true) + max(16.dp, bottomInset) +
                KEYPAD_COMPACT_MIN_HEIGHT.dp

        val centeredWindowMinHeight: Int
            get() = minimumHeight(WNavigationBar.DEFAULT_HEIGHT.dp, 0)
    }
}
