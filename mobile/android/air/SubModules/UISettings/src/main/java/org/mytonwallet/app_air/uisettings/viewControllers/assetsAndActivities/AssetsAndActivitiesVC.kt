package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells.AssetsAndActivitiesHeaderCell
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells.AssetsAndActivitiesTokenCell
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.EquatableChange
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import java.util.concurrent.Executors

class AssetsAndActivitiesVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, WalletCore.EventObserver {

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val TOKEN_CELL = WCell.Type(2)
    }

    override val shouldDisplayBottomBar = true

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(HEADER_CELL, TOKEN_CELL))

    private var oldHiddenTokens = ArrayList<Boolean>()
    private var allTokens = emptyArray<MToken>()
        set(value) {
            field = value
            oldHiddenTokens = value.map { it.isHidden() } as ArrayList<Boolean>
        }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.addItemDecoration(
            LastItemPaddingDecoration(
                navigationController?.getSystemBars()?.bottom ?: 0
            )
        )
        rv.setItemAnimator(null)
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0)
                    return
                updateBlurViews(recyclerView)
            }

            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE)
                    updateBlurViews(recyclerView)
            }
        })
        rv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Assets & Activity"))
        setupNavBar(true)
        if (navigationController?.viewControllers?.size == 1) {
            navigationBar?.addCloseButton()
        }

        reloadTokens()

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        recyclerView.clipToPadding = false
        view.setConstraints {
            toTop(recyclerView)
            toCenterX(recyclerView)
            toBottom(recyclerView)
        }

        WalletCore.registerObserver(this)

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun reloadTokens() {
        allTokens = AccountStore.assetsAndActivityData.getAllTokens().mapNotNull { tokenBalance ->
            TokenStore.getToken(tokenBalance.token)
        }.toTypedArray()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 2
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> 1
            else -> {
                allTokens.size
            }
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            0 -> HEADER_CELL
            else -> TOKEN_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                AssetsAndActivitiesHeaderCell(navigationController!!, recyclerView)
            }

            else -> {
                AssetsAndActivitiesTokenCell(recyclerView)
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (indexPath.section) {
            0 -> {
                (cellHolder.cell as AssetsAndActivitiesHeaderCell).configure(
                    onHideNoCostTokensChanged = { isHidden ->
                        WGlobalStorage.setAreNoCostTokensHidden(isHidden)
                        val data = AccountStore.assetsAndActivityData
                        val oldHiddenTokens = oldHiddenTokens
                        data.hiddenTokens.clear()
                        data.visibleTokens.clear()
                        AccountStore.updateAssetsAndActivityData(data, notify = true)
                        val indexPaths = ArrayList<IndexPath>()
                        Executors.newSingleThreadExecutor().execute {
                            this.oldHiddenTokens =
                                allTokens.map { it.isHidden() } as ArrayList<Boolean>
                            allTokens.forEachIndexed { index, mToken ->
                                if (mToken.isHidden() != oldHiddenTokens[index])
                                    indexPaths.add(IndexPath(1, index))
                            }
                            Handler(Looper.getMainLooper()).post {
                                rvAdapter.applyChanges(indexPaths.map { EquatableChange.Update(it) })
                            }
                        }
                    })
            }

            1 -> {
                val token = allTokens[indexPath.row]
                (cellHolder.cell as AssetsAndActivitiesTokenCell).configure(
                    token,
                    (BalanceStore.getBalances(AccountStore.activeAccountId!!)?.get(token.slug)
                        ?: BigInteger.valueOf(0)),
                    indexPath.row == allTokens.size - 1
                )
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BaseCurrencyChanged -> {
                rvAdapter.reloadData()
            }

            WalletEvent.BalanceChanged,
            WalletEvent.TokensChanged -> {
                reloadTokens()
                rvAdapter.reloadData()
            }

            WalletEvent.AssetsAndActivityDataUpdated -> {
                val allTokensCount = allTokens.size
                reloadTokens()
                if (allTokensCount != allTokens.size)
                    rvAdapter.reloadData()
            }

            else -> {}
        }
    }

}
