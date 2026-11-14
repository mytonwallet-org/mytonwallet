package org.mytonwallet.app_air.uifutures.viewControllers.futures

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.LinedCenteredTitleView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.SelectiveItemAnimator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.stories.StoriesPresentationSource
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesActivityCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesBalanceWithdrawalCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesMarketRowCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesOnboardingBannerCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesOperationStatusCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesPositionCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesPositionsSummaryCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesSectionHeaderCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesShowAllPositionsCell
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.setCardPadding
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.FuturesOnboarding
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.futuresCoin
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.marketSection
import org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity.presentAllFuturesActivities
import org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity.presentFuturesActivity
import org.mytonwallet.app_air.uifutures.viewControllers.futuresMarkets.FuturesMarketsVC
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.FuturesOperationActions
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.presentFuturesOperation
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.showFuturesOperationAlert
import org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.FuturesPositionVC
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketSection
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketToken
import org.mytonwallet.app_air.uimarket.viewControllers.market.cells.MarketGridSectionCell
import org.mytonwallet.app_air.uimarket.viewControllers.market.cells.MarketMoversSectionCell
import org.mytonwallet.app_air.uimarket.viewControllers.market.cells.SECTION_BOTTOM_SPACING
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsBalanceWithdrawal
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsMarketSection
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOperation
import org.mytonwallet.app_air.walletcore.moshi.PERPS_LAYOUT_GRID
import org.mytonwallet.app_air.walletcore.moshi.PERPS_LAYOUT_LARGE_HORIZONTAL
import org.mytonwallet.app_air.walletcore.moshi.PERPS_LAYOUT_ROWS
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

@SuppressLint("ViewConstructor")
class FuturesVC(context: Context) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    FuturesVM.Delegate {
    @Suppress("PropertyName")
    override val TAG = "Futures"

    override val shouldDisplayTopBar = true

