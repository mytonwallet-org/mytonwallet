package org.mytonwallet.uihome.home

import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.webkit.URLUtil
import android.widget.FrameLayout
import android.widget.Toast
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.sqscan.screen.QrScannerDialog
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WActionBar.TitleAnimationMode
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.IHeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.TabletHeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderSpaceCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.DirectionalTouchHandler
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uireceive.BuyWithCardLauncher
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisend.send.MultisendLauncher
import org.mytonwallet.app_air.uisend.send.SellWithCardLauncher
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uistake.earn.EarnViewModel
import org.mytonwallet.app_air.uistake.earn.EarnViewModelFactory
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.uiswap.screens.cex.SwapSendAddressOutputVC
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.uitonconnect.TonConnectController
import org.mytonwallet.app_air.uiwalletconnectpay.WalletConnectPayController
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.home.views.ActivityListView
import org.mytonwallet.uihome.home.views.UpdateStatusView
import org.mytonwallet.uihome.home.views.header.HomeHeaderView
import org.mytonwallet.uihome.home.views.header.StickyHeaderView
import org.mytonwallet.uihome.home.views.header.StickyHeaderView.Mode
import org.mytonwallet.uihome.walletsTabs.WalletsTabsVC
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.absoluteValue
import kotlin.math.min
import kotlin.math.roundToInt

