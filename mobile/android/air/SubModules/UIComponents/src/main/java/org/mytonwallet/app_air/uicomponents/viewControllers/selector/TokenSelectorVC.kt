package org.mytonwallet.app_air.uicomponents.viewControllers.selector

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.Guideline
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.core.widget.doOnTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconTitleSubtitleView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells.TokenSelectorCell
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItemVC
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.getTrustedUsdtTokens
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class TokenSelectorVC(
    context: Context,
    private val titleToShow: String,
    private val assets: List<IApiToken>,
    private val showMyAssets: Boolean,
    private val showChain: Boolean,
    private val showBalance: Boolean = true,
    private val secondaryAmountMode: TokenSelectorCell.SecondaryAmountMode =
        TokenSelectorCell.SecondaryAmountMode.BALANCE_VALUE,
    private val fiatOptions: List<FiatOption> = emptyList(),
    private val showsAssetCategories: Boolean = false,
    private val requiresBalance: Boolean = false,
    private val showOnlyMyAssets: Boolean = false,
    private val supportedAssetSlugs: Set<String>? = null,
    private val pageCategory: Category? = null
) : WViewController(context),
    WThemedView,
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver,
    WSegmentedControllerItemVC {
    @Suppress("PropertyName")
    override val TAG = "TokenSelector"

    companion object {
        private const val CATEGORY_TITLE_HEIGHT = 56
        private const val CATEGORY_TABS_EXTRA_HEIGHT = 6
        private const val CATEGORY_TABS_THUMB_HEIGHT = 36f
        private const val CATEGORY_SEARCH_HEIGHT = 64
        private const val SEARCH_HEIGHT = 48
        val TOKEN_SELECTOR_CELL = WCell.Type(1)
        val HEADER_CELL = WCell.Type(2)

        const val SECTION_MY = 0
        const val SECTION_FIAT = 1
        const val SECTION_STABLECOINS = 2
        const val SECTION_POPULAR = 3
        const val TOTAL_SECTIONS = 4
    }

    data class FiatOption(
        val currency: MBaseCurrency,
        val subtitle: String,
        val onSelect: () -> Unit
    )

    enum class Category(val title: String) {
        ALL("All"),
        FIAT("Fiat"),
        STABLECOINS("Stablecoins"),
        TOKENS("Tokens")
    }

    private data class SectionData(
        val title: String,
        val tokens: List<MTokenBalance>,
        val fiatOptions: List<FiatOption> = emptyList(),
        val showsHeader: Boolean = true
    ) {
        val itemCount: Int
            get() = fiatOptions.size + tokens.size
        val headerRows: Int
            get() = if (showsHeader) 1 else 0
    }

    private val category: Category
        get() = pageCategory ?: Category.ALL

    // Categories are swipeable pages of this selector; the container owns the search.
    private val isCategoryContainer by lazy {
        showsAssetCategories && pageCategory == null &&
            (!showOnlyMyAssets || hasMoreThanFiveOwnedAssets())
    }

    private fun hasMoreThanFiveOwnedAssets(): Boolean {
        if (!showMyAssets) return false
        val assetSlugs = assets.map { it.slug }.toSet()
        return AccountStore.assetsAndActivityData.getAllTokens()
            .distinctBy { it.token }
            .count {
                it.amountValue > BigInteger.ZERO && it.token in assetSlugs &&
                    isPairSupported(it.token) && TokenStore.getToken(it.token) != null
            } > 5
    }

    override var segmentedController: WSegmentedController? = null
    override var badge: String? = null

    init {
        pageCategory?.let { title = LocaleController.getString(it.title) }
    }

    private val categoryPages: List<TokenSelectorVC> by lazy {
        Category.entries.map { category ->
            TokenSelectorVC(
                context,
                titleToShow,
                assets,
                showMyAssets,
                showChain,
                showBalance,
                secondaryAmountMode,
                fiatOptions,
                showsAssetCategories = true,
                requiresBalance = requiresBalance,
                showOnlyMyAssets = showOnlyMyAssets,
                supportedAssetSlugs = supportedAssetSlugs,
                pageCategory = category
            ).apply {
                setOnAssetSelectListener { asset ->
                    this@TokenSelectorVC.onAssetSelectListener?.invoke(asset)
                }
            }
        }
    }

    private val categoryController: WSegmentedController by lazy {
        WSegmentedController(
            navigationController!!,
            categoryPages.map {
                WSegmentedControllerItem(it, identifier = it.pageCategory?.name)
            }.toMutableList(),
            applySideGutters = false,
            navTopPadding = CATEGORY_TITLE_HEIGHT.dp,
            navHeight = (WNavigationBar.DEFAULT_HEIGHT + CATEGORY_TABS_EXTRA_HEIGHT).dp,
            pilledTabs = true,
            pilledTabsFillWidth = true,
            pilledTabsHeight = WSegmentedController.PILLED_TABS_HEIGHT + CATEGORY_TABS_EXTRA_HEIGHT,
            pilledTabsThumbHeight = CATEGORY_TABS_THUMB_HEIGHT
        )
    }

    private data class TokenSortFactors(
        val specialOrder: Int = 0,
        val tickerExactMatch: Int = 0,
        val tickerMatchLength: Int = 0,
        val nameMatchLength: Int = 0
    )

    private var sections: Map<Int, SectionData> = emptyMap()

    override val shouldDisplayBottomBar = true

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(TOKEN_SELECTOR_CELL, HEADER_CELL))

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.layoutManager = layoutManager
        rv.clipToPadding = false
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                    updateListBlur(recyclerView)
                }
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0) return
                updateListBlur(recyclerView)
            }
        })
        rv
    }

    // Floating search pill; its glass blurs the list or category pages behind it.
    private val floatingSearchView by lazy {
        WFrameLayout(context).apply {
            setBackgroundColor(Color.TRANSPARENT, SEARCH_HEIGHT.dp / 2f, clipToBounds = true)
        }
    }
    private var searchGlass: WGlassView? = null

    private val searchEditText = WSearchEditText(context)

    private var query: String? = null

    private val emptyView: WEmptyIconTitleSubtitleView by lazy {
        WEmptyIconTitleSubtitleView(
            context,
            animation = R.raw.animation_empty,
            title = LocaleController.getString("No tokens yet"),
            subtitle = ""
        ).apply {
            isGone = true
        }
    }

    override val shouldDisplayTopBar: Boolean
        get() = !isCategoryContainer

    // Each category page draws its own gutter-inset top corners below the shared tabs header,
    // so the corners travel with the page while it is dragged horizontally.
    private val pageTopGuideline by lazy {
        Guideline(context).apply { id = android.view.View.generateViewId() }
    }
    override val topBlurViewGuideline: android.view.View?
        get() = if (pageCategory != null) pageTopGuideline else null

    override val isSwipeBackAllowed: Boolean
        get() = !isCategoryContainer
    override val isEdgeSwipeBackAllowed: Boolean
        get() = isCategoryContainer

    override fun setupViews() {
        super.setupViews()

        if (isCategoryContainer) {
            setupCategoryContainer()
            return
        }

        WalletCore.registerObserver(this)
        buildTokenItems()

        if (pageCategory != null) {
            view.addView(
                pageTopGuideline,
                ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    orientation = ConstraintLayout.LayoutParams.HORIZONTAL
                    guideBegin = segmentedController?.headerHeight ?: 0
                }
            )
        }
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(emptyView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        if (pageCategory == null) {
            setNavTitle(titleToShow)
            setupNavBar(true)
            if (navigationController?.viewControllers?.size == 1) {
                navigationBar?.addCloseButton()
            }
            navigationBar?.setTitleGravity(Gravity.START)
            setupFloatingSearch()
        }

        view.setConstraints {
            toCenterX(recyclerView)
            toTop(recyclerView)
            toBottom(recyclerView)

            toCenterX(emptyView, 32f)
            toCenterY(emptyView)
        }

        updateTheme()
        insetsUpdated()
    }

    private fun setupSearchField() {
        searchEditText.isSearchIconFixed = true
        searchEditText.hint = LocaleController.getString("Search...")
        searchEditText.doOnTextChanged { text, _, _, _ ->
            query = text?.toString()
            if (isCategoryContainer) applyFiltersToPages() else buildTokenItems()
        }
    }

    private fun setupCategoryContainer() {
        view.addView(
            categoryController,
            ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
                ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
            )
        )
        view.setConstraints { allEdges(categoryController) }
        setupFloatingSearch()

        setNavTitle(titleToShow)
        setupNavBar(true)
        navigationBar?.setTitleGravity(Gravity.START)
        if (navigationController?.viewControllers?.size == 1) {
            navigationBar?.addCloseButton()
        }
        navigationBar?.bringToFront()

        updateTheme()
        insetsUpdated()
    }

    private fun setupFloatingSearch() {
        setupSearchField()
        floatingSearchView.addView(
            searchEditText,
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        view.addView(
            floatingSearchView,
            ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
                SEARCH_HEIGHT.dp
            )
        )
        view.setConstraints {
            toCenterX(floatingSearchView, 16f)
        }
        searchGlass = WGlassView.attachTo(
            floatingSearchView,
            SEARCH_HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.SearchFieldBackground),
            view
        )
    }

    // A category page closes the whole selector, which is presented on its own when it has tabs.
    private fun finishSelection() {
        if (showsAssetCategories && navigationController?.viewControllers?.size == 1) {
            window?.dismissLastNav()
        } else {
            pop()
        }
    }

    private fun applyFiltersToPages() {
        categoryPages.forEach { it.applyFilters(query) }
    }

    private fun applyFilters(query: String?) {
        this.query = query
        buildTokenItems()
    }

    private fun updateListBlur(recyclerView: RecyclerView) {
        segmentedController?.updateBlurViews(recyclerView)
        updateBlurViews(recyclerView)
    }

    override fun onFullyVisible() {}

    override fun onPartiallyVisible() {}

    override fun didSetupViews() {
        super.didSetupViews()
        if (pageCategory == null) bringSearchToFront()
    }

    private fun bringSearchToFront() {
        searchGlass?.bringToFront()
        floatingSearchView.bringToFront()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
        if (pageCategory == null) {
            searchGlass?.updateTheme()
            searchEditText.updateTheme()
        }
    }

    override fun scrollToTop() {
        if (isCategoryContainer) {
            categoryController.scrollToTop()
            return
        }
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        if (pageCategory == null) {
            view.setConstraints {
                toStartPx(floatingSearchView, 16.dp + systemBarStartInset)
                toEndPx(floatingSearchView, 16.dp + systemBarEndInset)
                toBottomPx(
                    floatingSearchView,
                    max(
                        navigationController?.getSystemBars()?.bottom ?: 0,
                        navigationController?.imeInsetBottom ?: 0
                    ) + 8.dp
                )
            }
            bringSearchToFront()
        }
        if (isCategoryContainer) {
            categoryController.insetsUpdated()
            categoryPages.forEach { if (it.isViewConfigured) it.insetsUpdated() }
            return
        }

        val ime = (navigationController?.imeInsetBottom ?: 0)
        val nav = (navigationController?.bottomInset ?: 0)

        view.setConstraints {
            toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toBottomPx(recyclerView, ime)
        }

        val topPadding = segmentedController?.headerHeight
            ?: (
                (navigationController?.getSystemBars()?.top ?: 0) +
                    WNavigationBar.DEFAULT_HEIGHT.dp
                )
        if (pageCategory != null && pageTopGuideline.layoutParams != null) {
            pageTopGuideline.updateLayoutParams<ConstraintLayout.LayoutParams> {
                guideBegin = topPadding
            }
        }
        val bottomPadding = max(nav, ime) + CATEGORY_SEARCH_HEIGHT.dp - ime
        recyclerView.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            topPadding,
            systemBarEndInset,
            bottomPadding
        )
    }

    private var onAssetSelectListener: ((IApiToken) -> Unit)? = null

    fun setOnAssetSelectListener(listener: ((IApiToken) -> Unit)) {
        onAssetSelectListener = listener
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int =
        if (sections.isEmpty()) 0 else TOTAL_SECTIONS

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        val sectionData = sections[section] ?: return 0
        return if (sectionData.itemCount == 0) 0 else sectionData.itemCount + sectionData.headerRows
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        if (indexPath.row < (sections[indexPath.section]?.headerRows ?: 1)) {
            HEADER_CELL
        } else {
            TOKEN_SELECTOR_CELL
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            TOKEN_SELECTOR_CELL -> {
                val cell = TokenSelectorCell(context)
                cell.onTap = { tokenBalance ->
                    val asset = assets.find { it.slug == tokenBalance.token }
                    asset?.let { onAssetSelectListener?.invoke(it) }
                    finishSelection()
                }
                cell
            }

            HEADER_CELL -> {
                HeaderCell(context)
            }

            else -> throw IllegalArgumentException("Unknown cell type: $cellType")
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val cell = cellHolder.cell
        val sectionData = sections[indexPath.section] ?: return

        when (cell) {
            is TokenSelectorCell -> {
                val isLastOverall =
                    rvAdapter.indexPathToPosition(indexPath) == rvAdapter.itemCount - 1
                val row = indexPath.row - sectionData.headerRows
                sectionData.fiatOptions.getOrNull(row)?.let { option ->
                    cell.configure(option.currency, isLastOverall)
                    cell.onFiatTap = {
                        option.onSelect()
                        finishSelection()
                    }
                    return
                }
                if (row >= 0 && row < sectionData.tokens.size) {
                    val token = sectionData.tokens[row]
                    val position = rvAdapter.indexPathToPosition(indexPath)

                    cell.configure(
                        token,
                        showChain = showChain,
                        isLast = position == rvAdapter.itemCount - 1,
                        isFirst = position == 0,
                        showBalance = showBalance,
                        secondaryAmountMode = secondaryAmountMode,
                        isSelectable = isPairSupported(token.token) &&
                            (
                                !requiresLocalBalance(token.token) ||
                                    token.amountValue > BigInteger.ZERO
                                )
                    )
                }
            }

            is HeaderCell -> {
                val isFirstHeader = rvAdapter.indexPathToPosition(indexPath) == 0
                val topRounding =
                    if (isFirstHeader) {
                        HeaderCell.TopRounding.FIRST_ITEM
                    } else {
                        HeaderCell.TopRounding.ZERO
                    }

                cell.configure(
                    sectionData.title,
                    titleColor = WColor.Tint,
                    topRounding = topRounding
                )
            }
        }
    }

    private fun buildTokenItems() {
        val activeAccount = AccountStore.activeAccount
        val balances = AccountStore.assetsAndActivityData.getAllTokens()
        val rawSearch = query.orEmpty()
        val assets = this.assets.filter { token ->
            token.matchesSearch(rawSearch) && matchesFilters(token) &&
                (rawSearch.isNotBlank() || isPairSupported(token.slug))
        }
        val assetsMap = assets.associateBy { it.slug }

        val used = mutableSetOf<String>()
        val newSections = mutableMapOf<Int, SectionData>()

        // My tokens section
        if (showMyAssets) {
            val myTokens = mutableListOf<MTokenBalance>()
            for (balance in balances) {
                if (!assetsMap.containsKey(balance.token)) continue
                if (balance.amountValue == BigInteger.ZERO) continue
                val asset = assetsMap[balance.token] ?: continue
                if (!used.add(asset.slug)) continue

                val tokenBalance = createTokenBalance(asset, balance.amountValue) ?: continue
                myTokens.add(tokenBalance)
            }
            newSections[SECTION_MY] = SectionData(
                title = LocaleController.getString("My"),
                tokens = myTokens
            )
        } else {
            newSections[SECTION_MY] = SectionData(
                title = LocaleController.getString("My"),
                tokens = emptyList()
            )
        }

        val search = rawSearch.trim()
        val fiatMatches = fiatOptions.filter { option ->
            (category == Category.ALL || category == Category.FIAT) &&
                (
                    search.isEmpty() || listOf(
                        option.currency.currencyCode,
                        option.currency.currencyName,
                        option.subtitle
                    ).any { it.contains(search, ignoreCase = true) }
                    )
        }
        newSections[SECTION_FIAT] = SectionData(
            title = LocaleController.getString("Fiat"),
            tokens = emptyList(),
            fiatOptions = fiatMatches
        )

        val accountBalances = BalanceStore.getBalances(activeAccount?.accountId)
        val hidesZeroBalances = requiresBalance && rawSearch.isEmpty()
        val trustedUsdtTokens = getTrustedUsdtTokens(activeAccount?.network)
        if (showsAssetCategories && !showOnlyMyAssets && category == Category.ALL) {
            val stablecoinTokens = assets.mapNotNull { asset ->
                if (asset.slug !in trustedUsdtTokens || !used.add(asset.slug)) {
                    return@mapNotNull null
                }
                val tokenBalance = createTokenBalance(asset, accountBalances?.get(asset.slug))
                    ?: return@mapNotNull null
                tokenBalance.takeUnless {
                    hidesZeroBalances && requiresLocalBalance(asset.slug) &&
                        it.amountValue <= BigInteger.ZERO
                }
            }
            newSections[SECTION_STABLECOINS] = SectionData(
                title = LocaleController.getString("Stablecoins"),
                tokens = sortPopularTokens(
                    search = search.lowercase().takeIf { it.isNotEmpty() },
                    tokenBalances = stablecoinTokens,
                    assetsMap = assetsMap,
                    trustedUsdtTokens = trustedUsdtTokens
                )
            )
        }

        // Popular tokens section
        val showsAllAssets = rawSearch.isNotBlank() ||
            (!showOnlyMyAssets && category == Category.STABLECOINS)
        val popularAssets = if (showOnlyMyAssets) {
            emptyList()
        } else {
            assets.filter {
                it.isPopular ==
                    true
            }
        }
        val popularTokens = mutableListOf<MTokenBalance>()
        for (asset in popularAssets) {
            if (!used.add(asset.slug)) continue
            val balance = accountBalances?.get(asset.slug)
            val tokenBalance = createTokenBalance(asset, balance) ?: continue
            if (hidesZeroBalances && requiresLocalBalance(asset.slug) &&
                tokenBalance.amountValue <= BigInteger.ZERO
            ) {
                continue
            }
            popularTokens.add(tokenBalance)
        }
        // Additional tokens when searching (added to Popular section)
        if (showsAllAssets) {
            for (asset in assets) {
                if (!used.add(asset.slug)) continue
                val balance = accountBalances?.get(asset.slug)
                val tokenBalance = createTokenBalance(asset, balance) ?: continue
                if (hidesZeroBalances && requiresLocalBalance(asset.slug) &&
                    tokenBalance.amountValue <= BigInteger.ZERO
                ) {
                    continue
                }
                popularTokens.add(tokenBalance)
            }
        }

        // Sort tokens: web-like search ranking, fallback to predefined popular order
        val sortedPopularTokens = sortPopularTokens(
            search = rawSearch.trim().lowercase().takeIf { it.isNotEmpty() },
            tokenBalances = popularTokens,
            assetsMap = assetsMap,
            trustedUsdtTokens = trustedUsdtTokens
        )

        newSections[SECTION_POPULAR] = SectionData(
            title = LocaleController.getString(
                when {
                    showsAllAssets -> "A ~ Z"
                    showsAssetCategories -> "Tokens"
                    else -> "Popular"
                }
            ),
            tokens = sortedPopularTokens,
            showsHeader = !showsAllAssets || newSections.values.any { it.itemCount > 0 }
        )

        sections = newSections
        rvAdapter.reloadData()

        val isEmpty = newSections.values.all { it.itemCount == 0 }
        emptyView.setTitle(
            LocaleController.getString(
                if (rawSearch.isNotEmpty()) "Token Not Found" else "No tokens yet"
            )
        )
        emptyView.isVisible = isEmpty
        recyclerView.isGone = isEmpty
    }

    private fun isPairSupported(slug: String?): Boolean =
        supportedAssetSlugs?.contains(slug) != false

    private fun requiresLocalBalance(slug: String?): Boolean {
        if (showOnlyMyAssets) return requiresBalance
        val chain = TokenStore.getToken(slug)?.mBlockchain?.name ?: return requiresBalance
        return requiresBalance && AccountStore.activeAccount?.isChainSupported(chain) != false
    }

    private fun matchesFilters(token: IApiToken): Boolean = when (category) {
        Category.ALL, Category.TOKENS -> true
        Category.STABLECOINS -> isStablecoin(token)
        Category.FIAT -> false
    }

    private fun isStablecoin(token: IApiToken): Boolean =
        token.slug in getTrustedUsdtTokens(AccountStore.activeAccount?.network)

    private fun createTokenBalance(asset: IApiToken, balance: BigInteger? = null): MTokenBalance? {
        val token = TokenStore.getToken(asset.slug) ?: return null
        return MTokenBalance.fromParameters(token, balance ?: BigInteger.ZERO)
    }

    private fun sortPopularTokens(
        search: String?,
        tokenBalances: List<MTokenBalance>,
        assetsMap: Map<String, IApiToken>,
        trustedUsdtTokens: Set<String>
    ): List<MTokenBalance> {
        return tokenBalances.sortedWith { a, b ->
            if (!search.isNullOrBlank()) {
                val factorsA = getSearchSortFactors(assetsMap[a.token], search, trustedUsdtTokens)
                val factorsB = getSearchSortFactors(assetsMap[b.token], search, trustedUsdtTokens)
                val factorCompare = compareSearchFactors(factorsA, factorsB)
                if (factorCompare != 0) {
                    return@sortedWith factorCompare
                }

                val amountCompare = b.amountValue.compareTo(a.amountValue)
                if (amountCompare != 0) {
                    return@sortedWith amountCompare
                }

                val slugA = a.token ?: ""
                val slugB = b.token ?: ""
                return@sortedWith slugA.compareTo(slugB)
            }

            val symbolA = TokenStore.getToken(a.token)?.symbol
            val symbolB = TokenStore.getToken(b.token)?.symbol

            val orderA =
                MBlockchain.POPULAR_TOKEN_ORDER_MAP[symbolA] ?: MBlockchain.POPULAR_TOKEN_ORDER.size
            val orderB =
                MBlockchain.POPULAR_TOKEN_ORDER_MAP[symbolB] ?: MBlockchain.POPULAR_TOKEN_ORDER.size

            orderA.compareTo(orderB)
        }
    }

    private fun compareSearchFactors(a: TokenSortFactors, b: TokenSortFactors): Int {
        if (a.specialOrder != b.specialOrder) {
            return b.specialOrder - a.specialOrder
        }
        if (a.tickerExactMatch != b.tickerExactMatch) {
            return b.tickerExactMatch - a.tickerExactMatch
        }
        if (a.tickerMatchLength != b.tickerMatchLength) {
            return b.tickerMatchLength - a.tickerMatchLength
        }
        return b.nameMatchLength - a.nameMatchLength
    }

    private fun getSearchSortFactors(
        token: IApiToken?,
        search: String,
        trustedUsdtTokens: Set<String>
    ): TokenSortFactors {
        if (token == null || search.isBlank()) {
            return TokenSortFactors()
        }

        val lowercaseSearch = search.lowercase()
        val tokenSymbol = token.symbol?.lowercase() ?: ""
        val tokenName = token.displayName?.lowercase() ?: ""
        val chainPriority = token.mBlockchain?.let { MBlockchain.supportedChainIndexes[it.name] }
        val specialOrder = if (token.slug in trustedUsdtTokens && chainPriority != null) {
            MBlockchain.supportedChains.size - chainPriority
        } else {
            0
        }

        return TokenSortFactors(
            specialOrder = specialOrder,
            tickerExactMatch = if (tokenSymbol == lowercaseSearch) 1 else 0,
            tickerMatchLength = if (tokenSymbol.contains(
                    lowercaseSearch
                )
            ) {
                lowercaseSearch.length
            } else {
                0
            },
            nameMatchLength = if (tokenName.contains(lowercaseSearch)) lowercaseSearch.length else 0
        )
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.BalanceChanged,
            is WalletEvent.TokensChanged,
            is WalletEvent.AccountChanged,
            is WalletEvent.BaseCurrencyChanged -> {
                buildTokenItems()
            }

            else -> {}
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        searchGlass = null
        if (isCategoryContainer) {
            categoryController.onDestroy()
            return
        }
        recyclerView.onDestroy()
        recyclerView.adapter = null
        recyclerView.removeAllViews()
    }
}
