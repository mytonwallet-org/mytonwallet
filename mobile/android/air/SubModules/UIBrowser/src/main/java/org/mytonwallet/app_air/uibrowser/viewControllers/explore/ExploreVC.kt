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
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreCategoryCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreCategoryTitleCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreConnectedCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreTitleCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreTrendingCell
import org.mytonwallet.app_air.uibrowser.viewControllers.exploreCategory.ExploreCategoryVC
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.ConnectedAppsVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
class ExploreVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, ExploreVM.Delegate {
    override val TAG = "Explore"

    override var ignoreSideGuttering: Boolean = false

    companion object {
        val EXPLORE_HEADER_CELL = WCell.Type(1)
        val EXPLORE_TITLE_CELL = WCell.Type(2)
        val EXPLORE_CONNECTED_ROW_CELL = WCell.Type(3)
        val EXPLORE_TRENDING_CELL = WCell.Type(4)
        val EXPLORE_CATEGORY_CELL = WCell.Type(5)

        const val SECTION_HEADER = 0
        const val SECTION_CONNECTED = 1
        const val SECTION_TRENDING = 2
        const val SECTION_ALL = 3

    }

    override val shouldDisplayTopBar = false

    private var pendingTarget: Uri? = null

    private val exploreVM by lazy {
        ExploreVM(this)
    }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                EXPLORE_HEADER_CELL,
                EXPLORE_TITLE_CELL,
                EXPLORE_CONNECTED_ROW_CELL,
                EXPLORE_TRENDING_CELL,
                EXPLORE_CATEGORY_CELL
            )
        )

    private var emptyView: WEmptyIconView? = null

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val dappsCols = calculateNoOfColumns()
        val layoutManager = GridLayoutManager(context, (view.parent.parent as ViewGroup).width)
        layoutManager.isSmoothScrollbarEnabled = true
        layoutManager.spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
            override fun getSpanSize(position: Int): Int {
                val indexPath = rvAdapter.positionToIndexPath(position)
                return when (indexPath.section) {
                    SECTION_CONNECTED, SECTION_TRENDING -> {
                        view.width
                    }

                    else -> {
                        if (indexPath.row == 0) view.width else {
                            cellWidth +
                                (if (indexPath.row % dappsCols == 1) 8.dp + ViewConstants.HORIZONTAL_PADDINGS.dp else 0) +
                                (if (indexPath.row % dappsCols == 0) 8.dp + ViewConstants.HORIZONTAL_PADDINGS.dp else 0)
                        }
                    }
                }
            }
        }
        rv.layoutManager = layoutManager
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (recyclerView.computeVerticalScrollOffset() == 0)
                    updateBlurViews(recyclerView)
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0)
                    return
                updateBlurViews(recyclerView)
                if (recyclerView.computeVerticalScrollOffset() > 40.dp) {
                    setNavTitle(LocaleController.getString("Explore"))
                    setTopBlur(true, animated = true)
                } else {
                    setNavTitle("")
                    setTopBlur(false, animated = true)
                }
            }
        })
        rv.clipToPadding = false
        rv
    }

    init {
        WalletCore.doOnBridgeReady {
            exploreVM.delegateIsReady()
        }
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        setTopBlur(visible = false, animated = false)
        navigationBar?.setTitleGravity(Gravity.START)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }

        updateEmptyView()

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val topPadding = (navigationController?.getSystemBars()?.top ?: 0)
        recyclerView.setPadding(
            0,
            topPadding,
            0,
            navigationController?.getSystemBars()?.bottom ?: 0
        )
        bottomReversedCornerView?.setHorizontalPadding(ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat())
        rvAdapter.reloadData()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun viewWillDisappear() {
        // We don't want to hide keyboard on search, so super.viewWillDisappear is not called here.
        isDisappeared = true
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
        navigationController?.tabBarController?.navigationController?.push(categoryVC)
    }

    private val cellWidth: Int
        get() {
            val cols = calculateNoOfColumns()
            return (view.width - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - 16.dp) / cols
        }

    private val trendingCellWidth: Int
        get() {
            val cols = calculateNoOfColumns()
            return (view.width - 4.dp) / cols
        }

    override fun onBackPressed(): Boolean {
        (window?.window?.currentFocus as? SwapSearchEditText)?.let {
            it.clearFocus()
            return false
        }
        return super.onBackPressed()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 4
    }

    val catsCount: Int
        get() {
            val colCount = calculateNoOfColumns()
            return ((exploreVM.showingExploreCategories?.size
                ?: 0) / colCount.toFloat()).ceilToInt() * colCount
        }

    val showLargeConnectedApps: Boolean
        get() {
            return (exploreVM.connectedSites?.size ?: 0) > 3
        }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        if (exploreVM.showingExploreCategories == null)
            return 0
        when (section) {
            SECTION_HEADER -> {
                return 1
            }

            SECTION_CONNECTED -> {
                return if (exploreVM.connectedSites.isNullOrEmpty())
                    0
                else
                    2
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

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return when {
            indexPath.section == 0 -> EXPLORE_HEADER_CELL

            indexPath.row == 0 -> EXPLORE_TITLE_CELL

            indexPath.section == SECTION_CONNECTED -> {
                EXPLORE_CONNECTED_ROW_CELL
            }

            indexPath.section == SECTION_TRENDING -> EXPLORE_TRENDING_CELL

            else -> EXPLORE_CATEGORY_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            EXPLORE_HEADER_CELL -> {
                ExploreTitleCell(context)
            }

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
                    cellWidth, {
                        onSiteTap(it)
                    }
                ) {
                    onCategoryTap(it)
                }
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (cellHolder.cell) {
            is ExploreTitleCell -> {
                (cellHolder.cell as ExploreTitleCell).configure(
                    LocaleController.getString("Explore"),
                    38.dp,
                    48.dp
                )
            }

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
                        SECTION_CONNECTED -> "Connected Dapps"
                        SECTION_TRENDING -> "Happening Now"
                        else -> "Popular Apps"
                    }
                (cellHolder.cell as ExploreCategoryTitleCell).apply {
                    configure(
                        LocaleController.getString(title),
                        if (indexPath.section == SECTION_TRENDING) 18.dp else 10.dp,
                        when (indexPath.section) {
                            SECTION_CONNECTED -> if (showLargeConnectedApps) 7.dp else 11.dp
                            SECTION_TRENDING -> 5.dp
                            else -> 11.dp
                        }
                    )
                }
            }

            is ExploreCategoryCell -> {
                val colCount = calculateNoOfColumns()
                (cellHolder.cell as ExploreCategoryCell).configure(
                    exploreVM.showingExploreCategories!!.getOrNull(indexPath.row - 1),
                    isLeft = indexPath.row % colCount == 1,
                    isRight = indexPath.row % colCount == 0,
                    isTopLeft = indexPath.row == 1,
                    isTopRight = indexPath.row == colCount,
                    isBottomLeft = indexPath.row == ((catsCount - 1) / colCount) * colCount + 1,
                    isBottomRight = indexPath.row == catsCount && catsCount % colCount == 0
                )
            }
        }
    }

    override fun updateEmptyView() {
        if (exploreVM.showingExploreCategories == null) {
            if ((emptyView?.alpha ?: 0f) > 0)
                emptyView?.fadeOut()
        } else if (exploreVM.showingExploreCategories!!.isEmpty()) {
            // switch from loading view to wallet created view
            if (emptyView == null) {
                emptyView =
                    WEmptyIconView(
                        context,
                        R.raw.animation_empty,
                        LocaleController.getString("No Dapps Found!")
                    )
                view.addView(emptyView!!, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
                view.setConstraints {
                    toCenterX(emptyView!!)
                    toCenterY(emptyView!!)
                }
            } else if ((emptyView?.alpha ?: 0f) < 1) {
                if (emptyView?.startedAnimation == true)
                    emptyView?.fadeIn()
            }
        } else {
            if ((emptyView?.alpha ?: 0f) > 0)
                emptyView?.fadeOut()
        }
    }

    override fun sitesUpdated() {
        val newIgnoreSideGuttering = exploreVM.showingTrendingSites.size > 1
        if (ignoreSideGuttering != newIgnoreSideGuttering) {
            ignoreSideGuttering = newIgnoreSideGuttering
            val padding = if (newIgnoreSideGuttering) 0f else ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
            topReversedCornerView?.setHorizontalPadding(padding)
        }
        rvAdapter.reloadData()
        pendingTarget?.let { findSiteAndOpenTargetUri(it) }
    }

    override fun accountChanged() {
        navigationController?.popToRoot(false)
    }

    private fun calculateNoOfColumns(): Int {
        return max(2, ((view.parent.parent as View).width - 32.dp) / 190.dp)
    }

    // SUGGESTIONS //////////
    var searchVC: SearchVC? = null
    var isShowingSearch = false
    fun search(query: String?, isFocused: Boolean) {
        val searchResult = exploreVM.search(query ?: "")
        val shouldShowSearchScreen =
            !query.isNullOrEmpty() ||
                (isFocused &&
                    query.isNullOrEmpty() &&
                    !ExploreHistoryStore.exploreHistory?.searchHistory.isNullOrEmpty())
        if (!shouldShowSearchScreen) {
            searchVC?.keepKeyboardOpenOnDismiss = true
            navigationController?.popToRoot(false)
            isShowingSearch = false
            return
        }
        if (!isShowingSearch || searchVC?.isDisappeared == true) {
            isShowingSearch = true
            searchVC = SearchVC(context)
            navigationController?.push(searchVC!!, false)
        }
        searchVC?.updateSearchResult(searchResult)
    }

    private fun onDAppTap(it: ApiDapp?) {
        it?.let {
            val url = it.url ?: return
            if (it.sse != null) {
                val intent = Intent(Intent.ACTION_VIEW)
                intent.setData(url.toUri())
                window?.startActivity(intent)
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
                    saveInVisitedHistory = true,
                )
            )
            val nav = WNavigationController(window!!)
            nav.setRoot(inAppBrowserVC)
            window?.present(nav)
        } ?: run {
            pushConfigure()
        }
    }

    private fun pushConfigure() {
        navigationController?.tabBarController?.navigationController?.push(
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
            window.startActivity(Intent(Intent.ACTION_VIEW).apply {
                setData(uri)
            })
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
                saveInVisitedHistory = true,
            )
        )
        window.present(WNavigationController(window).apply {
            setRoot(inAppBrowserVC)
        })
    }
}
