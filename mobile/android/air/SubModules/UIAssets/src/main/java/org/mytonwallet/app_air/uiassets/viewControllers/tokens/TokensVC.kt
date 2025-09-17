package org.mytonwallet.app_air.uiassets.viewControllers.tokens

import WNavigationController
import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.cells.TokenCell
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.ShowAllView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

@SuppressLint("ViewConstructor")
class TokensVC(
    context: Context,
    private val mode: Mode,
    private val onHeightChanged: (() -> Unit)? = null,
    private val onScroll: ((rv: RecyclerView) -> Unit)? = null
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, WalletCore.EventObserver {

    enum class Mode {
        HOME,
        ALL
    }

    companion object {
        val TOKEN_CELL = WCell.Type(1)
    }

    override var title: String?
        get() {
            return LocaleController.getString("Assets")
        }
        set(_) {
        }

    override val shouldDisplayTopBar = false

    override val isSwipeBackAllowed = false

    private var walletTokens: Array<MTokenBalance> = emptyArray()

    private var thereAreMoreToShow: Boolean = false

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(TOKEN_CELL))

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0)
                return
            updateBlurViews(recyclerView)
            onScroll?.invoke(recyclerView)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                updateBlurViews(recyclerView)
                onScroll?.invoke(recyclerView)
            }
        }
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        if (mode == Mode.ALL) {
            rv.addItemDecoration(
                LastItemPaddingDecoration(
                    navigationController?.getSystemBars()?.bottom ?: 0
                )
            )
        }
        rv.setItemAnimator(null)
        if (mode == Mode.ALL) {
            rv.setPadding(
                0,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    WNavigationBar.DEFAULT_HEIGHT.dp,
                0,
                0
            )
            rv.clipToPadding = false
        }
        rv.addOnScrollListener(scrollListener)
        rv
    }

    private val showAllView: ShowAllView by lazy {
        val v = ShowAllView(context)
        v.titleLabel.text = LocaleController.getString("Show All Assets")
        v.onTap = {
            val window = this.window!!
            val navVC = WNavigationController(window)
            navVC.setRoot(AssetsTabVC(context))
            window.present(navVC)
        }
        v.visibility = View.GONE
        v
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (mode == Mode.HOME) {
            view.addView(showAllView, ViewGroup.LayoutParams(MATCH_PARENT, 56.dp))
        }
        view.setConstraints {
            allEdges(recyclerView)
            if (mode == Mode.HOME) {
                toTop(showAllView, 320f)
                toCenterX(showAllView)
            }
        }

        WalletCore.registerObserver(this)
        dataUpdated()

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        if (mode == Mode.HOME) {
            view.background = null
        } else {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
        }
        rvAdapter.reloadData()
    }

    var prevSize = -1
    private fun dataUpdated() {
        Executors.newSingleThreadExecutor().execute {
            val allWalletTokens =
                AccountStore.assetsAndActivityData.getAllTokens(addVirtualStakingTokens = true)
            val filteredWalletTokens = allWalletTokens.filter {
                val token = TokenStore.getToken(it.token)
                it.isVirtualStakingRow || token?.isHidden() != true
            }
            Handler(Looper.getMainLooper()).post {
                walletTokens = if (mode == Mode.HOME) filteredWalletTokens.take(5)
                    .toTypedArray() else filteredWalletTokens.toTypedArray()
                thereAreMoreToShow = filteredWalletTokens.size > 5
                showAllView.visibility = if (thereAreMoreToShow) View.VISIBLE else View.GONE
                if (walletTokens.size != prevSize) {
                    prevSize = walletTokens.size
                    onHeightChanged?.invoke()
                }
                rvAdapter.reloadData()
            }
        }
    }

    val calculatedHeight: Int
        get() {
            return (64 * walletTokens.size).dp + (if (thereAreMoreToShow) 56 else 0).dp
        }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BalanceChanged,
            WalletEvent.TokensChanged,
            WalletEvent.AssetsAndActivityDataUpdated,
            is WalletEvent.AccountChanged,
            WalletEvent.StakingDataUpdated,
            WalletEvent.BaseCurrencyChanged -> {
                dataUpdated()
            }

            else -> {}
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return walletTokens.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return TOKEN_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        when (cellType) {
            TOKEN_CELL -> {
                val cell = TokenCell(context, mode)
                cell.onTap = { tokenBalance ->
                    val token = TokenStore.getToken(tokenBalance.token)
                    token?.let {
                        if (tokenBalance.isVirtualStakingRow) {
                            val navVC = WNavigationController(window!!)
                            navVC.setRoot(EarnRootVC(context, tokenSlug = token.slug))
                            window?.present(navVC)
                            return@let
                        }
                        val tokenVC = TokenVC(context, it)
                        navigationController?.push(tokenVC)
                    }
                }
                return cell
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
        (cellHolder.cell as TokenCell).configure(
            walletTokens[indexPath.row],
            isLast = indexPath.row == walletTokens.size - 1
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.removeAllViews()
        showAllView.onTap = null
    }
}
