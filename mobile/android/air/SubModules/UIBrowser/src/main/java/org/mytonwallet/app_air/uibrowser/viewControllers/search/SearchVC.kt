package org.mytonwallet.app_air.uibrowser.viewControllers.search

import android.content.Context
import android.content.Intent
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.net.toUri
import androidx.core.view.isGone
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVM
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.GapCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchDappCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchHistoryCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchItemCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchMatchedCell
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import java.lang.ref.WeakReference

class SearchVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "Search"

    override val isSwipeBackAllowed = false

    companion object {
        val RECENT_SEARCH_TITLE_CELL = WCell.Type(1)
        val SEARCH_TITLE_CELL = WCell.Type(2)
        val SEARCH_SEARCHED_CELL = WCell.Type(3)
        val SEARCH_HISTORY_CELL = WCell.Type(4)
        val SEARCH_DAPP_CELL = WCell.Type(5)
        val SEARCH_MATCH_CELL = WCell.Type(6)
        val GAP_CELL = WCell.Type(7)

        const val SECTION_MATCH = 0
        const val SECTION_RECENT_QUERIES = 1
        const val SECTION_SUGGESTIONS = 2
        const val SECTION_DAPPS = 3
        const val SECTION_HISTORY = 4

        const val CLEAR_ALL_BUTTON_TAG = "clearAll"
    }

    override var title: String?
        get() {
            return LocaleController.getString("Search")
        }
        set(_) {
        }

    override val shouldDisplayTopBar = true
    override val shouldDisplayBottomBar = false

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                RECENT_SEARCH_TITLE_CELL,
                SEARCH_TITLE_CELL,
                SEARCH_SEARCHED_CELL,
                SEARCH_HISTORY_CELL,
                SEARCH_DAPP_CELL,
                SEARCH_MATCH_CELL,
                GAP_CELL
            )
        )

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        rv.layoutManager = LinearLayoutManager(context, RecyclerView.VERTICAL, false)
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

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.bottom ?: 0) - 16.dp
        )
    }

    var keepKeyboardOpenOnDismiss = false
    override fun viewWillDisappear() {
        if (keepKeyboardOpenOnDismiss) {
            isDisappeared = true
            return
        }
        super.viewWillDisappear()
    }

    var searchResult: ExploreVM.SearchResult? = null
    fun updateSearchResult(searchResult: ExploreVM.SearchResult?) {
        this.searchResult = searchResult
        rvAdapter.reloadData()
    }

    private fun openInAppBrowser(config: InAppBrowserConfig) {
        val inAppBrowserVC = InAppBrowserVC(
            context,
            navigationController?.tabBarController,
            config
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(inAppBrowserVC)
        window!!.present(nav)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 5
    }

    override fun recyclerViewNumberOfItems(
        rv: RecyclerView,
        section: Int
    ): Int {
        return when (section) {
            SECTION_MATCH -> {
                if (searchResult?.matchedVisitedSite == null) 0 else 2
            }

            SECTION_RECENT_QUERIES -> {
                if ((searchResult?.keyword.isNullOrEmpty() && !searchResult?.recentSearches.isNullOrEmpty()) ||
                    (!searchResult?.keyword.isNullOrEmpty() && searchResult?.noResultsFound == true)
                ) 2 + searchResult?.recentSearches!!.size else 0
            }

            SECTION_SUGGESTIONS -> {
                if (searchResult?.matchedVisitedSite == null &&
                    !searchResult?.keyword.isNullOrEmpty() &&
                    !searchResult?.recentSearches.isNullOrEmpty() &&
                    searchResult?.noResultsFound != true
                ) 2 + searchResult?.recentSearches!!.size else 0
            }

            SECTION_DAPPS -> {
                if (!searchResult?.keyword.isNullOrEmpty() && !searchResult?.dapps.isNullOrEmpty()) 2 + searchResult?.dapps!!.size else 0
            }

            SECTION_HISTORY -> {
                if (!searchResult?.keyword.isNullOrEmpty() && !searchResult?.recentVisitedSites.isNullOrEmpty()) 2 + searchResult?.recentVisitedSites!!.size else 0
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
        if (indexPath.row == 0)
            return when (indexPath.section) {
                SECTION_MATCH -> {
                    SEARCH_MATCH_CELL
                }

                SECTION_RECENT_QUERIES -> {
                    RECENT_SEARCH_TITLE_CELL
                }

                else -> {
                    SEARCH_TITLE_CELL
                }
            }
        if (indexPath.row == recyclerViewNumberOfItems(rv, indexPath.section) - 1) {
            return GAP_CELL
        }

        return when (indexPath.section) {
            SECTION_RECENT_QUERIES -> {
                SEARCH_SEARCHED_CELL
            }

            SECTION_SUGGESTIONS -> {
                SEARCH_HISTORY_CELL
            }

            SECTION_DAPPS -> {
                SEARCH_DAPP_CELL
            }

            SECTION_HISTORY -> {
                SEARCH_HISTORY_CELL
            }

            else -> {
                throw Error()
            }
        }
    }

    override fun recyclerViewCellView(
        rv: RecyclerView,
        cellType: WCell.Type
    ): WCell {
        return when (cellType) {
            GAP_CELL -> {
                GapCell(context)
            }

            SEARCH_MATCH_CELL -> {
                SearchMatchedCell(context, onTap = { site ->
                    openInAppBrowser(
                        InAppBrowserConfig(
                            url = site.url,
                            injectDappConnect = true,
                            saveInVisitedHistory = true,
                        )
                    )
                })
            }

            RECENT_SEARCH_TITLE_CELL -> {
                HeaderCell(context).apply {
                    titleLabel.setStyle(14f, WFont.DemiBold)
                    val clearAllButton = object : WLabel(context) {
                        private val ripple = WRippleDrawable.create(20f.dp)
                        init {
                            background = ripple
                        }
                        override fun updateTheme() {
                            super.updateTheme()
                            ripple.rippleColor = WColor.TintRipple.color
                        }
                    }.apply {
                        text = LocaleController.getString("Clear All")
                        setStyle(14f, WFont.Regular)
                        setTextColor(WColor.Tint)
                        setPadding(12.dp, 4.dp, 12.dp, 4.dp)
                        setOnClickListener {
                            ExploreHistoryStore.clearAccountHistory()
                            navigationController?.pop()
                        }
                        tag = CLEAR_ALL_BUTTON_TAG
                        updateTheme()
                    }
                    addView(clearAllButton)
                    setConstraints {
                        toEnd(clearAllButton, 8f)
                        centerYToCenterY(clearAllButton, titleLabel)
                    }
                }
            }

            SEARCH_TITLE_CELL -> {
                HeaderCell(context)
            }

            SEARCH_SEARCHED_CELL -> {
                SearchItemCell(context, onTap = { history ->
                    val (isValidUrl, uri) = InAppBrowserVC.convertToUri(history)
                    openInAppBrowser(
                        InAppBrowserConfig(
                            url = uri.toString(),
                            injectDappConnect = true,
                            saveInVisitedHistory = isValidUrl
                        )
                    )
                    if (!isValidUrl)
                        ExploreHistoryStore.saveSearchHistory(history)
                })
            }

            SEARCH_DAPP_CELL -> {
                SearchDappCell(context, onTap = { app ->
                    if (app !is MExploreSite ||
                        (app.isExternal ||
                            (!app.url!!.startsWith("http://") && !app.url!!.startsWith("https://")) ||
                            app.isTelegram)
                    ) {
                        val intent = Intent(Intent.ACTION_VIEW)
                        intent.setData(app.url?.toUri())
                        window!!.startActivity(intent)
                        return@SearchDappCell
                    }
                    openInAppBrowser(
                        InAppBrowserConfig(
                            url = app.url!!,
                            title = app.name,
                            thumbnail = app.iconUrl,
                            injectDappConnect = true,
                            saveInVisitedHistory = true,
                        )
                    )
                })
            }

            SEARCH_HISTORY_CELL -> {
                SearchHistoryCell(context)
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
        if (cellHolder.cell is GapCell)
            return

        when (indexPath.section) {
            SECTION_MATCH -> {
                (cellHolder.cell as SearchMatchedCell).configure(searchResult?.matchedVisitedSite!!)
            }

            SECTION_RECENT_QUERIES -> {
                if (indexPath.row == 0) {
                    (cellHolder.cell as HeaderCell).apply {
                        findViewWithTag<WButton>(CLEAR_ALL_BUTTON_TAG).isGone =
                            searchResult?.noResultsFound == true
                    }.configure(
                        LocaleController.getString(if (searchResult?.noResultsFound == true) "Search in Google" else "Recent Searches"),
                        titleColor = WColor.Tint,
                        topRounding = if (rvAdapter.indexPathToPosition(indexPath) == 0) HeaderCell.TopRounding.FIRST_ITEM else HeaderCell.TopRounding.NORMAL
                    )
                } else {
                    (cellHolder.cell as SearchItemCell).configure(
                        searchResult?.recentSearches!![indexPath.row - 1].title,
                        indexPath.row == searchResult?.recentSearches!!.size
                    )
                }
            }

            SECTION_SUGGESTIONS -> {
                if (indexPath.row == 0) {
                    (cellHolder.cell as HeaderCell).configure(
                        LocaleController.getString("Suggestions"),
                        titleColor = WColor.Tint,
                        topRounding = if (rvAdapter.indexPathToPosition(indexPath) == 0) HeaderCell.TopRounding.FIRST_ITEM else HeaderCell.TopRounding.NORMAL
                    )
                } else {
                    val search = searchResult?.recentSearches!![indexPath.row - 1]
                    (cellHolder.cell as SearchHistoryCell).configure(
                        search,
                        indexPath.row == searchResult?.recentSearches!!.size,
                        onTap = {
                            val (isValidUrl, uri) = InAppBrowserVC.convertToUri(search.title)
                            openInAppBrowser(
                                InAppBrowserConfig(
                                    url = uri.toString(),
                                    injectDappConnect = true,
                                    saveInVisitedHistory = isValidUrl
                                )
                            )
                        }
                    )
                }
            }

            SECTION_DAPPS -> {
                if (indexPath.row == 0) {
                    (cellHolder.cell as HeaderCell).configure(
                        LocaleController.getString("Popular and connected apps"),
                        titleColor = WColor.Tint,
                        topRounding = if (rvAdapter.indexPathToPosition(indexPath) == 0) HeaderCell.TopRounding.FIRST_ITEM else HeaderCell.TopRounding.NORMAL
                    )
                } else {
                    (cellHolder.cell as SearchDappCell).configure(
                        searchResult?.dapps!![indexPath.row - 1],
                        indexPath.row == searchResult?.dapps!!.size
                    )
                }
            }

            SECTION_HISTORY -> {
                if (indexPath.row == 0) {
                    (cellHolder.cell as HeaderCell).configure(
                        LocaleController.getString("History"),
                        titleColor = WColor.Tint,
                        topRounding = if (rvAdapter.indexPathToPosition(indexPath) == 0) HeaderCell.TopRounding.FIRST_ITEM else HeaderCell.TopRounding.NORMAL
                    )
                } else {
                    val site = searchResult?.recentVisitedSites!![indexPath.row - 1]
                    (cellHolder.cell as SearchHistoryCell).configure(
                        site,
                        indexPath.row == searchResult?.recentVisitedSites!!.size,
                        onTap = {
                            openInAppBrowser(
                                InAppBrowserConfig(
                                    url = site.url,
                                    injectDappConnect = true,
                                    saveInVisitedHistory = true
                                )
                            )
                        }
                    )
                }
            }
        }
    }

}
