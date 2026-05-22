package org.mytonwallet.app_air.ledger.screens.ledgerWallets

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isGone
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.ledger.LedgerManager
import org.mytonwallet.app_air.ledger.screens.ledgerWallets.cells.LedgerLoadMoreCell
import org.mytonwallet.app_air.ledger.screens.ledgerWallets.cells.LedgerWalletCell
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.GradientShaderDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.helpers.ToastHelper
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ledger.MLedgerWalletInfo
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference

class LedgerWalletsVC(
    context: Context,
    private val network: MBlockchainNetwork,
    discoveredWallets: List<MLedgerWalletInfo>
) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, LedgerWalletsVM.Delegate {
    override val TAG = "LedgerWallets"

    override val shouldDisplayBottomBar = !WGlobalStorage.isGradientNavigationBarActive()

    data class Item(
        val title: String?,
        val wallet: MLedgerWalletInfo,
        var isSelected: Boolean,
        val isAlreadyImported: Boolean
    )

    var items = mutableListOf<Item>()
    private var animatedBatchStart = Int.MAX_VALUE
    private var isLoadingMore = false
    private val ledgerWalletsVM by lazy {
        LedgerWalletsVM(this)
    }

    private val prevAccountsCount = WGlobalStorage.accountIds().size

    val accounts = WGlobalStorage.accountIds().mapNotNull { accountId ->
        val account = AccountStore.accountById(accountId)
        if (account?.accountType != MAccount.AccountType.VIEW)
            return@mapNotNull account
        else
            return@mapNotNull null
    }

    companion object {
        val WALLET_CELL = WCell.Type(1)
        val LOAD_MORE_CELL = WCell.Type(2)
    }

    val newlySelectedItems: List<Item>
        get() {
            return items.filter { it.isSelected && !it.isAlreadyImported }
        }

    private val continueButton by lazy {
        WButton(context).apply {
            id = View.generateViewId()
        }.apply {
            isEnabled = false
            text = LocaleController.getString("Continue")
            setOnClickListener {
                lockView()
                this@apply.isLoading = true
                this@apply.isEnabled = true
                ledgerWalletsVM.finalizeImport(network, newlySelectedItems.map { it.wallet })
            }
        }
    }

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(WALLET_CELL, LOAD_MORE_CELL))

    init {
        loaded(discoveredWallets)
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
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

    private val bottomGradientView = View(context).apply {
        id = View.generateViewId()
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Select Ledger Wallets"))
        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomGradientView,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            20.dp +
                continueButton.buttonHeight +
                20.dp +
                (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        recyclerView.clipToPadding = false
        view.setConstraints {
            toTop(recyclerView)
            toCenterX(recyclerView)
            toBottom(recyclerView)
            toCenterX(continueButton, 20f)
            toBottomPx(
                continueButton, 20.dp +
                    (navigationController?.getSystemBars()?.bottom ?: 0)
            )
            toStart(bottomGradientView)
            toEnd(bottomGradientView)
            toBottom(bottomGradientView)
            topToTop(
                bottomGradientView,
                continueButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
        }

        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            20.dp +
                continueButton.buttonHeight +
                20.dp +
                (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        view.setConstraints {
            toBottomPx(
                continueButton, 20.dp +
                    (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        if (WGlobalStorage.isGradientNavigationBarActive()) {
            bottomGradientView.isGone = false
            val bgColor = WColor.SecondaryBackground.color
            val bgColor80 = bgColor.colorWithAlpha(204)
            val bgColor90 = bgColor.colorWithAlpha(230)
            bottomGradientView.background = GradientShaderDrawable(
                intArrayOf(bgColor90 and 0x00FFFFFF, bgColor80, bgColor90),
                floatArrayOf(0f, 0.1f, 1f)
            )
        } else {
            bottomGradientView.isGone = true
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        LedgerManager.stopConnection()
    }

    override fun finalizedWallets(importedAccountsCount: Int) {
        if (prevAccountsCount == 0) {
            push(
                WalletContextManager.delegate?.getWalletAddedVC(
                    false,
                    importedAccountsCount
                ) as WViewController
            ) {
                navigationController?.removePrevViewControllers()
            }
        } else {
            WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
            if (importedAccountsCount == 1) {
                ToastHelper.notifyWalletImported(
                    viewController = this,
                    account = AccountStore.activeAccount
                )
            }
            window!!.dismissLastNav()
        }
    }

    override fun loaded(wallets: List<MLedgerWalletInfo>) {
        animatedBatchStart = if (isLoadingMore) items.size else Int.MAX_VALUE
        items.addAll(wallets.map { discoveredWallet ->
            val title = accounts.find { it.tonAddress == discoveredWallet.wallet.address }?.name
            return@map Item(
                title = title,
                wallet = discoveredWallet,
                isSelected = title != null,
                isAlreadyImported = title != null
            )
        })
        isLoadingMore = false
        rvAdapter.reloadData()
    }

    override fun finalizeFailed() {
        showError(MBridgeError.UNKNOWN)
        continueButton.isLoading = false
        continueButton.isEnabled = newlySelectedItems.isNotEmpty()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 2
    }

    override fun recyclerViewNumberOfItems(
        rv: RecyclerView,
        section: Int
    ): Int {
        if (section == 1)
            return 1
        return items.size
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return when (indexPath.section) {
            0 -> WALLET_CELL
            else -> LOAD_MORE_CELL
        }
    }

    override fun recyclerViewCellView(
        rv: RecyclerView,
        cellType: WCell.Type
    ): WCell {
        return when (cellType) {
            WALLET_CELL -> {
                LedgerWalletCell(context).apply {
                    onTap = { item ->
                        item.isSelected = !item.isSelected
                        selectionsUpdated()
                    }
                }
            }

            else -> {
                LedgerLoadMoreCell(context).apply {
                    onTap = {
                        if (!isLoadingMore) {
                            isLoadingMore = true
                            ledgerWalletsVM.loadMore(network, items.size)
                        }
                    }
                }
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        if (indexPath.section == 0) {
            val item = items[indexPath.row]
            val isAdded = indexPath.row >= animatedBatchStart
            (cellHolder.cell as LedgerWalletCell).configure(
                item,
                isAdded = isAdded,
                animationDelay = if (isAdded) 40L * (indexPath.row - animatedBatchStart) else 0L
            )
        } else {
            (cellHolder.cell as LedgerLoadMoreCell).configure(isLoading = isLoadingMore)
        }
    }

    private fun selectionsUpdated() {
        val newlySelectedItems = newlySelectedItems
        navigationBar?.setSubtitle(
            if (newlySelectedItems.isNotEmpty())
                LocaleController.getPlural(
                    newlySelectedItems.size,
                    "\$n_wallets_selected"
                )
            else null, false
        )
        continueButton.isEnabled = newlySelectedItems.isNotEmpty()
    }
}