class HomeVC(context: Context, private val mode: MScreenMode) :
    WViewControllerWithModelStore(context),
    HomeVM.Delegate,
    ActivityListView.DataSource, ActivityListView.Delegate,
    WThemedView, WProtectedView, ISortableView {
    override val TAG = "Home"

    private val px92 = 92.dp

    override val isWideHome: Boolean
        get() = window?.isWideLayout == true

    private var appliedWideHome: Boolean? = null

    override fun wideLayoutChanged() {
        val nowWide = isWideHome
        if (appliedWideHome == nowWide) return
        appliedWideHome = nowWide

        swapActionsView(nowWide)
        if (nowWide) {
            (phoneHeaderView.parent as? ViewGroup)?.removeView(phoneHeaderView)
            stickyHeaderView.updateStatusView.setAppearance(
                isShowing = false,
                animated = false
            )
            stickyHeaderView.update(stickyHeaderViewMode, null, false)
            allActivityListViews.forEach {
                it.recyclerView.removeOverScroll()
            }
        } else {
            if (phoneHeaderView.parent != view) {
                (phoneHeaderView.parent as? ViewGroup)?.removeView(phoneHeaderView)
                view.addView(phoneHeaderView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            }
            phoneHeaderView.doOnPreDraw { restorePhoneHeaderState() }
            applyHeaderCards(false)
            updateBalance(false)
            updateAccountName(homeVM.showingAccount?.name ?: "", false)
            stickyHeaderView.update(
                stickyHeaderViewMode,
                UpdateStatusView.State.Updated(homeVM.showingAccount?.name ?: ""),
                false
            )
        }
        allActivityListViews.forEach {
            it.onWideLayoutChanged()
        }
        if (!nowWide)
            moveActionsViewToCell()
        rvMode = if (nowWide) recyclerViewModeValue() else phoneHeaderView.mode
        if (!nowWide) {
            allActivityListViews.forEach { it.updateHeaderHeights() }
        }
    }

    private fun restorePhoneHeaderState() {
        if (window?.isConfiguring == true) {
            phoneHeaderView.post { restorePhoneHeaderState() }
            return
        }
        val verticalOffset = currentActivityListView.recyclerView.computeVerticalScrollOffset()
        if (verticalOffset > 0)
            phoneHeaderView.updateScroll(verticalOffset.coerceAtLeast(0), 0f, false)
        rvMode = phoneHeaderView.mode
        if (phoneHeaderView.mode == HomeHeaderView.Mode.Collapsed) {
            allActivityListViews.forEach {
                it.recyclerView.setupOverScroll()
                it.recyclerView.setMaxOverscrollOffset(
                    if (phoneHeaderView.canExpandForHeight) phoneHeaderView.diffPx else 0f
                )
            }
        }
    }

    private fun swapActionsView(wide: Boolean) {
        _actionsView?.onDestroy()
        _actionsView?.let { (it.asCell.parent as? ViewGroup)?.removeView(it.asCell) }
        _actionsView = null
        if (!wide) {
            actionsView.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
            updateActionsAlpha()
        }
    }

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar: Boolean
        get() {
            return window?.isWideLayout == true || mode is MScreenMode.SingleWallet
        }

    override val isSwipeBackAllowed = false
    override val isEdgeSwipeBackAllowed = mode is MScreenMode.SingleWallet

    override val displayedAccount: DisplayedAccount
        get() {
            return DisplayedAccount(
                homeVM.showingAccount?.accountId,
                mode is MScreenMode.SingleWallet
            )
        }
    // override val shouldMonitorFrames = true

    private val homeVM by lazy {
        HomeVM(mode, this)
    }

    private var rvMode = HomeHeaderView.DEFAULT_MODE

    private val earnToncoinViewModel by lazy {
        ViewModelProvider(
            window!!,
            EarnViewModelFactory(TONCOIN_SLUG)
        )[EarnViewModel.alias(TONCOIN_SLUG), EarnViewModel::class.java]
    }
    private val earnMycoinViewModel by lazy {
        ViewModelProvider(
            window!!,
            EarnViewModelFactory(MYCOIN_SLUG)
        )[EarnViewModel.alias(MYCOIN_SLUG), EarnViewModel::class.java]
    }

    private val tonConnectController by lazy {
        TonConnectController(window!!)
    }

    private val walletConnectPayController by lazy {
        WalletConnectPayController(window!!)
    }

    private fun isSellAllowed(): Boolean {
        return homeVM.showingAccount?.supportsBuyWithCard == true// && ConfigStore.isLimited != true
    }

    private var prevActivityListView =
        ActivityListView(
            context,
            WeakReference(this),
            WeakReference(this)
        ).apply {
            isInvisible = true
        }
    private var currentActivityListView =
        ActivityListView(
            context,
            WeakReference(this),
            WeakReference(this)
        )
    private var nextActivityListView =
        ActivityListView(
            context,
            WeakReference(this),
            WeakReference(this)
        ).apply {
            isInvisible = true
        }
    private val allActivityListViews =
        listOf(prevActivityListView, currentActivityListView, nextActivityListView)
    private val activityListViewsContainer = WFrameLayout(context).apply {
        addView(prevActivityListView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(currentActivityListView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(nextActivityListView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private val headerCell: HeaderSpaceCell
        get() {
            return currentActivityListView.headerCell
        }
    private val actionsCell: WCell
        get() {
            return currentActivityListView.actionsCell
        }
    private var swipeItemsOffset = 0
    private var swipeFadeInPercent = 1f
    private var actionsLayoutFadeInPercent = 0f

    private val touchHandler by lazy {
        DirectionalTouchHandler(
            verticalView = activityListViewsContainer,
            horizontalView = phoneHeaderView,
            interceptedViews = listOf(),
            interceptedByVerticalScrollViews = listOf(),
            isDirectionalScrollAllowed = { isVertical, event ->
                isVertical || (event?.y ?: 0f) < activityListViewHeaderHeight()
            },
            horizontalScrollAngle = 70.0
        ).apply {
            onScrollDetected = { isVertical ->
                if (isVertical) {
                    moveHeaderViewToCell()
                } else {
                    moveHeaderViewToParent()
                }
            }
            onScrollEnd = { wasVertical ->
                if (!wasVertical && phoneHeaderView.mode == HomeHeaderView.Mode.Expanded) {
                    moveHeaderViewToCell()
                }
            }
        }
    }
    override val view: ContainerView by lazy {
        object : ContainerView(WeakReference(this)) {
            private var isPassingToDirectionalTouchHandler = false
            override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
                if (ev.action == MotionEvent.ACTION_DOWN) {
                    isPassingToDirectionalTouchHandler =
                        phoneHeaderView.mode == HomeHeaderView.Mode.Expanded && ev.y < activityListViewHeaderHeight()
                    if (!isPassingToDirectionalTouchHandler) {
                        if (phoneHeaderView.mode == HomeHeaderView.Mode.Expanded) moveHeaderViewToCell()
                    }
                }
                return if (isPassingToDirectionalTouchHandler)
                    touchHandler.dispatchTouch(view, ev) ?: super.dispatchTouchEvent(ev)
                else
                    super.dispatchTouchEvent(ev)
            }
        }
    }

    private val stickyHeaderView = StickyHeaderView(context, mode) { onClick(it) }
    private val stickyHeaderViewMode: Mode
        get() {
            return when {
                isWideHome -> Mode.WideScreen
                phoneHeaderView.mode == HomeHeaderView.Mode.Expanded -> Mode.Expanded
                else -> Mode.Collapsed
            }
        }

    var panelHeaderView: HomeHeaderView? = null
        set(value) {
            field = value
            value?.updateMintIconVisibility()
            value?.updatePromotion()
        }

    val overrideAccountIds: Array<String>?
        get() = (mode as? MScreenMode.SingleWallet)?.let { arrayOf(it.accountId) }

    val headerView: HomeHeaderView
        get() {
            return if (isWideHome) (panelHeaderView ?: phoneHeaderView) else phoneHeaderView
        }
    override val phoneHeaderView: HomeHeaderView by lazy {
        val v = HomeHeaderView(
            window!!,
            overrideAccountIds,
            stickyHeaderView.updateStatusView,
            onModeChange = { animated ->
                if (animated) {
                    currentActivityListView.recyclerView.setBounceBackSkipValue(if (rvMode == phoneHeaderView.mode) 0 else phoneHeaderView.diffPx.toInt())
                } else {
                    headerModeChanged()
                }
                stickyHeaderView.update(
                    stickyHeaderViewMode,
                    if (stickyHeaderView.updateStatusView.state != null &&
                        stickyHeaderView.updateStatusView.state !is UpdateStatusView.State.Updated
                    )
                        stickyHeaderView.updateStatusView.state!!
                    else UpdateStatusView.State.Updated(homeVM.showingAccount?.name ?: ""),
                    true
                )
            },
            onExpandPressed = {
                expand()
                allActivityListViews.forEach {
                    it.recyclerView.removeOverScroll()
                }
            },
            onHeaderPressed = {
                scrollToTop()
            },
            onHorizontalScrollListener = { progress, verticalOffset, actionsFadeInPercent ->
                applyHorizontalSwipe(progress, verticalOffset, actionsFadeInPercent)
            },
            wideHomeHeaderView = false
        )
        v.apply {
            background = null
            onLayoutRecalculated = {
                if (mode == HomeHeaderView.Mode.Collapsed) {
                    currentActivityListView.recyclerView.setMaxOverscrollOffset(
                        if (canExpandForHeight) diffPx else 0f
                    )
                }
            }
        }
    }

    private fun createActionsView(wide: Boolean): IHeaderActionsView {
        return if (wide) {
            TabletHeaderActionsView(
                context,
                TabletHeaderActionsView.headerTabs(context, true),
                onClick = {
                    if (currentActivityListView.skeletonVisible)
                        return@TabletHeaderActionsView
                    onClick(HeaderActionsView.Identifier.valueOf(it.name))
                },
            ).apply {
                onHorizontalScroll = { updateTopBlurHorizontalPadding() }
            }
        } else {
            HeaderActionsView(
                context,
                HeaderActionsView.headerTabs(context, true),
                onClick = {
                    if (currentActivityListView.skeletonVisible)
                        return@HeaderActionsView
                    onClick(it)
                },
            ).apply {
                setPadding(0, 0, 0, 16.dp)
            }
        }
    }

    private var _actionsView: IHeaderActionsView? = null
    private var actionsView: IHeaderActionsView
        get() = _actionsView ?: createActionsView(isWideHome).also {
            _actionsView = it
        }
        set(value) {
            _actionsView = value
        }
    private val actionsCellView: WCell get() = actionsView.asCell

    private fun openSellWithCard(tokenSlug: String) {
        if (!isSellAllowed()) return
        val activeAccount = headerView.centerAccount ?: homeVM.showingAccount ?: return
        SellWithCardLauncher.launch(
            caller = WeakReference(this),
            account = activeAccount,
            tokenSlug = tokenSlug,
        )
    }

    override fun onHeaderAction(identifier: HeaderActionsView.Identifier) {
        onClick(identifier)
    }

    private fun onClick(identifier: HeaderActionsView.Identifier) {
        when (identifier) {
            HeaderActionsView.Identifier.BACK -> {
                navigationController?.pop()
            }

            HeaderActionsView.Identifier.LOCK_APP -> {
                WalletContextManager.delegate?.get()?.lockScreen()
            }

            HeaderActionsView.Identifier.TOGGLE_SENSITIVE_DATA_PROTECTION -> {
                WGlobalStorage.toggleSensitiveDataHidden()
            }

            HeaderActionsView.Identifier.BUY -> {
                val chain = homeVM.showingAccount?.firstChain ?: return
                BuyWithCardLauncher.launch(WeakReference(this), chain.name)
            }

            HeaderActionsView.Identifier.RECEIVE -> {
                val receiveVC = ReceiveVC.createIfAvailable(
                    context,
                    homeVM.showingAccount?.firstChain
                ) ?: return
                val navVC = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(receiveVC)
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SEND -> {
                val navVC = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(SendVC(context))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SELL -> {
                openSellWithCard(TONCOIN_SLUG)
            }

            HeaderActionsView.Identifier.MULTISEND -> {
                MultisendLauncher.launch(this)
            }

            HeaderActionsView.Identifier.SWAP -> {
                val navVC = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(SwapVC(context))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCAN_QR -> {
                if (currentActivityListView.skeletonVisible)
                    return
                QrScannerDialog.build(context) { qr ->
                    for (blockchain in MBlockchain.supportedChains) {
                        if (blockchain.isValidAddress(qr)) {
                            val navVC = WNavigationController(
                                window!!,
                                WNavigationController.PresentationConfig.PreferredFullScreen
                            )
                            navVC.setRoot(
                                SendVC(
                                    context, blockchain.nativeSlug, SendVC.InitialValues(
                                        address = qr
                                    )
                                )
                            )
                            window?.present(navVC)
                            return@build
                        }
                    }
                    val validDeeplink = WalletContextManager.delegate?.get()?.handleDeeplink(
                        qr,
                        DeeplinkOpenSource.QR_SCAN
                    )
                    if (validDeeplink == true)
                        return@build
                    if (URLUtil.isValidUrl(qr)) {
                        tonConnectController.connectStart(qr)
                        return@build
                    }
                    Toast.makeText(
                        context,
                        LocaleController.getString("This QR Code is not supported"),
                        Toast.LENGTH_SHORT
                    ).show()
                }.show()
            }

            HeaderActionsView.Identifier.EARN -> {
                val canShowEarn =
                    homeVM.isGeneralDataAvailable || AccountStore.activeAccount?.isNew == true
                if (!canShowEarn) return

                val activeStakingTokenSlug = AccountStore.stakingData?.activeStakingTokenSlug()
                val navVC = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                if (activeStakingTokenSlug != null) {
                    navVC.setRoot(EarnRootVC(context, tokenSlug = activeStakingTokenSlug))
                } else {
                    navVC.setRoot(StakingVC(context, TONCOIN_SLUG, StakingViewModel.Mode.STAKE))
                }
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCROLL_TO_TOP -> {
                scrollToTop()
            }

            HeaderActionsView.Identifier.WALLET_SETTINGS -> {
                if (phoneHeaderView.mode == HomeHeaderView.Mode.Collapsed)
                    return
                val navVC = WNavigationController(
                    window!!, WNavigationController.PresentationConfig(
                        style = WNavigationController.PresentationStyle.BottomSheet
                    )
                )
                navVC.setRoot(
                    WalletsTabsVC(
                        context,
                        WGlobalStorage.getAccountSelectorViewMode() ?: MWalletSettingsViewMode.GRID
                    )
                )
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.WALLET_MENU -> {
                val account = headerView.centerAccount ?: homeVM.showingAccount ?: return
                WalletNameMenuHelper.present(
                    viewController = this,
                    anchor = stickyHeaderView.updateStatusView,
                    account = account,
                    onManageWallets = {
                        onClick(HeaderActionsView.Identifier.WALLET_SETTINGS)
                    }
                )
            }

            HeaderActionsView.Identifier.EDIT -> {
                // Wide-screen home-assets edit/reorder entry point (sticky header Edit button).
                startSorting()
            }

            else -> {
                throw Error()
            }
        }
    }

    override val topBlurView: View
        get() = topBlurReversedCornerView

    private val topBlurReversedCornerView = ReversedCornerView(
        context, ReversedCornerView.Config(blurRootView = activityListViewsContainer)
    ).apply {
        isGone = true
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(activityListViewsContainer, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            topBlurReversedCornerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    HomeHeaderView.navDefaultHeight +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
            )
        )
        if (!isWideHome)
            view.addView(phoneHeaderView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(stickyHeaderView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.setConstraints {
            toTopPx(stickyHeaderView, navigationController?.getSystemBars()?.top ?: 0)
            toCenterX(stickyHeaderView)
            toTop(topBlurReversedCornerView)
        }

        view.alpha = 0f
        view.post {
            moveActionsViewToCell()
            view.fadeIn()
            if (isWideHome)
                stickyHeaderView.update(Mode.WideScreen, null, false)
            else
                allActivityListViews.forEach {
                    it.recyclerView.setMaxOverscrollOffset(
                        if (phoneHeaderView.canExpandForHeight) phoneHeaderView.diffPx else 0f
                    )
                }
        }

        WalletCore.doOnBridgeReady {
            homeVM.setupObservers()
            updateHeaderCards(false)
            updateBalance(false)
            configureAccountViews(shouldLoadNewWallets = true, skipSkeletonOnCache = false)
        }

        if (mode == MScreenMode.Default) {
            tonConnectController.onCreate()
            walletConnectPayController.onCreate()
        }

        updateTheme()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        topBlurReversedCornerView.resumeBlurring()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        phoneHeaderView.viewWillDisappear()
    }

    override fun didSetupViews() {
        super.didSetupViews()
        setBottomBlurSeparator(false)
    }

    private fun expand() {
        if (isWideHome) return
        if (phoneHeaderView.mode == HomeHeaderView.Mode.Expanded)
            return
        if (!phoneHeaderView.canExpandForHeight)
            return
        currentActivityListView.expandingProgrammatically = true
        topBlurReversedCornerView.pauseBlurring(false)
        topBlurReversedCornerView.isGone = true
        currentActivityListView.recyclerView.scrollToOverScroll(
            (phoneHeaderView.expandedContentHeight -
                phoneHeaderView.collapsedHeight).toInt()
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        homeVM.destroy()
        if (mode is MScreenMode.SingleWallet &&
            WGlobalStorage.temporaryAddedAccountIds.contains(mode.accountId)
        )
            homeVM.removeTemporaryAccount()
        _actionsView?.onDestroy()
        phoneHeaderView.onDestroy()
        if (mode == MScreenMode.Default) {
            walletConnectPayController.onDestroy()
            tonConnectController.onDestroy()
        }
        allActivityListViews.forEach {
            it.onDestroy()
        }
        currentActivityListView.assetsCell?.onDestroy()
    }

    // Header view is moved to recycler-view cell, to keep over-scroll effect
    fun moveHeaderViewToCell() {
        if (isWideHome) return
        if (phoneHeaderView.parent != headerCell &&
            currentActivityListView.recyclerView.computeVerticalScrollOffset() == 0 &&
            phoneHeaderView.mode == HomeHeaderView.Mode.Expanded
        ) {
            (phoneHeaderView.parent as? ViewGroup)?.removeView(phoneHeaderView)
            headerCell?.addView(phoneHeaderView)
            headerCell?.setConstraints {
                toCenterX(phoneHeaderView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
        }
    }

    // Header view is moved to parent view, to cross-fade content without effecting header
    private fun moveHeaderViewToParent() {
        if (isWideHome) return
        if (phoneHeaderView.parent != view) {
            (phoneHeaderView.parent as? ViewGroup)?.removeView(phoneHeaderView)
            view.addView(
                phoneHeaderView,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    headerCell?.height ?: WRAP_CONTENT
                )
            )
            sortViews()
        }
    }

    // Header view is moved to recycler-view cell whenever user overscroll, to keep over-scroll effect
    private fun moveActionsViewToCell() {
        if (isWideHome) return
        actionsView.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
        view.clipChildren = true
        view.post {
            val actionsCellView = actionsCellView
            val actionsCell = actionsCell ?: return@post
            for (i in actionsCell.childCount - 1 downTo 0) {
                val child = actionsCell.getChildAt(i)
                if (child !== actionsCellView) actionsCell.removeViewAt(i)
            }
            if (actionsCellView.parent != actionsCell) {
                (actionsCellView.parent as? ViewGroup)?.removeView(actionsCellView)
                actionsCell.addView(
                    actionsCellView,
                    FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
            }
        }
    }

    // Actions view is moved to parent view, to cross-fade content without effecting this view
    private fun moveActionsViewToParent() {
        if (isWideHome) return
        actionsView.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
        val actionsCellView = actionsCellView
        if (actionsCellView.parent != view) {
            (actionsCellView.parent as? ViewGroup)?.removeView(actionsCellView)
            view.addView(
                actionsCellView,
                FrameLayout.LayoutParams(
                    view.width - ViewConstants.HORIZONTAL_PADDINGS.dp * 2,
                    HeaderActionsView.HEIGHT.dp
                )
            )
            view.clipChildren = true
            view.setConstraints {
                toCenterX(actionsCellView)
                toTopPx(actionsCellView, phoneHeaderView.height)
            }
        }
    }

    // Sort views in hierarchy to keep all the buttons clickable
    private fun sortViews() {
        if (rvMode == HomeHeaderView.Mode.Expanded) {
            stickyHeaderView.bringToFront()
            navigationBar?.bringToFront()
        } else {
            phoneHeaderView.bringToFront()
            if (stickyHeaderView.isInActionMode) {
                stickyHeaderView.bringToFront()
            }
        }
    }

    fun applyHorizontalSwipe(progress: Float, verticalOffset: Int, actionsFadeInPercent: Float) {
        if (currentActivityListView.isInvisible)
            currentActivityListView.isInvisible = false
        currentActivityListView.updateAlpha(1 - abs(progress))
        if (progress == 0f) {
            actionsCellView.translationY = 0f
            view.post {
                configureActivityLists(
                    shouldLoadNewWallets = true,
                    skipSkeletonOnCache = true
                )
                moveActionsViewToCell()
            }
        } else {
            moveActionsViewToParent()
            actionsCellView.translationY = swipeItemsOffset.toFloat()
            endSorting()
        }
        this.swipeFadeInPercent = actionsFadeInPercent
        swipeItemsOffset = verticalOffset
        currentActivityListView.updateHeaderHeights()
        if (progress > 0.02) {
            nextActivityListView.isInvisible = false
            nextActivityListView.updateAlpha(progress)
            nextActivityListView.updateHeaderHeights()
        } else {
            nextActivityListView.updateAlpha(0f)
            nextActivityListView.isInvisible = true
        }
        if (progress < -0.02) {
            prevActivityListView.isInvisible = false
            prevActivityListView.updateAlpha(-progress)
            prevActivityListView.updateHeaderHeights()
        } else {
            prevActivityListView.updateAlpha(0f)
            prevActivityListView.isInvisible = true
        }
        updateActionsAlpha()
    }

    override fun updateScroll(dy: Int, velocity: Float?, isGoingBack: Boolean) {
        if (isWideHome) {
            if (dy > 1) {
                resumeBlurViews()
            } else if (currentActivityListView.recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                pauseBlurViews()
            }
            actionsLayoutFadeInPercent = 1f
            updateActionsAlpha()
            updateTopBlurHorizontalPadding()
            return
        }
        if (dy > 1) { // Ignore 1 pixel to prevent ui glitches
            if (phoneHeaderView.mode == HomeHeaderView.Mode.Collapsed) {
                resumeBlurViews()
                moveHeaderViewToParent()
            }
        } else {
            if (currentActivityListView.recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE ||
                currentActivityListView.recyclerView.getOverScrollOffset() > 0
            ) {
                pauseBlurViews()
            }
        }
        val scrollY =
            dy - (if (rvMode == HomeHeaderView.Mode.Expanded) phoneHeaderView.diffPx else 0f).roundToInt()
        // Do NOT accept negative scrollY values if user is not dragging anymore and dy >= 0, to prevent ui jumps/glitches.
        val acceptNegativeScrollY =
            dy < 0 ||
                phoneHeaderView.mode == HomeHeaderView.Mode.Expanded ||
                currentActivityListView.recyclerView.scrollState == RecyclerView.SCROLL_STATE_DRAGGING
        if (!acceptNegativeScrollY && scrollY < 0) {
            currentActivityListView.scrollEnded(0)
            currentActivityListView.recyclerView.stopScroll()
            currentActivityListView.recyclerView.scrollTo(0, 0)
        }
        if (!isWideHome && window?.isConfiguring != true) {
            phoneHeaderView.updateScroll(
                if (acceptNegativeScrollY) scrollY else scrollY.coerceAtLeast(0),
                velocity,
                isGoingBack
            )
            if (phoneHeaderView.parent == headerCell) {
                phoneHeaderView.y = dy.toFloat()
            } else {
                phoneHeaderView.y = 0f
            }
        }

        actionsLayoutFadeInPercent =
            1 - (if (scrollY > px92) (scrollY - px92) / px92.toFloat() else 0f).coerceIn(0f, 1f)
        updateActionsAlpha()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        currentActivityListView.scrollToTop()
    }

    private val pausedBlurViews: Boolean
        get() {
            return !topBlurReversedCornerView.isPlaying &&
                (bottomReversedCornerView?.let { !it.isPlaying }
                    ?: navigationController?.tabBarController?.pausedBlurViews
                    ?: false)
        }

    override fun pauseBlurViews() {
        if (rvMode == HomeHeaderView.Mode.Expanded ||
            phoneHeaderView.mode == HomeHeaderView.Mode.Expanded
        ) {
            if (pausedBlurViews)
                return
            topBlurReversedCornerView.pauseBlurring(false)
            topBlurReversedCornerView.isGone = true
            bottomReversedCornerView?.pauseBlurring()
            if (navigationController?.tabBarController?.activeNavigationController == navigationController)
                navigationController?.tabBarController?.pauseBlurring()
        }
    }

    private val resumedBlurViews: Boolean
        get() {
            return topBlurReversedCornerView.isVisible &&
                topBlurReversedCornerView.isPlaying &&
                (bottomReversedCornerView?.isPlaying
                    ?: navigationController?.tabBarController?.pausedBlurViews?.let { !it }
                    ?: false)
        }

    private fun resumeBlurViews() {
        if (resumedBlurViews)
            return
        topBlurReversedCornerView.isGone = false
        topBlurReversedCornerView.resumeBlurring()
        resumeBottomBlurViews()
    }

    override fun resumeBottomBlurViews() {
        bottomReversedCornerView?.resumeBlurring()
        navigationController?.tabBarController?.resumeBlurring()
    }

    override fun onTopItemHorizontalScroll() {
        updateTopBlurHorizontalPadding()
    }

    private var minHeaderHeight =
        ((navigationController?.getSystemBars()?.top ?: 0) + HomeHeaderView.navDefaultHeight)

    private fun updateTopReversedCornerViewHeight() {
        topBlurReversedCornerView.updateLayoutParams {
            height = (navigationController?.getSystemBars()?.top ?: 0) +
                HomeHeaderView.navDefaultHeight +
                ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        topBlurReversedCornerView.alpha = 1f
        activityListViewsContainer.setBackgroundColor(WColor.SecondaryBackground.color)
        allActivityListViews.forEach {
            it.updateTheme()
        }
        updateTopReversedCornerViewHeight()
        currentActivityListView.assetsCell?.updateSegmentItemsTheme()
        if (phoneHeaderView.parent is WCell)
            phoneHeaderView.updateTheme()
        if (!isWideHome && actionsCellView.parent is WCell)
            actionsView.updateTheme()
    }

    // Configure lists
    var renderedAccounts = ""
    private fun configureActivityLists(
        shouldLoadNewWallets: Boolean,
        skipSkeletonOnCache: Boolean
    ) {
        val activeAccount = headerView.centerAccount ?: homeVM.showingAccount ?: return
        homeVM.loadedAccountId = activeAccount.accountId
        val accountIds = WGlobalStorage.accountIds()
        val activeAccountIndex = accountIds.indexOf(activeAccount.accountId)
        val prevAccountId = accountIds.getOrNull(activeAccountIndex - 1)
        val nextAccountId = accountIds.getOrNull(activeAccountIndex + 1)
        if (shouldLoadNewWallets) {
            val newRenderedAccounts =
                "$prevAccountId${activeAccount.accountId}$nextAccountId"
            if (renderedAccounts == newRenderedAccounts)
                return
            renderedAccounts = newRenderedAccounts
        }

        // Recycle the activity list views to prevent unnecessary `configure` calls
        val activityListViewsCopy =
            mutableListOf(
                prevActivityListView,
                currentActivityListView,
                nextActivityListView
            )

        fun getViewForAccountId(id: String?): ActivityListView<HomeVC>? {
            return activityListViewsCopy.firstOrNull { activityListView ->
                activityListView.showingAccountId == id
            }
        }

        val prevView = getViewForAccountId(prevAccountId)
        if (prevView != null) activityListViewsCopy.remove(prevView)
        val currentView = getViewForAccountId(activeAccount.accountId)
        if (currentView != null) activityListViewsCopy.remove(currentView)
        val nextView = getViewForAccountId(nextAccountId)
        if (nextView != null) activityListViewsCopy.remove(nextView)

        prevActivityListView =
            (prevView ?: activityListViewsCopy.removeFirstOrNull()!!.apply {
                configure(
                    prevAccountId,
                    shouldLoadNewWallets,
                    skipSkeletonOnCache = skipSkeletonOnCache
                )
            }).apply {
                if (swipeItemsOffset == 0)
                    isInvisible = true
                if (prevView == null || alpha == 0f)
                    instantScrollToTop()
            }
        currentActivityListView =
            (currentView ?: activityListViewsCopy.removeFirstOrNull()!!.apply {
                configure(
                    activeAccount.accountId,
                    shouldLoadNewWallets,
                    skipSkeletonOnCache = skipSkeletonOnCache
                )
            }).apply {
                isInvisible = false
                if (currentView == null || alpha == 0f)
                    instantScrollToTop(shouldLoadNewWallets)
                if (swipeItemsOffset == 0)
                    alpha = 1f
            }
        nextActivityListView = (nextView ?: activityListViewsCopy.removeFirstOrNull()!!.apply {
            configure(
                nextAccountId,
                shouldLoadNewWallets,
                skipSkeletonOnCache = skipSkeletonOnCache
            )
        }).apply {
            if (swipeItemsOffset == 0)
                isInvisible = true
            if (nextView == null || alpha == 0f)
                instantScrollToTop()
        }
    }

    override fun updateProtectedView() {
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        stickyHeaderView.insetsUpdated(systemBarStartInset, systemBarEndInset)
        view.setConstraints {
            toTopPx(stickyHeaderView, navigationController?.getSystemBars()?.top ?: 0)
        }
        if (!isWideHome && window?.isConfiguring != true)
            phoneHeaderView.insetsUpdated()
        minHeaderHeight =
            ((navigationController?.getSystemBars()?.top ?: 0) + HomeHeaderView.navDefaultHeight)
        allActivityListViews.forEach {
            it.insetsUpdated()
        }
        updateTopBlurHorizontalPadding()
        _actionsView?.insetsUpdated()
    }

    private fun updateTopBlurHorizontalPadding() {
        val blurBottom = topBlurReversedCornerView.height
        val innerScrollOffset = listOfNotNull(
            _actionsView?.asCell to (_actionsView?.horizontalScrollOffset ?: 0),
            currentActivityListView.assetsCell?.asCell to (currentActivityListView.assetsCell?.horizontalScrollOffset
                ?: 0),
        ).firstOrNull { (cell, _) ->
            cell != null && cell.parent != null && cell.top < blurBottom && cell.bottom > 0
        }?.second ?: 0
        if (innerScrollOffset != 0) {
            topBlurReversedCornerView.setHorizontalPadding(
                -ViewConstants.TABLET_CONTENT_START_PADDING.dp,
                0f
            )
        } else {
            topBlurReversedCornerView.setHorizontalPadding(ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat())
        }
    }

    override fun onTransactionTap(accountId: String, transaction: MApiTransaction) {
        window?.let { window ->
            val isWaitingToPaySwap = (transaction is MApiTransaction.Swap) &&
                transaction.status.isPending &&
                transaction.swapType == SwapType.CROSS_CHAIN_TO_WALLET &&
                transaction.cex?.status?.uiStatus == MApiTransaction.UIStatus.PENDING

            val transactionNav: WNavigationController
            if (isWaitingToPaySwap) {
                transactionNav = WNavigationController(
                    window,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                transactionNav.setRoot(
                    SwapSendAddressOutputVC(
                        context,
                        transaction.fromToken!!,
                        transaction.toToken!!,
                        transaction.fromAmount.absoluteValue
                            .toBigInteger(transaction.fromToken!!.decimals),
                        transaction.toAmount
                            .toBigInteger(transaction.toToken!!.decimals),
                        transaction.cex?.payinAddress ?: "",
                        transaction.cex?.transactionId ?: ""
                    )
                )
            } else {
                transactionNav = WNavigationController(
                    window, WNavigationController.PresentationConfig(
                        style = WNavigationController.PresentationStyle.BottomSheet
                    )
                )
                transactionNav.setRoot(TransactionVC(context, accountId, transaction))
            }
            window.present(transactionNav)
        }
    }

    override fun update(state: UpdateStatusView.State, animated: Boolean) {
        val walletContextDelegate = WalletContextManager.delegate?.get()
        val shouldNotifyWalletReady = homeVM.isGeneralDataAvailable &&
            (!homeVM.calledReady || walletContextDelegate?.isWalletReady() == false)
        if (shouldNotifyWalletReady) {
            homeVM.calledReady = true
            walletContextDelegate?.walletIsReady()
        }
        val accountNotLoadedYet = !homeVM.isGeneralDataAvailable &&
            state == UpdateStatusView.State.Updating &&
            stickyHeaderView.updateStatusView.state is UpdateStatusView.State.Updated
        if (accountNotLoadedYet)
            return
        if (isWideHome) {
            return
        }
        phoneHeaderView.update(state, animated)
        stickyHeaderView.update(stickyHeaderViewMode, state, animated)
    }

    override fun updateHeaderCards(expand: Boolean) {
        if (window?.isConfiguring == true) return
        applyHeaderCards(expand)
    }

    private fun applyHeaderCards(expand: Boolean) {
        homeVM.showingAccount?.let {
            if (isWideHome) {
                headerView.updateAccountData(it)
                headerView.layoutCardView()
                return
            }
            phoneHeaderView.updateAccountData(it)
            if (expand) {
                phoneHeaderView.isExpandAllowed = true
                phoneHeaderView.expand(animated = false, velocity = null)
                pauseBlurViews()
            } else
                phoneHeaderView.layoutCardView()
        }
    }

    override fun updateBalance(accountChangedFromOtherScreens: Boolean) {
        val canShowBalance =
            homeVM.isGeneralDataAvailable || AccountStore.activeAccount?.isNew == true
        if (!canShowBalance && phoneHeaderView.isShowingSkeletons) {
            return
        }
        phoneHeaderView.updateBalance(!accountChangedFromOtherScreens)
    }

    override fun reloadCard() {
        phoneHeaderView.updateCardImage()
        panelHeaderView?.updateCardImage()
    }

    override fun reloadCardAddress(accountId: String) {
        phoneHeaderView.updateAddressLabel(accountId)
        panelHeaderView?.updateAddressLabel(accountId)
    }

    override fun transactionsUpdated(isUpdateEvent: Boolean) {
        allActivityListViews.forEach {
            it.transactionsUpdated(isUpdateEvent)
        }
    }

    override fun loadStakingData() {
        if (!homeVM.isGeneralDataAvailable) return

        if (homeVM.showingAccount?.isViewOnly == false)
            executeWithLowPriority {
                earnToncoinViewModel.loadOrRefreshStakingData()
                earnMycoinViewModel.loadOrRefreshStakingData()
            }
    }

    override fun stakingDataUpdated() {
        if (isWideHome) {
            allActivityListViews.forEach { it.updateActionsView() }
        } else {
            actionsView.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
        }
    }

    override fun headerModeChanged() {
        rvMode = phoneHeaderView.mode
        allActivityListViews.forEach {
            it.headerModeChanged()
        }
        sortViews()
    }

    private fun updateActionsAlpha() {
        if (isWideHome) return
        actionsView.fadeInPercent =
            min(
                swipeFadeInPercent,
                if (headerView.centerAccount?.isViewOnly == true) 0f else actionsLayoutFadeInPercent
            )
    }

    private fun updateAccountName(accountName: String, animated: Boolean) {
        phoneHeaderView.updateAccountName(accountName)
        if (isWideHome) {
            return
        }
        if (stickyHeaderView.updateStatusView.state is UpdateStatusView.State.Updated) {
            stickyHeaderView.updateStatusView.setAppearance(
                phoneHeaderView.mode == HomeHeaderView.Mode.Expanded,
                animated
            )
        } else {
            stickyHeaderView.updateStatusView.setAppearance(true, animated)
        }
    }

    override fun configureAccountViews(
        shouldLoadNewWallets: Boolean,
        skipSkeletonOnCache: Boolean
    ) {
        stickyHeaderView.updateActions()
        accountConfigChanged()
        val account = headerView.centerAccount ?: homeVM.showingAccount
        configureActivityLists(shouldLoadNewWallets, skipSkeletonOnCache)
        if (isWideHome) {
            allActivityListViews.forEach { it.updateActionsView() }
        } else {
            actionsView.updateActions(account)
            updateActionsAlpha()
        }
        if (shouldLoadNewWallets) {
            updateAccountName(
                (headerView.centerAccount ?: homeVM.showingAccount)?.name ?: "",
                false
            )
            currentActivityListView.updateHeaderHeights()
            moveActionsViewToCell()
        }
        loadStakingData()
    }

    // Nft tabs could be updated, should reload tabs
    override fun reloadTabs() {
        currentActivityListView.assetsCell?.reloadTabs(resetSelection = false)
    }

    override fun accountRenamed(accountId: String, accountName: String) {
        phoneHeaderView.accountRenamed(accountId, accountName)
        if (headerView.centerAccount?.accountId == accountId)
            phoneHeaderView.updateAccountName(accountName)
    }

    override fun accountConfigChanged() {
        phoneHeaderView.updateMintIconVisibility()
        phoneHeaderView.updatePromotion()
        panelHeaderView?.updateMintIconVisibility()
        panelHeaderView?.updatePromotion()
    }

    override fun seasonalThemeChanged() {
        phoneHeaderView.updateSeasonalTheme()
    }

    override fun accountWillChange(fromHome: Boolean) {
        configureAccountViews(shouldLoadNewWallets = !fromHome, skipSkeletonOnCache = fromHome)
        if (fromHome) {
            updateAccountName(headerView.centerAccount?.name ?: "", true)
        } else {
            // Account will change from another screen, invalidate swipeFadeInPercent
            swipeFadeInPercent = 1f
            moveHeaderViewToParent()
        }
    }

    override fun removeScreenFromStack() {
        navigationController?.removeViewController(this)
    }

    override fun popToRoot() {
        navigationController?.popToRoot(false)
    }

    override fun startSorting() {
        if (currentActivityListView.assetsCell?.isInSelectionMode == true) {
            currentActivityListView.assetsCell?.closeSelectionMode()
            phoneHeaderView.setUpdateStatusHidden(false)
        }
        setHeaderActionModeClipEnabled(true)
        currentActivityListView.assetsCell?.startSorting()
        stickyHeaderView.enterActionMode(onResult = { save ->
            currentActivityListView.assetsCell?.endSorting(save)
        })
        sortViews()
    }

    override fun endSorting() {
        endSorting(true)
    }

    private fun endSorting(save: Boolean) {
        currentActivityListView.assetsCell?.endSorting(save)
        setHeaderActionModeClipEnabled(false)
        stickyHeaderView.exitActionMode()
        sortViews()
    }

    override fun startSelectionMode(
        selectedCount: Int,
        shouldShowTransferActions: Boolean
    ) {
        setHeaderActionModeClipEnabled(true)
        phoneHeaderView.setUpdateStatusHidden(true)
        stickyHeaderView.enterSelectionMode(
            selectedCount = selectedCount,
            shouldShowTransferActions = shouldShowTransferActions,
            onClose = ::endSelectionMode,
            onHide = ::hideSelectedAssets,
            onSelectAll = ::selectAllVisibleAssets,
            onSend = ::sendSelectedAssets,
            onBurn = ::burnSelectedAssets
        )
        sortViews()
    }

    override fun updateSelectionMode(
        selectedCount: Int,
        animationMode: TitleAnimationMode?,
        shouldShowTransferActions: Boolean
    ) {
        stickyHeaderView.updateSelectionMode(
            selectedCount = selectedCount,
            animationMode = animationMode,
            shouldShowTransferActions = shouldShowTransferActions,
            onClose = ::endSelectionMode,
            onHide = ::hideSelectedAssets,
            onSelectAll = ::selectAllVisibleAssets,
            onSend = ::sendSelectedAssets,
            onBurn = ::burnSelectedAssets
        )
    }

    override fun endSelectionMode() {
        currentActivityListView.assetsCell?.closeSelectionMode()
        setHeaderActionModeClipEnabled(false)
        phoneHeaderView.setUpdateStatusHidden(false)
        stickyHeaderView.exitActionMode()
        sortViews()
    }

    private fun setHeaderActionModeClipEnabled(isEnabled: Boolean) {
        phoneHeaderView.setTopContentClipInset(
            if (isEnabled) phoneHeaderView.collapsedMinHeight else 0
        )
    }

    private fun hideSelectedAssets() {
        currentActivityListView.assetsCell?.hideSelectedAssets()
        endSelectionMode()
    }

    private fun sendSelectedAssets() {
        if (currentActivityListView.assetsCell?.sendSelectedNfts() == true) {
            endSelectionMode()
        }
    }

    private fun burnSelectedAssets() {
        if (currentActivityListView.assetsCell?.burnSelectedNfts() == true) {
            endSelectionMode()
        }
    }

    private fun selectAllVisibleAssets() {
        currentActivityListView.assetsCell?.selectAllVisibleAssets()
    }

    override fun onBackPressed(): Boolean {
        if (currentActivityListView.assetsCell?.isInSelectionMode == true) {
            endSelectionMode()
            return false
        }
        if (currentActivityListView.assetsCell?.isInDragMode == true) {
            endSorting(false)
            return false
        }
        return super.onBackPressed()
    }

    // Return header height to activity list viewer
    override fun activityListViewHeaderHeight(): Int {
        if (isWideHome) {
            return (window?.systemBars?.top ?: 0) + HomeHeaderView.navDefaultHeight
        }
        return (window?.systemBars?.top ?: 0) +
            HomeHeaderView.navDefaultHeight +
            if (rvMode == HomeHeaderView.Mode.Expanded) {
                phoneHeaderView.expandedContentHeight.toInt().takeIf { it > 0 }
                    ?: HomeHeaderView.expandedContentHeight(view.width).toInt()
            } else
                phoneHeaderView.collapsedHeight
    }

    override fun swipeItemsOffset(): Int {
        return swipeItemsOffset
    }

    override fun activityListReserveActionsCell(): Boolean {
        return headerView.centerAccount?.isViewOnly != true
    }

    override fun activityListActionsCellHeight(): Int {
        return if (isWideHome) TabletHeaderActionsView.HEIGHT.dp else HeaderActionsView.HEIGHT.dp
    }

    override fun activityListReserveAssetsCell(): Boolean = true

    override fun recyclerViewModeValue(): HomeHeaderView.Mode {
        if (isWideHome) return HomeHeaderView.Mode.Collapsed
        return rvMode
    }
}
