package org.mytonwallet.app_air.uifutures.viewControllers.futuresMarkets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.widget.doOnTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.SelectiveItemAnimator
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.FuturesVM
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesMarketRowCell
import org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.FuturesPositionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsMarketSection

/** The markets of one Futures group, or every market by trading volume; opened from Show All. */
@SuppressLint("ViewConstructor")
class FuturesMarketsVC(
    context: Context,
    private val groupId: String? = null,
    private val hasSearch: Boolean = false
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    FuturesVM.Delegate {
    @Suppress("PropertyName")
    override val TAG = "FuturesMarkets"

    override val shouldDisplayBottomBar: Boolean
        get() = !isInCenteredWindow

    private val futuresVM by lazy { FuturesVM(this) }
    private var query = ""
    private var markets: List<MApiPerpsListedAsset> = emptyList()

    private val searchEditText = WSearchEditText(context).apply {
        isSearchIconFixed = true
        hint = LocaleController.getString("Search...")
        doOnTextChanged { text, _, _, _ ->
            query = text?.toString()?.trim().orEmpty()
            updateMarkets()
        }
    }

    // Floating search pill; its glass blurs the list behind it.
    private val searchView = WFrameLayout(context).apply {
        setBackgroundColor(Color.TRANSPARENT, SEARCH_HEIGHT.dp / 2f, clipToBounds = true)
        addView(searchEditText, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }
    private var searchGlass: WGlassView? = null

    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(MARKET_CELL)).apply {
        setHasStableIds(true)
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            if (dy != 0) updateBlurViews(recyclerView)
        }
    }

    private val recyclerView by lazy {
        WRecyclerView(this).apply {
            adapter = rvAdapter
            layoutManager = LinearLayoutManager(context)
            clipToPadding = false
            itemAnimator = SelectiveItemAnimator().apply {
                setAll(WGlobalStorage.getAreAnimationsActive())
            }
            addOnScrollListener(scrollListener)
        }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        navigationBar?.setTitleGravity(Gravity.CENTER)
        navigationBar?.addCloseButton()
        setNavTitle(group?.title ?: LocaleController.getString("Futures Market"))
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }
        if (hasSearch) {
            view.addView(
                searchView,
                ConstraintLayout.LayoutParams(
                    ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
                    SEARCH_HEIGHT.dp
                )
            )
            searchGlass = WGlassView.attachTo(
                searchView,
                SEARCH_HEIGHT.dp / 2f,
                GlassProviders.pill(WColor.SearchFieldBackground),
                view
            )
        }
        futuresVM.start()
        insetsUpdated()
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.updateTheme()
        if (hasSearch) {
            searchGlass?.updateTheme()
            searchEditText.updateTheme()
        }
    }

    override fun didSetupViews() {
        super.didSetupViews()
        bringSearchToFront()
    }

    private fun bringSearchToFront() {
        if (!hasSearch) return
        searchGlass?.bringToFront()
        searchView.bringToFront()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottomInset = max(
            navigationController?.getSystemBars()?.bottom ?: 0,
            navigationController?.imeInsetBottom ?: 0
        )
        if (hasSearch) {
            view.setConstraints {
                toStartPx(searchView, SEARCH_HORIZONTAL_MARGIN.dp + systemBarStartInset)
                toEndPx(searchView, SEARCH_HORIZONTAL_MARGIN.dp + systemBarEndInset)
                toBottomPx(searchView, bottomInset + SEARCH_BOTTOM_MARGIN.dp)
            }
            bringSearchToFront()
        }
        recyclerView.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            navigationBar?.calculatedMinHeight ?: 0,
            systemBarEndInset,
            bottomInset + if (hasSearch) (SEARCH_BOTTOM_MARGIN * 2 + SEARCH_HEIGHT).dp else 0
        )
    }

    override fun scrollToTop() {
        recyclerView.smoothScrollToPosition(0)
    }

    override fun futuresUpdated() {
        updateMarkets()
    }

    private val group: MApiPerpsMarketSection?
        get() = futuresVM.marketGroups.firstOrNull { it.id == groupId }

    private fun updateMarkets() {
        setNavTitle(group?.title ?: LocaleController.getString("Futures Market"), animated = false)
        val groupMarkets = group?.assets ?: futuresVM.markets
        markets = if (query.isEmpty()) {
            groupMarkets
        } else {
            groupMarkets.filter {
                it.symbol.contains(query, ignoreCase = true) ||
                    it.name.contains(query, ignoreCase = true) ||
                    it.displayName?.contains(query, ignoreCase = true) == true
            }
        }
        rvAdapter.reloadData()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        futuresVM.isShown = true
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        futuresVM.isShown = false
    }

    override fun onDestroy() {
        futuresVM.stop()
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.layoutManager = null
        super.onDestroy()
    }

    private fun openMarket(market: MApiPerpsListedAsset) {
        navigationController?.push(FuturesPositionVC(context, market.name))
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = markets.size

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String =
        markets[indexPath.row].name

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        MARKET_CELL

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        FuturesMarketRowCell(context, ::openMarket)

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val index = indexPath.row
        (cellHolder.cell as? FuturesMarketRowCell)?.configure(
            markets[index],
            isFirst = index == 0,
            isLast = index == markets.lastIndex
        )
    }

    private companion object {
        val MARKET_CELL = WCell.Type(1)
        const val SEARCH_HEIGHT = 48
        const val SEARCH_HORIZONTAL_MARGIN = 16
        const val SEARCH_BOTTOM_MARGIN = 8
    }
}
