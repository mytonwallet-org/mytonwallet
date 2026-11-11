package org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.EmptyCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.ActivitySectionBackgroundDecoration
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesActivityRowCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

/** Presents the whole history, as the home screen's Show All Actions does. */
internal fun WViewController.presentAllFuturesActivities(coin: String?) {
    presentInNavigation(FuturesAllActivitiesVC(context, coin))
}

/** The full, paged perps history of an account, or one market's; opened from Show All Actions. */
@SuppressLint("ViewConstructor")
class FuturesAllActivitiesVC(context: Context, private val coin: String?) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "FuturesAllActivities"

    override val shouldDisplayBottomBar = true

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    private var activities: List<MApiPerpsFill>? = null
    private var hasMore = false

    private var oldActivityIds: Set<String>? = null
    private var oldFirstActivityTime: Long? = null
    private var isApplyingUpdate = false

    /** Nothing loaded yet, or older activity still to fetch. */
    private val showsLoadingRow: Boolean
        get() = activities == null || hasMore

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(ACTIVITY_CELL, EMPTY_VIEW_CELL, SKELETON_CELL)
        ).apply {
            setHasStableIds(true)
        }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            if (dx == 0 && dy == 0) return
            updateBlurViews(recyclerView)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                updateBlurViews(recyclerView)
            }
        }
    }

    private val sectionBackgroundDecoration = ActivitySectionBackgroundDecoration(
        firstPosition = { 0 },
        rowCount = { (activities?.size ?: 0) + if (showsLoadingRow) 1 else 0 }
    )

    private val recyclerView by lazy {
        WRecyclerView(this).apply {
            adapter = rvAdapter
            val manager = LinearLayoutManagerAccurateOffset(context)
            manager.isSmoothScrollbarEnabled = true
            layoutManager = manager
            setItemAnimator(null)
            addItemDecoration(sectionBackgroundDecoration)
            clipToPadding = false
            addOnScrollListener(scrollListener)
        }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        navigationBar?.addCloseButton()
        setNavTitle(LocaleController.getString("Activity"))
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }
        WalletCore.registerObserver(this)
        rebuild()
        insetsUpdated()
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.reloadData()
        recyclerView.invalidate()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            max(
                navigationController?.bottomInset ?: 0,
                navigationController?.getSystemBars()?.bottom ?: 0
            )
        )
    }

    override fun scrollToTop() {
        recyclerView.smoothScrollToPosition(0)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent == WalletEvent.PerpsUpdated) rebuild()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        PerpsStore.watch(this)
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        PerpsStore.unwatch(this)
    }

    override fun onDestroy() {
        WalletCore.unregisterObserver(this)
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.layoutManager = null
        super.onDestroy()
    }

    private fun rebuild() {
        if (isDestroyed) return
        if (recyclerView.isComputingLayout) {
            recyclerView.post { rebuild() }
            return
        }
        val accountId = displayedAccount.accountId
        activities = PerpsStore.fillsFor(accountId)?.filter { coin == null || it.coin == coin }
        hasMore = PerpsStore.hasMoreFills(accountId)
        isApplyingUpdate = oldActivityIds != null && WGlobalStorage.getAreAnimationsActive()
        rvAdapter.reloadData()
        recyclerView.post {
            isApplyingUpdate = false
            oldActivityIds = activities?.mapTo(HashSet()) { it.identity }
            oldFirstActivityTime = activities?.firstOrNull()?.time
        }
    }

    private fun loadMore() {
        displayedAccount.accountId?.let(PerpsStore::loadMoreFills)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 3

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = when (section) {
        ACTIVITY_SECTION -> activities?.size ?: 0
        EMPTY_VIEW_SECTION -> if (activities?.isEmpty() == true && !hasMore) 1 else 0
        LOADING_SECTION -> if (showsLoadingRow) 1 else 0
        else -> 0
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? =
        when (indexPath.section) {
            ACTIVITY_SECTION -> activities?.getOrNull(indexPath.row)?.identity
            else -> null
        }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when (indexPath.section) {
            ACTIVITY_SECTION -> ACTIVITY_CELL
            EMPTY_VIEW_SECTION -> EMPTY_VIEW_CELL
            else -> SKELETON_CELL
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            ACTIVITY_CELL -> FuturesActivityRowCell(context, ::presentFuturesActivity)
            EMPTY_VIEW_CELL -> EmptyCell(context)
            else -> SkeletonCell(context, drawsBackground = false)
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (indexPath.section) {
            ACTIVITY_SECTION -> {
                val activities = activities ?: return
                val activity = activities.getOrNull(indexPath.row) ?: return
                if (indexPath.row >= activities.size - LOAD_MORE_THRESHOLD) loadMore()
                (cellHolder.cell as? FuturesActivityRowCell)?.configure(
                    activity,
                    positioning(activities, indexPath.row)
                )
            }

            EMPTY_VIEW_SECTION -> (cellHolder.cell as EmptyCell).let { cell ->
                cell.updateTheme()
                cell.layoutParams = cell.layoutParams.apply {
                    height = recyclerView.height -
                        recyclerView.paddingTop -
                        recyclerView.paddingBottom
                }
            }

            LOADING_SECTION -> {
                // A market's activity can be sparse, so reaching this row also asks for more
                loadMore()
                (cellHolder.cell as SkeletonCell).apply {
                    configure(indexPath.row, false, isLast = true)
                    updateTheme()
                }
            }
        }
    }

    /** Only activity newer than what was shown is new; an older page just extends the list. */
    private fun positioning(
        activities: List<MApiPerpsFill>,
        row: Int
    ): FuturesActivityRowCell.Positioning {
        val activity = activities[row]
        val date = Date(activity.time)
        val isFirstInDay = row == 0 || !date.isSameDayAs(Date(activities[row - 1].time))
        val isNew = isApplyingUpdate &&
            oldActivityIds?.contains(activity.identity) == false &&
            activity.time > (oldFirstActivityTime ?: Long.MIN_VALUE)
        return FuturesActivityRowCell.Positioning(
            isFirst = row == 0,
            isFirstInDay = isFirstInDay,
            isLast = row == activities.lastIndex && !hasMore,
            isAdded = isNew,
            isAddedAsNewDay = isNew && isFirstInDay &&
                oldFirstActivityTime?.let { !date.isSameDayAs(Date(it)) } != false
        )
    }

    private companion object {
        val ACTIVITY_CELL = WCell.Type(1)
        val EMPTY_VIEW_CELL = WCell.Type(2)
        val SKELETON_CELL = WCell.Type(3)

        const val ACTIVITY_SECTION = 0
        const val EMPTY_VIEW_SECTION = 1
        const val LOADING_SECTION = 2

        const val LOAD_MORE_THRESHOLD = 20
    }
}
