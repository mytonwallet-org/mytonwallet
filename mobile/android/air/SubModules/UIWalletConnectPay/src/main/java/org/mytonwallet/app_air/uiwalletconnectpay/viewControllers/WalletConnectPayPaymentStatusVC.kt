package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.view.doOnPreDraw
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.WcPayAmount
import org.mytonwallet.app_air.walletcore.moshi.WcPayMerchant
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import java.math.BigInteger
import androidx.core.view.isVisible

@SuppressLint("ViewConstructor")
class WalletConnectPayPaymentStatusVC(
    context: Context,
    private var merchant: WcPayMerchant,
    processing: Boolean,
    private var paymentAmount: WcPayAmount? = null,
    private var token: MToken? = null,
) : WViewController(context) {
    override val TAG = "WalletConnectPayPaymentStatus"

    override val isBackAllowed: Boolean = false
    override val shouldDisplayTopBar = false

    companion object {
        private const val ANIMATION_SIZE = 160
        private const val SUBTITLE_ICON_SIZE = 18
        private const val AMOUNT_ICON_SIZE = 28
        private const val TRANSITION_SHIFT = 60
        private const val TRANSITION_SCALE = 0.5f
    }

    private var isProcessing: Boolean = processing

    private val waitAnimation = WAnimationView(context)
    private val doneAnimation = WAnimationView(context)

    private val animationContainer = FrameLayout(context).apply {
        id = View.generateViewId()
        clipChildren = false
        clipToPadding = false
        addView(
            waitAnimation,
            FrameLayout.LayoutParams(ANIMATION_SIZE.dp, ANIMATION_SIZE.dp, Gravity.CENTER)
        )
        addView(
            doneAnimation,
            FrameLayout.LayoutParams(ANIMATION_SIZE.dp, ANIMATION_SIZE.dp, Gravity.CENTER)
        )
    }

    private val amountLabel = WBalanceView(context).apply {
        primarySize = 36f
        decimalsSize = 28f
        currencySize = 32f
        typeface = WFont.Medium.typeface
        defaultHeight = 40.dp
    }

    private val amountIconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Round
        defaultPlaceholder = Content.Placeholder.Color(WColor.SecondaryBackground)
        chainSize = 10.dp
    }

    private val amountRow = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        clipChildren = false
        addView(amountLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(
            amountIconView,
            LinearLayout.LayoutParams(AMOUNT_ICON_SIZE.dp, AMOUNT_ICON_SIZE.dp).apply {
                marginStart = 8.dp
                gravity = Gravity.CENTER_VERTICAL
            }
        )
    }

    private val amountContainer = AutoScaleContainerView(amountRow).apply {
        id = View.generateViewId()
        clipChildren = false
        clipToPadding = false
        minPadding = 16.dp
    }

    private val subtitlePrefixLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        text = LocaleController.getString("Send to")
    }

    private val subtitleIconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(4f.dp)
        defaultPlaceholder = Content.Placeholder.Color(WColor.SecondaryBackground)
        chainSize = 0
        set(Content.ofUrl(merchant.iconUrl ?: ""))
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        text = merchant.name
    }

    private val subtitleRow = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        clipChildren = false
        addView(
            subtitlePrefixLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginEnd = 4.dp }
        )
        addView(
            subtitleIconView,
            LinearLayout.LayoutParams(SUBTITLE_ICON_SIZE.dp, SUBTITLE_ICON_SIZE.dp).apply {
                marginEnd = 4.dp
            }
        )
        addView(subtitleLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString(if (isProcessing) "Processing Payment" else "Paid!")
        subtitle =
            if (isProcessing) LocaleController.getString("It may take a few seconds") else null
        setupNavBar(true)
        navigationBar?.addCloseButton()
        navigationBar?.setTitleGravity(Gravity.CENTER)
        navigationBar?.titleLabel?.setStyle(20f, WFont.Medium)
        navigationBar?.subtitleLabel?.apply {
            setStyle(12f, WFont.Medium)
            (layoutParams as? LinearLayout.LayoutParams)?.let {
                it.topMargin = 2.dp
                layoutParams = it
            }
        }
        navigationBar?.translationY = 6f.dp

        view.clipChildren = false
        view.clipToPadding = false
        view.addView(animationContainer, LayoutParams(ANIMATION_SIZE.dp, ANIMATION_SIZE.dp))
        view.addView(amountContainer, LayoutParams(0, WRAP_CONTENT))
        view.addView(subtitleRow, LayoutParams(0, WRAP_CONTENT))

        applyConstraints()

        val active = if (isProcessing) waitAnimation else doneAnimation
        val inactive = if (isProcessing) doneAnimation else waitAnimation
        inactive.visibility = View.GONE
        active.play(animationFor(isProcessing), repeat = true, onStart = null)

        renderState()
        updateTheme()

        view.doOnPreDraw {
            updateAmountMaxWidth()
            applyHeight()
        }
    }

    private fun updateAmountMaxWidth() {
        val contentWidth = view.width - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp
        if (contentWidth <= 0) return
        if (amountContainer.maxAllowedWidth != contentWidth) {
            amountContainer.maxAllowedWidth = contentWidth
            amountContainer.updateScale()
        }
    }

    private fun applyConstraints() {
        view.setConstraints {
            toTopPx(animationContainer, topInset + WNavigationBar.DEFAULT_HEIGHT.dp + 24.dp - 50.dp)
            toCenterX(animationContainer)

            topToBottom(amountContainer, animationContainer, 26f)
            toCenterX(amountContainer, ViewConstants.HORIZONTAL_PADDINGS.toFloat())

            val subtitleAnchor =
                if (amountContainer.isVisible) amountContainer else animationContainer
            topToBottom(subtitleRow, subtitleAnchor, if (amountContainer.isVisible) 10f else 30f)
            toCenterX(subtitleRow, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toBottomPx(subtitleRow, bottomInset)
            setVerticalBias(subtitleRow.id, 0f)
        }
    }

    private val topInset: Int
        get() = (navigationController?.getSystemBars()?.top ?: 0)

    private val bottomInset: Int
        get() = 40.dp + (navigationController?.getSystemBars()?.bottom ?: 0)

    private fun renderState() {
        bindAmount()
        applyConstraints()
    }

    private fun bindAmount() {
        val amount = paymentAmount
        val config = amount?.let { payAmountConfig(it) }
        if (config != null) {
            amountLabel.animateText(config)
            val matchedToken = token?.takeIf {
                amount.fiatCurrency == null &&
                    it.symbol.equals(amount.display.assetSymbol, ignoreCase = true)
            }
            val iconContent = matchedToken?.let { Content.of(it, showChain = true) }
                ?: amount.display.iconUrl?.let { Content.ofUrl(it) }
            if (iconContent != null) {
                amountIconView.set(iconContent)
                amountIconView.visibility = View.VISIBLE
            } else {
                amountIconView.visibility = View.GONE
            }
            amountContainer.visibility = View.VISIBLE
        } else {
            amountContainer.visibility = View.GONE
        }
    }

    private fun animationFor(processing: Boolean) =
        if (processing) R.raw.animation_wait else R.raw.animation_thumb

    private fun transitionToDone() {
        if (!isProcessing) return
        isProcessing = false

        doneAnimation.play(animationFor(false), repeat = true, onStart = null)

        if (!WGlobalStorage.getAreAnimationsActive()) {
            waitAnimation.visibility = View.GONE
            doneAnimation.resetTransition()
            doneAnimation.visibility = View.VISIBLE
            return
        }

        val shift = TRANSITION_SHIFT.dp.toFloat()

        waitAnimation.animate()
            .translationY(-shift)
            .scaleX(TRANSITION_SCALE)
            .scaleY(TRANSITION_SCALE)
            .alpha(0f)
            .setDuration(AnimationConstants.SLOW_ANIMATION)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .withEndAction {
                waitAnimation.visibility = View.GONE
                waitAnimation.resetTransition()
            }

        doneAnimation.apply {
            visibility = View.VISIBLE
            translationY = shift + (1 - TRANSITION_SCALE) * ANIMATION_SIZE.dp / 2f
            scaleX = TRANSITION_SCALE
            scaleY = TRANSITION_SCALE
            alpha = 0f
        }
        doneAnimation.animate()
            .translationY(0f)
            .scaleX(1f)
            .scaleY(1f)
            .alpha(1f)
            .setDuration(AnimationConstants.SLOW_ANIMATION)
            .setInterpolator(AccelerateDecelerateInterpolator())
    }

    private fun WAnimationView.resetTransition() {
        translationY = 0f
        scaleX = 1f
        scaleY = 1f
        alpha = 1f
    }

    fun update(complete: ApiUpdate.ApiUpdateWalletConnectPayPaymentComplete) {
        merchant = complete.merchant
        complete.paymentAmount?.let { paymentAmount = it }
        subtitleLabel.text = complete.merchant.name
        subtitleIconView.set(Content.ofUrl(complete.merchant.iconUrl ?: ""))
        setNavTitle(LocaleController.getString("Paid!"))
        subtitle = null
        navigationBar?.setSubtitle(null, animated = true)
        transitionToDone()
        renderState()

        applyHeight()
    }

    private fun measureContentHeight(): Int {
        val width = maxOf(
            view.width,
            navigationController?.width ?: 0,
            context.resources.displayMetrics.widthPixels
        )
        view.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val total = view.measuredHeight
        val windowHeight = window?.windowView?.height?.takeIf { it > 0 } ?: return total
        return minOf(total, windowHeight)
    }

    private fun applyHeight() {
        val nav = navigationController ?: return
        if (!nav.isBottomSheet) return
        val target = measureContentHeight().takeIf { it > 0 } ?: return
        nav.layoutParams?.height = target
        nav.onBottomSheetHeightChanged()
    }

    override val isExpandable = false
    override fun getModalHalfExpandedHeight(): Int {
        return measureContentHeight()
    }

    private fun payAmountConfig(amount: WcPayAmount): WBalanceView.AnimateConfig? {
        val value = runCatching { BigInteger(amount.value) }.getOrNull() ?: return null
        return WBalanceView.AnimateConfig(
            amount = value,
            decimals = amount.display.decimals,
            currency = amount.display.assetSymbol,
            animated = false,
            setInstantly = true,
            forceCurrencyToRight = true
        )
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        amountLabel.currencyColor = WColor.SecondaryText.color
        amountLabel.updateColors(
            primaryColor = WColor.PrimaryText.color,
            secondaryColor = WColor.PrimaryText.color,
            drawGradient = false,
        )
        subtitlePrefixLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        applyConstraints()
    }

    override fun onDestroy() {
        super.onDestroy()
        waitAnimation.animate().cancel()
        doneAnimation.animate().cancel()
    }
}
