package org.mytonwallet.app_air.uicomponents.viewControllers

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.widget.doOnTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconTitleSubtitleView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells.TokenSelectorCell
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class SendTokenVC(
    context: Context,
    private val selectedChain: MBlockchain? = null
) : WViewController(context), WThemedView, WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver {
    override val TAG = "SendToken"

    companion object {
        val TOKEN_CELL = WCell.Type(1)
        val HEADER_CELL = WCell.Type(2)

        const val SECTION_MY = 0
        const val SECTION_OTHER = 1
        const val TOTAL_SECTIONS = 2
    }

    private data class SectionData(
        val title: String,
        val tokens: List<MTokenBalance>
    )

    private var sections: Map<Int, SectionData> = emptyMap()

    override val shouldDisplayBottomBar = true

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(TOKEN_CELL, HEADER_CELL))

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

    private val emptyView: WEmptyIconTitleSubtitleView by lazy {
        WEmptyIconTitleSubtitleView(
            context,
            animation = R.raw.animation_empty,
            title = LocaleController.getString("No tokens yet"),
            subtitle = "",
        ).apply {
            isGone = true
        }
    }

    private val searchContainer = WFrameLayout(context)
    private val searchEditText = SwapSearchEditText(context)
    private var query: String? = null

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        buildTokenItems()
        setNavTitle(LocaleController.getString("Select Token"))
        setupNavBar(true)

        searchEditText.isSearchIconFixed = true
        searchEditText.hint = LocaleController.getString("Search...")
        searchContainer.addView(searchEditText, ViewGroup.LayoutParams(MATCH_PARENT, 48.dp))
        searchContainer.setPadding(10.dp, 0, 10.dp, 8.dp)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(emptyView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        navigationBar?.addBottomView(searchContainer, 56.dp)

        searchEditText.doOnTextChanged { text, _, _, _ ->
            query = text?.toString()
            buildTokenItems()
        }

        view.setConstraints {
            topToBottom(searchContainer, navigationBar!!)
            toCenterX(searchContainer)

            toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toTop(recyclerView)
            toBottom(recyclerView)
            toCenterX(emptyView, 32f)
            toCenterY(emptyView)
        }

        updateTheme()
        insetsUpdated()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
        searchEditText.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        val ime = (navigationController?.imeInsetBottom ?: 0)
        val nav = (navigationController?.bottomInset ?: 0)

        recyclerView.setPaddingRelative(
            systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp +
                56.dp,
            systemBarEndInset,
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
            TOKEN_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            TOKEN_CELL -> {
                val cell = TokenSelectorCell(context)
                cell.onTap = { tokenBalance ->
                    val token = TokenStore.getToken(tokenBalance.token)
                    token?.let { onAssetSelectListener?.invoke(it) }
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

                    val isLastOverall =
                        rvAdapter.indexPathToPosition(indexPath) == rvAdapter.itemCount - 1

                    cell.configure(
                        tokenBalance = token,
                        showChain = AccountStore.activeAccount?.isMultichain == true,
                        isLast = isLastOverall,
                    )
                }
            }

            is HeaderCell -> {
                val isFirstHeader = rvAdapter.indexPathToPosition(indexPath) == 0
                val topRounding =
                    if (isFirstHeader) HeaderCell.TopRounding.FIRST_ITEM else HeaderCell.TopRounding.ZERO

                cell.configure(
                    sectionData.title,
                    titleColor = WColor.Tint,
                    topRounding = topRounding
                )
            }
        }
    }


    private fun buildTokenItems() {
        val balances = AccountStore.assetsAndActivityData.getAllTokens()
        val search = query?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }

        val filteredBalances = balances.filter { balance ->
            val token = TokenStore.getToken(balance.token) ?: return@filter false
            if (selectedChain != null && token.chain != selectedChain.name) return@filter false
            if (token.isLpToken && balance.amountValue <= BigInteger.ZERO) return@filter false
            if (search != null) {
                val isName = token.name?.lowercase()?.contains(search) == true
                val isSymbol = token.symbol?.lowercase()?.contains(search) == true
                val isAddress = token.tokenAddress?.lowercase()?.contains(search) == true
                val isKeyword = token.keywords?.any { it.lowercase().contains(search) } == true
                if (!isName && !isSymbol && !isAddress && !isKeyword) return@filter false
            }
            true
        }

        val newSections = mutableMapOf<Int, SectionData>()

        // My tokens section (with balance)
        newSections[SECTION_MY] = SectionData(
            title = LocaleController.getString("Select Token to Send"),
            tokens = filteredBalances
        )

        // Other tokens section (currently empty, reserved for future use)
        newSections[SECTION_OTHER] = SectionData(
            title = LocaleController.getString("Other"),
            tokens = emptyList()
        )

        sections = newSections
        rvAdapter.reloadData()

        val isEmpty = filteredBalances.isEmpty()
        emptyView.setTitle(
            LocaleController.getString(
                if (search != null) "Token Not Found" else "No tokens yet"
            )
        )
        emptyView.isVisible = isEmpty
        recyclerView.isGone = isEmpty
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
