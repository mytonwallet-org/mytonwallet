package org.mytonwallet.app_air.uibrowser.viewControllers.explore

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.net.toUri
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlin.math.max
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreCategoryCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreCategoryTitleCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreConnectedCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreTrendingCell
import org.mytonwallet.app_air.uibrowser.viewControllers.exploreCategory.ExploreCategoryVC
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.ConnectedAppsVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore

@SuppressLint("ViewConstructor")
class ExploreVC(context: Context) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    ExploreVM.Delegate {
    @Suppress("PropertyName")
    override val TAG = "Explore"

    companion object {
        val EXPLORE_TITLE_CELL = WCell.Type(1)
        val EXPLORE_CONNECTED_ROW_CELL = WCell.Type(2)
        val EXPLORE_TRENDING_CELL = WCell.Type(3)
        val EXPLORE_CATEGORY_CELL = WCell.Type(4)

        const val SECTION_CONNECTED = 0
        const val SECTION_TRENDING = 1
        const val SECTION_ALL = 2
    }

    override val shouldDisplayTopBar = true
    override val shouldHideKeyboardOnDisappear = false

    private var pendingTarget: Uri? = null

    private val exploreVMLazy = lazy {
        ExploreVM(this)
    }
    private val exploreVM by exploreVMLazy

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                EXPLORE_TITLE_CELL,
                EXPLORE_CONNECTED_ROW_CELL,
                EXPLORE_TRENDING_CELL,
                EXPLORE_CATEGORY_CELL
            )
        )

    private var emptyView: WEmptyIconView? = null

    private val recyclerView: WRecyclerView by lazy {
        val layoutManager = GridLayoutManager(context, gridWidth.coerceAtLeast(1))
        val rv = object : WRecyclerView(this) {
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                if (w == oldw) return
                onWidthChanged(w)
            }
        }
        rv.adapter = rvAdapter
        layoutManager.isSmoothScrollbarEnabled = true
        layoutManager.spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
            override fun getSpanSize(position: Int): Int {
                val indexPath = rvAdapter.positionToIndexPath(position)
                val fullWidth = gridWidth
                val span = when (indexPath.section) {
                    SECTION_CONNECTED, SECTION_TRENDING -> fullWidth

                    else -> {
                        if (indexPath.row == 0) {
                            fullWidth
                        } else {
                            val dappsCols = calculateNoOfColumns()
                            val col = indexPath.row % dappsCols // 1=first, 0=last
                            val baseCell = cellWidth
                            val leftGap = 8.dp + ViewConstants.HORIZONTAL_PADDINGS.dp
                            if (col == 0) {
                                val others = (baseCell * (dappsCols - 1)) + leftGap
                                fullWidth - others
                            } else {
                                baseCell + (if (col == 1) leftGap else 0)
                            }
                        }
                    }
                }
                return span.coerceIn(1, layoutManager.spanCount)
            }
        }
        rv.layoutManager = layoutManager
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
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
        })
        rv.clipToPadding = false
        rv
    }

    init {
        WalletCore.doOnBridgeReady {
            if (!isDestroyed) exploreVM.delegateIsReady()
        }
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

        updateEmptyView()

        updateTheme()
    }

    private fun updateTopOverlay(animated: Boolean) {
        setNavTitle(
            if (isRootTopGradientEnabled) "" else LocaleController.getString("Explore"),
            animated
        )
    }

    override fun onRootTopGradientModeChanged(enabled: Boolean) {
        updateTopOverlay(animated = false)
        if (isViewConfigured) insetsUpdated()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val topPadding = (navigationController?.getSystemBars()?.top ?: 0) +
            if (isRootTopGradientEnabled) 0 else WNavigationBar.DEFAULT_HEIGHT.dp
        val bottomPadding = if (isRootTopGradientEnabled) {
            navigationController?.getSystemBars()?.bottom ?: 0
        } else {
            navigationController?.bottomInset ?: 0
        }
        recyclerView.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            topPadding,
            systemBarEndInset,
            bottomPadding
        )
        bottomReversedCornerView?.setHorizontalPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
        )
        rvAdapter.reloadData()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun onSiteTap(app: MExploreSite) {
        pendingTarget = null
        if (app.url.isNullOrEmpty()) {
            return
        }
        val uri = app.uri ?: return
        openTargetUri(app, uri)
    }

    private fun onCategoryTap(category: MExploreCategory) {
        val categoryVC = ExploreCategoryVC(context, category)
        navigationController?.tabBarController?.mainNavigationController?.push(categoryVC)
    }

    private var lastEffectiveViewWidth = 0
    private val effectiveViewWidth: Int
        get() {
            val w = (view.parent?.parent as? View)?.width ?: 0
            if (w > 0) {
                lastEffectiveViewWidth = w
                return w
            }
            return if (lastEffectiveViewWidth > 0) {
                lastEffectiveViewWidth
            } else {
                context.resources.displayMetrics.widthPixels
            }
        }

    private val contentWidth: Int
        get() = effectiveViewWidth - additionalTabletPadding - systemBarStartInset -
            systemBarEndInset

    private val gridWidth: Int
        get() = contentWidth

    private val cellWidth: Int
        get() {
            val cols = calculateNoOfColumns()
            return (contentWidth - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - 16.dp) / cols
        }

    private val trendingCellWidth: Int
        get() {
            val cols = calculateNoOfColumns()
            return (contentWidth - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - 4.dp) / cols
        }

    override fun onBackPressed(): Boolean {
        (window?.window?.currentFocus as? WSearchEditText)?.let {
            it.clearFocus()
            return false
        }
        return super.onBackPressed()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 3

    val catsCount: Int
        get() {
            val colCount = calculateNoOfColumns()
            return (
                (
                    exploreVM.showingExploreCategories?.size
                        ?: 0
                    ) / colCount.toFloat()
                ).ceilToInt() * colCount
        }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        if (exploreVM.showingExploreCategories == null) return 0
        when (section) {
            SECTION_CONNECTED -> {
                return if (exploreVM.connectedSites.isNullOrEmpty()) {
                    0
                } else {
                    2
                }
            }

            SECTION_TRENDING -> {
                return if (exploreVM.showingTrendingSites.isEmpty()) 0 else 2
            }

            SECTION_ALL -> {
                return if (catsCount > 0) 1 + catsCount else 0
            }

            else -> {
                throw Exception()
            }
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type = when {
        indexPath.row == 0 -> EXPLORE_TITLE_CELL

        indexPath.section == SECTION_CONNECTED -> {
            EXPLORE_CONNECTED_ROW_CELL
        }

        indexPath.section == SECTION_TRENDING -> EXPLORE_TRENDING_CELL

        else -> EXPLORE_CATEGORY_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            EXPLORE_TITLE_CELL -> {
                ExploreCategoryTitleCell(context)
            }

            EXPLORE_CONNECTED_ROW_CELL -> {
                ExploreConnectedCell(context, dAppPressed = {
                    onDAppTap(it)
                }) {
                    pushConfigure()
                }
            }

            EXPLORE_TRENDING_CELL -> {
                ExploreTrendingCell(context, trendingCellWidth) {
                    onSiteTap(it)
                }
            }

            else -> {
                ExploreCategoryCell(
                    context,
                    cellWidth,
                    {
                        onSiteTap(it)
                    }
                ) {
                    onCategoryTap(it)
                }
            }
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (cellHolder.cell) {
            is ExploreTrendingCell -> {
                (cellHolder.cell as ExploreTrendingCell).configure(exploreVM.showingTrendingSites)
            }

            is ExploreConnectedCell -> {
                (cellHolder.cell as ExploreConnectedCell).configure(
                    exploreVM.connectedSites ?: emptyArray()
                )
            }

            is ExploreCategoryTitleCell -> {
                val title =
                    when (indexPath.section) {
                        SECTION_CONNECTED -> "Connected Apps"
                        SECTION_TRENDING -> "Happening Now"
                        else -> "Popular Apps"
                    }
                (cellHolder.cell as ExploreCategoryTitleCell).configure(
                    LocaleController.getString(title)
                )
            }

            is ExploreCategoryCell -> {
                val colCount = calculateNoOfColumns()
                (cellHolder.cell as ExploreCategoryCell).configure(
                    exploreVM.showingExploreCategories?.getOrNull(indexPath.row - 1),
                    isLeading = indexPath.row % colCount == 1,
                    isTrailing = indexPath.row % colCount == 0,
                    isFirstRow = indexPath.row <= colCount,
                    isLastRow = indexPath.row > catsCount - colCount,
                    isBottomLeading = indexPath.row == ((catsCount - 1) / colCount) * colCount + 1,
                    isBottomTrailing = indexPath.row == catsCount && catsCount % colCount == 0
                )
            }
        }
    }

    override fun updateEmptyView() {
        val categories = exploreVM.showingExploreCategories
        if (categories == null) {
            if ((emptyView?.alpha ?: 0f) > 0) emptyView?.fadeOut()
        } else if (categories.isEmpty()) {
            // switch from loading view to wallet created view
            if (emptyView == null) {
                val emptyView =
                    WEmptyIconView(
                        context,
                        R.raw.animation_empty,
                        LocaleController.getString("No Dapps Found!")
                    )
                this.emptyView = emptyView
                view.addView(emptyView, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
                view.setConstraints {
                    toCenterX(emptyView)
                    toCenterY(emptyView)
                }
            } else if ((emptyView?.alpha ?: 0f) < 1) {
                if (emptyView?.startedAnimation == true) emptyView?.fadeIn()
            }
        } else {
            if ((emptyView?.alpha ?: 0f) > 0) emptyView?.fadeOut()
        }
    }

    override fun sitesUpdated() {
        rvAdapter.reloadData()
        pendingTarget?.let { findSiteAndOpenTargetUri(it) }
    }

    override fun accountChanged() {
        exploreVM.cancelSearch()
        dismissSearchScreen()
        navigationController?.popToRoot(false)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (exploreVMLazy.isInitialized()) exploreVM.onDestroy()
    }

    private fun onWidthChanged(newWidth: Int) {
        val w = ((view.parent?.parent as? View)?.width ?: 0).takeIf { it > 0 } ?: newWidth
        if (w > 0) lastEffectiveViewWidth = w
        cachedColumnsForWidth = 0
        val newSpanCount = gridWidth.coerceAtLeast(1)
        if ((recyclerView.layoutManager as? GridLayoutManager)?.spanCount != newSpanCount) {
            (recyclerView.layoutManager as? GridLayoutManager)?.spanCount = newSpanCount
        }
        recyclerView.recycledViewPool.clear()
        recyclerView.adapter = null
        recyclerView.adapter = rvAdapter
        rvAdapter.reloadData()
    }

    private var cachedColumnsForWidth = 0
    private var cachedColumns = 0
    private fun calculateNoOfColumns(): Int {
        val width = contentWidth
        if (width == cachedColumnsForWidth && cachedColumns != 0) return cachedColumns
        cachedColumnsForWidth = width
        cachedColumns = max(if (window?.isWideLayout == true) 1 else 2, (width - 32.dp) / 190.dp)
        return cachedColumns
    }

    // SUGGESTIONS //////////
    var searchVC: SearchVC? = null
    var isShowingSearch = false
    private var searchNavigationController: WNavigationController? = null
    private var isGlobalSearchSession = false
    private var enhancedSearchEnabled = false
    val shouldKeepSearchActiveOnKeyboardDismiss: Boolean
        get() = enhancedSearchEnabled && isShowingSearch && searchVC?.isDisappeared != true

    fun search(
        query: String?,
        isFocused: Boolean,
        targetNavigationController: WNavigationController? = navigationController,
        isGlobalSearch: Boolean = false
    ) {
        val keyword = query ?: ""
        val hasActiveSearchScreen = isShowingSearch && searchVC?.isDisappeared != true
        val useEnhancedSearch = if (hasActiveSearchScreen) {
            enhancedSearchEnabled
        } else {
            WGlobalStorage.areTopTabsEnabled()
        }
        val shouldShowSearchScreen = !query.isNullOrEmpty() ||
            (
                isFocused &&
                    (
                        useEnhancedSearch ||
                            !ExploreHistoryStore.exploreHistory?.searchHistory.isNullOrEmpty()
                        )
                )
        if (!shouldShowSearchScreen) {
            dismissSearchScreen()
            return
        }
        if (
            hasActiveSearchScreen &&
            searchNavigationController !== targetNavigationController
        ) {
            dismissSearchScreen()
        }
        if (!isShowingSearch || searchVC?.isDisappeared == true) {
            val targetNavigationController = targetNavigationController ?: return
            isShowingSearch = true
            enhancedSearchEnabled = useEnhancedSearch
            val searchVC = SearchVC(
                context,
                enhancedSearchEnabled,
                usesGlobalSearchOverlay = isGlobalSearch,
                // Covers dismissals that bypass dismissSearchScreen (swipe back, nav pop),
                // which would otherwise leave the search request refreshing on every poll.
                onDestroyed = { exploreVM.cancelSearch() }
            )
            searchNavigationController = targetNavigationController
            isGlobalSearchSession = isGlobalSearch
            this.searchVC = searchVC
            if (targetNavigationController.viewControllers.isEmpty()) {
                // The overlay stack starts empty, and push() is a no-op without a root. setRoot()
                // skips the appearance callbacks that push() drives, so run them here: results are
                // dropped while the screen still reports itself as disappeared.
                targetNavigationController.setRoot(searchVC)
                searchVC.viewWillAppear()
                searchVC.viewDidAppear()
            } else {
                targetNavigationController.push(searchVC, false)
            }
            if (isGlobalSearch) {
                targetNavigationController.tabBarController?.revealSearchOverlay()
            }
        }
        searchVC?.updateSearchQuery(keyword)
        exploreVM.search(keyword, enhancedSearchEnabled) { searchResult ->
            if (isShowingSearch && searchVC?.isDisappeared != true) {
                searchVC?.updateSearchResult(searchResult)
                exploreVM.searchWalletInfo(searchResult) { updated ->
                    if (exploreVM.currentSearchKeyword == keyword) {
                        searchVC?.updateSearchResult(updated)
                    }
                }
            }
        }
    }

    private fun dismissSearchScreen(globalSearch: Boolean = isGlobalSearchSession) {
        exploreVM.cancelSearch()
        val searchVC = searchVC
        val searchNavigationController = searchNavigationController
        searchVC?.keepKeyboardOpenOnDismiss = true
        this.searchVC = null
        this.searchNavigationController = null
        this.isGlobalSearchSession = false
        if (!globalSearch) {
            navigationController?.popToRoot(false)
        } else if (searchVC != null && searchNavigationController != null) {
            searchNavigationController.tabBarController?.hideSearchOverlay()
        }
        if (isShowingSearch) {
            isShowingSearch = false
        }
    }

    fun openBestSearchMatch(onResolved: (Boolean) -> Unit): Boolean {
        val searchVC = searchVC ?: return false
        searchVC.openBestMatch(onResolved)
        return true
    }

    private fun onDAppTap(it: ApiDapp?) {
        it?.let {
            val url = it.url ?: return
            if (it.sse != null) {
                val intent = Intent(Intent.ACTION_VIEW)
                intent.setData(url.toUri())
                try {
                    window?.startActivity(intent)
                } catch (_: Exception) {
                }
                return
            }
            val inAppBrowserVC = InAppBrowserVC(
                context,
                navigationController?.tabBarController,
                InAppBrowserConfig(
                    url = url,
                    title = it.name,
                    thumbnail = it.iconUrl,
                    injectDappConnect = true,
                    saveInVisitedHistory = true
                )
            )
            val window = window ?: return
            val nav = WNavigationController(window)
            nav.setRoot(inAppBrowserVC)
            window.present(nav)
        } ?: run {
            pushConfigure()
        }
    }

    private fun pushConfigure() {
        navigationController?.tabBarController?.mainNavigationController?.push(
            ConnectedAppsVC(context)
        )
    }

    fun findSiteAndOpenTargetUri(targetUri: Uri) {
        val sites = exploreVM.allSites
        if (sites == null) {
            pendingTarget = targetUri
            return
        }
        pendingTarget = null

        val targetHost = targetUri.host?.lowercase()
        if (targetHost.isNullOrEmpty()) {
            return
        }

        val matchedSite = sites.firstOrNull { site ->
            site.url?.toUri()?.host?.lowercase() == targetHost
        } ?: return

        openTargetUri(matchedSite, targetUri)
    }

    private fun openTargetUri(app: MExploreSite, uri: Uri) {
        val window = this.window ?: return
        if (app.isExternal || (uri.scheme != "http" && uri.scheme != "https") || app.isTelegram) {
            try {
                window.startActivity(
                    Intent(Intent.ACTION_VIEW).apply {
                        setData(uri)
                    }
                )
            } catch (_: Exception) {
            }
            return
        }
        val inAppBrowserVC = InAppBrowserVC(
            context,
            navigationController?.tabBarController,
            InAppBrowserConfig(
                url = uri.toString(),
                title = app.name,
                thumbnail = app.iconUrl,
                injectDappConnect = true,
                saveInVisitedHistory = true
            )
        )
        window.present(
            WNavigationController(window).apply {
                setRoot(inAppBrowserVC)
            }
        )
    }
}
