package org.mytonwallet.app_air.uiassets.viewControllers.token

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.View.GONE
import android.view.View.INVISIBLE
import android.view.View.VISIBLE
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.core.view.updatePadding
import androidx.core.widget.doAfterTextChanged
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.math.BigInteger
import java.util.Date
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.FloatAnimator
import org.mytonwallet.app_air.blur3.drawable.color.BlurredBackgroundColorProvider
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNavigation
import org.mytonwallet.app_air.uiassets.viewControllers.token.cells.TokenChartCell
import org.mytonwallet.app_air.uiassets.viewControllers.token.cells.TokenInfoCell
import org.mytonwallet.app_air.uiassets.viewControllers.token.views.TokenHeaderView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.ISearchOverlayHost
import org.mytonwallet.app_air.uicomponents.base.ITabsVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter.WRecyclerViewDataSource
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.EmptyCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderSpaceCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonHeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.ActivitySectionBackgroundDecoration
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisend.send.MultisendLauncher
import org.mytonwallet.app_air.uisend.send.SellWithCardLauncher
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeDirection
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeVC
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.WalletCreationVM
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AssetRef
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class TokenVC(context: Context, private val account: MAccount, var token: MToken) :
    WViewController(context),
    WRecyclerViewDataSource,
    TokenVM.Delegate,
    WThemedView,
    WProtectedView,
    WalletCreationVM.Delegate,
    ISearchOverlayHost {
    @Suppress("PropertyName")
    override val TAG = "Token"

    private val isLpToken: Boolean
        get() = token.isLpToken

    private val tokenInfoRow: Int
        get() = if (isLpToken) 2 else 3

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true

    override val displayedAccount =
        DisplayedAccount(account.accountId, AccountStore.isPushedTemporary)

    private val headerCollapseDistance: Int
        get() = (232.dp * balanceModeProgress).roundToInt()

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val ACTIONS_CELL = WCell.Type(2)
        val CHART_CELL = WCell.Type(3)
        val TRANSACTION_CELL = WCell.Type(4)
        val EMPTY_VIEW_CELL = WCell.Type(5)
        val TRANSACTION_SMALL_CELL = WCell.Type(6)
        val TRANSACTION_SMALL_FIRST_IN_DAY_CELL = WCell.Type(7)

        val SKELETON_HEADER_CELL = WCell.Type(8)
        val SKELETON_CELL = WCell.Type(9)
        val INFO_CELL = WCell.Type(10)

        const val HEADER_SECTION = 0
        const val TRANSACTION_SECTION = 1
        const val EMPTY_VIEW_SECTION = 2
        const val LOADING_SECTION = 3

        const val LARGE_INT = 10000

        private const val REMOVE_ANIMATION_FALLBACK_MS = 1500L

        private const val BOTTOM_BAR_HEIGHT = 48
        private const val SEARCH_GAP = 12
        private const val SEARCH_KEYBOARD_GAP = 12
        private const val SEARCH_OVERLAY_ANIMATION = AnimationConstants.VERY_VERY_QUICK_ANIMATION
    }

    private var tokenChartCell: TokenChartCell? = null
    private var tokenInfoCell: TokenInfoCell? = null

    private val tokenVM by lazy {
        TokenVM(
            context,
            account.accountId,
            token,
            account.isChainSupported(token.chain),
            WeakReference(this)
        )
    }

    private val areTradeActionsAvailable: Boolean
        get() = account.supportsSwap && !isLpToken

    private val isReceiveAvailable: Boolean
        get() = account.accountType != MAccount.AccountType.VIEW

    private fun isSellAllowed(): Boolean =
        account.supportsBuyWithCard && ConfigStore.isLimited != true

    private fun openSellWithCard(tokenSlug: String) {
        if (!isSellAllowed()) return
        SellWithCardLauncher.launch(
            caller = WeakReference(this),
            account = account,
            tokenSlug = tokenSlug
        )
    }

    private fun showUnsupportedChainAlertIfNeeded(): Boolean {
        if (account.isChainSupported(token.chain)) return false
        showAlert(
            LocaleController.getString("Unsupported Chain"),
            LocaleController.getStringWithKeyValues(
                "\$token_chain_not_supported_by_wallet",
                listOf(Pair("%chain%", token.mBlockchain?.displayName ?: token.chain))
            ),
            button = LocaleController.getString("Create Multichain Wallet"),
            buttonPressed = { createMultichainWallet() },
            secondaryButton = LocaleController.getString("Cancel")
        )
        return true
    }

    private val walletCreationVM by lazy {
        WalletCreationVM(this)
    }
    private var creationPasscodeConfirmVC: PasscodeConfirmVC? = null

    private fun createMultichainWallet() {
        if (!WGlobalStorage.isPasscodeSet()) {
            presentAddAccount()
            return
        }
        val window = window ?: return
        lateinit var passcodeConfirmVC: PasscodeConfirmVC
        passcodeConfirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.Default(
                LocaleController.getString("Enter Passcode"),
                "",
                LocaleController.getString("Create Multichain Wallet"),
                showNavigationSeparator = false,
                startWithBiometrics = true
            ),
            task = { enclaveToken ->
                createWallet(passcodeConfirmVC, enclaveToken)
            }
        )
        passcodeConfirmVC.isTaskAsync = true
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig.PreferredFullScreen
        )
        nav.setRoot(passcodeConfirmVC)
        window.present(nav)
    }

    private fun createWallet(passcodeConfirmVC: PasscodeConfirmVC, enclaveToken: String) {
        passcodeConfirmVC.view.lockView()
        creationPasscodeConfirmVC = passcodeConfirmVC
        WalletCore.call(ApiMethod.Auth.GenerateMnemonic(), callback = { words, err ->
            val window = window
            if (words == null || window == null) {
                showError(err?.parsed)
                return@call
            }
            walletCreationVM.finalizeAccount(
                window,
                MBlockchainNetwork.ofAccountId(account.accountId),
                words,
                0,
                enclaveToken
            )
        })
    }

    override fun showError(error: MBridgeError?) {
        val passcodeConfirmVC = creationPasscodeConfirmVC
        if (passcodeConfirmVC != null && !passcodeConfirmVC.isDestroyed) {
            passcodeConfirmVC.restartAuth()
            passcodeConfirmVC.showError(error)
            return
        }
        creationPasscodeConfirmVC = null
        super.showError(error)
    }

    override fun finalizedCreation(createdAccount: MAccount, importedAccountsCount: Int) {
        val passcodeConfirmVC = creationPasscodeConfirmVC
        creationPasscodeConfirmVC = null
        WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
        val tokenSlug = token.slug
        val openToken = { WalletCore.notifyEvent(WalletEvent.OpenToken(tokenSlug)) }
        val passcodeWindow = passcodeConfirmVC?.takeUnless { it.isDestroyed }?.window
        if (passcodeWindow != null) {
            passcodeWindow.dismissLastNav(onCompletion = openToken)
        } else {
            openToken()
        }
    }

    private fun presentAddAccount() {
        val window = window ?: return
        val addAccountVC = WalletContextManager.delegate?.get()
            ?.getAddAccountVC(MBlockchainNetwork.ofAccountId(account.accountId))
            as? WViewController ?: return
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet
            )
        )
        nav.setRoot(addAccountVC)
        window.present(nav)
    }

    @Volatile
    private var showingTransactions: List<MApiTransaction>? = null

    private var dataSource: WRecyclerViewDataSource? = object : WRecyclerViewDataSource {
        override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 2

        override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int =
            if (section == 0) 1 else 100

        override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
            when (indexPath.section) {
                HEADER_SECTION -> {
                    HEADER_CELL
                }

                else -> {
                    if (indexPath.row == 0) SKELETON_HEADER_CELL else SKELETON_CELL
                }
            }

        override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
            when (cellType) {
                HEADER_CELL -> {
                    HeaderSpaceCell(context).apply { alpha = 0f }
                }

                SKELETON_HEADER_CELL -> {
                    SkeletonHeaderCell(context, 48.dp)
                }

                else -> {
                    SkeletonCell(context)
                }
            }

        override fun recyclerViewConfigureCell(
            rv: RecyclerView,
            cellHolder: WCell.Holder,
            indexPath: IndexPath
        ) {
            when (cellHolder.cell) {
                is HeaderSpaceCell -> {
                    val cellLayoutParams = cellHolder.cell.layoutParams
                    val layoutManager =
                        recyclerView.layoutManager as? LinearLayoutManagerAccurateOffset
                            ?: return
                    val height =
                        (navigationController?.getSystemBars()?.top ?: 0) +
                            TokenHeaderView.navDefaultHeight +
                            headerView.contentHeight +
                            (tokenChartCell?.height ?: 0) +
                            (
                                tokenInfoCell?.height?.takeIf { it > 0 }
                                    ?: TokenInfoCell.collapsedCellHeight
                                ) +
                            (
                                layoutManager.getItemHeight(1) ?: 0
                                )
                    cellLayoutParams.height = height
                    cellHolder.cell.layoutParams = cellLayoutParams
                }

                is SkeletonHeaderCell -> {
                    (cellHolder.cell as SkeletonHeaderCell).updateTheme()
                }

                is SkeletonCell -> {
                    (cellHolder.cell as SkeletonCell).apply {
                        configure(indexPath.row, isFirst = false, isLast = false)
                        updateTheme()
                    }
                }
            }
        }
    }

    private val rvSkeletonAdapter =
        WRecyclerViewAdapter(
            WeakReference(dataSource),
            arrayOf(HEADER_CELL, SKELETON_HEADER_CELL, SKELETON_CELL)
        )

    private val skeletonRecyclerView: WRecyclerView by lazy {
        val rv = object : WRecyclerView(this) {
            override fun onTouchEvent(event: MotionEvent): Boolean = false
        }
        rv.adapter = rvSkeletonAdapter
        rv.setLayoutManager(LinearLayoutManager(context))
        rv.setItemAnimator(null)
        rv.alpha = 0f
        rv.visibility = GONE
        rv
    }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                HEADER_CELL,
                ACTIONS_CELL,
                CHART_CELL,
                INFO_CELL,
                TRANSACTION_CELL,
                TRANSACTION_SMALL_CELL,
                TRANSACTION_SMALL_FIRST_IN_DAY_CELL,
                EMPTY_VIEW_CELL,
                SKELETON_CELL
            )
        ).apply {
            setHasStableIds(true)
        }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            if (showingTransactions == null) return
            updateScroll(currentScrollDy() ?: return)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                executeWithLowPriority {
                    if (recyclerView.scrollState == RecyclerView.SCROLL_STATE_IDLE) {
                        heavyAnimationDone()
                    }
                }
                adjustScrollingPosition()
            } else {
                heavyAnimationInProgress()
            }
        }
    }

    private var headerCell: HeaderSpaceCell? = null
    private var actionsCell: WCell? = null

    private val activitySectionBackgroundDecoration = ActivitySectionBackgroundDecoration(
        firstPosition = { tokenInfoRow + 1 },
        rowCount = {
            recyclerViewNumberOfItems(recyclerView, TRANSACTION_SECTION) +
                recyclerViewNumberOfItems(recyclerView, EMPTY_VIEW_SECTION) +
                if (showingTransactions != null && tokenVM.activityLoader?.loadedAll == false) {
                    1
                } else {
                    0
                }
        }
    )

    private val recyclerView: WRecyclerView = WRecyclerView(context).apply {
        adapter = rvAdapter
        addItemDecoration(activitySectionBackgroundDecoration)
        val layoutManager = object : LinearLayoutManagerAccurateOffset(context) {
            override fun canScrollVertically(): Boolean = !skeletonView.isVisible

            override fun onLayoutCompleted(state: RecyclerView.State) {
                super.onLayoutCompleted(state)
                updateEmptyCellHeight()
                updateCollapseGap()
            }
        }
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        addOnScrollListener(scrollListener)
        setOnOverScrollListener { _, _, offset, _ ->
            updateScroll(
                -offset.toInt() + computeVerticalScrollOffset()
            )
            emptyView?.let { emptyView ->
                view.setConstraints {
                    topToBottomPx(emptyView, headerView, offset.toInt())
                }
            }
        }
        setItemAnimator(null)
        clipToPadding = false
    }

    override val topBlurView: View?
        get() = topBlurReversedCornerView

    private val topBlurReversedCornerView = ReversedCornerView(
        context,
        ReversedCornerView.Config(
            blurRootView = recyclerView
        )
    )

    private val headerView: TokenHeaderView by lazy {
        navigationBar = run {
            val navBar = WNavigationBar(
                this,
                defaultHeight = TokenHeaderView.NAV_DEFAULT_HEIGHT_DP,
                contentMarginTop = TokenHeaderView.navContentMarginTop
            )
            navBar.setTitleGravity(Gravity.CENTER)
            navBar.titleLabel.id = UIComponentsR.id.token_title
            navBar
        }
        TokenHeaderView(
            navigationController!!,
            navigationBar!!,
            account.accountId,
            token
        ) {
            (tokenVM.tokenInfoState as? TokenVM.TokenInfoState.Details)?.info
        }
    }

    private val skeletonView = SkeletonView(context)

    private var actionsView: HeaderActionsView? = null

    private val buyButton = WButton(context, WButton.Type.PRIMARY).apply {
        id = UIComponentsR.id.token_buy
        text = LocaleController.getString("Buy")
        customTint = WColor.Buy.color
        setOnClickListener {
            if (showUnsupportedChainAlertIfNeeded()) return@setOnClickListener
            presentSwap(isBuying = true)
        }
    }

    private val sellButton = WButton(context, WButton.Type.PRIMARY).apply {
        id = UIComponentsR.id.token_sell
        text = LocaleController.getString("Sell")
        customTint = WColor.Sell.color
        setOnClickListener {
            if (showUnsupportedChainAlertIfNeeded()) return@setOnClickListener
            presentSwap(isBuying = false)
        }
    }

    private val receiveButton = WButton(context, WButton.Type.SECONDARY_NEUTRAL).apply {
        id = UIComponentsR.id.token_receive
        text = LocaleController.getString("Receive")
        setOnClickListener {
            onClick(HeaderActionsView.Identifier.RECEIVE)
        }
    }

    private val tradeButtonGlasses = mutableListOf<WGlassView>()

    private fun tradeButtonCell(button: WButton) = FrameLayout(context).apply {
        clipChildren = false
        button.buttonHeight = BOTTOM_BAR_HEIGHT.dp
        addView(button, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private fun attachTradeButtonGlass(
        button: WButton,
        provider: BlurredBackgroundColorProvider,
        root: ViewGroup?
    ) {
        tradeButtonGlasses += WGlassView.attachTo(button, BOTTOM_BAR_HEIGHT.dp / 2f, provider, root)
    }

    private val receiveCell = tradeButtonCell(receiveButton)
    private val sellCell by lazy { tradeButtonCell(sellButton) }

    private val tradeButtonsView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        clipChildren = false
        clipToPadding = false
        // Room for the button shadows, which the parent would otherwise clip.
        val shadowPadding = WGlassView.GLASS_PADDING_DP.dp
        setPadding(shadowPadding, shadowPadding, shadowPadding, shadowPadding)
        addView(receiveCell, LinearLayout.LayoutParams(0, BOTTOM_BAR_HEIGHT.dp, 1f))
        if (areTradeActionsAvailable) {
            addView(
                tradeButtonCell(buyButton),
                LinearLayout.LayoutParams(0, BOTTOM_BAR_HEIGHT.dp, 1f)
            )
            addView(sellCell, LinearLayout.LayoutParams(0, BOTTOM_BAR_HEIGHT.dp, 1f))
        }
    }

    private val exploreSearchTabs: ITabsVC?
        get() = navigationController?.tabBarController
            ?: window?.navigationControllers?.firstOrNull()
                ?.viewControllers?.firstOrNull() as? ITabsVC

    private val isSearchAvailable by lazy { exploreSearchTabs != null }

    private val isBottomBarVisible: Boolean
        get() = isReceiveAvailable || isSearchAvailable

    private val searchExpanded = BoolAnimator(
        AnimationConstants.VERY_QUICK_ANIMATION,
        CubicBezierInterpolator.EASE_BOTH,
        false
    ) { _, _, _, _ ->
        updateSearchWidth()
    }

    private val searchEditText by lazy {
        WSearchEditText(context, multilinePaste = false).apply {
            id = UIComponentsR.id.token_search_input
            isSaveEnabled = false
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            doAfterTextChanged {
                if (hasFocus()) showSearchResults()
                updateSearchExpanded()
            }
            onFocusChangeListener = View.OnFocusChangeListener { _, hasFocus ->
                if (hasFocus) {
                    showSearchResults()
                    post { if (hasFocus()) showKeyboard() }
                } else {
                    dismissSearchResults()
                }
                updateSearchExpanded()
            }
            setOnEditorActionListener { _, actionId, event ->
                if (event?.keyCode == KeyEvent.KEYCODE_ENTER) {
                    // The release is consumed too, or `TextView` moves focus on it and the blur
                    // closes the search before a submit waiting for results can open anything
                    if (event.action == KeyEvent.ACTION_DOWN) {
                        exploreSearchTabs?.submitExploreSearch(this)
                    }
                    return@setOnEditorActionListener true
                }
                val isSubmit = actionId == EditorInfo.IME_ACTION_DONE
                if (isSubmit) exploreSearchTabs?.submitExploreSearch(this)
                isSubmit
            }
        }
    }

    private var searchGlass: WGlassView? = null
    private val searchView by lazy {
        WFrameLayout(context).apply {
            setBackgroundColor(Color.TRANSPARENT, BOTTOM_BAR_HEIGHT.dp / 2f, clipToBounds = true)
            addView(searchEditText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    private val keyboardLift = FloatAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, 0f) {
        applyKeyboardLift()
    }

    private fun tradeButtonsBottomMargin(): Int =
        10.dp + (navigationController?.getSystemBars()?.bottom ?: 0)

    override val additionalBottomGradientHeight: Int
        get() = if (isBottomBarVisible) 60.dp else 0

    private val bottomBarStartMargin: Int
        get() = ViewConstants.HORIZONTAL_PADDINGS.dp + 10.dp +
            additionalTabletPadding + systemBarStartInset

    private val bottomBarEndMargin: Int
        get() = ViewConstants.HORIZONTAL_PADDINGS.dp + 10.dp + systemBarEndInset

    private fun updateTradeButtonsLayout() {
        if (!isBottomBarVisible) return
        val bottomMargin = tradeButtonsBottomMargin()
        view.setConstraints {
            if (isSearchAvailable) {
                toStartPx(searchView, bottomBarStartMargin)
                toBottomPx(searchView, bottomMargin)
            }
            if (isReceiveAvailable) {
                val shadowPadding = WGlassView.GLASS_PADDING_DP.dp
                if (isSearchAvailable) {
                    startToEndPx(tradeButtonsView, searchView, SEARCH_GAP.dp - shadowPadding)
                } else {
                    toStartPx(tradeButtonsView, bottomBarStartMargin - shadowPadding)
                }
                toEndPx(tradeButtonsView, bottomBarEndMargin - shadowPadding)
                toBottomPx(tradeButtonsView, bottomMargin - shadowPadding)
            }
        }
        if (isSearchAvailable) updateSearchWidth()
    }

    private fun bringBottomBarToFront() {
        if (isSearchAvailable) {
            searchGlass?.bringToFront()
            searchView.bringToFront()
        }
        if (isReceiveAvailable) tradeButtonsView.bringToFront()
    }

    private fun updateSearchExpanded() {
        val expanded = searchEditText.hasFocus() || !searchEditText.text.isNullOrEmpty()
        searchExpanded.animatedValue = expanded
    }

    private var isSearchHintShown = false

    private fun updateSearchWidth() {
        val progress = searchExpanded.floatValue
        val expandedWidth = (
            view.width.takeIf { it > 0 } ?: context.resources.displayMetrics.widthPixels
            ) - bottomBarStartMargin - bottomBarEndMargin
        val width = lerp(
            BOTTOM_BAR_HEIGHT.dp.toFloat(),
            expandedWidth.toFloat(),
            progress
        ).roundToInt()
        if (searchView.layoutParams.width != width) {
            searchView.updateLayoutParams { this.width = width }
        }
        searchEditText.setPaddingDpLocalized(
            lerp(22f, 16f, progress).ceilToInt(),
            0,
            lerp(0f, 48f, progress).ceilToInt(),
            0
        )
        val showsHint = progress >= 0.5f
        if (isSearchHintShown != showsHint) {
            isSearchHintShown = showsHint
            searchEditText.hint = if (showsHint) LocaleController.getString("Search or Ask") else ""
        }
        tradeButtonsView.alpha = (1f - progress * 2f).coerceAtLeast(0f)
        tradeButtonsView.isVisible = tradeButtonsView.alpha > 0f
    }

    private fun targetKeyboardLift(): Float {
        val imeBottom = navigationController?.imeInsetBottom ?: 0
        if (imeBottom <= 0 || !searchEditText.hasFocus()) return 0f
        return (imeBottom + SEARCH_KEYBOARD_GAP.dp - tradeButtonsBottomMargin())
            .coerceAtLeast(0).toFloat()
    }

    private fun applyKeyboardLift() {
        val translation = -keyboardLift.value
        searchView.translationY = translation
        tradeButtonsView.translationY = translation
        searchOverlayNav?.insetsUpdated()
    }

    private var searchOverlayNav: WNavigationController? = null

    private fun obtainSearchOverlayNav(): WNavigationController? {
        searchOverlayNav?.let { return it }
        val window = window ?: return null
        val nav = WNavigationController(window)
        nav.tabBarController = exploreSearchTabs
        nav.searchOverlayHost = this
        nav.alpha = 0f
        searchOverlayNav = nav
        view.addView(
            nav,
            view.indexOfChild(searchGlass ?: searchView),
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        nav.insetsUpdated()
        return nav
    }

    private fun showSearchResults() {
        if (isDestroyed) return
        val nav = obtainSearchOverlayNav() ?: return
        exploreSearchTabs?.searchExplore(searchEditText.typedText(), true, nav)
    }

    private fun dismissSearchResults() {
        val nav = searchOverlayNav?.takeIf { it.viewControllers.isNotEmpty() } ?: return
        exploreSearchTabs?.searchExplore(null, false, nav)
    }

    override fun getBottomNavigationHeight(): Int =
        tradeButtonsBottomMargin() + BOTTOM_BAR_HEIGHT.dp + 10.dp +
            keyboardLift.value.roundToInt()

    override fun clearSearchFocus() {
        searchEditText.hideKeyboard()
    }

    override val searchNavigationBarHeight = TokenHeaderView.NAV_DEFAULT_HEIGHT_DP
    override val searchNavigationBarContentMarginTop = TokenHeaderView.navContentMarginTop

    override val searchResultNavigationController: WNavigationController?
        get() = navigationController

    override fun revealSearchOverlay() {
        val nav = searchOverlayNav?.takeIf { it.viewControllers.isNotEmpty() } ?: return
        nav.fadeIn(SEARCH_OVERLAY_ANIMATION)
    }

    override fun hideSearchOverlay() {
        val nav = searchOverlayNav ?: return
        searchOverlayNav = null
        if (nav.viewControllers.isEmpty()) {
            view.removeView(nav)
            return
        }
        nav.blockTouches()
        nav.fadeOut(SEARCH_OVERLAY_ANIMATION) {
            nav.viewControllers.forEach { it.viewWillDisappear() }
            // Detached so the outgoing search cannot clear focus of a replacement session.
            nav.searchOverlayHost = null
            nav.tabBarController = null
            nav.onDestroy()
            view.removeView(nav)
        }
    }

    private fun shouldShowBalanceHeader(): Boolean =
        (BalanceStore.getBalances(account.accountId)?.get(token.slug) ?: BigInteger.ZERO) >
            BigInteger.ZERO

    private var isBalanceModeShown = shouldShowBalanceHeader()

    // 1: balance header and Sell; 0: chart icon and Receive.
    private var balanceModeProgress = if (isBalanceModeShown) 1f else 0f
    private var balanceModeAnimator: ValueAnimator? = null

    private val actionsFullHeight: Int
        get() =
            if (account.accountType == MAccount.AccountType.VIEW) 0 else HeaderActionsView.HEIGHT.dp

    private val actionsRowHeight: Int
        get() = (actionsFullHeight * balanceModeProgress).roundToInt()

    private fun applyBalanceModeProgress(progress: Float) {
        balanceModeProgress = progress
        headerView.contentProgress = progress
        tokenChartCell?.iconProgress = 1f - progress
        receiveButton.alpha = 1f - progress
        receiveButton.isVisible = progress < 1f
        receiveCell.updateLayoutParams<LinearLayout.LayoutParams> { weight = 1f - progress }
        if (areTradeActionsAvailable) {
            receiveCell.updateLayoutParams<LinearLayout.LayoutParams> {
                marginEnd = (12.dp * (1f - progress)).roundToInt()
            }
            sellButton.alpha = progress
            sellButton.isVisible = progress > 0f
            sellCell.updateLayoutParams<LinearLayout.LayoutParams> {
                weight = progress
                marginStart = (12.dp * progress).roundToInt()
            }
        }
        val headerRowHeight = (navigationController?.getSystemBars()?.top ?: 0) +
            TokenHeaderView.navDefaultHeight +
            headerView.contentHeight
        headerCell?.takeIf { it.layoutParams != null }?.updateLayoutParams {
            height = headerRowHeight
        }
        actionsCell?.takeIf { it.layoutParams != null }?.updateLayoutParams {
            height = actionsRowHeight
        }
        // Off-screen rows keep stale cached heights, which skews the scroll offset.
        (recyclerView.layoutManager as? LinearLayoutManagerAccurateOffset)?.apply {
            setItemHeight(0, headerRowHeight)
            setItemHeight(1, actionsRowHeight)
        }
        if (!headerView.isAttachedToWindow) return
        val dy = if (showingTransactions == null) 0 else currentScrollDy() ?: 0
        lastDy = -1
        updateScroll(dy)
    }

    private fun currentScrollDy(): Int? {
        val layoutManager =
            recyclerView.layoutManager as? LinearLayoutManagerAccurateOffset ?: return null
        return if (layoutManager.findFirstVisibleItemPosition() < 2) {
            recyclerView.computeVerticalScrollOffset()
        } else {
            LARGE_INT
        }
    }

    private fun updateBalanceMode() {
        val shouldShow = shouldShowBalanceHeader()
        if (shouldShow == isBalanceModeShown) return
        isBalanceModeShown = shouldShow
        balanceModeAnimator?.cancel()
        tokenInfoCell?.setHasBalance(shouldShow, animated = view.isLaidOut)
        val target = if (shouldShow) 1f else 0f
        if (!view.isLaidOut || !WGlobalStorage.getAreAnimationsActive()) {
            applyBalanceModeProgress(target)
            rvSkeletonAdapter.notifyItemChanged(0)
            return
        }
        balanceModeAnimator =
            ValueAnimator.ofFloat(balanceModeProgress, target).apply {
                duration = AnimationConstants.QUICK_ANIMATION
                interpolator = CubicBezierInterpolator.EASE_BOTH
                addUpdateListener { applyBalanceModeProgress(it.animatedValue as Float) }
                doOnEnd {
                    balanceModeAnimator = null
                    rvSkeletonAdapter.notifyItemChanged(0)
                    updateCollapseGap()
                }
                start()
            }
        updateCollapseGap()
    }

    override fun setupViews() {
        super.setupViews()

        heavyAnimationInProgress()
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(skeletonRecyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            topBlurReversedCornerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    TokenHeaderView.navDefaultHeight +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
            )
        )
        HeaderSpaceCell(context).also { headerCell = it }.apply {
            addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            setConstraints {
                toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
        }
        view.addView(navigationBar, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(skeletonView)
        if (isSearchAvailable) {
            view.addView(
                searchView,
                ViewGroup.LayoutParams(BOTTOM_BAR_HEIGHT.dp, BOTTOM_BAR_HEIGHT.dp)
            )
            searchGlass = WGlassView.attachTo(
                searchView,
                BOTTOM_BAR_HEIGHT.dp / 2f,
                GlassProviders.pill(WColor.SearchFieldBackground),
                view
            )
        }
        if (isReceiveAvailable) {
            view.addView(
                tradeButtonsView,
                ViewGroup.LayoutParams(0, (BOTTOM_BAR_HEIGHT + WGlassView.GLASS_PADDING_DP * 2).dp)
            )
            attachTradeButtonGlass(
                receiveButton,
                GlassProviders.pill(WColor.SearchFieldBackground),
                view
            )
            if (areTradeActionsAvailable) {
                attachTradeButtonGlass(buyButton, GlassProviders.shadowOnly(), null)
                attachTradeButtonGlass(sellButton, GlassProviders.shadowOnly(), null)
            }
        }
        view.setConstraints {
            allEdges(recyclerView)
            allEdges(skeletonRecyclerView)
            allEdges(skeletonView)
            toTop(topBlurReversedCornerView)
        }
        updateTradeButtonsLayout()
        applyBalanceModeProgress(balanceModeProgress)

        tokenVM.refreshTransactions()
        topBlurReversedCornerView.alpha = 0f

        updateSkeletonState()
        updateTheme()
    }

    override fun didSetupViews() {
        super.didSetupViews()
        bringBottomBarToFront()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        ExploreHistoryStore.saveTokenVisit(account.accountId, token.slug)
        heavyAnimationDone()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun adjustScrollingPosition(): Boolean {
        val scrollOffset = recyclerView.computeVerticalScrollOffset()
        val collapseDistance = headerCollapseDistance
        if (scrollOffset in 0..collapseDistance) {
            val canGoDown = recyclerView.canScrollVertically(1)
            if (!canGoDown) return true
            val adjustment =
                if (scrollOffset < collapseDistance / 2) {
                    -scrollOffset
                } else {
                    collapseDistance - scrollOffset
                }
            if (adjustment != 0) {
                recyclerView.smoothScrollBy(0, adjustment)
                return true
            }
        }
        return false
    }

    private fun updateSkeletonViews() {
        val skeletonViews = mutableListOf<View>()
        val skeletonViewsRadius = hashMapOf<Int, Float>()
        for (i in 1 until skeletonRecyclerView.childCount) {
            val child = skeletonRecyclerView.getChildAt(i)
            if (child is SkeletonContainer) {
                child.getChildViewMap().forEach {
                    skeletonViews.add(it.key)
                    skeletonViewsRadius[skeletonViews.lastIndex] = it.value
                }
            }
        }
        skeletonView.applyMask(skeletonViews, skeletonViewsRadius)
    }

    private fun onClick(identifier: HeaderActionsView.Identifier) {
        val window = window ?: return
        when (identifier) {
            HeaderActionsView.Identifier.RECEIVE,
            HeaderActionsView.Identifier.SEND,
            HeaderActionsView.Identifier.SWAP,
            HeaderActionsView.Identifier.SELL ->
                if (showUnsupportedChainAlertIfNeeded()) return

            else -> {}
        }
        when (identifier) {
            HeaderActionsView.Identifier.RECEIVE -> {
                val chain = MBlockchain.valueOfOrNull(token.chain) ?: return
                val receiveVC = ReceiveVC.createIfAvailable(
                    context,
                    chain,
                    singleChain = true,
                    tokenSymbol = token.symbol
                ) ?: return
                val navVC = WNavigationController(
                    window,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(receiveVC)
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SEND -> {
                val navVC = WNavigationController(
                    window,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(SendVC(context, token.slug))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SWAP -> {
                val navVC = WNavigationController(
                    window,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(SwapVC(context, defaultSendingToken = MApiSwapAsset.from(token)))
                window.present(navVC)
            }

            HeaderActionsView.Identifier.SELL -> {
                openSellWithCard(token.slug)
            }

            HeaderActionsView.Identifier.MULTISEND -> {
                MultisendLauncher.launch(this)
            }

            HeaderActionsView.Identifier.EARN -> {
                val hasActiveStaking =
                    AccountStore.stakingData?.hasActiveStaking(token.slug) == true
                val navVC = WNavigationController(
                    window,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                if (hasActiveStaking) {
                    navVC.setRoot(EarnRootVC(context, token.slug))
                } else {
                    navVC.setRoot(StakingVC(context, token.slug, StakingViewModel.Mode.STAKE))
                }
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCROLL_TO_TOP -> {
                scrollToTop()
            }

            else -> {}
        }
    }

    private fun presentSwap(isBuying: Boolean) {
        val window = window ?: return
        val selectedAsset = MApiSwapAsset.from(token)
        val navVC = object : WNavigationController(
            window,
            PresentationConfig.PreferredFullScreen
        ) {
            override val centeredWindowMinHeight: Int
                get() = TokenTradeVC.centeredWindowMinHeight
        }
        navVC.setRoot(
            TokenTradeVC(
                context,
                selectedAsset,
                if (isBuying) TokenTradeDirection.BUY else TokenTradeDirection.SELL
            )
        )
        window.present(navVC)
    }

    private var lastDy = -1
    private fun updateScroll(dy: Int) {
        if (dy == lastDy) {
            return
        }
        lastDy = dy
        headerView.updateScroll(dy)
        val actionsLayoutFadeOutPercent =
            max(0f, min(1f, 1 + (headerView.contentHeight - dy.toFloat() - 12.dp) / 92.dp))
        val actionsReveal = if (balanceModeProgress >= 1f) {
            1f
        } else {
            TokenHeaderView.revealFraction(
                actionsRowHeight,
                actionsFullHeight - 16.dp,
                actionsFullHeight,
                balanceModeProgress
            )
        }
        actionsView?.fadeInPercent = actionsLayoutFadeOutPercent
        actionsView?.translationY = (1f - actionsReveal) * TokenHeaderView.REVEAL_OFFSET.dp
        actionsCell?.alpha = actionsReveal
        val alpha = min(
            1f,
            max(
                0f,
                (
                    headerView.contentHeight - dy + (
                        if (account.accountType ==
                            MAccount.AccountType.VIEW
                        ) {
                            0
                        } else {
                            (92.dp * balanceModeProgress).roundToInt()
                        }
                        )
                    ) /
                    ViewConstants.GAP.dp.toFloat() -
                    1
            )
        )
        topBlurReversedCornerView.alpha = 1 - alpha
        if (dy > 0) {
            if (headerView.parent == headerCell) {
                view.post {
                    if (headerView.parent == headerCell) {
                        headerCell?.removeView(headerView)
                        view.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                        headerView.setPaddingLocalized(
                            additionalTabletPadding + systemBarStartInset,
                            0,
                            systemBarEndInset,
                            0
                        )
                        skeletonView.bringToFront()
                        navigationBar?.bringToFront()
                        topBlurViewGuideline?.bringToFront()
                    }
                }
            }
        } else {
            if (headerView.parent == view && headerCell != null) {
                view.post {
                    if (headerView.parent == view && headerCell != null) {
                        view.removeView(headerView)
                        headerCell?.addView(
                            headerView,
                            ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                        )
                        headerView.setPadding(0)
                        headerCell?.setConstraints {
                            toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                        }
                    }
                }
            }
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 4

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            HEADER_SECTION -> tokenInfoRow + 1

            TRANSACTION_SECTION -> if ((showingTransactions?.size ?: 0) > 0) {
                (showingTransactions?.size ?: 0)
            } else {
                0
            }

            EMPTY_VIEW_SECTION -> {
                return if (showingTransactions?.size == 0 || removingEmptyCell) 1 else 0
            }

            LOADING_SECTION -> {
                1
            }

            else -> throw Error()
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            HEADER_SECTION -> {
                when (indexPath.row) {
                    0 -> {
                        HEADER_CELL
                    }

                    1 -> {
                        ACTIONS_CELL
                    }

                    tokenInfoRow -> INFO_CELL

                    else -> CHART_CELL
                }
            }

            EMPTY_VIEW_SECTION -> {
                EMPTY_VIEW_CELL
            }

            LOADING_SECTION -> {
                SKELETON_CELL
            }

            else -> {
                val tx = showingTransactions?.getOrNull(indexPath.row)
                return tx?.let { transaction ->
                    if (transaction.isNft ||
                        (transaction as? MApiTransaction.Transaction)?.hasComment == true
                    ) {
                        TRANSACTION_CELL
                    } else if (indexPath.row == 0 || !transaction.dt.isSameDayAs(
                            showingTransactions?.getOrNull(indexPath.row - 1)?.dt ?: transaction.dt
                        )
                    ) {
                        TRANSACTION_SMALL_FIRST_IN_DAY_CELL
                    } else {
                        TRANSACTION_SMALL_CELL
                    }
                } ?: HEADER_CELL
            }
        }
    }

    private fun onHeightChange(isExpanding: Boolean) {
        rvSkeletonAdapter.notifyItemChanged(0)
        // Handle header height updates when recycler-view scrolled to the end and collapsing the chart
        if (!isExpanding) updateScroll(recyclerView.computeVerticalScrollOffset())
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            HEADER_CELL -> {
                headerCell ?: HeaderSpaceCell(context).also { headerCell = it }
            }

            ACTIONS_CELL -> {
                val actionsView = HeaderActionsView(
                    context,
                    tabs = HeaderActionsView.headerTabs(context, token.isEarnAvailable),
                    onClick = {
                        onClick(it)
                    }
                )
                this.actionsView = actionsView
                actionsView.setPadding(0, 0, 0, 16.dp)
                actionsView.updateActions(account, token.slug)
                WCell(context, ViewGroup.LayoutParams(MATCH_PARENT, actionsRowHeight)).apply {
                    addView(actionsView, ViewGroup.LayoutParams(MATCH_PARENT, actionsFullHeight))
                }.also { actionsCell = it }
            }

            CHART_CELL -> {
                tokenChartCell ?: TokenChartCell(
                    recyclerView,
                    activePeriod = tokenVM.selectedPeriod,
                    onSelectedPeriodChanged = {
                        tokenVM.selectedPeriod = it
                    },
                    onAnalyze = if (EnvironmentStore.isAgentChartAnalysisEnabled) {
                        ::openAgent
                    } else {
                        null
                    },
                    onHeightChange = { isExpanding, _ ->
                        onHeightChange(isExpanding)
                    },
                    viewId = UIComponentsR.id.token_price_card
                ).also {
                    tokenChartCell = it
                    it.iconProgress = 1f - balanceModeProgress
                }
            }

            INFO_CELL -> {
                tokenInfoCell ?: TokenInfoCell(
                    recyclerView,
                    onHeightChange = { isExpanding, _ ->
                        onHeightChange(isExpanding)
                    },
                    onShowInfo = { title, text ->
                        showAlert(title, text)
                    },
                    viewId = UIComponentsR.id.token_info_card
                ).also {
                    tokenInfoCell = it
                    it.setHasBalance(isBalanceModeShown, animated = false)
                }
            }

            TRANSACTION_CELL -> {
                val cell =
                    ActivityCell(
                        recyclerView,
                        withoutTagAndComment = false,
                        isFirstInDay = null,
                        drawsBackground = false
                    )
                cell.allowNftMenu = true
                cell.onTap = { transaction ->
                    onTransactionTap(transaction)
                }
                cell
            }

            TRANSACTION_SMALL_CELL -> {
                val cell =
                    ActivityCell(
                        recyclerView,
                        withoutTagAndComment = true,
                        isFirstInDay = false,
                        drawsBackground = false
                    )
                cell.allowNftMenu = true
                cell.onTap = { transaction ->
                    onTransactionTap(transaction)
                }
                cell
            }

            TRANSACTION_SMALL_FIRST_IN_DAY_CELL -> {
                val cell =
                    ActivityCell(
                        recyclerView,
                        withoutTagAndComment = true,
                        isFirstInDay = true,
                        drawsBackground = false
                    )
                cell.allowNftMenu = true
                cell.onTap = { transaction ->
                    onTransactionTap(transaction)
                }
                cell
            }

            EMPTY_VIEW_CELL -> {
                EmptyCell(context)
            }

            SKELETON_CELL -> {
                SkeletonCell(context, drawsBackground = false)
            }

            else -> {
                throw Error()
            }
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        if (indexPath.section == TRANSACTION_SECTION &&
            indexPath.row >= (showingTransactions?.size ?: 0) - 20
        ) {
            tokenVM.activityLoader?.useBudgetTransactions()
        }

        when (indexPath.section) {
            HEADER_SECTION -> {
                when (indexPath.row) {
                    0 -> {
                        val cellLayoutParams = RecyclerView.LayoutParams(MATCH_PARENT, 0)
                        cellLayoutParams.height =
                            (navigationController?.getSystemBars()?.top ?: 0) +
                            TokenHeaderView.navDefaultHeight +
                            headerView.contentHeight
                        cellHolder.cell.layoutParams = cellLayoutParams
                    }

                    1 -> {
                    }

                    tokenInfoRow -> {
                        val cell = cellHolder.cell as TokenInfoCell
                        cell.configure(tokenVM.tokenInfoState)
                    }

                    else -> {
                        val cell = cellHolder.cell as TokenChartCell
                        cell.configure(
                            token,
                            tokenVM.historyData,
                            tokenVM.selectedPeriod,
                            tokenVM.backfill
                        )
                    }
                }
                return
            }

            TRANSACTION_SECTION -> {
                val transactions = showingTransactions
                val transaction = transactions?.getOrNull(indexPath.row)
                if (transactions != null && transaction != null) {
                    val homeTransactionCell = cellHolder.cell as ActivityCell
                    val nextTransaction = transactions.getOrNull(indexPath.row + 1)
                    val previousTransaction = transactions.getOrNull(indexPath.row - 1)
                    val isFirstInDay =
                        previousTransaction == null ||
                            !transaction.dt.isSameDayAs(previousTransaction.dt)
                    val isLastInDay =
                        nextTransaction == null ||
                            (
                                !transaction.dt.isSameDayAs(nextTransaction.dt) &&
                                    tokenVM.activityLoader?.loadedAll != false
                                )
                    val isAddedAsNewDay = isFirstInDay &&
                        oldTransactionsFirstDt?.let { !transaction.dt.isSameDayAs(it) } != false
                    homeTransactionCell.configure(
                        transaction,
                        account.accountId,
                        account.isMultichain,
                        ActivityCell.Positioning(
                            isFirst = indexPath.row == 0,
                            isFirstInDay = isFirstInDay,
                            isLastInDay = isLastInDay,
                            isLast = false,
                            isAdded = isApplyingUpdate &&
                                oldTransactions?.contains(transaction.getStableId()) == false,
                            isAddedAsNewDay = isAddedAsNewDay
                        )
                    )
                } else {
                    val layoutParams: ViewGroup.LayoutParams = cellHolder.cell.layoutParams
                    layoutParams.height =
                        if (tokenVM.activityLoader?.loadedAll != false) ViewConstants.GAP.dp else 0
                    cellHolder.cell.layoutParams = layoutParams
                }
            }

            EMPTY_VIEW_SECTION -> {
                (cellHolder.cell as EmptyCell).let { cell ->
                    cell.updateTheme()
                    if (removingEmptyCell) {
                        collapseEmptyCell(cell)
                        return@let
                    }
                    emptyCellCollapseAnimation?.cancel()
                    cell.emptyView.alpha = 1f
                    cell.layoutParams = cell.layoutParams.apply {
                        height = emptyCellHeight()
                    }
                }
            }

            LOADING_SECTION -> {
                (cellHolder.cell as SkeletonCell).apply {
                    configure(indexPath.row, false, isLast = true)
                    updateTheme()
                    val isHidden = showingTransactions == null ||
                        tokenVM.activityLoader?.loadedAll != false
                    visibility = if (isHidden) INVISIBLE else VISIBLE
                    layoutParams = layoutParams.apply {
                        height = if (isHidden) 0 else SkeletonCell.HEIGHT
                    }
                }
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        when (indexPath.section) {
            TRANSACTION_SECTION -> {
                showingTransactions?.getOrNull(indexPath.row)?.let { return it.getStableId() }
            }
        }
        return super.recyclerViewCellItemId(rv, indexPath)
    }

    override fun updateTheme() {
        super.updateTheme()
        recyclerView.setBackgroundColor(WColor.SecondaryBackground.color)
        recyclerView.invalidate()
        updateSkeletonState()
        headerView.updateTheme()
        actionsView?.updateTheme()
        tokenInfoCell?.updateTheme()
        tradeButtonGlasses.forEach { it.updateTheme() }
        if (isSearchAvailable) {
            searchGlass?.updateTheme()
            searchEditText.updateTheme()
            searchEditText.highlightColor = WColor.Tint.color.colorWithAlpha(51)
        }
        rvAdapter.reloadData()
    }

    override fun updateProtectedView() {
    }

    // Bottom padding that lets short content scroll far enough to collapse the header.
    private var baseBottomPadding = 0
    private var collapseGap = 0

    private fun updateCollapseGap() {
        val gap = computeCollapseGap()
        if (gap == collapseGap) return
        collapseGap = gap
        recyclerView.updatePadding(bottom = baseBottomPadding + collapseGap)
    }

    private var removingEmptyCell = false
    private var emptyCellCollapseAnimation: SpringAnimation? = null
    private val removalFallbackHandler = Handler(Looper.getMainLooper())
    private var removalFallback: Runnable? = null

    private fun collapseEmptyCell(cell: EmptyCell) {
        if (emptyCellCollapseAnimation?.isRunning == true) return
        val startHeight = if (cell.height > 0) cell.height else cell.layoutParams.height
        if (startHeight <= 0) {
            finishRemovingEmptyCell()
            return
        }
        val fadeStartHeight = 0.7f * startHeight
        val fadeRange = startHeight - fadeStartHeight
        emptyCellCollapseAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(startHeight.toFloat())
            spring = SpringForce(0f).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            setMinValue(0f)
            addUpdateListener { _, value, _ ->
                cell.updateLayoutParams { height = value.toInt().coerceAtLeast(0) }
                cell.emptyView.alpha = ((value - fadeStartHeight) / fadeRange).coerceIn(0f, 1f)
            }
            addEndListener { _, _, _, _ ->
                emptyCellCollapseAnimation = null
                finishRemovingEmptyCell()
            }
            start()
        }
    }

    private fun finishRemovingEmptyCell() {
        removalFallback?.let { removalFallbackHandler.removeCallbacks(it) }
        removalFallback = null
        if (!removingEmptyCell) return
        if (recyclerView.isComputingLayout) {
            recyclerView.post { if (!isDestroyed) finishRemovingEmptyCell() }
            return
        }
        removingEmptyCell = false
        rvAdapter.reloadData()
    }

    private fun emptyCellHeight(): Int {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManagerAccurateOffset
        val occupiedHeight =
            (navigationController?.getSystemBars()?.top ?: 0) +
                TokenHeaderView.navDefaultHeight +
                headerView.contentHeight - headerCollapseDistance +
                (layoutManager?.getItemHeight(1) ?: 0) +
                (tokenChartCell?.height ?: 0) +
                (tokenInfoCell?.height?.takeIf { it > 0 } ?: TokenInfoCell.collapsedCellHeight) +
                (if (tokenVM.activityLoader?.loadedAll == false) SkeletonCell.HEIGHT else 0) +
                baseBottomPadding
        return (recyclerView.height - occupiedHeight).coerceAtLeast(160.dp)
    }

    private fun updateEmptyCellHeight() {
        if (showingTransactions?.size != 0 || recyclerView.height <= 0) return
        val layoutManager =
            recyclerView.layoutManager as? LinearLayoutManagerAccurateOffset ?: return
        val cell = layoutManager.findViewByPosition(tokenInfoRow + 1) as? EmptyCell ?: return
        if (cell.layoutParams.height == emptyCellHeight()) return
        recyclerView.post {
            if (showingTransactions?.size != 0) return@post
            val attachedCell = (recyclerView.layoutManager as? LinearLayoutManagerAccurateOffset)
                ?.findViewByPosition(tokenInfoRow + 1) as? EmptyCell ?: return@post
            val height = emptyCellHeight()
            if (attachedCell.layoutParams.height != height) {
                attachedCell.layoutParams = attachedCell.layoutParams.apply {
                    this.height = height
                }
            }
        }
    }

    private fun computeCollapseGap(): Int {
        val layoutManager =
            recyclerView.layoutManager as? LinearLayoutManagerAccurateOffset ?: return 0
        val itemCount = rvAdapter.itemCount
        if (itemCount == 0 || recyclerView.height <= 0) return 0
        // Rows shrink during the balance transition; keep the scroll position reachable.
        if (balanceModeAnimator != null) return recyclerView.height
        var contentBottom = layoutManager.findViewByPosition(itemCount - 1)?.let {
            layoutManager.getDecoratedBottom(it)
        } ?: layoutManager.estimateContentBottom(itemCount) ?: return 0
        if (removingEmptyCell) {
            val emptyPosition = tokenInfoRow + 1 + (showingTransactions?.size ?: 0)
            layoutManager.findViewByPosition(emptyPosition)?.let {
                contentBottom -= it.height
            }
        }
        val currentOffset = recyclerView.computeVerticalScrollOffset()
        val contentTop = recyclerView.paddingTop - currentOffset
        val scrollable = contentBottom - contentTop +
            recyclerView.paddingTop + baseBottomPadding - recyclerView.height
        val collapseOffset = recyclerView.paddingTop + headerCollapseDistance
        return (max(collapseOffset, currentOffset) - scrollable).coerceAtLeast(0)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val navBottomPadding = navigationController?.bottomInset ?: 0
        baseBottomPadding = if (isBottomBarVisible) {
            maxOf(
                navBottomPadding + 60.dp,
                tradeButtonsBottomMargin() + (BOTTOM_BAR_HEIGHT + ViewConstants.GAP).dp
            )
        } else {
            navBottomPadding
        }
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            baseBottomPadding + collapseGap
        )
        skeletonRecyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            skeletonRecyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            skeletonRecyclerView.paddingBottom
        )
        if (topBlurReversedCornerView.layoutParams != null) {
            topBlurReversedCornerView.updateLayoutParams {
                height = (navigationController?.getSystemBars()?.top ?: 0) +
                    TokenHeaderView.navDefaultHeight +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
            }
        }
        if (headerView.layoutParams != null) {
            headerView.updateLayoutParams {
                height = (navigationController?.getSystemBars()?.top ?: 0) +
                    TokenHeaderView.navDefaultHeight + headerView.contentHeight
            }
        }
        if (headerView.parent == headerCell) {
            headerCell?.setConstraints {
                toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
        } else {
            headerView.setPaddingLocalized(
                additionalTabletPadding + systemBarStartInset,
                0,
                systemBarEndInset,
                0
            )
        }
        rvAdapter.notifyItemChanged(0)
        rvSkeletonAdapter.notifyItemChanged(0)
        actionsView?.insetsUpdated()
        updateTradeButtonsLayout()
        bringBottomBarToFront()
        if (isSearchAvailable) {
            keyboardLift.animatedValue = targetKeyboardLift()
            searchOverlayNav?.insetsUpdated()
        }
    }

    override fun onBackPressed(): Boolean {
        searchOverlayNav?.takeIf { it.viewControllers.size > 1 }?.let {
            return it.onBackPressed()
        }
        if (isSearchAvailable) {
            if (searchEditText.hasFocus()) {
                clearSearchFocus()
                return false
            }
            if (!searchEditText.text.isNullOrEmpty()) {
                searchEditText.setText("")
                return false
            }
        }
        return super.onBackPressed()
    }

    private fun onTransactionTap(transaction: MApiTransaction) {
        window?.let { window ->
            val transactionNav = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.BottomSheet
                )
            )
            transactionNav.setRoot(TransactionVC(context, account.accountId, transaction))
            window.present(transactionNav)
        }
    }

    private fun openAgent() {
        val navigationController = navigationController ?: return
        val prompt = LocaleController.getStringWithKeyValues(
            "\$agent_prompt_token_price",
            listOf("%token%" to (token.displayName ?: token.name ?: token.symbol))
        )
        val entryPoint = AgentV2EntryPoint(
            kind = "tokenScreen",
            asset = AgentV2AssetRef(
                slug = token.slug,
                chain = token.chain,
                tokenAddress = token.tokenAddress
            )
        )
        AgentNavigation.openNewChat(context, navigationController, prompt, entryPoint)
    }

    private var emptyView: WEmptyView? = null
    private var oldTransactions: Set<String>? = null
    private var oldTransactionsFirstDt: Date? = null
    private var isApplyingUpdate = false

    override fun dataUpdated(isUpdateEvent: Boolean) {
        if (isDestroyed) return
        if (recyclerView.isComputingLayout) {
            recyclerView.post { dataUpdated(isUpdateEvent) }
            return
        }
        showingTransactions = tokenVM.showingTransactions?.toList()
        updateSkeletonState()
        if (isUpdateEvent &&
            oldTransactions?.isEmpty() == true &&
            (showingTransactions?.size ?: 0) > 0
        ) {
            removingEmptyCell = true
            removalFallback?.let { removalFallbackHandler.removeCallbacks(it) }
            val fallback = Runnable { finishRemovingEmptyCell() }
            removalFallback = fallback
            removalFallbackHandler.postDelayed(fallback, REMOVE_ANIMATION_FALLBACK_MS)
        }
        isApplyingUpdate = isUpdateEvent && oldTransactions != null
        rvAdapter.reloadData()
        view.post {
            isApplyingUpdate = false
            showingTransactions?.let { showingTransactions ->
                oldTransactions =
                    showingTransactions.map { it.getStableId() }.toSet()
                oldTransactionsFirstDt = showingTransactions.firstOrNull()?.dt
            } ?: run {
                oldTransactions = null
                oldTransactionsFirstDt = null
            }
        }
    }

    override fun loadedAll() {
        dataUpdated(isUpdateEvent = false)
    }

    override fun priceDataUpdated() {
        token = TokenStore.getToken(token.slug) ?: token
        updateSkeletonState()
        updateBalanceMode()
        headerView.reloadData()
        if (!isLpToken) {
            recyclerView.post {
                rvAdapter.notifyItemChanged(2)
            }
        }
    }

    override fun tokenInfoUpdated() {
        recyclerView.post {
            rvAdapter.notifyItemChanged(tokenInfoRow)
            rvSkeletonAdapter.notifyItemChanged(0)
        }
    }

    override fun stateChanged() {
    }

    override fun accountChanged() {
        if (isDestroyed) return
        if (!AccountStore.isPushedTemporary && AccountStore.activeAccountId != account.accountId) {
            navigationController?.pop(animated = false)
        }
    }

    override fun accountRemoved() {
        navigationController?.removeViewController(this)
    }

    override fun cacheNotFound() {
        rvSkeletonAdapter.reloadData()
        view.post {
            updateSkeletonViews()
            skeletonAlpha = 1f
            skeletonRecyclerView.visibility = VISIBLE
            skeletonRecyclerView.alpha = 1f
            skeletonView.startAnimating()
        }
    }

    private var skeletonAlpha = 0f
    private fun updateSkeletonState() {
        if (skeletonAlpha > 0f &&
            showingTransactions != null &&
            (
                (showingTransactions?.size ?: 0) > 0 ||
                    tokenVM.activityLoader?.loadedAll == true
                )
        ) {
            skeletonAlpha = 0f
            skeletonView.fadeOut(onCompletion = {
                skeletonView.stopAnimating()
            })
            skeletonRecyclerView.fadeOut {
                if (skeletonAlpha == 0f) skeletonRecyclerView.visibility = GONE
            }
        }
    }

    override fun onDestroy() {
        buyButton.setOnClickListener(null)
        sellButton.setOnClickListener(null)
        receiveButton.setOnClickListener(null)
        removalFallbackHandler.removeCallbacksAndMessages(null)
        emptyCellCollapseAnimation?.cancel()
        balanceModeAnimator?.cancel()
        dismissSearchResults()
        searchOverlayNav?.let { nav ->
            searchOverlayNav = null
            nav.viewControllers.forEach { it.viewWillDisappear() }
            view.removeView(nav)
            nav.onDestroy()
        }
        super.onDestroy()
        dataSource = null
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.setOnOverScrollListener(null)
        recyclerView.layoutManager = null
        recyclerView.adapter = null
        recyclerView.removeAllViews()
        skeletonRecyclerView.adapter = null
        skeletonRecyclerView.removeAllViews()
        tokenChartCell?.onDestroy()
        tokenInfoCell?.onDestroy()
        actionsView?.onDestroy()
        tokenVM.onDestroy()
    }
}
