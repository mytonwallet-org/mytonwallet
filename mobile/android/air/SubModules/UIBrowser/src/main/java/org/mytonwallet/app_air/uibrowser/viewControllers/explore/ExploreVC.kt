package org.mytonwallet.app_air.uibrowser.viewControllers.explore

import WNavigationController
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.net.toUri
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreCategoryCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreCategoryTitleCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreConnectedCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreLargeConnectedItemCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells.ExploreTrendingCell
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.views.ExploreSuggestionsView
import org.mytonwallet.app_air.uibrowser.viewControllers.exploreCategory.ExploreCategoryVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.LinedCenteredTitleView
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.PositionBasedItemDecoration
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.ConnectedAppsVC
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class ExploreVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, ExploreVM.Delegate {

    companion object {
        val EXPLORE_TITLE_CELL = WCell.Type(1)
        val EXPLORE_TITLE_CENTER_CELL = WCell.Type(2)
        val EXPLORE_CONNECTED_ITEM_CELL = WCell.Type(3)
        val EXPLORE_CONNECTED_ROW_CELL = WCell.Type(4)
        val EXPLORE_TRENDING_CELL = WCell.Type(5)
        val EXPLORE_CATEGORY_CELL = WCell.Type(6)

        const val SECTION_CONNECTED = 0
        const val SECTION_TRENDING = 1
        const val SECTION_ALL = 2

        private const val PADDING = 4
    }

    override var title: String?
        get() {
            return LocaleController.getString("Explore")
        }
        set(_) {
        }

    override val shouldDisplayTopBar = true

    private val exploreVM by lazy {
        ExploreVM(this)
    }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                EXPLORE_TITLE_CELL,
                EXPLORE_TITLE_CENTER_CELL,
                EXPLORE_CONNECTED_ITEM_CELL,
                EXPLORE_CONNECTED_ROW_CELL,
                EXPLORE_TRENDING_CELL,
                EXPLORE_CATEGORY_CELL
            )
        )

    private var emptyView: WEmptyIconView? = null

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val connectedAppsColumnCount = calculateNoOfConnectedAppsColumns()
        val connectedAppsDefaultSpacing = 28f.dp / connectedAppsColumnCount
        val dappsCols = calculateNoOfColumns()
        val dappsDefaultSpacing = 32f.dp / (dappsCols - 1)
        val totalCols = connectedAppsColumnCount * dappsCols
        val layoutManager = GridLayoutManager(context, totalCols)
        layoutManager.isSmoothScrollbarEnabled = true
        layoutManager.spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
            override fun getSpanSize(position: Int): Int {
                val indexPath = rvAdapter.positionToIndexPath(position)
                return when (indexPath.section) {
                    SECTION_CONNECTED -> {
                        if (showLargeConnectedApps) {
                            dappsCols
                        } else {
                            totalCols
                        }
                    }

                    SECTION_TRENDING -> {
                        totalCols
                    }

                    else -> {
                        if (indexPath.row == 0) totalCols else connectedAppsColumnCount
                    }
                }
            }
        }
        rv.layoutManager = layoutManager
        rv.setLayoutManager(layoutManager)
        rv.addItemDecoration(
            PositionBasedItemDecoration { position ->
                val indexPath = rvAdapter.positionToIndexPath(position)
                return@PositionBasedItemDecoration when (indexPath.section) {
                    SECTION_CONNECTED -> {
                        if (showLargeConnectedApps) {
                            Rect(
                                14.dp - (connectedAppsDefaultSpacing * (indexPath.row % connectedAppsColumnCount)).roundToInt(),
                                0,
                                0,
                                8.dp
                            )
                        } else {
                            Rect(0, 0, 0, 0)
                        }
                    }

                    SECTION_ALL -> {
                        if (indexPath.row == 0)
                            Rect(0, 0, 0, 0)
                        else
                            Rect(
                                16.dp - (dappsDefaultSpacing * ((indexPath.row - 1) % dappsCols)).roundToInt(),
                                0,
                                0,
                                8.dp
                            )
                    }

                    else -> {
                        Rect(0, 0, 0, 0)
                    }
                }
            }
        )
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
            }
        })
        rv.clipToPadding = false
        rv
    }

    val exploreSuggestionsView: ExploreSuggestionsView by lazy {
        ExploreSuggestionsView(context) {
            onSiteTap(it)
        }.apply {
            alpha = 0f
            elevation = 2f.dp
        }
    }

    init {
        WalletCore.doOnBridgeReady {
            exploreVM.delegateIsReady()
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Explore"))
        setupNavBar(true)
        navigationBar?.titleLabel?.setStyle(20f, WFont.Regular)
        navigationBar?.setTitleGravity(Gravity.CENTER)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(exploreSuggestionsView, ViewGroup.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        view.setConstraints {
            allEdges(recyclerView)
            toCenterX(exploreSuggestionsView, 20f)
        }
        val topPadding = (navigationController?.getSystemBars()?.top ?: 0)
        recyclerView.setPadding(
            0,
            topPadding + WNavigationBar.DEFAULT_HEIGHT.dp,
            0,
            recyclerView.paddingBottom
        )

        updateEmptyView()

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.reloadData()
        updateExploreSuggestionsPosition()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val topPadding = (navigationController?.getSystemBars()?.top ?: 0)
        recyclerView.setPadding(
            0,
            topPadding + WNavigationBar.DEFAULT_HEIGHT.dp,
            0,
            PADDING.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        updateExploreSuggestionsPosition()
    }

    private fun updateExploreSuggestionsPosition() {
        view.setConstraints {
            bottomToBottomPx(
                exploreSuggestionsView,
                view,
                PADDING.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun onSiteTap(app: MExploreSite) {
        if (app.url.isNullOrEmpty())
            return
        if (app.isExternal ||
            (!app.url!!.startsWith("http://") && !app.url!!.startsWith("https://")) ||
            app.isTelegram
        ) {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.setData(app.url?.toUri())
            window?.startActivity(intent)
            return
        }
        val inAppBrowserVC = InAppBrowserVC(
            context,
            navigationController?.tabBarController,
            InAppBrowserConfig(
                url = app.url!!,
                title = app.name,
                thumbnail = app.icon,
                injectTonConnectBridge = true
            )
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(inAppBrowserVC)
        window?.present(nav)
    }

    private fun onCategoryTap(category: MExploreCategory) {
        val categoryVC = ExploreCategoryVC(context, category)
        navigationController?.tabBarController?.navigationController?.push(categoryVC)
    }

    private val cellWidth: Int
        get() {
            val cols = calculateNoOfColumns()
            return ((view.width - 32.dp)) / cols
        }

    private val connectedItemCellWidth: Int
        get() {
            val cols = calculateNoOfConnectedAppsColumns()
            return ((view.width - 28.dp)) / cols
        }

    override fun onBackPressed(): Boolean {
        (window?.window?.currentFocus as? SwapSearchEditText)?.let {
            it.clearFocus()
            return false
        }
        return super.onBackPressed()
    }

    val showLargeConnectedApps: Boolean
        get() {
            return (exploreVM.connectedSites?.size ?: 0) > 3
        }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 3
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        if (exploreVM.showingExploreCategories == null)
            return 0
        when (section) {
            SECTION_CONNECTED -> {
                return if (exploreVM.connectedSites.isNullOrEmpty())
                    0
                else
                    if (showLargeConnectedApps) exploreVM.connectedSites!!.size + 1 else 1
            }

            SECTION_TRENDING -> {
                return if (exploreVM.showingTrendingSites.isEmpty()) 0 else 2
            }

            else -> {
                val catsCount = exploreVM.showingExploreCategories?.size ?: 0
                return if (catsCount > 0) 1 + catsCount else 0
            }
        }
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        if (indexPath.section == 1 && indexPath.row == 0)
            return EXPLORE_TITLE_CELL
        else if (indexPath.section == 2 && indexPath.row == 0)
            return EXPLORE_TITLE_CENTER_CELL
        return when (indexPath.section) {
            SECTION_CONNECTED -> {
                if (showLargeConnectedApps)
                    EXPLORE_CONNECTED_ITEM_CELL
                else
                    EXPLORE_CONNECTED_ROW_CELL
            }

            SECTION_TRENDING -> EXPLORE_TRENDING_CELL
            else -> EXPLORE_CATEGORY_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            EXPLORE_TITLE_CELL -> {
                ExploreCategoryTitleCell(context)
            }

            EXPLORE_TITLE_CENTER_CELL -> {
                LinedCenteredTitleView(context)
            }

            EXPLORE_CONNECTED_ROW_CELL -> {
                ExploreConnectedCell(context, dAppPressed = {
                    onDAppTap(it)
                }) {
                    pushConfigure()
                }
            }

            EXPLORE_CONNECTED_ITEM_CELL -> {
                ExploreLargeConnectedItemCell(context, connectedItemCellWidth, onDAppTap = {
                    onDAppTap(it)
                })
            }

            EXPLORE_TRENDING_CELL -> {
                ExploreTrendingCell(context, cellWidth) {
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
            is ExploreTrendingCell -> {
                (cellHolder.cell as ExploreTrendingCell).configure(exploreVM.showingTrendingSites)
            }

            is ExploreConnectedCell -> {
                (cellHolder.cell as ExploreConnectedCell).configure(
                    exploreVM.connectedSites ?: emptyArray()
                )
            }

            is ExploreLargeConnectedItemCell -> {
                (cellHolder.cell as ExploreLargeConnectedItemCell).configure(
                    exploreVM.connectedSites?.getOrNull(indexPath.row)
                )
            }

            is ExploreCategoryTitleCell -> {
                val title =
                    when (indexPath.section) {
                        SECTION_TRENDING -> "Happening Now"
                        else -> null
                    }
                (cellHolder.cell as ExploreCategoryTitleCell).apply {
                    configure(
                        LocaleController.getString(title!!),
                        9.dp
                    )
                }
            }

            is LinedCenteredTitleView -> {
                val title =
                    when (indexPath.section) {
                        SECTION_ALL -> "Popular Apps"
                        else -> null
                    }
                (cellHolder.cell as LinedCenteredTitleView).apply {
                    configure(
                        LocaleController.getString(title!!),
                        topPadding = 8.dp,
                        bottomPadding = 12.dp
                    )
                }
            }

            is ExploreCategoryCell -> {
                (cellHolder.cell as ExploreCategoryCell).configure(exploreVM.showingExploreCategories!![indexPath.row - 1])
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
        rvAdapter.reloadData()
    }

    private fun calculateNoOfColumns(): Int {
        return max(2, ((view.parent.parent as View).width - 32.dp) / 190.dp)
    }

    private fun calculateNoOfConnectedAppsColumns(): Int {
        return max(2, ((view.parent.parent as View).width - 28.dp) / 76.dp)
    }

    // SUGGESTIONS //////////
    var isSuggestionsVisible = false

    fun search(query: String?) {
        val shouldHideSuggestions =
            query.isNullOrEmpty() || exploreVM.filterSites(query).isNullOrEmpty()

        if (shouldHideSuggestions) {
            if (isSuggestionsVisible) hideSuggestions()
            return
        }

        val filteredSites = exploreVM.filterSites(query) ?: return

        exploreSuggestionsView.config(filteredSites)
        if (!isSuggestionsVisible) showSuggestions()
    }

    private fun hideSuggestions() {
        isSuggestionsVisible = false
        exploreSuggestionsView.translationY = 0f
        exploreSuggestionsView.animate().setDuration(AnimationConstants.QUICK_ANIMATION)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .alpha(0f)
            .translationY((-8f).dp)
            .withEndAction {
                if (!isSuggestionsVisible) {
                    exploreSuggestionsView.visibility = View.GONE
                }
            }
    }

    private fun showSuggestions() {
        isSuggestionsVisible = true
        exploreSuggestionsView.visibility = View.VISIBLE
        exploreSuggestionsView.translationY = 8f.dp
        exploreSuggestionsView.animate().setDuration(AnimationConstants.QUICK_ANIMATION)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .alpha(1f)
            .translationY(0f)
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
                    injectTonConnectBridge = true
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
}
