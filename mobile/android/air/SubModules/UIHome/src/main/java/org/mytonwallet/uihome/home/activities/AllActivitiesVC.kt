package org.mytonwallet.uihome.home.activities

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.EmptyCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.helpers.ActivityLoader
import org.mytonwallet.app_air.walletcore.helpers.IActivityLoader
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

/** Full, paged activity history of one account; opened from the home "Show All Actions" row. */
class AllActivitiesVC(
    context: Context,
    private val accountId: String,
    private val onTransactionTap: (transaction: MApiTransaction) -> Unit
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    IActivityLoader.Delegate {
    @Suppress("PropertyName")
    override val TAG = "AllActivities"

    companion object {
        val TRANSACTION_CELL = WCell.Type(1)
        val TRANSACTION_SMALL_CELL = WCell.Type(2)
        val TRANSACTION_SMALL_FIRST_IN_DAY_CELL = WCell.Type(3)
        val EMPTY_VIEW_CELL = WCell.Type(4)
        val SKELETON_CELL = WCell.Type(5)

        const val TRANSACTION_SECTION = 0
        const val EMPTY_VIEW_SECTION = 1
        const val LOADING_SECTION = 2
    }

    override val shouldDisplayBottomBar = true

    private val isMultichain = WGlobalStorage.isMultichain(accountId)
    private var activityLoader: IActivityLoader? = null
    private val showingTransactions: List<MApiTransaction>?
        get() = activityLoader?.showingTransactions

    private var oldTransactions: Set<String>? = null
    private var oldTransactionsFirstDt: Date? = null
    private var oldShowingTransactions: List<MApiTransaction>? = null
    private var isApplyingUpdate = false

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
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
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0) return
            updateBlurViews(recyclerView)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                updateBlurViews(recyclerView)
            }
        }
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.setItemAnimator(null)
        rv.clipToPadding = false
        rv.addOnScrollListener(scrollListener)
        rv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Activity"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }

        activityLoader = ActivityLoader(context, accountId, null, WeakReference(this))
        activityLoader?.askForActivities()

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.reloadData()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top ?: 0),
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            navigationController?.bottomInset ?: 0
        )
    }

    override fun onDestroy() {
        activityLoader?.clean()
        activityLoader = null
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        super.onDestroy()
    }

    // ACTIVITY LOADER /////////////////////////////////////////////////////////////////////////////
    override fun activityLoaderDataLoaded(isUpdateEvent: Boolean) {
        isApplyingUpdate = isUpdateEvent && oldTransactions != null
        val old = oldShowingTransactions
        val new = showingTransactions
        if (old.isNullOrEmpty() || new.isNullOrEmpty()) {
            rvAdapter.reloadData()
        } else {
            rvAdapter.applyChanges(old, new, TRANSACTION_SECTION, true)
        }
        oldShowingTransactions = new?.toList()
        recyclerView.post {
            isApplyingUpdate = false
            oldTransactions = showingTransactions?.map { it.getStableId() }?.toSet()
            oldTransactionsFirstDt = showingTransactions?.firstOrNull()?.dt
        }
    }

    override fun activityLoaderCacheNotFound() {
        rvAdapter.reloadData()
    }

    override fun activityLoaderLoadedAll() {
        rvAdapter.reloadData()
    }

    // RECYCLER VIEW ///////////////////////////////////////////////////////////////////////////////
    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 3

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = when (section) {
        TRANSACTION_SECTION -> showingTransactions?.size ?: 0
        EMPTY_VIEW_SECTION -> if (showingTransactions?.isEmpty() == true) 1 else 0
        LOADING_SECTION -> 1
        else -> 0
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when (indexPath.section) {
            EMPTY_VIEW_SECTION -> EMPTY_VIEW_CELL

            LOADING_SECTION -> SKELETON_CELL

            else -> {
                val transactions = showingTransactions ?: return SKELETON_CELL
                val transaction = transactions[indexPath.row]
                if (transaction.isNft ||
                    (transaction as? MApiTransaction.Transaction)?.hasComment == true
                ) {
                    TRANSACTION_CELL
                } else if (indexPath.row == 0 ||
                    !transaction.dt.isSameDayAs(transactions[indexPath.row - 1].dt)
                ) {
                    TRANSACTION_SMALL_FIRST_IN_DAY_CELL
                } else {
                    TRANSACTION_SMALL_CELL
                }
            }
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            TRANSACTION_CELL -> activityCell(withoutTagAndComment = false, isFirstInDay = null)

            TRANSACTION_SMALL_CELL -> activityCell(
                withoutTagAndComment = true,
                isFirstInDay = false
            )

            TRANSACTION_SMALL_FIRST_IN_DAY_CELL ->
                activityCell(withoutTagAndComment = true, isFirstInDay = true)

            EMPTY_VIEW_CELL -> EmptyCell(context)

            else -> SkeletonCell(context)
        }

    private fun activityCell(withoutTagAndComment: Boolean, isFirstInDay: Boolean?): ActivityCell =
        ActivityCell(recyclerView, withoutTagAndComment, isFirstInDay).apply {
            allowNftMenu = true
            onTap = { transaction -> onTransactionTap(transaction) }
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        if (indexPath.section == TRANSACTION_SECTION &&
            indexPath.row >= (showingTransactions?.size ?: 0) - 20
        ) {
            activityLoader?.useBudgetTransactions()
        }

        when (indexPath.section) {
            TRANSACTION_SECTION -> {
                val transactions = showingTransactions ?: return
                val transaction = transactions[indexPath.row]
                val isFirstInDay = indexPath.row == 0 ||
                    !transaction.dt.isSameDayAs(transactions[indexPath.row - 1].dt)
                val isLastRow = indexPath.row == transactions.size - 1
                (cellHolder.cell as ActivityCell).configure(
                    transaction = transaction,
                    accountId = accountId,
                    isMultichain = isMultichain,
                    positioning = ActivityCell.Positioning(
                        isFirst = indexPath.row == 0,
                        isFirstInDay = isFirstInDay,
                        isLastInDay = isLastRow ||
                            !transaction.dt.isSameDayAs(transactions[indexPath.row + 1].dt),
                        isLast = isLastRow && activityLoader?.loadedAll != false,
                        isAdded = isApplyingUpdate &&
                            oldTransactions?.contains(transaction.getStableId()) == false,
                        isAddedAsNewDay = isFirstInDay &&
                            oldTransactionsFirstDt?.let { !transaction.dt.isSameDayAs(it) } != false
                    )
                )
            }

            EMPTY_VIEW_SECTION -> {
                (cellHolder.cell as EmptyCell).let { cell ->
                    cell.updateTheme()
                    cell.layoutParams = cell.layoutParams.apply {
                        height = recyclerView.height -
                            recyclerView.paddingTop -
                            recyclerView.paddingBottom
                    }
                }
            }

            LOADING_SECTION -> {
                (cellHolder.cell as SkeletonCell).apply {
                    configure(indexPath.row, false, isLast = true)
                    updateTheme()
                    visibility =
                        if (showingTransactions == null || activityLoader?.loadedAll == true) {
                            View.INVISIBLE
                        } else {
                            View.VISIBLE
                        }
                }
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? =
        when (indexPath.section) {
            TRANSACTION_SECTION -> showingTransactions?.getOrNull(indexPath.row)?.getStableId()
            else -> null
        }
}
