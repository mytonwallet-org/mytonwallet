package org.mytonwallet.app_air.uisettings.viewControllers.mintCard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isGone
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import java.lang.ref.WeakReference
import java.math.BigInteger
import java.util.Locale
import kotlin.math.pow
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.toast.ToastManager
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setupSpringFling
import org.mytonwallet.app_air.uicomponents.extensions.springToItem
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.viewControllers.MfaActionConfirmVC
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uipasscode.ProtectedActionAuth
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views.MintCardDotsView
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views.MintCardInfoView
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views.MintCardPosterView
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views.MintCardProsView
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.utils.lerpColor
import org.mytonwallet.app_air.walletcore.MINT_CARD_ADDRESS
import org.mytonwallet.app_air.walletcore.MINT_CARD_COMMENT
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MCardInfo
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferPayload
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class MintCardVC(context: Context, accountId: String? = AccountStore.activeAccountId) :
    WViewController(context),
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "MintCard"

    override val displayedAccount =
        DisplayedAccount(
            accountId,
            accountId == AccountStore.activeAccountId && AccountStore.isPushedTemporary
        )

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = false
    override val isSwipeBackAllowed = false

    private val countdownHandler = Handler(Looper.getMainLooper())
    private val countdownTick = Runnable { bindButton(boundButtonIndex) }

    private val orderedTypes = MintCardTypeInfo.ordered
    private var sideStartInset = 0
    private var sideEndInset = 0
    private val allowSoldOutUpgrade: Boolean
        get() = (DEBUG_MODE || EnvironmentStore.isBeta) &&
            WGlobalStorage.getAllowSoldOutMintCardUpgrade()
    private var currentIndex = 0
    private val initialPage = Int.MAX_VALUE / 2 - (Int.MAX_VALUE / 2) % orderedTypes.size
    private var dragStartPage = initialPage

    private fun cardIndex(page: Int): Int = page % orderedTypes.size

    private var cardsInfo = MintCardHelpers.cardsInfo(displayedAccount.accountId ?: "")

    private val viewPager = ViewPager2(context).apply {
        id = View.generateViewId()
    }

    private fun freeViewPagerVerticalDrags() {
        (viewPager.getChildAt(0) as? RecyclerView)?.apply {
            isNestedScrollingEnabled = false
            addOnItemTouchListener(
                object : RecyclerView.OnItemTouchListener {
                    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
                    private var downX = 0f
                    private var downY = 0f
                    private var isTap = false

                    override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                        when (e.actionMasked) {
                            MotionEvent.ACTION_DOWN -> {
                                downX = e.x
                                downY = e.y
                                isTap = true
                            }

                            MotionEvent.ACTION_MOVE -> {
                                if (kotlin.math.abs(e.x - downX) > touchSlop ||
                                    kotlin.math.abs(e.y - downY) > touchSlop
                                ) {
                                    isTap = false
                                }
                            }

                            MotionEvent.ACTION_UP -> {
                                val shouldSettle = isTap &&
                                    rv.scrollState == RecyclerView.SCROLL_STATE_IDLE
                                isTap = false
                                if (shouldSettle) {
                                    rv.post {
                                        if (scrollOffset > 0f) {
                                            val nearestPage = scrollPosition +
                                                if (scrollOffset >= 0.5f) 1 else 0
                                            viewPager.springToItem(nearestPage)
                                        }
                                    }
                                }
                            }

                            MotionEvent.ACTION_CANCEL -> isTap = false
                        }
                        return false
                    }

                    override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {}
                    override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
                }
            )
        }
    }

    private val dotsView = MintCardDotsView(context, orderedTypes.size).apply {
        id = View.generateViewId()
    }

    private val cardInfoViews = Array(2) { MintCardInfoView(context) }
    private val cardInfoOverlay = FrameLayout(context).apply {
        setPaddingRelative(16.dp, 0, 16.dp, 0)
        cardInfoViews.forEach { infoView ->
            addView(
                infoView,
                FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    gravity = android.view.Gravity.BOTTOM
                }
            )
        }
        cardInfoViews[1].alpha = 0f
    }

    private val leftArrow = WImageButton(context).apply {
        setImageResource(R.drawable.ic_arrow_left_sharp)
        layoutDirection = View.LAYOUT_DIRECTION_LTR
        scaleType = ImageView.ScaleType.CENTER
        imageAlpha = 191
        updateColors(WColor.White, WColor.BackgroundRipple)
        setOnClickListener { navigateCard(-1) }
    }

    private val rightArrow = WImageButton(context).apply {
        setImageResource(R.drawable.ic_arrow_left_sharp)
        layoutDirection = View.LAYOUT_DIRECTION_LTR
        rotation = 180f
        scaleType = ImageView.ScaleType.CENTER
        imageAlpha = 191
        updateColors(WColor.White, WColor.BackgroundRipple)
        setOnClickListener { navigateCard(1) }
    }

    private fun navigateCard(physicalDirection: Int) {
        val pageOffset = if (pagerHost.layoutDirection == View.LAYOUT_DIRECTION_RTL) {
            -physicalDirection
        } else {
            physicalDirection
        }
        val target = viewPager.currentItem + pageOffset
        if (target in 0 until slideAdapter.itemCount) {
            viewPager.springToItem(target)
        }
    }

    private fun updateArrowDescriptions(layoutDirection: Int) {
        if (layoutDirection == View.LAYOUT_DIRECTION_RTL) {
            leftArrow.contentDescription = LocaleController.getString("Next")
            rightArrow.contentDescription = LocaleController.getString("Previous")
        } else {
            leftArrow.contentDescription = LocaleController.getString("Previous")
            rightArrow.contentDescription = LocaleController.getString("Next")
        }
    }

    private val pagerHost: android.widget.FrameLayout =
        object : android.widget.FrameLayout(context) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val w = MeasureSpec.getSize(widthMeasureSpec)
                super.onMeasure(
                    widthMeasureSpec,
                    MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY)
                )
            }

            override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
                super.onLayout(changed, left, top, right, bottom)
                val controlsTop = (width * 164f / 402f).roundToInt() - leftArrow.measuredHeight / 2
                val inset = 12.dp
                val leftInset = if (LocaleController.isRTL) sideEndInset else sideStartInset
                val rightInset = if (LocaleController.isRTL) sideStartInset else sideEndInset
                leftArrow.layout(
                    inset + leftInset,
                    controlsTop,
                    inset + leftInset + leftArrow.measuredWidth,
                    controlsTop + leftArrow.measuredHeight
                )
                rightArrow.layout(
                    width - inset - rightInset - rightArrow.measuredWidth,
                    controlsTop,
                    width - inset - rightInset,
                    controlsTop + rightArrow.measuredHeight
                )
            }

            override fun onRtlPropertiesChanged(layoutDirection: Int) {
                super.onRtlPropertiesChanged(layoutDirection)
                updateArrowDescriptions(layoutDirection)
            }
        }.apply {
            id = View.generateViewId()
            addView(viewPager, android.widget.FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(cardInfoOverlay, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(
                dotsView,
                android.widget.FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
                    bottomMargin = 112.dp
                }
            )
            addView(leftArrow, android.widget.FrameLayout.LayoutParams(44.dp, 72.dp))
            addView(rightArrow, android.widget.FrameLayout.LayoutParams(44.dp, 72.dp))
            updateArrowDescriptions(layoutDirection)
        }

    private val contentContainer = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
    }

    private val prosView = MintCardProsView(context).apply {
        id = View.generateViewId()
    }

    private val upgradeButton = WButton(context).apply {
        id = View.generateViewId()
        accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfo
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.isEnabled = host.isEnabled && host.isClickable
            }
        }
        setOnClickListener {
            val info = orderedTypes[boundButtonIndex]
            onUpgradePressed(cardsInfo?.get(info.type))
        }
    }

    private val bottomSection = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
    }

    // Routes gestures at dispatch level (which reliably receives every event). A horizontal drag —
    // anywhere in the scroll view — is forwarded as a native touch stream to the pager's
    // RecyclerView, so the pager handles it with its own drag + spring-fling physics. Vertical
    // drags fall through to the scroll view.
    @SuppressLint("ClickableViewAccessibility")
    private val scrollView: NestedScrollView = object : NestedScrollView(context) {
        private val touchSlop = android.view.ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var forwarding = false
        private var decided = false
        private val pagerBounds = Rect()

        private fun forwardToPager(ev: android.view.MotionEvent, action: Int) {
            val rv = pagerRecyclerView ?: return
            val copy = android.view.MotionEvent.obtain(ev)
            copy.action = action
            pagerBounds.set(0, 0, rv.width, rv.height)
            offsetDescendantRectToMyCoords(rv, pagerBounds)
            copy.offsetLocation(-pagerBounds.left.toFloat(), -pagerBounds.top.toFloat())
            rv.dispatchTouchEvent(copy)
            copy.recycle()
        }

        override fun dispatchTouchEvent(ev: android.view.MotionEvent): Boolean {
            when (ev.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    dragStartPage = viewPager.currentItem
                    downX = ev.x
                    downY = ev.y
                    forwarding = false
                    decided = false
                }

                android.view.MotionEvent.ACTION_MOVE -> {
                    if (!decided) {
                        val dx = kotlin.math.abs(ev.x - downX)
                        val dy = kotlin.math.abs(ev.y - downY)
                        if (dx > touchSlop || dy > touchSlop) {
                            decided = true
                            forwarding = dx > dy
                            if (forwarding) {
                                // Cancel whoever started handling this gesture in the scroll tree.
                                val cancel = android.view.MotionEvent.obtain(ev)
                                cancel.action = android.view.MotionEvent.ACTION_CANCEL
                                super.dispatchTouchEvent(cancel)
                                cancel.recycle()
                                // Start a fresh native gesture on the pager.
                                forwardToPager(ev, android.view.MotionEvent.ACTION_DOWN)
                            }
                        }
                    }
                    if (forwarding) {
                        forwardToPager(ev, android.view.MotionEvent.ACTION_MOVE)
                        return true
                    }
                }

                android.view.MotionEvent.ACTION_UP,
                android.view.MotionEvent.ACTION_CANCEL -> {
                    if (forwarding) {
                        forwardToPager(ev, ev.actionMasked)
                        forwarding = false
                        decided = false
                        return true
                    }
                    decided = false
                }
            }
            return super.dispatchTouchEvent(ev)
        }
    }.apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
        overScrollMode = NestedScrollView.OVER_SCROLL_NEVER
    }

    private val bottomReversedCorner = ReversedCornerViewUpsideDown(context, scrollView)

    private val closeButton = WImageButton(context).apply {
        id = View.generateViewId()
        setImageDrawable(context.getDrawableCompat(R.drawable.ic_close))
        updateColors(WColor.White, WColor.BackgroundRipple)
        setPaddingDp(8, 8, 8, 8)
        setOnClickListener { window?.dismissLastNav() }
    }

    private val slideAdapter = SlideAdapter()

    override fun setupViews() {
        super.setupViews()

        viewPager.adapter = slideAdapter
        viewPager.setCurrentItem(initialPage, false)
        viewPager.offscreenPageLimit = if (DevicePerformanceClassifier.isHighClass) 4 else 2
        freeViewPagerVerticalDrags()
        viewPager.setupSpringFling { target ->
            target.coerceIn(
                (dragStartPage - 1).coerceAtLeast(0),
                (dragStartPage + 1).coerceAtMost(slideAdapter.itemCount - 1)
            )
        }
        cardInfoViews.forEach { it.setupBlur(viewPager) }
        viewPager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageScrollStateChanged(state: Int) {
                val isIdle = state == ViewPager2.SCROLL_STATE_IDLE
                leftArrow.isEnabled = isIdle
                rightArrow.isEnabled = isIdle
                if (isIdle) dragStartPage = viewPager.currentItem
            }

            override fun onPageScrolled(
                position: Int,
                positionOffset: Float,
                positionOffsetPixels: Int
            ) {
                applyScrollProgress(position, positionOffset)
                dotsView.setPosition(cardIndex(position) + positionOffset)
                val distanceFromCard = minOf(positionOffset, 1f - positionOffset)
                val arrowsAlpha = (1f - distanceFromCard / ARROW_FADE_DISTANCE).coerceIn(0f, 1f)
                leftArrow.alpha = arrowsAlpha
                rightArrow.alpha = arrowsAlpha
                updateVideoPlaybackForVisibility()
            }

            override fun onPageSelected(position: Int) {
                currentIndex = cardIndex(position)
                updateVideoPlaybackForVisibility()
            }
        })

        bottomSection.addView(
            prosView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 20.dp
                bottomMargin = 20.dp
                leftMargin = 24.dp
                rightMargin = 24.dp
            }
        )

        contentContainer.addView(
            pagerHost,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        contentContainer.addView(
            bottomSection,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        scrollView.clipToPadding = false
        scrollView.addView(contentContainer, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            bottomReversedCorner,
            ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_CONSTRAINT)
        )
        view.addView(upgradeButton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 50.dp))
        view.addView(closeButton, ConstraintLayout.LayoutParams(40.dp, 40.dp))

        view.setConstraints {
            toStart(upgradeButton, 16f)
            toEnd(upgradeButton, 16f)

            topToTop(
                bottomReversedCorner,
                upgradeButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCorner)
        }

        bindFixedContent(0)
        updateTheme()

        // Prefetch every card's video so all tabs play instantly (and offline).
        MintCardVideoCache.precache(context, orderedTypes.map { it.type })
        WalletCore.registerObserver(this)
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        if (navigationController?.isSwipingBack == true) return
        window?.forceStatusBarLight = true
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        window?.forceStatusBarLight = true
    }

    override fun viewDidEnterForeground() {
        super.viewDidEnterForeground()
        window?.forceStatusBarLight = true
        bindButton(boundButtonIndex)
    }

    override fun viewWillDisappear() {
        countdownHandler.removeCallbacks(countdownTick)
        super.viewWillDisappear()
        window?.forceStatusBarLight = null
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AccountConfigReceived,
            WalletEvent.TokensChanged -> {
                cardsInfo = MintCardHelpers.cardsInfo(displayedAccount.accountId ?: "")
                updateCardInfoViews(scrollPosition, scrollOffset, force = true)
                bindButton(boundButtonIndex)
            }

            is WalletEvent.AccountWillChange,
            is WalletEvent.AccountChangedInApp,
            WalletEvent.AccountChangeAborted -> bindButton(boundButtonIndex)

            else -> {}
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottom = navigationController?.bottomInset ?: 0
        val top = navigationController?.getSystemBars()?.top ?: 0
        sideStartInset = systemBarStartInset
        sideEndInset = systemBarEndInset
        pagerHost.requestLayout()
        bottomSection.setPaddingRelative(sideStartInset, 0, sideEndInset, 0)
        cardInfoOverlay.setPaddingRelative(
            16.dp + sideStartInset,
            0,
            16.dp + sideEndInset,
            0
        )
        view.setConstraints {
            toBottomPx(upgradeButton, BUTTON_GAP_DP.dp + bottom)
            toTopPx(closeButton, top + 8.dp)
            toStartPx(upgradeButton, 16.dp + systemBarStartInset)
            toEndPx(upgradeButton, 16.dp + systemBarEndInset)
            toEndPx(closeButton, 8.dp + systemBarEndInset)
        }
        scrollView.setPaddingRelative(
            0,
            0,
            0,
            BUTTON_GAP_DP.dp + BUTTON_HEIGHT_DP.dp + BUTTON_GAP_DP.dp + bottom
        )
        bottomReversedCorner.setSideInsets(
            systemBarStartInset.toFloat(),
            systemBarEndInset.toFloat()
        )
    }

    override fun onDestroy() {
        countdownHandler.removeCallbacks(countdownTick)
        super.onDestroy()
        Handler(Looper.getMainLooper()).post {
            releaseAllVideos()
        }
    }

    private fun releaseAllVideos() {
        val rv = pagerRecyclerView ?: return
        for (i in 0 until rv.childCount) {
            ((rv.getChildAt(i)) as? MintCardPosterView)?.releaseVideo()
        }
    }

    private var boundButtonIndex = 0
    private var scrollPosition = initialPage
    private var scrollOffset = 0f
    private var cardInfoPage = Int.MIN_VALUE

    private fun updateCardInfoViews(position: Int, offset: Float, force: Boolean = false) {
        if (force || cardInfoPage != position) {
            for (i in cardInfoViews.indices) {
                val info = orderedTypes[cardIndex(position + i)]
                cardInfoViews[i].configure(
                    LocaleController.getString(info.displayNameKey),
                    cardsInfo?.get(info.type),
                    isComingSoon = cardsInfo == null
                )
            }
            cardInfoPage = position
        }
        cardInfoViews[0].alpha = 1f - offset
        cardInfoViews[1].alpha = offset
        val visibleIndex = if (offset < 0.5f) 0 else 1
        cardInfoViews.forEachIndexed { index, infoView ->
            infoView.importantForAccessibility = if (index == visibleIndex) {
                View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
            } else {
                View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
        }
    }

    private fun applyScrollProgress(position: Int, offset: Float) {
        scrollPosition = position
        scrollOffset = offset
        updateCardInfoViews(position, offset)
        val fromType = orderedTypes[cardIndex(position)].type
        val toType = orderedTypes[cardIndex(position + 1)].type

        val accent = lerpColor(
            MintCardTypeInfo.accentColor(fromType),
            MintCardTypeInfo.accentColor(toType),
            offset
        )
        prosView.setAccentColor(accent)

        val bottomColor = lerpColor(
            bottomSectionBaseColor(fromType),
            bottomSectionBaseColor(toType),
            offset
        )
        applyBaseColor(bottomColor)

        prosView.setBlackProgress(
            lerpFloat(blackProgress(fromType), blackProgress(toType), offset)
        )

        val targetIndex = cardIndex(position + if (offset > 0.5f) 1 else 0)
        if (targetIndex != boundButtonIndex) {
            boundButtonIndex = targetIndex
            bindButton(targetIndex)
        }
        updateButtonTint()
    }

    private fun updateButtonTint() {
        val cardInfo = cardsInfo?.get(orderedTypes[boundButtonIndex].type)
        if (cardInfo?.mintStartsAtMillis != null) {
            upgradeButton.customTint = Color.rgb(142, 142, 147)
            upgradeButton.customTextColor = Color.WHITE
            return
        }
        val fromType = orderedTypes[cardIndex(scrollPosition)].type
        val toType = orderedTypes[cardIndex(scrollPosition + 1)].type
        upgradeButton.customTint = lerpColor(
            MintCardTypeInfo.accentColor(fromType),
            MintCardTypeInfo.accentColor(toType),
            scrollOffset
        )
        upgradeButton.customTextColor = lerpColor(
            buttonTextColor(fromType),
            buttonTextColor(toType),
            scrollOffset
        )
    }

    private fun bottomSectionBaseColor(type: ApiMtwCardType): Int =
        if (type == ApiMtwCardType.BLACK) Color.BLACK else WColor.Background.color

    private fun buttonTextColor(type: ApiMtwCardType): Int =
        if (type == ApiMtwCardType.BLACK) Color.BLACK else WColor.TextOnTint.color

    private fun applyBaseColor(color: Int) {
        view.setBackgroundColor(color)
        bottomSection.setBackgroundColor(color)
        bottomReversedCorner.setBlurOverlayColor(color)
    }

    private fun blackProgress(type: ApiMtwCardType): Float =
        if (type == ApiMtwCardType.BLACK) 1f else 0f

    private fun lerpFloat(a: Float, b: Float, t: Float): Float = a + (b - a) * t

    private fun bindFixedContent(position: Int) {
        val info = orderedTypes[position]
        val accent = MintCardTypeInfo.accentColor(info.type)
        prosView.setAccentColor(accent)
        upgradeButton.customTint = accent
        upgradeButton.customTextColor = buttonTextColor(info.type)
        applyBaseColor(bottomSectionBaseColor(info.type))
        prosView.setBlackProgress(blackProgress(info.type))
        boundButtonIndex = position
        bindButton(position)
    }

    private fun bindButton(position: Int) {
        countdownHandler.removeCallbacks(countdownTick)
        val info = orderedTypes[position]
        val cardInfo = cardsInfo?.get(info.type)
        val accountId = displayedAccount.accountId
        val price = cardInfo?.price
        val mycoin = MintCardHelpers.mycoin
        val startsAt = cardInfo?.mintStartsAtMillis
        upgradeButton.isClickable = startsAt == null
        if (cardsInfo == null) {
            upgradeButton.isGone = false
            upgradeButton.setText(LocaleController.getString("Coming soon"))
            upgradeButton.isEnabled = false
        } else if (startsAt != null) {
            val remaining = ((startsAt - System.currentTimeMillis() + 999) / 1000).coerceAtLeast(0)
            val time = String.format(
                Locale.US,
                "%02d:%02d:%02d",
                remaining / 3600,
                remaining / 60 % 60,
                remaining % 60
            )
            upgradeButton.isGone = false
            upgradeButton.setText(
                LocaleController.getString("Mint starts in %time%").replace("%time%", time),
                isAnimated = false
            )
            upgradeButton.isEnabled = true
            if (!isDisappeared && remaining > 0) {
                countdownHandler.postDelayed(countdownTick, 1000)
            }
        } else if (cardInfo != null && !cardInfo.isAvailable && !allowSoldOutUpgrade) {
            upgradeButton.isGone = false
            upgradeButton.setText(LocaleController.getString("This card has been sold out"))
            upgradeButton.isEnabled = false
        } else if (price != null && price > 0.0) {
            upgradeButton.isGone = false
            val priceString = price.toString(mycoin?.decimals ?: 9, "", 2, false) ?: ""
            val currency = mycoin?.symbol ?: "MY"
            upgradeButton.setText(
                LocaleController.getString("Upgrade for %amount% %currency%")
                    .replace("%amount%", "\u200E$priceString $currency\u200F")
                    .replace("%currency%", "")
            )
            upgradeButton.isEnabled =
                isDisplayedAccountActive(accountId) &&
                (cardInfo.isAvailable || allowSoldOutUpgrade) &&
                mycoin != null
        } else {
            upgradeButton.isGone = true
        }
        updateButtonTint()
    }

    private fun isDisplayedAccountActive(accountId: String?): Boolean = accountId != null &&
        WalletCore.nextAccountId == null &&
        AccountStore.activeAccountId == accountId

    private val pagerRecyclerView: RecyclerView?
        get() = viewPager.getChildAt(0) as? RecyclerView

    private fun updateVideoPlaybackForVisibility() {
        val rv = pagerRecyclerView ?: return
        val pagerWidth = rv.width
        if (pagerWidth <= 0) return
        for (i in 0 until rv.childCount) {
            val poster = rv.getChildAt(i) as? MintCardPosterView ?: continue
            val fullyOffscreen = poster.right <= 0 || poster.left >= pagerWidth
            if (fullyOffscreen) {
                poster.stopVideo()
                poster.prepareVideo()
            } else {
                poster.playVideo()
            }
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        cardInfoPage = Int.MIN_VALUE
        applyScrollProgress(viewPager.currentItem, 0f)
    }

    private inner class SlideAdapter : RecyclerView.Adapter<SlideAdapter.SlideHolder>() {

        inner class SlideHolder(val poster: MintCardPosterView) :
            RecyclerView.ViewHolder(poster)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SlideHolder {
            val poster = MintCardPosterView(parent.context).apply {
                layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            }
            return SlideHolder(poster)
        }

        override fun onBindViewHolder(holder: SlideHolder, position: Int) {
            val info = orderedTypes[cardIndex(position)]
            holder.poster.configure(info.type)
        }

        override fun onViewAttachedToWindow(holder: SlideHolder) {
            if (holder.bindingAdapterPosition == viewPager.currentItem) {
                holder.poster.playVideo()
            } else {
                holder.poster.prepareVideo()
            }
        }

        override fun onViewDetachedFromWindow(holder: SlideHolder) {
            holder.poster.stopVideo()
        }

        override fun onViewRecycled(holder: SlideHolder) {
            holder.poster.releaseVideo()
        }

        override fun getItemCount(): Int = Int.MAX_VALUE
    }

    private fun onUpgradePressed(cardInfo: MCardInfo?) {
        val accountId = displayedAccount.accountId ?: return
        val account = AccountStore.accountById(accountId) ?: return
        if (!isDisplayedAccountActive(accountId)) return
        if (account.isViewOnly) {
            showAlert(
                LocaleController.getString("Error"),
                LocaleController.getString("Read-only account")
            )
            return
        }
        val mycoin = MintCardHelpers.mycoin ?: return
        cardInfo ?: return
        if (cardInfo.mintStartsAtMillis != null) return
        if (!cardInfo.isAvailable && !allowSoldOutUpgrade) return

        val enoughMycoin = MintCardHelpers.isEnoughMycoin(accountId, cardInfo, mycoin)
        val enoughToncoin = MintCardHelpers.isEnoughToncoin(accountId)

        if (enoughMycoin && enoughToncoin) {
            startMinting(account, cardInfo)
            return
        }

        if (!enoughMycoin) {
            startSwapForShortfall(accountId, cardInfo, mycoin)
            return
        }

        val tonSymbol = TokenStore.getToken(TONCOIN_SLUG)?.symbol ?: "TON"
        showAlert(
            LocaleController.getString("Insufficient Fee"),
            LocaleController.getString("Please top up your %token% balance.")
                .replace("%token%", tonSymbol)
        )
    }

    private fun startSwapForShortfall(
        accountId: String,
        cardInfo: MCardInfo,
        mycoin: org.mytonwallet.app_air.walletcore.models.MToken
    ) {
        val requiredAmount = MintCardHelpers.priceAmount(cardInfo, mycoin) ?: return
        val currentBalance = MintCardHelpers.mycoinBalance(accountId)
        val missing = (requiredAmount - currentBalance).max(BigInteger.ZERO)
        // Add 5% reserve to cover swap slippage, mirroring web SWAP_AMOUNT_RESERVE_MULTIPLIER.
        val missingWithReserve = missing * BigInteger.valueOf(105) / BigInteger.valueOf(100)
        val amountOut = missingWithReserve.toDouble() / 10.0.pow(mycoin.decimals.toDouble())

        val receivingAsset = MApiSwapAsset.from(mycoin)
        val swapVC = SwapVC(
            context,
            defaultReceivingToken = receivingAsset,
            amountIn = if (amountOut > 0) amountOut else null
        )

        val win = window ?: return
        win.dismissLastNav {
            val nav = WNavigationController(win)
            nav.setRoot(swapVC)
            win.present(nav)
        }
    }

    private val headerView: View
        get() {
            val info = orderedTypes[currentIndex]
            val maximumHeight =
                ((window?.windowView?.height ?: 0) * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO)
                    .roundToInt()
            return PasscodeHeaderSendView(
                WeakReference(this),
                maximumHeight
            ).apply {
                config(
                    Content(image = Content.Image.Empty),
                    LocaleController.getString("Confirm Upgrading"),
                    LocaleController.getString(info.displayNameKey),
                    Content.Rounding.Radius(12f.dp)
                )
            }
        }

    private fun buildTransferOptions(
        cardInfo: MCardInfo,
        enclaveToken: String
    ): MApiSubmitTransferOptions? {
        val accountId = displayedAccount.accountId ?: return null
        val mycoin = MintCardHelpers.mycoin ?: return null
        val amount = MintCardHelpers.priceAmount(cardInfo, mycoin) ?: return null
        return MApiSubmitTransferOptions(
            accountId = accountId,
            toAddress = MINT_CARD_ADDRESS,
            payload = ApiTransferPayload.Comment(MINT_CARD_COMMENT),
            tokenAddress = mycoin.tokenAddress,
            enclaveToken = enclaveToken,
            amount = amount
        )
    }

    private var flowNav: WNavigationController? = null
    private var isAutoConfirmSubmitting = false

    private fun presentFlow(rootVC: WViewController) {
        val win = window ?: return
        val nav = WNavigationController(win)
        nav.setRoot(rootVC)
        flowNav = nav
        win.present(nav)
    }

    private fun startMinting(account: MAccount, cardInfo: MCardInfo) {
        val startedAt = System.currentTimeMillis()
        if (account.isHardware) {
            mintWithHardware(account, cardInfo, startedAt)
        } else {
            mintWithPassword(cardInfo, startedAt)
        }
    }

    private fun mintWithPassword(cardInfo: MCardInfo, startedAt: Long) {
        ProtectedActionAuth.confirm(
            onConfirmed = { token ->
                flowNav = null
                isAutoConfirmSubmitting = true
                view.lockView()
                upgradeButton.isLoading = true
                submitMintWithToken(cardInfo, startedAt, token)
            },
            onPasscodeRequired = { showPasscodeMint(cardInfo, startedAt) }
        )
    }

    private fun showPasscodeMint(cardInfo: MCardInfo, startedAt: Long) {
        val passcodeConfirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                headerView,
                LocaleController.getString("Confirm Upgrading"),
                showNavbarTitle = false
            ),
            task = { enclaveToken -> submitMintWithToken(cardInfo, startedAt, enclaveToken) }
        )
        presentFlow(passcodeConfirmVC)
    }

    private fun submitMintWithToken(cardInfo: MCardInfo, startedAt: Long, token: String) {
        val options = buildTransferOptions(cardInfo, token)
        if (options == null) {
            showMintSubmissionError(MBridgeError.Type.UNEXPECTED_ERROR)
            return
        }
        submitMint(options, startedAt)
    }

    private fun mintWithHardware(account: MAccount, cardInfo: MCardInfo, startedAt: Long) {
        val tonAddress = account.tonAddress ?: return
        val mycoin = MintCardHelpers.mycoin ?: return
        val options = buildTransferOptions(cardInfo, "") ?: run {
            showError(null)
            return
        }
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                tonAddress,
                signData = LedgerConnectVC.SignData.SignTransfer(
                    accountId = account.accountId,
                    transferOptions = options,
                    slug = mycoin.slug
                ),
                onDone = {
                    onMintSucceeded(startedAt)
                }
            ),
            headerView = headerView
        )
        presentFlow(ledgerConnectVC)
    }

    private fun submitMint(options: MApiSubmitTransferOptions, startedAt: Long) {
        WalletCore.call(
            ApiMethod.Transfer.SubmitTransfer(MBlockchain.ton, options)
        ) { res, err ->
            if (err != null || res == null || res.error != null) {
                if (!isDestroyed) {
                    showMintSubmissionError(
                        err?.parsed ?: MBridgeError.fromErrorName(res?.error)
                            ?: MBridgeError.Type.UNEXPECTED_ERROR
                    )
                }
                return@call
            }
            val mfaHash = res.mfaRequestHash
            if (mfaHash != null) {
                if (isDestroyed) return@call
                stopAutoConfirmProgress()
                val mfaVC = MfaActionConfirmVC(
                    context,
                    requestHash = mfaHash,
                    onFinishOverride = {
                        onMintSucceeded(startedAt)
                    }
                )
                val nav = flowNav
                if (nav != null) {
                    nav.push(mfaVC, onCompletion = {
                        nav.removePrevViewControllerOnly()
                    })
                } else {
                    presentFlow(mfaVC)
                }
                return@call
            }
            if (res.activityId.isNullOrBlank()) {
                showMintSubmissionError(MBridgeError.Type.UNEXPECTED_ERROR)
                return@call
            }
            onMintSucceeded(startedAt)
        }
    }

    private fun stopAutoConfirmProgress() {
        if (!isAutoConfirmSubmitting) return
        isAutoConfirmSubmitting = false
        view.unlockView()
        upgradeButton.isLoading = false
    }

    private fun showMintSubmissionError(error: MBridgeError) {
        stopAutoConfirmProgress()
        val passcodeVC = flowNav?.viewControllers?.lastOrNull() as? PasscodeConfirmVC
        if (passcodeVC != null) {
            passcodeVC.restartAuth()
            passcodeVC.showError(error)
        } else {
            showError(error)
        }
    }

    private fun onMintSucceeded(startedAt: Long) {
        displayedAccount.accountId?.let { accountId ->
            NftStore.setCardMinting(accountId, true)
            ActivityStore.markCardMintSubmitted(accountId, startedAt)
        }
        Haptics.play(view, HapticType.SUCCESS)
        val message = LocaleController.getString("\$mint_card_result").replace("**", "")
        val showToast = {
            ToastManager.show(
                ToastManager.Toast(
                    iconResId = R.drawable.ic_check,
                    text = message,
                    isLarge = true
                ),
                onUndelivered = { Toast.makeText(context, message, Toast.LENGTH_LONG).show() }
            )
        }
        val win = window
        if (win != null && win.navigationControllers.lastOrNull() === flowNav) {
            win.dismissNav(navigationController, animated = false)
            win.dismissLastNav(onCompletion = showToast)
        } else if (win != null && flowNav == null) {
            win.dismissLastNav(onCompletion = showToast)
        } else {
            showToast()
        }
    }

    companion object {
        private const val ARROW_FADE_DISTANCE = 0.07f
        private const val BUTTON_HEIGHT_DP = 50
        private const val BUTTON_GAP_DP = 16 // gap above and below the pinned button

        fun present(
            navigationController: WNavigationController,
            accountId: String? = AccountStore.activeAccountId
        ) {
            if (navigationController.window.topViewController is MintCardVC) return
            val nav = object : WNavigationController(
                navigationController.window,
                PresentationConfig.PreferredFullScreen
            ) {
                override val centeredWindowWidth: Int = 500.dp
            }
            nav.setRoot(MintCardVC(navigationController.context, accountId))
            navigationController.window.present(nav)
        }
    }
}
