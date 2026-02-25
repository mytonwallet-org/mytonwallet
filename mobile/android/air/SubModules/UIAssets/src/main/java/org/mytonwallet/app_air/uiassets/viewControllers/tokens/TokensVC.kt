package org.mytonwallet.app_air.uiassets.viewControllers.tokens

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.cells.TokenCell
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconTitleSubtitleActionView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.ShowAllView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.helpers.SelectiveItemAnimator
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItemVC
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.AssetsAndActivitiesVC
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uistake.helpers.ClaimRewardsHelper
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

@SuppressLint("ViewConstructor")
class TokensVC(
    context: Context,
    private var showingAccountId: String,
    private val mode: Mode,
    private val onHeightChanged: (() -> Unit)? = null,
    private val onAssetsShown: (() -> Unit)? = null,
    private val onScroll: ((rv: RecyclerView) -> Unit)? = null
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, WalletCore.EventObserver,
    WSegmentedControllerItemVC {
    override val TAG = "Tokens"

    private var isShowingAccountMultichain = WGlobalStorage.isMultichain(showingAccountId)
    private var _showingAccount: MAccount? = null
    private fun fetchAccount(accountId: String): MAccount {
        _showingAccount?.let {
            if (it.accountId == accountId)
                return it
        }
        val activeAccount = AccountStore.activeAccount
        _showingAccount = if (activeAccount?.accountId == accountId)
            activeAccount
        else
            AccountStore.accountById(accountId)
        return _showingAccount!!
    }

    enum class Mode {
        HOME,
        ALL
    }

    companion object {
        val TOKEN_CELL = WCell.Type(1)
    }

    override var title: String?
        get() {
            return LocaleController.getString("Assets")
        }
        set(_) {
        }

    override val shouldDisplayTopBar = false

    override val isSwipeBackAllowed = false

    private val queueDispatcher =
        Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + queueDispatcher)

    private var walletTokens: Array<MTokenBalance> = emptyArray()
    private var pinnedSlugs: Set<String> = emptySet()

    private var thereAreMoreToShow: Boolean = false
    private var isScreenFullyVisible = false
    private var emptyTokensViewHeight = 0
    private var isEmptyStateVisible = false
    private var currentHeight: Int = 0
    private var heightAnimator: ValueAnimator? = null

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(TOKEN_CELL)).apply {
            setHasStableIds(true)
        }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0)
                return
            updateBlurViews(recyclerView)
            onScroll?.invoke(recyclerView)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                updateBlurViews(recyclerView)
                onScroll?.invoke(recyclerView)
            }
        }
    }

    private val itemAnimator: SelectiveItemAnimator = SelectiveItemAnimator().apply {
        setAll(WGlobalStorage.getAreAnimationsActive())
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        if (mode == Mode.ALL) {
            rv.addItemDecoration(
                LastItemPaddingDecoration(
                    navigationController?.getSystemBars()?.bottom ?: 0
                )
            )
        }
        rv.itemAnimator = itemAnimator
        if (mode == Mode.ALL) {
            rv.setPadding(
                0,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    WNavigationBar.DEFAULT_HEIGHT.dp,
                0,
                0
            )
            rv.clipToPadding = false
        }
        rv.addOnScrollListener(scrollListener)
        rv
    }

    private val showAllView: ShowAllView by lazy {
        val v = ShowAllView(context)
        v.configure(
            icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_show_assets,
            text = LocaleController.getString("Show All Assets")
        )
        v.onTap = {
            val window = this.window!!
            val navVC = WNavigationController(window)
            navVC.setRoot(
                AssetsTabVC(
                    context,
                    showingAccountId = showingAccountId,
                    defaultSelectedIdentifier = AssetsTabVC.TAB_COINS
                )
            )
            window.present(navVC)
        }
        v.visibility = View.GONE
        v
    }

    private val emptyDataView: WEmptyIconTitleSubtitleActionView by lazy {
        WEmptyIconTitleSubtitleActionView(context).apply {
            configure(
                titleText = LocaleController.getString("No tokens yet"),
                subtitleText = LocaleController.getString($$"$no_tokens_description"),
                actionText = LocaleController.getString("Add Tokens"),
                animation = org.mytonwallet.app_air.uicomponents.R.raw.animation_empty
            ) {
                openManageTokens()
            }
            isGone = true
        }
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (mode == Mode.HOME) {
            view.addView(showAllView, ViewGroup.LayoutParams(MATCH_PARENT, 56.dp))
        }
        view.addView(emptyDataView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.setConstraints {
            allEdges(recyclerView)
            toCenterX(emptyDataView)
            if (mode == Mode.HOME) {
                toTop(showAllView, 300f)
                toCenterX(showAllView)
                toTop(emptyDataView)
            } else {
                toCenterY(emptyDataView)
            }
        }

        if (mode == Mode.ALL)
            recyclerView.disallowInterceptOnOverscroll()

        WalletCore.registerObserver(this)
        dataUpdated(forceUpdate = false)

        updateTheme()
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        super.updateTheme()

        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark

        if (mode == Mode.HOME) {
            view.background = null
        } else {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
        }
        emptyDataView.updateTheme()
        rvAdapter.reloadData()
    }

    fun configure(accountId: String) {
        if (showingAccountId == accountId)
            return
        scope.coroutineContext.cancelChildren()
        walletTokens = emptyArray()
        rvAdapter.reloadData()
        prevSize = -1
        showingAccountId = accountId
        isShowingAccountMultichain = WGlobalStorage.isMultichain(accountId)
        dataUpdated(forceUpdate = true)
    }

    var prevSize = -1
    private fun dataUpdated(forceUpdate: Boolean) {
        scope.launch {
            val accountId = showingAccountId
            val showingAccount = fetchAccount(accountId)
            val isSingleWalletActive = MScreenMode.SingleWallet(accountId).isScreenActive

            if (!forceUpdate && !isSingleWalletActive) {
                return@launch
            }

            val cachedAssetsAndActivityData = AccountStore.assetsAndActivityData
            val assetsAndActivityData = if (cachedAssetsAndActivityData.accountId == accountId) {
                cachedAssetsAndActivityData
            } else {
                MAssetsAndActivityData(accountId)
            }
            val newPinnedSlugs = assetsAndActivityData.pinnedTokens.toSet()
            val allWalletTokens: Array<MTokenBalance> = assetsAndActivityData.getAllTokens(
                addVirtualStakingTokens = true
            )

            val filteredWalletTokens = allWalletTokens.filter {
                if (it.isVirtualStakingRow) {
                    val slug = it.virtualStakingToken ?: return@filter false
                    !assetsAndActivityData.hiddenTokens.contains(slug)
                } else {
                    val token = TokenStore.getToken(it.token)
                    token?.isHidden(
                        showingAccount,
                        assetsAndActivityData
                    ) != true
                }
            }
            withContext(Dispatchers.Main) {
                pinnedSlugs = newPinnedSlugs
                walletTokens = if (mode == Mode.HOME) {
                    filteredWalletTokens.take(5).toTypedArray()
                } else {
                    filteredWalletTokens.toTypedArray()
                }
                val moreToShow = mode == Mode.HOME && filteredWalletTokens.size > 5
                val moreToShowChanged = thereAreMoreToShow != moreToShow
                thereAreMoreToShow = moreToShow
                showAllView.visibility = if (thereAreMoreToShow) View.VISIBLE else View.GONE
                updateEmptyTokensState()
                if (walletTokens.size != prevSize || moreToShowChanged) {
                    prevSize = walletTokens.size
                    if (mode == Mode.HOME) {
                        animateHeight()
                    } else {
                        onHeightChanged?.invoke()
                    }
                }
                itemAnimator.with(recyclerView) {
                    rvAdapter.reloadData()
                }
                onAssetsShown?.invoke()
            }
        }
    }

    val calculatedHeight: Int
        get() {
            return if (mode == Mode.HOME) {
                currentHeight
            } else {
                finalHeight
            }
        }

    private val finalHeight: Int
        get() {
            return if (mode == Mode.HOME && walletTokens.isEmpty()) {
                if (view.width > 0 && emptyDataView.width != view.width) {
                    emptyDataView.measure(view.width.exactly, view.height.unspecified)
                    emptyTokensViewHeight = emptyDataView.measuredHeight
                }
                emptyTokensViewHeight
            } else {
                (60 * walletTokens.size).dp + (if (thereAreMoreToShow) 56 else 0).dp
            }
        }

    private fun animateHeight() {
        if (mode != Mode.HOME) {
            return
        }
        val targetHeight = finalHeight
        val startHeight = currentHeight
        if (startHeight == 0) {
            currentHeight = targetHeight
            onHeightChanged?.invoke()
            return
        }
        if (startHeight == targetHeight) {
            return
        }
        heightAnimator?.cancel()
        if (!WGlobalStorage.getAreAnimationsActive()) {
            currentHeight = targetHeight
            onHeightChanged?.invoke()
            return
        }
        heightAnimator = ValueAnimator.ofInt(startHeight, targetHeight).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener { animator ->
                currentHeight = animator.animatedValue as Int
                onHeightChanged?.invoke()
            }
            start()
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BalanceChanged,
            WalletEvent.TokensChanged,
            WalletEvent.AssetsAndActivityDataUpdated,
            is WalletEvent.AccountChanged,
            WalletEvent.StakingDataUpdated,
            WalletEvent.BaseCurrencyChanged -> {
                dataUpdated(forceUpdate = false)
            }

            else -> {}
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return walletTokens.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return TOKEN_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        when (cellType) {
            TOKEN_CELL -> {
                val cell = TokenCell(context, mode)
                cell.onTap = { tokenBalance ->
                    val token = TokenStore.getToken(tokenBalance.token)
                    token?.let {
                        if (tokenBalance.isVirtualStakingRow) {
                            val navVC = WNavigationController(window!!)
                            navVC.setRoot(EarnRootVC(context, tokenSlug = token.slug))
                            window?.present(navVC)
                            return@let
                        }
                        val account = AccountStore.activeAccount ?: return@let
                        val tokenVC = TokenVC(context, account, it)
                        navigationController?.push(tokenVC)
                    }
                }
                cell.onLongPress = { tokenBalance ->
                    TokenStore.getToken(tokenBalance.token)?.let { token ->
                        onTokenPressed(cell, tokenBalance, token)
                    }
                }
                return cell
            }

            else -> {
                throw Exception()
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val tokenBalance = walletTokens[indexPath.row]
        val isPinned = tokenBalance.virtualStakingToken?.let { pinnedSlugs.contains(it) } == true
        (cellHolder.cell as TokenCell).configure(
            showingAccountId,
            isShowingAccountMultichain,
            tokenBalance,
            isPinned,
            isFirst = mode == Mode.ALL && indexPath.row == 0 && isScreenFullyVisible,
            isLast = indexPath.row == walletTokens.size - 1 && !thereAreMoreToShow
        )
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return walletTokens.getOrNull(indexPath.row)?.virtualStakingToken
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        queueDispatcher.close()
        heightAnimator?.cancel()
        WalletCore.unregisterObserver(this)
        recyclerView.onDestroy()
        recyclerView.adapter = null
        recyclerView.removeAllViews()
        showAllView.onTap = null
    }

    override fun onFullyVisible() {
        updateScreenVisibility(true)
    }

    override fun onPartiallyVisible() {
        updateScreenVisibility(false)
    }

    private fun updateScreenVisibility(isFullyVisible: Boolean) {
        isScreenFullyVisible = isFullyVisible
        if (walletTokens.isNotEmpty()) {
            rvAdapter.notifyItemChanged(0)
        }
    }

    private fun updateEmptyTokensState() {
        val shouldShowEmptyState = walletTokens.isEmpty()
        if (shouldShowEmptyState != isEmptyStateVisible) {
            isEmptyStateVisible = shouldShowEmptyState
            onHeightChanged?.invoke()
        }
        emptyDataView.isVisible = shouldShowEmptyState
        recyclerView.isGone = shouldShowEmptyState
        onHeightChanged?.invoke()
    }

    private fun onTokenPressed(tokenView: View, tokenBalance: MTokenBalance, token: MToken) {
        val items = buildActions(tokenBalance, token)
        if (items.isEmpty()) {
            return
        }
        WMenuPopup.present(
            tokenView,
            items = items,
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.BELOW,
            centerHorizontally = true,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout(
                tokenView.frameAsPath(
                    ViewConstants.BLOCK_RADIUS.dp
                )
            )
        )
    }

    private fun buildActions(tokenBalance: MTokenBalance, token: MToken): List<WMenuPopup.Item> {
        val accountType = _showingAccount?.accountType ?: return emptyList()
        return if (accountType != MAccount.AccountType.VIEW) {
            buildUserAccountActions(tokenBalance, token)
        } else {
            emptyList()
        }.toMutableList().apply {
            val isPinned =
                tokenBalance.virtualStakingToken?.let { pinnedSlugs.contains(it) } == true
            if (isPinned) {
                add(
                    WMenuPopup.Item(
                        R.drawable.ic_unpin_30,
                        LocaleController.getString("Unpin")
                    ) { unPin(tokenBalance) }
                )
            } else {
                add(
                    WMenuPopup.Item(
                        R.drawable.ic_pin_30,
                        LocaleController.getString("Pin")
                    ) { pin(tokenBalance) }
                )
            }
            add(
                WMenuPopup.Item(
                    R.drawable.ic_manage_30,
                    LocaleController.getString("Manage Tokens")
                ) { openManageTokens() }
            )
        }
    }

    private fun buildUserAccountActions(
        tokenBalance: MTokenBalance,
        token: MToken
    ): List<WMenuPopup.Item> {
        val actions = if (tokenBalance.isVirtualStakingRow) {
            buildStakingActions(tokenBalance)
        } else {
            buildTokenActions(token)
        }.toMutableList()
        actions.last().hasSeparator = true
        return actions
    }

    private fun buildTokenActions(token: MToken): List<WMenuPopup.Item> {
        val actions: MutableList<WMenuPopup.Item> = mutableListOf()
        actions.add(
            WMenuPopup.Item(
                R.drawable.ic_plus_30,
                LocaleController.getString("Fund")
            ) { openAdd(token) }
        )
        actions.add(
            WMenuPopup.Item(
                R.drawable.ic_arrow_up_thin_30,
                LocaleController.getString("Send")
            ) { openSend(token) }
        )
        actions.add(
            WMenuPopup.Item(
                R.drawable.ic_swap_30,
                LocaleController.getString("Swap")
            ) { openSwap(token) }
        )
        if (token.isEarnAvailable) {
            val hasActiveStaking = AccountStore.stakingData?.hasActiveStaking(token.slug) == true
            actions.add(
                WMenuPopup.Item(
                    R.drawable.ic_stake_30,
                    LocaleController.getString(if (hasActiveStaking) "Earning" else "Earn")
                ) { openStake(token, hasActiveStaking) }
            )
        }
        return actions
    }

    private fun buildStakingActions(tokenBalance: MTokenBalance): List<WMenuPopup.Item> {
        val actions = mutableListOf(
            WMenuPopup.Item(
                R.drawable.ic_arrow_up_thin_30,
                LocaleController.getString("Stake More")
            ) { stakeMore(tokenBalance) },
            WMenuPopup.Item(
                R.drawable.ic_arrow_down_thin_30,
                LocaleController.getString("Unstake")
            ) { unstake(tokenBalance) }
        )
        val stakingState = AccountStore.stakingData?.stakingState(tokenBalance.token)
        if (ClaimRewardsHelper.canClaimRewards(stakingState)) {
            actions.add(
                WMenuPopup.Item(
                    R.drawable.ic_diamond_30,
                    LocaleController.getString("Claim Rewards")
                ) { claimRewards(tokenBalance) }
            )
        }
        return actions
    }

    private fun openAdd(token: MToken) {
        val window = this.window ?: return
        val navVC = WNavigationController(window).apply {
            setRoot(ReceiveVC(context, MBlockchain.valueOf(token.chain)))
        }
        window.present(navVC)
    }

    private fun openSend(token: MToken) {
        val window = this.window ?: return
        val navVC = WNavigationController(window).apply {
            setRoot(SendVC(context, token.slug))
        }
        window.present(navVC)
    }

    private fun openSwap(token: MToken) {
        val window = this.window ?: return
        val navVC = WNavigationController(window)
        navVC.setRoot(
            SwapVC(
                context,
                defaultSendingToken = MApiSwapAsset.from(token),
                defaultReceivingToken =
                    if (token.slug == MBlockchain.ton.nativeSlug) {
                        null
                    } else {
                        MApiSwapAsset(
                            slug = MBlockchain.ton.nativeSlug,
                            symbol = "TON",
                            chain = MBlockchain.ton.name,
                            decimals = 9
                        )
                    }
            )
        )
        window.present(navVC)
    }

    private fun openStake(token: MToken, hasActiveStaking: Boolean) {
        val window = this.window ?: return
        val navVC = WNavigationController(window).apply {
            if (hasActiveStaking) {
                setRoot(EarnRootVC(context, token.slug))
            } else {
                setRoot(StakingVC(context, token.slug, StakingViewModel.Mode.STAKE))
            }
        }
        window.present(navVC)
    }

    private fun openManageTokens() {
        val window = this.window ?: return
        val navVC = WNavigationController(window).apply {
            setRoot(AssetsAndActivitiesVC(context))
        }
        window.present(navVC)
    }

    private fun pin(tokenBalance: MTokenBalance) {
        updatePinnedToken(tokenBalance, shouldPin = true)
    }

    private fun unPin(tokenBalance: MTokenBalance) {
        updatePinnedToken(tokenBalance, shouldPin = false)
    }

    private fun stakeMore(tokenBalance: MTokenBalance) {
        val token = tokenBalance.token ?: return
        val window = this.window ?: return
        val navVC = WNavigationController(window).apply {
            setRoot(StakingVC(context, token, StakingViewModel.Mode.STAKE))
        }
        window.present(navVC)
    }

    private fun unstake(tokenBalance: MTokenBalance) {
        val token = tokenBalance.token ?: return
        val window = this.window ?: return
        val navVC = WNavigationController(window).apply {
            setRoot(StakingVC(context, token, StakingViewModel.Mode.UNSTAKE))
        }
        window.present(navVC)
    }

    private fun claimRewards(tokenBalance: MTokenBalance) {
        val tokenSlug = tokenBalance.token ?: return
        val stakingState = AccountStore.stakingData?.stakingState(tokenSlug) ?: return
        ClaimRewardsHelper.presentClaimRewards(
            viewController = this,
            tokenSlug = tokenSlug,
            stakingState = stakingState,
            amountToClaim = stakingState.amountToClaim,
            onError = { error ->
                showError(error)
            }
        )
    }

    private fun updatePinnedToken(tokenBalance: MTokenBalance, shouldPin: Boolean) {
        val accountId = showingAccountId
        if (AccountStore.activeAccountId != accountId) {
            return
        }
        val virtualStakingSlug = tokenBalance.virtualStakingToken ?: return
        val currentData = AccountStore.assetsAndActivityData
        val pinned = currentData.pinnedTokens.toMutableList()
        val isPinned = pinned.contains(virtualStakingSlug)
        if (shouldPin == isPinned) {
            return
        }
        pinned.removeAll { it == virtualStakingSlug }
        if (shouldPin) {
            pinned.add(0, virtualStakingSlug)
        }
        currentData.pinnedTokens = ArrayList(pinned)
        AccountStore.updateAssetsAndActivityData(
            newValue = currentData,
            notify = true,
            saveToStorage = true
        )
    }
}
