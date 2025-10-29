package org.mytonwallet.uihome.home.views.header

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WGradientMaskView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView.AnimateConfig
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.home.views.UpdateStatusView
import kotlin.math.abs
import kotlin.math.absoluteValue
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class HomeHeaderView(
    window: WWindow,
    private val updateStatusView: UpdateStatusView,
    private var onModeChange: ((animated: Boolean) -> Unit)?,
    private var onExpandPressed: (() -> Unit)?,
    private var onHeaderPressed: (() -> Unit)?
) : FrameLayout(window), WThemedView, WProtectedView {

    companion object {
        val DEFAULT_MODE = Mode.Expanded
        private val NAV_SIZE_OFFSET = 8.dp
        val navDefaultHeight = WNavigationBar.DEFAULT_HEIGHT.dp - NAV_SIZE_OFFSET
    }

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    // State variables /////////////////////////////////////////////////////////////////////////////
    enum class Mode {
        Collapsed,
        Expanded
    }

    var mode = DEFAULT_MODE

    private var scrollY = 0
    private val expandProgress: Float
        get() {
            return currentExpandProgress.coerceIn(minExpandProgress, maxExpandProgress)
        }
    private var currentExpandProgress = if (DEFAULT_MODE == Mode.Expanded) 1f else 0f

    // If user scrolls down a little bit, we increase this
    private var minExpandProgress = 0f

    // If user scrolls up a little bit, we increase this
    private var maxExpandProgress = currentExpandProgress

    private var activeValueAnimator: ValueAnimator? = null

    var expandedContentHeight: Float = 0f
    var diffPx: Float = 0f
    var isExpandAllowed = true
        set(value) {
            field = if (mode == Mode.Expanded)
                true
            else
                value
        }
    private val skeletonView = SkeletonView(context, isVertical = false, forcedLight = true)
    var isShowingSkeletons: Boolean = false
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Views ///////////////////////////////////////////////////////////////////////////////////////
    private val cardView = WalletCardView(window)
    private val balanceView = WBalanceView(context).apply {
        typeface = WFont.NunitoExtraBold.typeface
        clipChildren = false
        clipToPadding = false
    }
    private val balanceViewMaskWrapper = WGradientMaskView(balanceView)
    private val balanceLabel = WSensitiveDataContainer(
        AutoScaleContainerView(balanceViewMaskWrapper).apply {
            clipChildren = false
            clipToPadding = false
            maxAllowedWidth = window.windowView.width - 34.dp
            minPadding = 11.dp
            additionalRightPadding = 22f.dp.roundToInt()
        },
        WSensitiveDataContainer.MaskConfig(
            16,
            4,
            Gravity.CENTER,
            protectContentLayoutSize = false
        )
    ).apply {
        clipChildren = false
        clipToPadding = false
    }

    private val walletNameLabel = WLabel(context).apply {
        setStyle(16f, WFont.Regular)
        setSingleLine()
        isHorizontalFadingEdgeEnabled = true
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isSelected = true
    }
    private val balanceSkeletonView = View(context).apply {
        visibility = GONE
    }
    private val walletNameSkeletonView = View(context).apply {
        visibility = GONE
    }

    /*private val separatorView = WBaseView(context).apply {
        alpha = 0f
    }*/
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Helpers /////////////////////////////////////////////////////////////////////////////////////
    val collapsedMinHeight =
        (window.systemBars?.top ?: 0) + navDefaultHeight
    val collapsedHeight = 101.dp + NAV_SIZE_OFFSET
    private val smallCardWidth = 34.dp
    private val topInset = window.systemBars?.top ?: 0
    private val cardRatio = 208 / 358f

    private fun calcMaxExpandProgress(): Float {
        val realPossibleWidth = max(0, collapsedHeight - scrollY) / cardRatio - 3.dp
        return max(
            minExpandProgress,
            ((realPossibleWidth) / (width))
                .coerceIn(0f, 1f)
        )
    }

    // Setup views /////////////////////////////////////////////////////////////////////////////////
    private var configured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (configured)
            return
        configured = true
        setupViews()
    }

    private fun setupViews() {
        addView(balanceLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })
        addView(walletNameLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })
        addView(balanceSkeletonView, LayoutParams(134.dp, 56.dp).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })
        addView(walletNameSkeletonView, LayoutParams(80.dp, 28.dp).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })
        addView(cardView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        })
        addView(skeletonView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        render()
        updateTheme()

        cardView.setOnClickListener {
            onExpandPressed?.invoke()
        }
        cardView.isClickable = DEFAULT_MODE == Mode.Collapsed
        setOnClickListener {
            onHeaderPressed?.invoke()
        }
        isClickable = false
        balanceView.onTotalWidthChanged = { width ->
            balanceViewMaskWrapper.setupLayout(
                width = width,
                height = 56.dp,
                parentWidth = this@HomeHeaderView.width
            )
        }
    }

    override fun updateTheme() {
        balanceViewMaskWrapper.setupColors(
            intArrayOf(
                WColor.SecondaryBackground.color,
                WColor.SecondaryText.color,
                WColor.SecondaryBackground.color
            )
        )
        walletNameLabel.setTextColor(WColor.SubtitleText.color)
        cardView.balanceChangeLabel.contentView.setBackgroundColor(
            Color.WHITE.colorWithAlpha(25),
            14f.dp
        )

        if (isShowingSkeletons)
            updateSkeletonViewColors()
    }

    override fun updateProtectedView() {}

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w - oldw > 2) {
            balanceViewMaskWrapper.setupLayout(parentWidth = w)
            cardView.balanceViewMaskWrapper.setupLayout(parentWidth = w)
            expandedContentHeight = NAV_SIZE_OFFSET + (w - 32.dp) * cardRatio + 8.dp
            diffPx = expandedContentHeight - collapsedHeight
            post {
                scrollY = -diffPx.toInt()
                expand(false, null)
            }
        }
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Events //////////////////////////////////////////////////////////////////////////////////////
    fun updateScroll(scrollY: Int, velocity: Float? = null, isGoingBack: Boolean = false) {
        if (width == 0)
            return

        // Ignore if scrolling down in full collapsed mode
        val prevScrollY = this.scrollY
        this.scrollY = scrollY
        if (maxExpandProgress == 0f && scrollY > prevScrollY) {
            return
        }

        // Ignore if scrolling up and still it's fully collapsed
        val prevMaxExpandProgress = maxExpandProgress
        maxExpandProgress = calcMaxExpandProgress()
        if (prevMaxExpandProgress == 0f && maxExpandProgress == 0f) {
            return
        }

        val secondaryPossibleWidth = max(0, -scrollY) / cardRatio
        minExpandProgress =
            (secondaryPossibleWidth / (width - 32.dp - smallCardWidth)).pow(if (isExpandAllowed) 2 else 4)
                .coerceAtMost(1f)
        if (isExpandAllowed && mode == Mode.Collapsed && maxExpandProgress > 0.7f) {
            expand(true, velocity)
        } else if (mode == Mode.Expanded && (maxExpandProgress < 0.66f)) {
            collapse(velocity, isGoingBack)
        } else {
            render()
        }
    }

    private fun expand(animated: Boolean, velocity: Float?) {
        mode = Mode.Expanded
        onModeChange?.invoke(animated)
        cardView.expand(animated)
        cardView.isClickable = false
        activeValueAnimator?.cancel()
        if (animated) {
            activeValueAnimator = ValueAnimator.ofFloat(currentExpandProgress, 1f).apply {
                duration = AnimationConstants.SLOW_ANIMATION /
                    ((velocity ?: 0f).roundToInt()).coerceIn(1, 2)
                interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
                addUpdateListener {
                    currentExpandProgress = animatedValue as Float
                    render()
                }
                start()
            }
        } else {
            currentExpandProgress = 1f
            render()
        }
    }

    private fun collapse(velocity: Float?, isGoingBack: Boolean) {
        mode = Mode.Collapsed
        onModeChange?.invoke(true)
        cardView.collapse()
        cardView.isClickable = true
        activeValueAnimator?.cancel()
        activeValueAnimator = ValueAnimator.ofFloat(currentExpandProgress, 0f).apply {
            duration =
                if (isGoingBack) AnimationConstants.VERY_QUICK_ANIMATION else
                    (AnimationConstants.SLOW_ANIMATION /
                        ((abs(velocity ?: 0f).times(2f)).roundToInt()).coerceIn(1, 5))
            interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
            addUpdateListener {
                currentExpandProgress = animatedValue as Float
                render()
            }
            start()
        }
    }

    fun insetsUpdated() {
        render()
        (parent as? WCell)?.setConstraints {
            toCenterX(this@HomeHeaderView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }
    }

    fun update(state: UpdateStatusView.State, animated: Boolean) {
        cardView.setStatusViewState(state, animated)
        balanceViewMaskWrapper.isLoading = state == UpdateStatusView.State.Updating
    }

    fun updateAccountData() {
        cardView.updateAccountData()
    }

    fun updateCardImage() {
        cardView.updateCardImage()
    }

    private var prevBalance: Double? = null
    private var showBalanceChangePlace = false

    @SuppressLint("SetTextI18n")
    fun updateBalance(balance: Double?, balance24h: Double?, accountChanged: Boolean = false) {
        val animated = !accountChanged
        val isBalanceLoaded = balance != null

        // Updating wallet name
        if (balanceView.text.isNullOrEmpty() && isBalanceLoaded) {
            if (animated) {
                walletNameLabel.alpha = 0f
                walletNameLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            } else
                walletNameLabel.alpha = 1f
            walletNameLabel.setTextIfChanged(AccountStore.activeAccount?.name)
        } else if (!isBalanceLoaded && accountChanged) {
            walletNameLabel.setTextIfChanged("")
        }

        // Updating balance change
        var balanceChangeString: String? = null
        showBalanceChangePlace = false
        balance?.let {
            balance24h?.let {
                if (balance > 0) {
                    val changeValue = balance - balance24h
                    if (changeValue.isFinite()) {
                        val balanceChangeValueString = (changeValue.absoluteValue).toString(
                            2,
                            WalletCore.baseCurrency.sign,
                            WalletCore.baseCurrency.decimalsCount,
                            true
                        )
                        val balanceChangePercentString =
                            if (balance24h == 0.0) "" else "${if (balance - balance24h >= 0) "+" else ""}${((balance - balance24h) / balance24h * 10000).roundToInt() / 100f}% · "
                        balanceChangeString =
                            "$balanceChangePercentString$balanceChangeValueString"
                        showBalanceChangePlace = true
                    }
                }
            }
        } ?: run {
            if (AccountStore.activeAccount?.isNew != true)
                showBalanceChangePlace = true
        }
        if (cardView.balanceChangeLabel.contentView.text.isEmpty() && showBalanceChangePlace) {
            cardView.balanceChangeLabel.alpha = 0f
            cardView.balanceChangeLabel.fadeIn()
        }
        cardView.balanceChangeLabel.contentView.text = balanceChangeString
        cardView.balanceChangeLabel.visibility =
            if (cardView.balanceChangeLabel.contentView.text.isNullOrEmpty()) INVISIBLE else VISIBLE

        // Set items' visibility
        val wasEmpty = prevBalance == null
        prevBalance = balance
        if (animated &&
            (
                (wasEmpty && isBalanceLoaded) || // Fade-in balance
                    (wasEmpty && !isShowingSkeletons)) // Fade-in skeletons
        ) {
            balanceLabel.alpha = 0f
            cardView.balanceViewContainer.alpha = 0f
            balanceLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            cardView.balanceViewContainer.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }
        if (isBalanceLoaded) {
            // Hide skeletons
            if (cardView.arrowImageView.isInvisible) {
                cardView.arrowImageView.visibility = VISIBLE
                if (animated)
                    cardView.arrowImageView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            }
            hideSkeletons()
        }

        // Update balance labels
        balanceView.animateText(
            AnimateConfig(
                balance?.toBigInteger(WalletCore.baseCurrency.decimalsCount),
                WalletCore.baseCurrency.decimalsCount,
                WalletCore.baseCurrency.sign,
                animated,
                forceCurrencyToRight = false
            )
        )
        cardView.balanceView.animateText(
            AnimateConfig(
                balance?.toBigInteger(WalletCore.baseCurrency.decimalsCount),
                WalletCore.baseCurrency.decimalsCount,
                WalletCore.baseCurrency.sign,
                animated,
                forceCurrencyToRight = false
            )
        )
        layoutBalance()

        // Show skeletons
        if (!isBalanceLoaded) {
            cardView.balanceChangeLabel.contentView.text = null
            cardView.balanceViewContainer.layoutParams =
                cardView.balanceViewContainer.layoutParams.apply {
                    width = WRAP_CONTENT
                }
            showSkeletons()
        }
    }

    val walletNameLabelSelectionHandler = Handler(Looper.getMainLooper())
    val walletNameLabelSelectionTask = Runnable {
        walletNameLabel.isSelected = true
    }

    private fun updateWalletNameMargin(balanceExpandProgress: Float) {
        val walletNameLayoutParams = walletNameLabel.layoutParams as? MarginLayoutParams ?: return
        val maxLabelMargin =
            if (AccountStore.activeAccount?.accountType == MAccount.AccountType.MNEMONIC) 96.dp else 56.dp
        val labelMargin = lerp(maxLabelMargin.toFloat(), 20f.dp, balanceExpandProgress).roundToInt()
        if (walletNameLayoutParams.marginStart == labelMargin)
            return
        walletNameLabel.layoutParams = walletNameLayoutParams.apply {
            marginStart = labelMargin
            marginEnd = labelMargin
        }
        walletNameLabel.isSelected = false
        walletNameLabelSelectionHandler.removeCallbacks(walletNameLabelSelectionTask)
        walletNameLabelSelectionHandler.postDelayed(walletNameLabelSelectionTask, 1000)
    }

    fun updateAccountName() {
        if (prevBalance != null) {
            walletNameLabel.setTextIfChanged(AccountStore.activeAccount?.name)
        } else {
            walletNameLabel.setTextIfChanged("")
        }
    }

    fun updateMintIconVisibility() {
        cardView.updateMintIconVisibility()
    }

    private fun showSkeletons() {
        if (isShowingSkeletons)
            return
        isShowingSkeletons = true

        if (cardView.balanceViewContainer.layoutParams != null)
            cardView.balanceViewContainer.layoutParams =
                cardView.balanceViewContainer.layoutParams.apply {
                    width = WRAP_CONTENT
                }

        balanceSkeletonView.visibility = VISIBLE
        balanceSkeletonView.alpha = 1f
        walletNameSkeletonView.visibility = VISIBLE
        walletNameSkeletonView.alpha = 1f
        cardView.balanceSkeletonView.visibility = VISIBLE
        cardView.balanceSkeletonView.alpha = 1f
        cardView.balanceChangeSkeletonView.isVisible = showBalanceChangePlace
        cardView.balanceChangeSkeletonView.alpha = 1f
        updateSkeletonViewColors()
        cardView.arrowImageView.visibility = INVISIBLE

        post {
            updateSkeletonMasks()
            skeletonView.startAnimating()
        }
    }

    private fun updateSkeletonViewColors() {
        balanceSkeletonView.setBackgroundColor(WColor.GroupedBackground.color, 8f.dp)
        walletNameSkeletonView.setBackgroundColor(WColor.GroupedBackground.color, 8f.dp)

        cardView.balanceSkeletonView.setBackgroundColor(
            Color.WHITE.colorWithAlpha(25),
            8f.dp
        )
        cardView.balanceChangeSkeletonView.setBackgroundColor(
            Color.WHITE.colorWithAlpha(25),
            14f.dp
        )
    }

    private fun updateSkeletonMasks() {
        if (mode == Mode.Expanded) {
            skeletonView.applyMask(
                listOf(
                    cardView.balanceSkeletonView,
                    cardView.balanceChangeSkeletonView
                ),
                hashMapOf(0 to 8f.dp, 1 to 14f.dp)
            )
        } else {
            skeletonView.applyMask(
                listOf(
                    balanceSkeletonView,
                    walletNameSkeletonView
                ),
                hashMapOf(0 to 8f.dp, 1 to 8f.dp)
            )
        }
    }

    private fun hideSkeletons() {
        if (!isShowingSkeletons)
            return
        isShowingSkeletons = false
        balanceSkeletonView.fadeOut()
        walletNameSkeletonView.fadeOut()
        cardView.balanceSkeletonView.fadeOut()
        cardView.balanceChangeSkeletonView.fadeOut(onCompletion = {
            if (!isShowingSkeletons) {
                walletNameSkeletonView.visibility = GONE
                walletNameSkeletonView.visibility = GONE
                cardView.balanceSkeletonView.visibility = GONE
                cardView.balanceChangeSkeletonView.visibility = GONE
            }
        })
        skeletonView.stopAnimating()
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Frame renderer //////////////////////////////////////////////////////////////////////////////
    private fun render() {
        layoutCardView()
        layoutBalance()
        layoutParams?.height = collapsedMinHeight + max(0, collapsedHeight - scrollY)
        val isFullyCollapsed = collapsedHeight - scrollY <= 0
        isClickable = isFullyCollapsed
        /*separatorView.alpha =
            1 - ((((layoutParams?.height ?: 0) - collapsedMinHeight) / 10f).coerceIn(0f, 1f))*/
        balanceLabel.visibility = if (expandProgress == 1f) INVISIBLE else VISIBLE
    }

    private fun layoutCardView() {
        val expandProgress = this.expandProgress
        val viewWidth = width
        val newWidth =
            (smallCardWidth + (viewWidth - 26.dp - smallCardWidth) * expandProgress).roundToInt()
        cardView.layoutParams = cardView.layoutParams.apply {
            width = newWidth
            height = max(20, (newWidth * cardRatio).toInt())
        }
        cardView.y =
            topInset +
                19.dp +
                (WNavigationBar.DEFAULT_HEIGHT.dp - 27f.dp) * min(1f, expandProgress * 2) -
                scrollY -
                expandProgress.pow(2) * (expandedContentHeight - collapsedHeight)
        // Roundings
        cardView.setRoundingParam(
            (WalletCardView.COLLAPSED_RADIUS +
                expandProgress * (WalletCardView.EXPANDED_RADIUS - WalletCardView.COLLAPSED_RADIUS)).dp
        )
        // Address Container
        cardView.addressLabelContainer.alpha =
            if (expandProgress <= 0.9f) 0f else
                ((expandProgress - 0.9f) / 0.1f).coerceIn(0f, 1f)
        cardView.mintIcon.alpha = cardView.addressLabelContainer.alpha
        cardView.walletTypeView.alpha = cardView.addressLabelContainer.alpha
        cardView.exploreButton.alpha = cardView.addressLabelContainer.alpha
    }

    private fun layoutBalance() {
        val expandedBalanceY = (width - 32.dp) * cardRatio * 0.41f - 28.dp
        val expandProgress = this.expandProgress
        val balanceExpandProgress = if (scrollY > 0) (1 - scrollY / 92f.dp).coerceIn(0f, 1f) else 1f
        balanceLabel.y =
            collapsedMinHeight -
                74f.dp + (balanceExpandProgress * 76.5f.dp) -
                min(scrollY, 0) -
                (if (isExpandAllowed) (expandedContentHeight - collapsedHeight - 2f.dp - expandedBalanceY) * expandProgress.pow(
                    2
                ) else 0f)
        balanceLabel.visibility = if (expandProgress < 1f) VISIBLE else INVISIBLE
        balanceView.setScale(
            (18 + 18 * balanceExpandProgress + 16f * expandProgress) / 52f,
            (18 + 12 * balanceExpandProgress + 8f * expandProgress) / 38f,
            (-1f).dp - 2.5f.dp * balanceExpandProgress + 1f.dp * expandProgress
        )
        balanceLabel.contentView.updateScale()
        balanceView.translationX = (-11).dp * expandProgress
        cardView.updatePositions(
            balanceLabel.y - cardView.y,
            expandProgress
        )
        balanceLabel.setMaskPivotYPercent(1f)
        balanceLabel.setMaskScale(0.5f + balanceExpandProgress / 2f)
        walletNameLabel.pivotX = walletNameLabel.width.toFloat() / 2
        walletNameLabel.pivotY = walletNameLabel.height.toFloat() / 2
        walletNameLabel.scaleX = (14 + 2 * balanceExpandProgress) / 16
        walletNameLabel.scaleY = walletNameLabel.scaleX

        walletNameLabel.x = (width - walletNameLabel.width) / 2f
        walletNameLabel.y =
            balanceLabel.y + balanceLabel.height - 10.dp + (9.5f * balanceExpandProgress).dp
        updateWalletNameMargin(balanceExpandProgress)

        updateStatusView.alpha = balanceExpandProgress
        updateStatusView.isGone = balanceExpandProgress == 0f

        balanceSkeletonView.pivotX = balanceSkeletonView.width.toFloat() / 2
        balanceSkeletonView.pivotY = balanceView.balanceBaseline + balanceView.offset2 * 2
        balanceSkeletonView.scaleX = balanceView.scale1
        balanceSkeletonView.scaleY = balanceView.scale1
        balanceSkeletonView.y = balanceLabel.y
        walletNameSkeletonView.pivotX = walletNameSkeletonView.width.toFloat() / 2
        walletNameSkeletonView.pivotY = walletNameSkeletonView.height.toFloat() / 2
        walletNameSkeletonView.y = walletNameLabel.y
    }

    fun onDestroy() {
        balanceView.onTotalWidthChanged = null
        balanceViewMaskWrapper.onDestroy()
        cardView.balanceView.onTotalWidthChanged = null
        cardView.balanceViewMaskWrapper.onDestroy()
        onModeChange = null
        onExpandPressed = null
        onHeaderPressed = null
    }
}
