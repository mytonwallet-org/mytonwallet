package org.mytonwallet.app_air.uifutures.viewControllers.futuresWalletSelection

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsAccountCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

@SuppressLint("ViewConstructor")
class FuturesWalletSelectionVC(context: Context, private val onSelect: (MAccount) -> Unit) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {
    @Suppress("PropertyName")
    override val TAG = "FuturesWalletSelection"

    override val shouldDisplayBottomBar = true

    private val accounts = WalletCore.getAllAccounts()

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(HEADER_CELL, WALLET_CELL, ADD_WALLET_CELL)
    ).apply {
        setHasStableIds(true)
    }

    private val recyclerView by lazy {
        WRecyclerView(this).apply {
            adapter = rvAdapter
            layoutManager = LinearLayoutManager(context)
            clipToPadding = false
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    if (dy != 0) updateBlurViews(recyclerView)
                }
            })
        }
    }

    override fun setupViews() {
        super.setupViews()
        setNavTitle(LocaleController.getString("Choose Wallet"))
        setupNavBar(true)
        navigationBar?.addCloseButton { window?.dismissLastNav() }
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
        recyclerView.setPaddingRelative(
            systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            systemBarEndInset,
            navigationController?.getSystemBars()?.bottom ?: 0
        )
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = accounts.size + 2

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when (indexPath.row) {
            0 -> HEADER_CELL
            accounts.size + 1 -> ADD_WALLET_CELL
            else -> WALLET_CELL
        }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String =
        accounts.getOrNull(indexPath.row - 1)?.accountId
            ?: recyclerViewCellType(rv, indexPath).value.toString()

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            HEADER_CELL -> HeaderCell(context)
            WALLET_CELL -> SettingsAccountCell(context)
            else -> SettingsItemCell(context)
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (val cell = cellHolder.cell) {
            is HeaderCell -> cell.configure(
                LocaleController.getString("Choose Wallet"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )

            is SettingsAccountCell -> {
                val account = accounts[indexPath.row - 1]
                cell.configure(
                    item = SettingsItem(
                        identifier = SettingsItem.Identifier.ACCOUNT,
                        title = account.name,
                        account = account,
                        hasTintColor = false
                    ),
                    subtitle = null,
                    isFirst = false,
                    isLast = false,
                    isEnabled = PerpsStore.canTrade(account)
                ) {
                    window?.dismissLastNav { onSelect(account) }
                }
            }

            is SettingsItemCell -> cell.configure(
                item = SettingsItem(
                    identifier = SettingsItem.Identifier.ADD_ACCOUNT,
                    icon = IconsR.drawable.ic_add,
                    title = LocaleController.getString("Add Wallet"),
                    hasTintColor = true
                ),
                subtitle = null,
                isFirst = false,
                isLast = true,
                isEnabled = true,
                onTap = ::addWallet
            )
        }
    }

    private fun addWallet() {
        val window = window ?: return
        val addAccountVC = WalletContextManager.delegate?.get()
            ?.getAddAccountVC(MBlockchainNetwork.MAINNET) as? WViewController ?: return
        window.dismissLastNav {
            val nav = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.BottomSheet
                )
            )
            nav.setRoot(addAccountVC)
            window.present(nav)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        recyclerView.onDestroy()
        recyclerView.adapter = null
    }

    private companion object {
        val HEADER_CELL = WCell.Type(1)
        val WALLET_CELL = WCell.Type(2)
        val ADD_WALLET_CELL = WCell.Type(3)
    }
}
