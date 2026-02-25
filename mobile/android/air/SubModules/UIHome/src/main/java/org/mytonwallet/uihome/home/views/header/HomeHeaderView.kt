package org.mytonwallet.uihome.home.views.header

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Scroller
import androidx.core.view.isGone
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
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
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.uihome.home.views.UpdateStatusView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
open class HomeHeaderView(
    window: WWindow,
    private val overrideAccountIds: Array<String>?,
    private val updateStatusView: UpdateStatusView,
    private var onModeChange: ((animated: Boolean) -> Unit)?,
    private var onExpandPressed: (() -> Unit)?,
    private var onHeaderPressed: (() -> Unit)?,
    private var onHorizontalScrollListener: ((progress: Float, verticalOffset: Int, actionsFadeOutPercent: Float) -> Unit)? = null,
) : WFrameLayout(window), WThemedView, WProtectedView {

    companion object {
        val DEFAULT_MODE = Mode.Expanded
        private val NAV_SIZE_OFFSET = 8.dp
        val navDefaultHeight = WNavigationBar.DEFAULT_HEIGHT.dp - NAV_SIZE_OFFSET
    }

    init {
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

    // Horizontal scroll state variables ///////////////////////////////////////////////////////////
    private var horizontalScrollOffset = 0f
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var lastTouchX = 0f
    private var isHorizontalScrolling = false
    private var scrollDirectionLocked = false
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val horizontalScroller = Scroller(context)
    private val horizontalGestureDetector = GestureDetector(context, HorizontalGestureListener())
    private var horizontalScrollAnimator: ValueAnimator? = null
    private var balanceExpandProgress = 1f
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Views ///////////////////////////////////////////////////////////////////////////////////////
    private var prevCardView = WalletCardView(window).apply {
        setRoundingParam(WalletCardView.EXPANDED_RADIUS.dp.toFloat())
        expand(false)
    }
    private var cardView = WalletCardView(window)
    private var nextCardView = WalletCardView(window).apply {
        setRoundingParam(WalletCardView.EXPANDED_RADIUS.dp.toFloat())
        expand(false)
    }
    private val cardViews = setOf(prevCardView, cardView, nextCardView)
    private val balanceView = WBalanceView(context).apply {
        typeface = WFont.NunitoExtraBold.typeface
        clipChildren = false
        clipToPadding = false
        smartDecimalsColor = true
    }
    private val balanceViewMaskWrapper = WGradientMaskView(balanceView)
    private val balanceLabel = WSensitiveDataContainer(
        AutoScaleContainerView(balanceViewMaskWrapper).apply {
            clipChildren = false
            clipToPadding = false
            maxAllowedWidth = window.windowView.width - 34.dp
            minPadding = 16.dp
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
        setStyle(16f, WFont.DemiBold)
        setSingleLine()
        isHorizontalFadingEdgeEnabled = true
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isSelected = true
        setPadding(10.dp, 4.dp, 10.dp, 4.dp)
        foreground = WRippleDrawable.create(12f.dp).apply {
            rippleColor = WColor.SubtitleText.color.colorWithAlpha(25)
        }
    }
    private val balanceSkeletonView = View(context).apply {
        visibility = GONE
    }
    private val walletNameSkeletonView = View(context).apply {
        visibility = GONE
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Helpers /////////////////////////////////////////////////////////////////////////////////////
    val collapsedMinHeight =
        (window.systemBars?.top ?: 0) + navDefaultHeight
    val collapsedHeight = 101.dp + NAV_SIZE_OFFSET
    val centerAccount: MAccount?
        get() {
            return cardView.account
        }
    private val smallCardWidth = 36.dp
    private val topInset = window.systemBars?.top ?: 0
    private val cardRatio = 208 / 358f

    private fun calcMaxExpandProgress(): Float {
        val realPossibleWidth = max(0, collapsedHeight - scrollY) / cardRatio
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
        addView(prevCardView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        })
        addView(cardView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        })
        addView(nextCardView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        })
        addView(skeletonView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        render()
        updateTheme()

        cardViews.forEach {
            it.setOnClickListener {
                onExpandPressed?.invoke()
            }
        }
        cardView.isClickable = DEFAULT_MODE == Mode.Collapsed

        walletNameLabel.setOnClickListener {
            if (mode == Mode.Collapsed) {
                cardView.openAddressMenu(walletNameLabel)
            }
        }
        walletNameLabel.setOnLongClickListener {
            if (mode == Mode.Collapsed) {
                cardView.copyFirstAddress()
                true
            } else {
                false
            }
        }

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

        WalletCore.doOnBridgeReady {
            AccountStore.activeAccount?.let { account ->
                updateAccountData(account)
            }
        }
    }

    fun viewWillDisappear() {
        balanceView.interruptAnimation()
        cardViews.forEach { it.viewWillDisappear() }
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
        cardViews.forEach {
            it.updateTheme()
        }

        if (isShowingSkeletons)
            updateSkeletonViewColors()
    }

    override fun updateProtectedView() {}

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w - oldw > 2) {
            balanceViewMaskWrapper.setupLayout(parentWidth = w)
            cardViews.forEach { it.setupLayout(parentWidth = w) }
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

    fun expand(animated: Boolean, velocity: Float?) {
        mode = Mode.Expanded
        cardViews.forEach { it.headerMode = Mode.Expanded }
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
        cardViews.forEach { it.headerMode = Mode.Collapsed }
        onModeChange?.invoke(true)
        cardView.collapse(true)
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
        cardViews.forEach { it.setStatusViewState(state, animated && it == cardView) }
        balanceViewMaskWrapper.isLoading = state == UpdateStatusView.State.Updating
    }

    fun updateAccountData(activeAccount: MAccount) {
        val accountIds = overrideAccountIds ?: WGlobalStorage.accountIds()
        val activeAccountIndex = accountIds.indexOf(activeAccount.accountId)
        val prevAccountId = accountIds.getOrNull(activeAccountIndex - 1)
        val nextAccountId = accountIds.getOrNull(activeAccountIndex + 1)

        // Recycle the card views to prevent unnecessary `updateAccountData` calls
        val cardViewsCopy = mutableListOf(prevCardView, cardView, nextCardView)
        fun getViewForAccountId(id: String?): WalletCardView? {
            return cardViewsCopy.firstOrNull { cardView ->
                cardView.account?.accountId == id
            }
        }

        val prevView = getViewForAccountId(prevAccountId)
        if (prevView != null) cardViewsCopy.remove(prevView)
        val currentView = getViewForAccountId(activeAccount.accountId)
        if (currentView != null) cardViewsCopy.remove(currentView)
        val nextView = getViewForAccountId(nextAccountId)
        if (nextView != null) cardViewsCopy.remove(nextView)

        prevCardView = (prevView ?: cardViewsCopy.removeFirstOrNull()!!.apply {
            updateAccountData(AccountStore.accountById(prevAccountId))
        }).apply {
            expand(false)
            setRoundingParam(WalletCardView.EXPANDED_RADIUS.dp.toFloat())
        }
        prevCardView.isInGoneState = expandProgress <= 0.9f
        cardView = (currentView ?: cardViewsCopy.removeFirstOrNull()!!.apply {
            updateAccountData(activeAccount)
        }).apply {
            this@HomeHeaderView.updateStatusView.state?.let {
                setStatusViewState(it, animated = false)
            }
            if (this@HomeHeaderView.mode == Mode.Expanded)
                expand(false)
            else
                collapse(false)
            setRoundingParam(
                (WalletCardView.COLLAPSED_RADIUS +
                    expandProgress * (WalletCardView.EXPANDED_RADIUS - WalletCardView.COLLAPSED_RADIUS)).dp
            )
        }
        cardView.isInGoneState = false
        cardView.alpha = 1f
        nextCardView = (nextView ?: cardViewsCopy.removeFirstOrNull()!!.apply {
            updateAccountData(AccountStore.accountById(nextAccountId))
        }).apply {
            expand(false)
            setRoundingParam(WalletCardView.EXPANDED_RADIUS.dp.toFloat())
        }
        nextCardView.isInGoneState = expandProgress <= 0.9f
    }

    fun updateCardImage() {
        cardViews.forEach {
            it.updateCardImage()
        }
    }

    fun updateSeasonalTheme() {
        cardViews.forEach {
            it.updateSeasonalTheme()
        }
    }

    fun updateAddressLabel(accountId: String) {
        cardViews.forEach {
            if (it.account?.accountId == accountId)
                it.updateAddressLabel()
        }
    }

    val isAnimating: Boolean
        get() {
            return springAnimation?.isRunning == true
        }

    private var prevBalance: Double? = null

    fun updateBalance(accountName: String, animated: Boolean = true) {
        val activeAccountId = cardView.account?.accountId ?: return

        fun fetchBalances(): Pair<Double?, Double?> {
            val balance = BalanceStore.totalBalanceInBaseCurrency(activeAccountId)
            val balance24h = BalanceStore.totalBalance24hInBaseCurrency(activeAccountId)
            return balance to balance24h
        }

        CoroutineScope(Dispatchers.Main).launch {
            val (balance, balance24h) =
                if (animated) {
                    withContext(Dispatchers.Default) {
                        fetchBalances()
                    }
                } else {
                    fetchBalances()
                }

            if (activeAccountId != cardView.account?.accountId)
                return@launch

            applyBalance(accountName, balance, balance24h, animated)
        }
    }

    private fun applyBalance(
        accountName: String,
        balance: Double?,
        balance24h: Double?,
        animated: Boolean
    ) {
        updateWalletName(shouldShow = balance != null, accountName, animated)
        cardView.updateBalanceChange(balance, balance24h, animated)
        updateBalanceViews(balance, animated)
        updateSideCardBalanceViews(animated)

        if (balance != null)
            hideSkeletons()
        else
            showSkeletons()
    }

    private fun updateWalletName(shouldShow: Boolean, accountName: String, animated: Boolean) {
        if (shouldShow) {
            if (prevBalance == null && animated) {
                walletNameLabel.alpha = 0f
                walletNameLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            } else
                walletNameLabel.alpha = 1f
            walletNameLabel.setTextIfChanged(accountName)
        } else {
            walletNameLabel.setTextIfChanged("")
        }
    }

    private fun updateBalanceViews(balance: Double?, animated: Boolean) {
        val animateConfig = AnimateConfig(
            amount = balance?.toBigInteger(WalletCore.baseCurrency.decimalsCount),
            decimals = WalletCore.baseCurrency.decimalsCount,
            currency = WalletCore.baseCurrency.sign,
            animated = animated,
            setInstantly = true,
            forceCurrencyToRight = (WalletCore.baseCurrency == MBaseCurrency.RUB)
        )
        animateBalance(animateConfig.copy(animated = animateConfig.animated && mode == Mode.Collapsed))
        cardView.animateBalance(animateConfig.copy(animated = animateConfig.animated && mode == Mode.Expanded))
        prevBalance = balance
        layoutBalance()
    }

    private fun updateSideCardBalanceViews(animated: Boolean) {
        setOf(prevCardView, nextCardView).forEach { cardView ->
            val accountId = cardView.account?.accountId ?: return@forEach

            CoroutineScope(Dispatchers.Main).launch {
                fun fetchBalances(): Pair<Double?, Double?> {
                    val balance = BalanceStore.totalBalanceInBaseCurrency(accountId)
                    val balance24h = BalanceStore.totalBalance24hInBaseCurrency(accountId)
                    return balance to balance24h
                }

                val (balance, balance24h) =
                    withContext(Dispatchers.IO) { fetchBalances() }

                if (accountId != cardView.account?.accountId)
                    return@launch
                cardView.animateBalance(
                    AnimateConfig(
                        amount = balance?.toBigInteger(WalletCore.baseCurrency.decimalsCount),
                        WalletCore.baseCurrency.decimalsCount,
                        WalletCore.baseCurrency.sign,
                        animated = animated && cardView.alpha > 0.05,
                        setInstantly = false,
                        false
                    )
                )
                cardView.updateBalanceChange(
                    balance,
                    balance24h,
                    animated = animated && horizontalScrollOffset != 0f,
                )
            }
        }
    }

    private fun animateBalance(animateConfig: AnimateConfig) {
        if (animateConfig.animated && prevBalance == null && animateConfig.amount != null) {
            balanceLabel.alpha = 0f
            balanceLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }
        balanceView.animateText(animateConfig)
    }

    val walletNameLabelSelectionHandler = Handler(Looper.getMainLooper())
    val walletNameLabelSelectionTask = Runnable {
        walletNameLabel.isSelected = true
    }

    private fun updateWalletNameMargin(balanceExpandProgress: Float) {
        val walletNameLayoutParams = walletNameLabel.layoutParams as? MarginLayoutParams ?: return
        val maxLabelMargin =
            if (cardView.account?.accountType == MAccount.AccountType.MNEMONIC) 96.dp else 56.dp
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

    fun updateAccountName(accountName: String) {
        if (prevBalance != null) {
            walletNameLabel.setTextIfChanged(accountName)
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

        balanceSkeletonView.visibility = VISIBLE
        balanceSkeletonView.alpha = 1f
        walletNameSkeletonView.visibility = VISIBLE
        walletNameSkeletonView.alpha = 1f
        updateSkeletonViewColors()

        post {
            if (!isShowingSkeletons)
                return@post
            updateSkeletonMasks()
            skeletonView.startAnimating()
        }
    }

    private fun updateSkeletonViewColors() {
        balanceSkeletonView.setBackgroundColor(WColor.GroupedBackground.color, 8f.dp)
        walletNameSkeletonView.setBackgroundColor(WColor.GroupedBackground.color, 8f.dp)
    }

    private fun updateSkeletonMasks() {
        if (mode == Mode.Expanded) {
            skeletonView.applyMask(
                cardView.getSkeletonViews(),
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
        walletNameSkeletonView.fadeOut(onCompletion = {
            if (!isShowingSkeletons) {
                walletNameSkeletonView.visibility = GONE
                walletNameSkeletonView.visibility = GONE
            }
        })
        skeletonView.stopAnimating()
    }

    private var isHeavyAnimationIsProgress = false
    fun heavyAnimationInProgress() {
        if (isHeavyAnimationIsProgress)
            return
        isHeavyAnimationIsProgress = true
        WGlobalStorage.incDoNotSynchronize()
    }

    fun heavyAnimationDone() {
        if (!isHeavyAnimationIsProgress)
            return
        isHeavyAnimationIsProgress = false
        WGlobalStorage.decDoNotSynchronize()
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Frame renderer //////////////////////////////////////////////////////////////////////////////
    private fun render() {
        layoutCardView()
        layoutBalance()
        layoutParams?.height = collapsedMinHeight + max(0, collapsedHeight - scrollY)
        val isFullyCollapsed = collapsedHeight - scrollY <= 0
        isClickable = isFullyCollapsed
        balanceLabel.visibility = if (expandProgress == 1f) INVISIBLE else VISIBLE
    }

    fun layoutCardView() {
        val expandProgress = this.expandProgress
        val newWidth =
            (smallCardWidth + (width - 26.dp - smallCardWidth) * expandProgress).roundToInt()
        if (cardView.layoutParams.width != newWidth)
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
        val actionsTransformProgress = if (expandProgress <= 0.9f) {
            0f
        } else {
            ((expandProgress - 0.9f) / 0.1f).coerceIn(0f, 1f)
        }
        cardView.updateActionsTransformProgress(actionsTransformProgress)

        balanceView.isGone = expandProgress > 0.98
        walletNameLabel.isGone = balanceView.isGone
        if (expandProgress > 0.9) {
            setOf(prevCardView, nextCardView).forEach {
                if (it.layoutParams.width != cardView.layoutParams.width)
                    it.layoutParams = it.layoutParams.apply {
                        width = cardView.layoutParams.width
                        height = cardView.layoutParams.height
                    }
                it.y = cardView.y
                it.alpha = if (expandProgress > 0.98) 1f else (expandProgress - 0.9f) * 10f
                it.isInGoneState = false
            }

            val baseOffset = -horizontalScrollOffset
            val cardWidth = cardView.layoutParams.width
            val prevCardViewProgress = (baseOffset - cardWidth) / cardWidth
            val cardViewProgress = baseOffset / cardWidth
            val nextCardViewProgress = (baseOffset + cardWidth) / cardWidth

            prevCardView.translationX =
                -cardWidth.toFloat() + baseOffset + prevCardViewProgress * 10.dp
            cardView.isInGoneState = false
            cardView.translationX = baseOffset + cardViewProgress * 10.dp
            nextCardView.translationX =
                cardWidth.toFloat() + baseOffset + nextCardViewProgress * 10.dp
        } else {
            prevCardView.isInGoneState = true
            nextCardView.isInGoneState = true
            cardView.isInGoneState = false
            cardView.translationX = 0f
        }
    }

    private fun layoutBalance() {
        val expandedBalanceY = (width - 32.dp) * cardRatio * 0.41f - 28.dp
        val expandProgress = this.expandProgress
        balanceExpandProgress = if (scrollY > 0) (1 - scrollY / 92f.dp).coerceIn(0f, 1f) else 1f
        balanceLabel.y =
            collapsedMinHeight -
                74f.dp + (balanceExpandProgress * 84f.dp) -
                min(scrollY, 0) -
                (if (isExpandAllowed) (expandedContentHeight - collapsedHeight + 5.5f.dp - expandedBalanceY) * expandProgress.pow(
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
        cardViews.forEach {
            it.updatePositions(
                balanceLabel.y - cardView.y,
                expandProgress
            )
        }
        balanceLabel.setMaskPivotYPercent(1f)
        balanceLabel.setMaskScale(0.5f + balanceExpandProgress / 2f)
        walletNameLabel.pivotX = walletNameLabel.width.toFloat() / 2
        walletNameLabel.pivotY = walletNameLabel.height.toFloat() / 2
        walletNameLabel.scaleX = (14 + 2 * balanceExpandProgress) / 16
        walletNameLabel.scaleY = walletNameLabel.scaleX

        walletNameLabel.x = (width - walletNameLabel.width) / 2f
        walletNameLabel.y =
            balanceLabel.y + balanceLabel.height - 10.dp + (10f * balanceExpandProgress).dp
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
        cardView.onDestroy()
        onModeChange = null
        onExpandPressed = null
        onHeaderPressed = null
        onHorizontalScrollListener = null
        horizontalScrollAnimator?.cancel()
    }

    // Horizontal Scroll Implementation ///////////////////////////////////////////////////////////
    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                springAnimation?.cancel()
                springAnimation = null
                heavyAnimationDone()
                scrollerOffset = 0f
                if (!horizontalScroller.isFinished) {
                    horizontalScroller.abortAnimation()
                }
                horizontalScrollAnimator?.cancel()
                initialTouchX = event.x
                initialTouchY = event.y
                lastTouchX = event.x
                isHorizontalScrolling = false
                scrollDirectionLocked = false

                return false
            }

            MotionEvent.ACTION_MOVE -> {
                if (!scrollDirectionLocked) {
                    val dx = abs(event.x - initialTouchX)
                    val dy = abs(event.y - initialTouchY)

                    when {
                        dy > touchSlop && dy > dx -> {
                            scrollDirectionLocked = true
                            return false
                        }

                        dx > touchSlop && dx > dy -> {
                            scrollDirectionLocked = true
                            isHorizontalScrolling = true
                            initialTouchX = event.x
                            initialTouchY = event.y
                            parent.requestDisallowInterceptTouchEvent(true)
                            return true
                        }
                    }
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (onTouchEnd())
                    return true
            }
        }
        return false
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (mode != Mode.Expanded || expandProgress < 0.95f) {
            return super.onTouchEvent(event)
        }

        horizontalGestureDetector.onTouchEvent(event)

        when (event.action) {
            MotionEvent.ACTION_DOWN -> return true

            MotionEvent.ACTION_MOVE -> {
                heavyAnimationInProgress()
                if (!scrollDirectionLocked) {
                    val dx = abs(event.x - initialTouchX)
                    val dy = abs(event.y - initialTouchY)

                    when {
                        dy > touchSlop && dy > dx -> {
                            scrollDirectionLocked = true
                            isHorizontalScrolling = false
                            return false
                        }

                        dx > touchSlop && dx > dy -> {
                            scrollDirectionLocked = true
                            isHorizontalScrolling = true
                            initialTouchX = event.x
                            initialTouchY = event.y
                            parent.requestDisallowInterceptTouchEvent(true)
                        }
                    }
                }

                if (isHorizontalScrolling) {
                    var scrollCandidate = initialTouchX - event.x
                    if (prevCardView.account == null && scrollCandidate < 0)
                        scrollCandidate = 0f
                    else if (nextCardView.account == null && scrollCandidate > 0)
                        scrollCandidate = 0f
                    onScrollOffsetChanged(scrollCandidate)
                    return true
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                heavyAnimationDone()
                if (onTouchEnd())
                    return true
            }
        }

        return super.onTouchEvent(event)
    }

    private fun onTouchEnd(): Boolean {
        if (isHorizontalScrolling || horizontalScrollOffset != 0f) {
            if (springAnimation?.isRunning != true) {
                scrollerOffset = 0f
                animateToTargetHorizontalOffset(
                    targetHorizontalOffset = 0f,
                    startVelocity = 0f
                )
            }
            parent.requestDisallowInterceptTouchEvent(false)
            isHorizontalScrolling = false
            scrollDirectionLocked = false
            return true
        }
        return false
    }

    private var springAnimation: SpringAnimation? = null
    private fun animateToTargetHorizontalOffset(
        targetHorizontalOffset: Float,
        startVelocity: Float
    ) {
        val startOffset = horizontalScrollOffset
        val distance = targetHorizontalOffset - startOffset

        if (abs(distance) <= 1f) {
            onScrollOffsetChanged(0f)
            return
        }

        springAnimation?.cancel()

        springAnimation = SpringAnimation(FloatValueHolder(startVelocity)).apply {
            setStartValue(startOffset)
            spring = SpringForce(targetHorizontalOffset).apply {
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
                stiffness = 500f
            }

            addUpdateListener { _, value, _ ->
                val offset = value + scrollerOffset
                onScrollOffsetChanged(if (abs(offset) < 2) 0f else offset)
            }

            addEndListener { _, _, _, _ ->
                heavyAnimationDone()
            }
        }

        heavyAnimationInProgress()
        springAnimation!!.start()
    }

    var changingAccountTo: String? = null
        private set
    private var scrollerOffset = 0f

    private fun onScrollOffsetChanged(value: Float) {
        if (horizontalScrollOffset == value)
            return
        horizontalScrollOffset = value
        val progress = horizontalScrollOffset / cardView.width
        if (progress > 0.52 || progress < -0.52) {
            val nextAccount =
                if (progress > 0) nextCardView.account else prevCardView.account
            if (changingAccountTo == null || nextAccount?.accountId != changingAccountTo) {
                nextAccount?.accountId?.let { nextAccountId ->
                    changingAccountTo = nextAccountId
                    Haptics.play(this, HapticType.TRANSITION)
                    scrollerOffset = (if (progress > 0) -1f else 1f) * cardView.width
                    initialTouchX += scrollerOffset
                    horizontalScrollOffset += scrollerOffset
                    updateAccountData(nextAccount)
                    layoutCardView()
                    WalletCore.activateAccount(
                        nextAccountId,
                        notifySDK = true,
                        fromHome = true
                    ) { res, err ->
                        if (res == null || err != null) {
                            // Should not happen!
                            Logger.e(
                                Logger.LogTag.ACCOUNT,
                                LogMessage.Builder()
                                    .append(
                                        "Activation failed in home slider: $err",
                                        LogMessage.MessagePartPrivacy.PUBLIC
                                    ).build()
                            )
                            throw Exception()
                        } else {
                            WalletCore.notifyEvent(
                                WalletEvent.AccountChangedInApp(
                                    persistedAccountsModified = false
                                )
                            )
                            changingAccountTo = null
                        }
                    }
                    val progress = horizontalScrollOffset / cardView.width
                    notifyVerticalOffsetChange(progress)
                    return
                }
            }
        }
        layoutCardView()
        notifyVerticalOffsetChange(progress)
    }

    private fun notifyVerticalOffsetChange(progress: Float) {
        val verticalOffset = if (progress < 0) {
            lerp(
                if (cardView.account?.isViewOnly == true) 0f else 94f.dp,
                if (prevCardView.account?.isViewOnly == true) 0f else 94f.dp,
                abs(progress)
            ) - if (cardView.account?.isViewOnly == true) 0f else 94f.dp
        } else {
            lerp(
                if (cardView.account?.isViewOnly == true) 0f else 94f.dp,
                if (nextCardView.account?.isViewOnly == true) 0f else 94f.dp,
                progress
            ) - if (cardView.account?.isViewOnly == true) 0f else 94f.dp
        }
        val actionsFadeOutPercent = if (progress < 0)
            lerp(
                if (cardView.account?.isViewOnly != true) 1f else 0f,
                if (prevCardView.account?.isViewOnly != true) 1f else 0f,
                -progress * 2
            )
        else
            lerp(
                if (cardView.account?.isViewOnly != true) 1f else 0f,
                if (nextCardView.account?.isViewOnly != true) 1f else 0f,
                progress * 2
            )
        onHorizontalScrollListener?.invoke(
            progress,
            verticalOffset.roundToInt(),
            actionsFadeOutPercent.coerceIn(0f, 1f)
        )
    }

    private inner class HorizontalGestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onFling(
            e1: MotionEvent?,
            e2: MotionEvent,
            velocityX: Float,
            velocityY: Float
        ): Boolean {
            if (mode != Mode.Expanded) return false

            val accountIds = overrideAccountIds ?: WGlobalStorage.accountIds()
            if (accountIds.size <= 1) return false

            val cardWidth = cardView.width + 8.dp
            val velocity = -velocityX * 0.5f
            val flingThreshold = 300

            val flingScrollTarget = when {
                velocity > flingThreshold && horizontalScrollOffset > 0 ->
                    cardWidth.toFloat() - 8.dp

                velocity < -flingThreshold && horizontalScrollOffset < 0 ->
                    -cardWidth.toFloat() + 8.dp

                else -> 0f
            }
            if (flingScrollTarget == 0f)
                scrollerOffset = 0f
            animateToTargetHorizontalOffset(flingScrollTarget, velocityX)

            return true
        }
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////
}