    private val futuresVM by lazy { FuturesVM(this) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var operationActions: FuturesOperationActions? = null
    private var showsAllPositions = false
    private var rowsAccountId: String? = null

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(
            SUMMARY_CELL,
            OPERATION_STATUS_CELL,
            BALANCE_WITHDRAWAL_CELL,
            ONBOARDING_CELL,
            POSITION_CELL,
            SHOW_ALL_POSITIONS_CELL,
            TITLE_CELL,
            MARKET_CELL,
            SHOW_ALL_MARKETS_CELL,
            MOVERS_CELL,
            GRID_CELL,
            MOVERS_HEADERLESS_CELL,
            SECTION_HEADER_CELL,
            ACTIVITY_CELL
        )
    ).apply {
        setHasStableIds(true)
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.computeVerticalScrollOffset() == 0 ||
                !recyclerView.canScrollVertically(1)
            ) {
                updateBlurViews(recyclerView)
            }
        }

        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dy != 0) updateBlurViews(recyclerView)
        }
    }
    private val recyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        layoutManager = LinearLayoutManager(context)
        clipToPadding = false
        itemAnimator = SelectiveItemAnimator().apply {
            setAll(WGlobalStorage.getAreAnimationsActive())
        }
        addOnScrollListener(scrollListener)
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        navigationBar?.setTitleGravity(Gravity.START)
        updateTopOverlay(animated = false)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }

        futuresVM.start()
        updateTheme()
        insetsUpdated()
    }

    override fun onRootTopGradientModeChanged(enabled: Boolean) {
        rvAdapter.updateVisibleCells()
        updateTopOverlay(animated = false)
        if (isViewConfigured) insetsUpdated()
    }

    private fun updateTopOverlay(animated: Boolean) {
        setNavTitle(
            if (isRootTopGradientEnabled) "" else LocaleController.getString("Futures"),
            animated
        )
        // The titleless bar must not take the list's touches
        navigationBar?.isClickable = !isRootTopGradientEnabled
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        updateTopOverlay(animated = false)
        val top = (navigationController?.getSystemBars()?.top ?: 0) +
            if (isRootTopGradientEnabled) 0 else WNavigationBar.DEFAULT_HEIGHT.dp
        val bottom = if (isRootTopGradientEnabled) {
            navigationController?.getSystemBars()?.bottom ?: 0
        } else {
            navigationController?.bottomInset ?: 0
        }
        recyclerView.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            top,
            systemBarEndInset,
            bottom
        )
    }

    override fun scrollToTop() {
        recyclerView.smoothScrollToPosition(0)
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        futuresVM.isShown = true
        futuresVM.refresh()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        futuresVM.isShown = false
    }

    override fun futuresUpdated() {
        reloadRows()
    }

    private fun reloadRows() {
        val accountId = AccountStore.activeAccountId
        if (accountId != rowsAccountId) {
            rowsAccountId = accountId
            showsAllPositions = false
        }
        val oldRows = rows
        rows = buildRows()
        if (isOnboardingSwap(oldRows, rows)) {
            animateOnboardingSwap()
            rvAdapter.notifyItemChanged(0)
            // A payload rebinds without a crossfade
            rvAdapter.notifyItemRangeChanged(1, rows.size - 1, REBIND_PAYLOAD)
        } else {
            rvAdapter.reloadData()
        }
    }

    private fun animateOnboardingSwap() {
        val animator = recyclerView.itemAnimator as? SelectiveItemAnimator ?: return
        if (!WGlobalStorage.getAreAnimationsActive()) return
        animator.supportsChangeAnimations = true
        animator.changeDuration = AnimationConstants.QUICK_ANIMATION
        animator.moveDuration = AnimationConstants.QUICK_ANIMATION
        recyclerView.post {
            animator.isRunning {
                animator.supportsChangeAnimations = false
                animator.changeDuration = 0
                animator.moveDuration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
            }
        }
    }

    private fun isOnboardingSwap(oldRows: List<Row>, newRows: List<Row>): Boolean {
        val oldFirst = oldRows.firstOrNull() ?: return false
        val newFirst = newRows.firstOrNull() ?: return false
        return (oldFirst == Row.Onboarding) != (newFirst == Row.Onboarding) &&
            oldRows.drop(1).map { it.id } == newRows.drop(1).map { it.id }
    }

    private val visiblePositions: List<MApiPerpsNativePosition>
        get() = if (showsAllPositions) {
            futuresVM.positions
        } else {
            futuresVM.positions.take(VISIBLE_POSITIONS)
        }

    private sealed interface Row {
        val id: String
        val type: WCell.Type

        data object Summary : Row {
            override val id = "summary"
            override val type = SUMMARY_CELL
        }

        // Shares the summary's id so the swap crossfades
        data object Onboarding : Row {
            override val id = Summary.id
            override val type = ONBOARDING_CELL
        }

        data class OperationStatus(val operation: MApiPerpsOperation) : Row {
            override val id = "operationStatus"
            override val type = OPERATION_STATUS_CELL
        }

        data class BalanceWithdrawal(val withdrawal: MApiPerpsBalanceWithdrawal) : Row {
            override val id = "balanceWithdrawal"
            override val type = BALANCE_WITHDRAWAL_CELL
        }

        data class Position(
            val position: MApiPerpsNativePosition,
            val isFirst: Boolean,
            val isLast: Boolean
        ) : Row {
            override val id = "position:${position.coin}"
            override val type = POSITION_CELL
        }

        data class ShowAllPositions(val count: Int) : Row {
            override val id = "showAllPositions"
            override val type = SHOW_ALL_POSITIONS_CELL
        }

        /** The lined title above the backend's sections. */
        data object MarketsTitle : Row {
            override val id = "marketsTitle"
            override val type = TITLE_CELL
        }

        data class SectionHeader(val group: MApiPerpsMarketSection) : Row {
            override val id = "sectionHeader:${group.id}"
            override val type = SECTION_HEADER_CELL
        }

        data class GroupTitle(val group: MApiPerpsMarketSection) : Row {
            override val id = "groupTitle:${group.id}"
            override val type = TITLE_CELL
        }

        data class Market(
            val group: MApiPerpsMarketSection,
            val market: MApiPerpsListedAsset,
            val isFirst: Boolean,
            val isLast: Boolean
        ) : Row {
            override val id = "market:${group.id}:${market.name}"
            override val type = MARKET_CELL
        }

        /** A section drawn as the Market screen's cards or grid, with its own header. */
        data class MarketSectionCard(
            val group: MApiPerpsMarketSection,
            override val type: WCell.Type
        ) : Row {
            override val id = "marketSection:${group.id}"
        }

        data class ShowAllMarkets(val group: MApiPerpsMarketSection) : Row {
            override val id = "showAllMarkets:${group.id}"
            override val type = SHOW_ALL_MARKETS_CELL
        }

        data object Activity : Row {
            override val id = "activity"
            override val type = ACTIVITY_CELL
        }
    }

    private var rows: List<Row> = listOf(Row.Summary)

    private fun buildRows(): List<Row> = buildList {
        when {
            futuresVM.showsOnboarding -> add(Row.Onboarding)

            futuresVM.snapshot == null || futuresVM.positionsStatus != null ||
                futuresVM.snapshot?.unavailableDexs?.isNotEmpty() == true ||
                futuresVM.positions.isNotEmpty() -> add(Row.Summary)
        }
        PerpsStore.visibleOperationStatus(AccountStore.activeAccountId)?.let {
            add(Row.OperationStatus(it))
        }
        val positions = visiblePositions
        val hasMorePositions = futuresVM.positions.size > positions.size
        positions.forEachIndexed { index, position ->
            add(
                Row.Position(
                    position,
                    isFirst = index == 0,
                    isLast = index == positions.lastIndex && !hasMorePositions
                )
            )
        }
        if (hasMorePositions) add(Row.ShowAllPositions(futuresVM.positions.size))
        futuresVM.snapshot?.balanceWithdrawal?.let { add(Row.BalanceWithdrawal(it)) }
        val groups = futuresVM.marketGroups
        if (groups.any { it.id != FuturesVM.ALL_MARKETS_GROUP_ID }) add(Row.MarketsTitle)
        for (group in groups) {
            when {
                group.id == FuturesVM.ALL_MARKETS_GROUP_ID -> addAllMarketsGroup(group)

                group.layout == PERPS_LAYOUT_LARGE_HORIZONTAL -> add(
                    Row.MarketSectionCard(
                        group,
                        if (group.title.isBlank()) MOVERS_HEADERLESS_CELL else MOVERS_CELL
                    )
                )

                group.layout == PERPS_LAYOUT_GRID -> add(Row.MarketSectionCard(group, GRID_CELL))

                else -> {
                    add(Row.SectionHeader(group))
                    val markets = group.visibleAssets
                    markets.forEachIndexed { index, market ->
                        add(
                            Row.Market(
                                group,
                                market,
                                isFirst = false,
                                isLast = index == markets.lastIndex
                            )
                        )
                    }
                }
            }
        }
        if (futuresVM.activities.isNotEmpty() || futuresVM.isLoadingActivities) add(Row.Activity)
    }

    /** Every market under a lined title, for a backend without sections. */
    private fun MutableList<Row>.addAllMarketsGroup(group: MApiPerpsMarketSection) {
        add(Row.GroupTitle(group))
        val markets = group.visibleAssets
        markets.forEachIndexed { index, market ->
            add(
                Row.Market(
                    group,
                    market,
                    isFirst = index == 0,
                    isLast = index == markets.lastIndex && !group.hasHiddenAssets
                )
            )
        }
        if (group.hasHiddenAssets) add(Row.ShowAllMarkets(group))
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = rows.size

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String =
        rows[indexPath.row].id

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        rows[indexPath.row].type

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            SUMMARY_CELL -> FuturesPositionsSummaryCell(context)

            ONBOARDING_CELL -> FuturesOnboardingBannerCell(
                context,
                ::openOnboarding,
                futuresVM::dismissOnboarding
            )

            BALANCE_WITHDRAWAL_CELL -> FuturesBalanceWithdrawalCell(context) {
                AccountStore.activeAccountId?.let { operationActions(it).withdrawBalance() }
            }

            OPERATION_STATUS_CELL -> FuturesOperationStatusCell(context) {
                PerpsStore.visibleOperationStatus(AccountStore.activeAccountId)
                    ?.let(::presentOperation)
            }

            POSITION_CELL -> FuturesPositionCell(context, ::openPosition)

            SHOW_ALL_POSITIONS_CELL -> FuturesShowAllPositionsCell(
                context,
                LocaleController.getString("Show All Positions"),
                ::showAllPositions
            )

            SHOW_ALL_MARKETS_CELL -> FuturesShowAllPositionsCell(
                context,
                LocaleController.getString("Show All")
            ) {}

            MARKET_CELL -> FuturesMarketRowCell(context, ::openMarket)

            MOVERS_CELL -> MarketMoversSectionCell(context, ::showAllSection, ::openMarketToken)

            MOVERS_HEADERLESS_CELL -> MarketMoversSectionCell(
                context,
                ::showAllSection,
                ::openMarketToken,
                showsHeader = false
            )

            SECTION_HEADER_CELL -> FuturesSectionHeaderCell(context)

            GRID_CELL -> MarketGridSectionCell(context, ::showAllSection, ::openMarketToken)

            TITLE_CELL -> LinedCenteredTitleView(context).apply {
                configureText(WFont.Regular, WColor.SecondaryText, 16f)
                lineColor = WColor.SecondaryText
            }

            else -> FuturesActivityCell(context, ::presentFuturesActivity) {
                presentAllFuturesActivities(null)
            }
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val bottomSpacing = if (isRootTopGradientEnabled && indexPath.row == rows.lastIndex) {
            0
        } else {
            SECTION_BOTTOM_SPACING
        }
        val cell = cellHolder.cell
        when (val row = rows[indexPath.row]) {
            Row.Summary -> (cell as FuturesPositionsSummaryCell).configure(
                futuresVM.snapshot,
                futuresVM.isLoading,
                futuresVM.positionsStatus,
                isStatusRetryable = futuresVM.isPositionsStatusRetryable,
                isStale = futuresVM.isStale
            )

            Row.Onboarding -> (cell as FuturesOnboardingBannerCell).configure()

            is Row.OperationStatus -> (cell as FuturesOperationStatusCell).configure(row.operation)

            is Row.BalanceWithdrawal -> (cell as FuturesBalanceWithdrawalCell).configure(
                row.withdrawal,
                canWithdraw = PerpsStore.canTrade(AccountStore.activeAccount),
                isPreparing = operationActions?.isBusy == true
            )

            is Row.Position -> (cell as FuturesPositionCell).configure(
                row.position,
                isFirst = row.isFirst,
                isLast = row.isLast,
                isStale = futuresVM.isStale
            )

            is Row.ShowAllPositions -> (cell as FuturesShowAllPositionsCell).configure(row.count)

            Row.MarketsTitle -> (cell as LinedCenteredTitleView).configure(
                LocaleController.getString("Futures Market"),
                11.dp,
                24.dp
            )

            is Row.SectionHeader -> (cell as FuturesSectionHeaderCell).configure(
                row.group.title,
                row.group.showsSeeAll
            ) { showAllMarkets(row.group) }

            is Row.GroupTitle ->
                (cell as LinedCenteredTitleView).configure(row.group.title, 11.dp, 24.dp)

            is Row.Market -> (cell as FuturesMarketRowCell).configure(
                row.market,
                isFirst = row.isFirst,
                isLast = row.isLast
            )

            is Row.MarketSectionCard -> {
                when (cell) {
                    is MarketMoversSectionCell -> cell.configure(row.group.marketSection)
                    is MarketGridSectionCell -> cell.configure(row.group.marketSection)
                    else -> {}
                }
                // Market insets these by its list padding
                cell.setCardPadding(cell.paddingBottom)
            }

            is Row.ShowAllMarkets -> (cell as FuturesShowAllPositionsCell).configure(
                row.group.assets.size
            ) { showAllMarkets(row.group) }

            Row.Activity ->
                (cell as FuturesActivityCell).configure(
                    futuresVM.activities,
                    bottomSpacing,
                    isLoading = futuresVM.isLoadingActivities,
                    showsAll = futuresVM.hasMoreActivities,
                    animatesChanges = WGlobalStorage.getAreAnimationsActive()
                )
        }
    }

    private fun presentOperation(operation: MApiPerpsOperation) {
        if (DEBUG_MODE) {
            presentFuturesOperation(operation)
            return
        }
        showFuturesOperationAlert(operation, operationActions(operation.accountId))
    }

    private fun operationActions(accountId: String) =
        operationActions?.takeIf { it.accountId == accountId }
            ?: FuturesOperationActions(this, accountId, scope, onBusyChanged = ::reloadRows)
                .also { operationActions = it }

    override fun onDestroy() {
        scope.cancel()
        futuresVM.stop()
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.layoutManager = null
        super.onDestroy()
    }

    private fun openOnboarding(source: StoriesPresentationSource) {
        val window = window ?: return
        FuturesOnboarding.makeStoriesView(window, PerpsStore.onboarding)
            .apply {
                presentationSource = source
                onPresented = { recyclerView.scrollToPosition(0) }
            }
            .present()
    }

    private fun showAllPositions() {
        if (showsAllPositions) return
        showsAllPositions = true
        reloadRows()
    }

    private fun openPosition(position: MApiPerpsNativePosition) {
        val targetNavigationController =
            navigationController?.tabBarController?.mainNavigationController
                ?: navigationController
        targetNavigationController?.push(FuturesPositionVC(context, position.coin))
    }

    private fun showAllMarkets(group: MApiPerpsMarketSection) {
        presentInNavigation(
            FuturesMarketsVC(
                context,
                group.id,
                hasSearch = group.layout == PERPS_LAYOUT_ROWS
            )
        )
    }

    private fun showAllSection(section: MarketSection) {
        futuresVM.marketGroups.firstOrNull { it.id == section.section.id }?.let(::showAllMarkets)
    }

    private fun openMarketToken(token: MarketToken) {
        val coin = token.futuresCoin ?: return
        val targetNavigationController =
            navigationController?.tabBarController?.mainNavigationController
                ?: navigationController
        targetNavigationController?.push(FuturesPositionVC(context, coin))
    }

    private fun openMarket(market: MApiPerpsListedAsset) {
        val targetNavigationController =
            navigationController?.tabBarController?.mainNavigationController
                ?: navigationController
        targetNavigationController?.push(FuturesPositionVC(context, market.name))
    }

    private companion object {
        val SUMMARY_CELL = WCell.Type(1)
        val POSITION_CELL = WCell.Type(2)
        val SHOW_ALL_POSITIONS_CELL = WCell.Type(3)
        val TITLE_CELL = WCell.Type(4)
        val MARKET_CELL = WCell.Type(5)
        val SHOW_ALL_MARKETS_CELL = WCell.Type(6)
        val MOVERS_CELL = WCell.Type(7)
        val ACTIVITY_CELL = WCell.Type(8)
        val GRID_CELL = WCell.Type(9)
        val MOVERS_HEADERLESS_CELL = WCell.Type(10)
        val SECTION_HEADER_CELL = WCell.Type(11)
        val OPERATION_STATUS_CELL = WCell.Type(12)
        val BALANCE_WITHDRAWAL_CELL = WCell.Type(13)
        val ONBOARDING_CELL = WCell.Type(14)

        const val VISIBLE_POSITIONS = 5
        private const val REBIND_PAYLOAD = "rebind"
    }
}
