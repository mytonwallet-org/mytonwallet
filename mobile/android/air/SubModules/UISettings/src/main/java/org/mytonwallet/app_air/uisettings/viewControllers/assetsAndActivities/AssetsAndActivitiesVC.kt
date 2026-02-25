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
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference

class AssetsAndActivitiesVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, WalletCore.EventObserver {
    override val TAG = "AssetsAndActivities"

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val TOKEN_CELL = WCell.Type(2)
    }

    private data class TokenRow(
        val token: MToken,
        val balance: MTokenBalance
    ) : WEquatable<MTokenBalance> {

        override fun isSame(comparing: WEquatable<*>): Boolean {
            return comparing is TokenRow
                && balance.virtualStakingToken != null
                && balance.virtualStakingToken == comparing.balance.virtualStakingToken
        }

        override fun isChanged(comparing: WEquatable<*>): Boolean {
            return true
        }

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
    private var allTokens = emptyList<TokenRow>()
        set(value) {
            field = value
            val data = AccountStore.assetsAndActivityData
            oldHiddenTokens = value.map { row ->
                isTokenHidden(row, data)
            } as ArrayList<Boolean>
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
        allTokens = AccountStore.assetsAndActivityData
            .getAllTokens(addVirtualStakingTokens = true)
            .mapNotNull { balance ->
                val slug = balance.token ?: return@mapNotNull null
                val token = TokenStore.getToken(slug) ?: return@mapNotNull null
                TokenRow(token, balance)
            }
    }

    private fun checkAndUpdateHeader(prevTokens: List<TokenRow>) {
        val hadTokens = prevTokens.isNotEmpty()
        val hasTokens = allTokens.isNotEmpty()
        if (hadTokens != hasTokens) {
            rvAdapter.notifyItemChanged(0)
        }
    }

    private fun isTokenHidden(
        row: TokenRow,
        data: MAssetsAndActivityData
    ): Boolean {
        return if (row.balance.isVirtualStakingRow) {
            row.balance.virtualStakingToken?.let { data.hiddenTokens.contains(it) } == true
        } else {
            row.token.isHidden(AccountStore.activeAccount, data)
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
                    hasTokens = allTokens.isNotEmpty(),
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
                            val data = AccountStore.assetsAndActivityData
                            this@AssetsAndActivitiesVC.oldHiddenTokens =
                                allTokens.map { row ->
                                    isTokenHidden(row, data)
                                } as ArrayList<Boolean>
                            allTokens.forEachIndexed { index, row ->
                                val isHidden = isTokenHidden(row, data)
                                if (isHidden != oldHiddenTokens[index])
                                    indexes.add(index)
                            }
                            withContext(Dispatchers.Main) {
                                val aboveItemsCount = recyclerViewNumberOfItems(recyclerView, 0)
                                indexes.forEach {
                                    rvAdapter.notifyItemChanged(aboveItemsCount + it)
                                }
                            }
                        }
                    }
                )
            }

            1 -> {
                val row = allTokens[indexPath.row]
                val slug = row.balance.token ?: return
                val virtualStakingSlug = row.balance.virtualStakingToken ?: return
                val cell = cellHolder.cell as AssetsAndActivitiesTokenCell
                val assetsAndActivityData = AccountStore.assetsAndActivityData

                val isSwipeEnabled =
                    assetsAndActivityData.isTokenRemovable(slug, row.balance.isVirtualStakingRow)
                val isHidden = isTokenHidden(row, assetsAndActivityData)
                val isPinned = assetsAndActivityData.pinnedTokens.contains(virtualStakingSlug)

                if (isSwipeEnabled) {
                    viewBinderHelper.bind(
                        cell.swipeRevealLayout,
                        virtualStakingSlug
                    )
                }

                cell.configure(
                    row.token,
                    row.balance,
                    indexPath.row == allTokens.size - 1,
                    isHidden = isHidden,
                    isPinned = isPinned,
                    isSwipeEnabled = isSwipeEnabled,
                    onDeleteToken = if (isSwipeEnabled) {
                        {
                            val assetsAndActivityData = AccountStore.assetsAndActivityData
                            assetsAndActivityData.deleteToken(virtualStakingSlug)
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
                            checkAndUpdateHeader(prevAllTokens)
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
                checkAndUpdateHeader(prevAllTokens)
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
                return allTokens[indexPath.row].balance.virtualStakingToken
            }
        }
        return super.recyclerViewCellItemId(rv, indexPath)
    }

}
