package org.mytonwallet.app_air.uimarket.viewControllers.market

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.view.Gravity
import android.view.KeyEvent
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.core.widget.doOnTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlin.math.min
import kotlin.math.roundToInt
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.FloatAnimator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uimarket.viewControllers.market.cells.MarketGridSectionCell
import org.mytonwallet.app_air.uimarket.viewControllers.market.cells.MarketMoversSectionCell
import org.mytonwallet.app_air.uimarket.viewControllers.market.cells.MarketRowsSectionCell
import org.mytonwallet.app_air.uimarket.viewControllers.market.cells.SECTION_BOTTOM_SPACING
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketSectionLayout

@SuppressLint("ViewConstructor")
class MarketVC(context: Context) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    MarketVM.Delegate {
    @Suppress("PropertyName")
    override val TAG = "Market"

    override val shouldDisplayTopBar = true
    override val shouldHideKeyboardOnDisappear = false

    private val marketVM by lazy { MarketVM(this) }
    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(MOVERS_CELL, GRID_CELL, ROWS_CELL)
    )

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.computeVerticalScrollOffset() == 0 ||
                !recyclerView.canScrollVertically(1)
            ) {
                updateMarketBlurViews(recyclerView)
            }
        }

        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dy != 0) updateMarketBlurViews(recyclerView)
        }
    }
    private val recyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        layoutManager = LinearLayoutManager(context)
        clipToPadding = false
        itemAnimator = null
        addOnScrollListener(scrollListener)
    }

    private val searchFocused = BoolAnimator(
        AnimationConstants.VERY_QUICK_ANIMATION,
        CubicBezierInterpolator.EASE_BOTH,
        false
    ) { _, _, _, _ ->
        updateSearchWidth()
    }
    private val searchEditText = object : WSearchEditText(context) {
        override fun onFocusChanged(
            focused: Boolean,
            direction: Int,
            previouslyFocusedRect: Rect?
        ) {
            super.onFocusChanged(focused, direction, previouslyFocusedRect)
            searchFocused.animatedValue = focused
        }
    }.apply {
        hint = LocaleController.getString("Search token or stock")
        imeOptions = EditorInfo.IME_ACTION_DONE
        setOnEditorActionListener { _, actionId, event ->
            val shouldDismiss = actionId == EditorInfo.IME_ACTION_DONE ||
                (event?.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_ENTER)
            if (shouldDismiss) {
                clearFocus()
                hideKeyboard()
            }
            shouldDismiss
        }
    }
    private val searchTextWatcher = searchEditText.doOnTextChanged { value, _, _, _ ->
        marketVM.search(value?.toString().orEmpty())
    }
    private var searchGlass: WGlassView? = null
    private val searchView = WFrameLayout(context).apply {
        setBackgroundColor(Color.TRANSPARENT, SEARCH_HEIGHT.dp / 2f, clipToBounds = true)
        addView(searchEditText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }
    private val collapsedSearchWidth by lazy {
        val hintWidth = searchEditText.paint.measureText(
            LocaleController.getString("Search token or stock")
        ).ceilToInt()
        (62.dp + hintWidth).coerceAtMost(COLLAPSED_SEARCH_MAX_WIDTH.dp)
    }
    private var expandedSearchWidth = collapsedSearchWidth
    private val searchBottomAnimator = FloatAnimator(
        220L,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        0f
    ) { bottom ->
        view.setConstraints {
            toCenterX(searchView)
            toBottomPx(searchView, bottom.roundToInt())
        }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        navigationBar?.setTitleGravity(Gravity.START)
        updateTopOverlay(animated = false)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            searchView,
            ConstraintLayout.LayoutParams(collapsedSearchWidth, SEARCH_HEIGHT.dp)
        )
        val initialSearchBottom = searchBottomMargin()
        view.setConstraints {
            allEdges(recyclerView)
            toCenterX(searchView)
            toBottomPx(searchView, initialSearchBottom)
        }
        searchGlass = WGlassView.attachTo(
            searchView,
            SEARCH_HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.SearchFieldBackground),
            view
        )
        searchBottomAnimator.forcedValue = initialSearchBottom.toFloat()
        updateLocalSearchVisibility()

        marketVM.start()
        updateTheme()
        insetsUpdated()
    }

    override fun onRootTopGradientModeChanged(enabled: Boolean) {
        updateLocalSearchVisibility()
        rvAdapter.updateVisibleCells()
        updateTopOverlay(animated = false)
        if (isViewConfigured) insetsUpdated()
    }

    private fun updateTopOverlay(animated: Boolean) {
        setNavTitle(
            if (isRootTopGradientEnabled) "" else LocaleController.getString("Market"),
            animated
        )
    }

    override fun didSetupViews() {
        super.didSetupViews()
        bringSearchToFront()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        searchGlass?.updateTheme()
        searchEditText.updateTheme()
        searchEditText.highlightColor = WColor.Tint.color.colorWithAlpha(51)
        rvAdapter.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        updateLocalSearchVisibility()
        updateTopOverlay(animated = false)
        val top = (navigationController?.getSystemBars()?.top ?: 0) +
            if (isRootTopGradientEnabled) 0 else WNavigationBar.DEFAULT_HEIGHT.dp
        val bottom = if (isRootTopGradientEnabled) {
            navigationController?.getSystemBars()?.bottom ?: 0
        } else {
            navigationController?.bottomInset ?: 0
        }
        val searchContentPadding = if (!shouldShowLocalSearch) {
            0
        } else if (window?.isWideLayout == true) {
            WIDE_LAYOUT_SEARCH_CONTENT_PADDING
        } else {
            PHONE_SEARCH_CONTENT_PADDING
        }
        recyclerView.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            top,
            systemBarEndInset,
            bottom + searchContentPadding.dp
        )
        val availableWidth = (
            view.width.takeIf { it > 0 }
                ?: context.resources.displayMetrics.widthPixels
            ) -
            additionalTabletPadding - systemBarStartInset - systemBarEndInset - 40.dp
        expandedSearchWidth = availableWidth.coerceAtLeast(MIN_SEARCH_WIDTH.dp)
        updateSearchWidth()
        searchBottomAnimator.animatedValue = searchBottomMargin().toFloat()
        bringSearchToFront()
    }

    private fun bringSearchToFront() {
        if (!shouldShowLocalSearch) return
        if (view.indexOfChild(searchView) == view.childCount - 1) return
        searchGlass?.bringToFront()
        searchView.bringToFront()
    }

    private val shouldShowLocalSearch: Boolean
        get() = !isRootTopGradientEnabled

    private fun updateLocalSearchVisibility() {
        val shouldShow = shouldShowLocalSearch
        if (searchView.isVisible == shouldShow) {
            return
        }
        searchView.isVisible = shouldShow
        if (!shouldShow) {
            if (searchEditText.text?.isNotEmpty() == true) searchEditText.setText("")
            if (searchEditText.hasFocus()) {
                searchEditText.clearFocus()
                searchEditText.hideKeyboard()
            }
        }
    }

    private fun updateMarketBlurViews(recyclerView: RecyclerView) {
        updateBlurViews(recyclerView)
    }

    private fun updateSearchWidth() {
        val expandedWidth = expandedSearchWidth
        val collapsedWidth = min(collapsedSearchWidth, expandedWidth)
        searchView.updateLayoutParams<ConstraintLayout.LayoutParams> {
            width = lerp(
                collapsedWidth.toFloat(),
                expandedWidth.toFloat(),
                searchFocused.floatValue
            ).roundToInt()
        }
        searchEditText.setPaddingDpLocalized(
            lerp(21f, 16f, searchFocused.floatValue).ceilToInt(),
            0,
            lerp(0f, 48f, searchFocused.floatValue).ceilToInt(),
            0
        )
    }

    override fun scrollToTop() {
        recyclerView.smoothScrollToPosition(0)
    }

    override fun onBackPressed(): Boolean {
        (window?.window?.currentFocus as? WSearchEditText)?.let {
            it.clearFocus()
            return false
        }
        return super.onBackPressed()
    }

    override fun marketSectionsUpdated() {
        rvAdapter.reloadData()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int =
        marketVM.sections.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        val sections = marketVM.sections
        val section = sections.getOrNull(indexPath.row) ?: return ROWS_CELL
        return when (section.layout) {
            MApiMarketSectionLayout.LARGE_HORIZONTAL -> MOVERS_CELL
            MApiMarketSectionLayout.GRID -> GRID_CELL
            MApiMarketSectionLayout.ROWS, null -> ROWS_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            MOVERS_CELL -> MarketMoversSectionCell(context, ::showAll, ::openToken)
            GRID_CELL -> MarketGridSectionCell(context, ::showAll, ::openToken)
            else -> MarketRowsSectionCell(context, ::showAll, ::openToken)
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val sections = marketVM.sections
        val section = sections.getOrNull(indexPath.row) ?: return
        val bottomSpacing = if (
            isRootTopGradientEnabled && indexPath.row == sections.lastIndex
        ) {
            0
        } else {
            SECTION_BOTTOM_SPACING
        }
        when (val cell = cellHolder.cell) {
            is MarketMoversSectionCell -> cell.configure(section, bottomSpacing)
            is MarketGridSectionCell -> cell.configure(section, bottomSpacing)
            is MarketRowsSectionCell -> cell.configure(section, bottomSpacing)
        }
    }

    override fun onDestroy() {
        marketVM.stop()
        searchBottomAnimator.stopAnimation()
        searchGlass = null
        searchEditText.removeTextChangedListener(searchTextWatcher)
        searchEditText.setOnEditorActionListener(null)
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.layoutManager = null
        super.onDestroy()
    }

    private fun searchBottomMargin(): Int {
        val wideLayoutOffset = if (window?.isWideLayout == true) {
            WIDE_LAYOUT_BOTTOM_OFFSET
        } else {
            0
        }
        return (navigationController?.getSystemBars()?.bottom ?: 0) +
            (
                SEARCH_BOTTOM_MARGIN -
                    BOTTOM_NAVIGATION_VERTICAL_OFFSET -
                    PHONE_LAYOUT_VERTICAL_OFFSET +
                    wideLayoutOffset
                ).dp
    }

    private fun showAll(section: MarketSection) {
        val targetNavigationController =
            navigationController?.tabBarController?.mainNavigationController
                ?: navigationController
        targetNavigationController?.push(
            MarketTokenListVC(context, section.title, section.tokens)
        )
    }

    private fun openToken(token: MarketToken) {
        WalletCore.notifyEvent(WalletEvent.OpenToken(token.id))
    }

    private companion object {
        val MOVERS_CELL = WCell.Type(1)
        val GRID_CELL = WCell.Type(2)
        val ROWS_CELL = WCell.Type(3)

        const val SEARCH_HEIGHT = 48
        const val COLLAPSED_SEARCH_MAX_WIDTH = 320
        const val MIN_SEARCH_WIDTH = 220
        const val SEARCH_BOTTOM_MARGIN = 10
        const val BOTTOM_NAVIGATION_VERTICAL_OFFSET = 2
        const val PHONE_LAYOUT_VERTICAL_OFFSET = 5
        const val WIDE_LAYOUT_BOTTOM_OFFSET = 13
        const val PHONE_SEARCH_CONTENT_PADDING = 50
        const val WIDE_LAYOUT_SEARCH_CONTENT_PADDING = 52
    }
}
