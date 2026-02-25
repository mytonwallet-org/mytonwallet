package org.mytonwallet.app_air.uicomponents.viewControllers

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells.TokenSelectorCell
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
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

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        buildTokenItems()
        setNavTitle(LocaleController.getString("Currency"))
        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
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

        recyclerView.setPadding(
            0,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp,
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
        val balances = AccountStore.assetsAndActivityData.getAllTokens(ignorePriorities = true)

        val filteredBalances = balances.filter { balance ->
            if (balance.amountValue == BigInteger.ZERO) return@filter false
            val token = TokenStore.getToken(balance.token) ?: return@filter false
            selectedChain == null || token.chain == selectedChain.name
        }

        val newSections = mutableMapOf<Int, SectionData>()

        // My tokens section (with balance)
        newSections[SECTION_MY] = SectionData(
            title = LocaleController.getString("Choose Currency to Send"),
            tokens = filteredBalances
        )

        // Other tokens section (currently empty, reserved for future use)
        newSections[SECTION_OTHER] = SectionData(
            title = LocaleController.getString("Other"),
            tokens = emptyList()
        )

        sections = newSections
        rvAdapter.reloadData()
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
