package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities

import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.helpers.swipeRevealLayout.ViewBinderHelper
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells.AssetsAndActivitiesHeaderCell
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells.AssetsAndActivitiesTokenCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger

class AssetsAndActivitiesVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, WalletCore.EventObserver {
    override val TAG = "AssetsAndActivities"

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val TOKEN_CELL = WCell.Type(2)
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override val shouldDisplayBottomBar = true

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(HEADER_CELL, TOKEN_CELL)).apply {
            setHasStableIds(true)
        }

    private val viewBinderHelper = ViewBinderHelper().apply {
        setOpenOnlyOne(true)
    }

    private var oldHiddenTokens = ArrayList<Boolean>()
    private var allTokens = emptyList<MToken>()
        set(value) {
            field = value
            oldHiddenTokens = value.map { it.isHidden() } as ArrayList<Boolean>
        }

    private val recyclerView: WRecyclerView by lazy {
        WRecyclerView(this).apply {
            adapter = rvAdapter
            val layoutManager = LinearLayoutManagerAccurateOffset(context)
            layoutManager.isSmoothScrollbarEnabled = true
            setLayoutManager(layoutManager)
            addItemDecoration(
                LastItemPaddingDecoration(
                    navigationController?.getSystemBars()?.bottom ?: 0
                )
            )
            setItemAnimator(null)
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    super.onScrolled(recyclerView, dx, dy)
                    if (dx == 0 && dy == 0)
                        return
                    updateBlurViews(recyclerView)
                }

                override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                    super.onScrollStateChanged(recyclerView, newState)
                    if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                        updateBlurViews(recyclerView)
                        closeAllSwipedCells()
                    }
                }
            })
        }
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

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    private fun reloadTokens() {
        allTokens = AccountStore.assetsAndActivityData.getAllTokens().mapNotNull { tokenBalance ->
            TokenStore.getToken(tokenBalance.token)
        }
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
                        AccountStore.updateAssetsAndActivityData(
                            data,
                            notify = true,
                            saveToStorage = true
                        )
                        val indexes = ArrayList<Int>()
                        scope.launch {
                            this@AssetsAndActivitiesVC.oldHiddenTokens =
                                allTokens.map { it.isHidden() } as ArrayList<Boolean>
                            allTokens.forEachIndexed { index, mToken ->
                                if (mToken.isHidden() != oldHiddenTokens[index])
                                    indexes.add(index)
                            }
                            withContext(Dispatchers.Main) {
                                val aboveItemsCount = recyclerViewNumberOfItems(recyclerView, 0)
                                indexes.forEach {
                                    rvAdapter.notifyItemChanged(aboveItemsCount + it)
                                }
                            }
                        }
                    })
            }

            1 -> {
                val token = allTokens[indexPath.row]
                val cell = cellHolder.cell as AssetsAndActivitiesTokenCell
                val assetsAndActivityData = AccountStore.assetsAndActivityData

                val isSwipeEnabled = assetsAndActivityData.isTokenRemovable(token.slug)

                if (isSwipeEnabled) {
                    viewBinderHelper.bind(
                        cell.swipeRevealLayout,
                        token.slug
                    )
                }

                cell.configure(
                    token,
                    (BalanceStore.getBalances(AccountStore.activeAccountId!!)?.get(token.slug)
                        ?: BigInteger.valueOf(0)),
                    indexPath.row == allTokens.size - 1,
                    isSwipeEnabled = isSwipeEnabled,
                    onDeleteToken = if (isSwipeEnabled) {
                        {
                            val assetsAndActivityData = AccountStore.assetsAndActivityData
                            assetsAndActivityData.visibleTokens.removeAll { hiddenSlug ->
                                hiddenSlug == token.slug
                            }
                            assetsAndActivityData.addedTokens.removeAll { hiddenSlug ->
                                hiddenSlug == token.slug
                            }
                            AccountStore.updateAssetsAndActivityData(
                                assetsAndActivityData,
                                notify = true,
                                saveToStorage = true
                            )

                            cell.closeSwipe()
                            val prevAllTokens = allTokens
                            reloadTokens()
                            rvAdapter.applyChanges(
                                prevAllTokens,
                                allTokens,
                                1,
                                false
                            )
                        }
                    } else null
                )
            }
        }
    }

    private fun closeAllSwipedCells() {
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i)
            val viewHolder = recyclerView.getChildViewHolder(child)
            if (viewHolder != null) {
                val cell = (viewHolder as? WCell.Holder)?.cell
                if (cell is AssetsAndActivitiesTokenCell) {
                    cell.closeSwipe()
                }
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
                val prevAllTokens = allTokens
                reloadTokens()
                rvAdapter.applyChanges(
                    prevAllTokens,
                    allTokens,
                    1,
                    true
                )
            }

            else -> {}
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        when (indexPath.section) {
            0 -> {
                return ""
            }

            1 -> {
                return allTokens[indexPath.row].slug
            }
        }
        return super.recyclerViewCellItemId(rv, indexPath)
    }

}
