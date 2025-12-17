package org.mytonwallet.app_air.uicomponents.viewControllers.selector

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.widget.doOnTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells.TokenSelectorCell
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class TokenSelectorVC(
    context: Context,
    private val titleToShow: String,
    private val assets: List<IApiToken>,
    private val showMyAssets: Boolean = true
) : WViewController(context), WThemedView, WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver {
    override val TAG = "TokenSelector"

    companion object {
        val TOKEN_SELECTOR_CELL = WCell.Type(1)
        val HEADER_CELL = WCell.Type(2)

        const val SECTION_MY = 0
        const val SECTION_POPULAR = 1
        const val TOTAL_SECTIONS = 2
    }

    private data class SectionData(
        val title: String,
        val tokens: List<MTokenBalance>
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
                if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE)
                    updateBlurViews(recyclerView)
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0)
                    return
                updateBlurViews(recyclerView)
            }
        })
        rv
    }

    private val searchContainer = WFrameLayout(context)

    private val searchEditText = SwapSearchEditText(context)
    private var query: String? = null

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        buildTokenItems()

        setNavTitle(titleToShow)
        setupNavBar(true)

        searchContainer.addView(searchEditText, ViewGroup.LayoutParams(MATCH_PARENT, 48.dp))
        searchContainer.setPadding(10.dp, 0, 10.dp, 8.dp)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        navigationBar?.addBottomView(searchContainer, 56.dp)

        searchEditText.doOnTextChanged { text, _, _, _ ->
            query = text?.toString()
            buildTokenItems()
        }

        view.setConstraints {
            topToBottom(searchContainer, navigationBar!!)
            toCenterX(searchContainer)

            toCenterX(recyclerView)
            toTop(recyclerView)
            toBottom(recyclerView)
        }

        updateTheme()
        insetsUpdated()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        val ime = (window?.imeInsets?.bottom ?: 0)
        val nav = (navigationController?.getSystemBars()?.bottom ?: 0)

        view.setConstraints {
            toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toBottomPx(recyclerView, ime)
        }

        recyclerView.setPadding(
            0,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp +
                56.dp,
            0,
            max(0, nav - ime)
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
        return if (sectionData.tokens.isEmpty()) 0 else sectionData.tokens.size + 1 // +1 for header
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return if (indexPath.row == 0) {
            HEADER_CELL
        } else {
            TOKEN_SELECTOR_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            TOKEN_SELECTOR_CELL -> {
                val cell = TokenSelectorCell(context)
                cell.onTap = { tokenBalance ->
                    val asset = assets.find { it.slug == tokenBalance.token }
                    asset?.let { onAssetSelectListener?.invoke(it) }
                    pop()
                }
                cell
            }

            HEADER_CELL -> {
                HeaderCell(context)
            }

            else -> throw IllegalArgumentException("Unknown cell type: $cellType")
        }
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
                val tokenIndex = indexPath.row - 1 // -1 because row 0 is header
                if (tokenIndex >= 0 && tokenIndex < sectionData.tokens.size) {
                    val token = sectionData.tokens[tokenIndex]
                    val isLastInSection = indexPath.row == sectionData.tokens.size

                    val isLastOverall =
                        rvAdapter.indexPathToPosition(indexPath) == rvAdapter.itemCount - 1

                    cell.configure(
                        token,
                        isLast = isLastOverall,
                        hideSeparator = isLastInSection
                    )
                }
            }

            is HeaderCell -> {
                val isFirstHeader = rvAdapter.indexPathToPosition(indexPath) == 0
                val topRounding = if (isFirstHeader) ViewConstants.BIG_RADIUS.dp else 0f

                cell.configure(sectionData.title, topRounding = topRounding)
            }
        }

    }


    private fun buildTokenItems() {
        val balances = AccountStore.assetsAndActivityData.getAllTokens(ignorePriorities = true)
        val search = query?.takeIf { it.isNotEmpty() }?.lowercase()
        val assets = this.assets.filter { token ->
            search?.let {
                token.name?.lowercase()?.contains(it) == true ||
                    token.symbol?.lowercase()?.contains(it) == true ||
                    token.tokenAddress?.lowercase()?.contains(it) == true
            } != false
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

        // Popular tokens section
        val popularAssets = assets.filter { it.isPopular == true }
        val popularTokens = mutableListOf<MTokenBalance>()
        for (asset in popularAssets) {
            if (!used.add(asset.slug)) continue
            val tokenBalance = createTokenBalance(asset) ?: continue
            popularTokens.add(tokenBalance)
        }
        // Additional tokens when searching (added to Popular section)
        if (query?.isNotEmpty() == true) {
            for (asset in assets) {
                if (!used.add(asset.slug)) continue
                val tokenBalance = createTokenBalance(asset) ?: continue
                popularTokens.add(tokenBalance)
            }
        }

        // Sort popular tokens according to the predefined order
        val sortedPopularTokens = sortPopularTokens(popularTokens)

        newSections[SECTION_POPULAR] = SectionData(
            title = LocaleController.getString("Popular"),
            tokens = sortedPopularTokens
        )

        sections = newSections
        rvAdapter.reloadData()
    }

    private fun createTokenBalance(asset: IApiToken, balance: BigInteger? = null): MTokenBalance? {
        val token = TokenStore.getToken(asset.slug) ?: return null
        return MTokenBalance.fromParameters(token, balance ?: BigInteger.ZERO)
    }

    private fun sortPopularTokens(tokenBalances: List<MTokenBalance>): List<MTokenBalance> {
        return tokenBalances.sortedWith { a, b ->
            val symbolA = TokenStore.getToken(a.token)?.symbol
            val symbolB = TokenStore.getToken(b.token)?.symbol

            val orderA =
                MBlockchain.POPULAR_TOKEN_ORDER_MAP[symbolA] ?: MBlockchain.POPULAR_TOKEN_ORDER.size
            val orderB =
                MBlockchain.POPULAR_TOKEN_ORDER_MAP[symbolB] ?: MBlockchain.POPULAR_TOKEN_ORDER.size

            orderA.compareTo(orderB)
        }
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

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
        recyclerView.onDestroy()
        recyclerView.adapter = null
        recyclerView.removeAllViews()
    }
}
