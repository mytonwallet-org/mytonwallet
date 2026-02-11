package org.mytonwallet.app_air.uitonconnect.viewControllers.connect

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
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsAccountCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class WalletSelectionVC(
    context: Context,
    private val dappHost: String
) : WViewController(context), WThemedView, WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "WalletSelection"

    override val shouldDisplayBottomBar = true

    companion object {
        val WALLET_CELL = WCell.Type(1)
        val HEADER_CELL = WCell.Type(2)

        const val TOTAL_SECTIONS = 1
    }

    private var accounts: List<MAccount> = emptyList()

    private var onWalletSelectListener: ((MAccount) -> Unit)? = null

    override val isSwipeBackAllowed: Boolean = true

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(WALLET_CELL, HEADER_CELL)).apply {
            setHasStableIds(true)
        }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.layoutManager = layoutManager
        rv.clipToPadding = false
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
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

        loadAccounts()
        setNavTitle(LocaleController.getString("Choose Wallet"))
        setupNavBar(true)

        navigationBar?.addCloseButton {
            // Close button will dismiss the entire modal
            navigationController?.window?.dismissLastNav()
        }

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

        recyclerView.setPadding(
            0,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp,
            0,
            (navigationController?.getSystemBars()?.bottom ?: 0)
        )
    }

    fun setOnWalletSelectListener(listener: (MAccount) -> Unit) {
        onWalletSelectListener = listener
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int =
        if (accounts.isEmpty()) 0 else TOTAL_SECTIONS

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return if (accounts.isEmpty()) 0 else accounts.size + 1 // +1 for header
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return if (indexPath.row == 0) {
            HEADER_CELL
        } else {
            WALLET_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            WALLET_CELL -> {
                val cell = SettingsAccountCell(context)
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

        when (cell) {
            is SettingsAccountCell -> {
                val accountIndex = indexPath.row - 1 // -1 because row 0 is header
                if (accountIndex >= 0 && accountIndex < accounts.size) {
                    val account = accounts[accountIndex]
                    val isFirst = false // Never round the top because there's always a header above
                    val isLast = indexPath.row == accounts.size

                    cell.configure(
                        item = SettingsItem(
                            identifier = SettingsItem.Identifier.ACCOUNT,
                            title = account.name,
                            account = account,
                            hasTintColor = false,
                            icon = null,
                            value = null
                        ),
                        subtitle = null,
                        isFirst = isFirst,
                        isLast = isLast,
                        onTap = {
                            onWalletSelectListener?.invoke(account)
                            pop()
                        }
                    )
                }
            }

            is HeaderCell -> {
                val headerText = "${LocaleController.getString("Wallet to use on")} $dappHost"
                val isFirstHeader = rvAdapter.indexPathToPosition(indexPath) == 0
                val topRounding =
                    if (isFirstHeader) HeaderCell.TopRounding.FIRST_ITEM else HeaderCell.TopRounding.NORMAL

                cell.configure(
                    headerText,
                    titleColor = WColor.Tint,
                    topRounding = topRounding
                )
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return accounts.getOrNull(indexPath.row - 1)?.accountId
    }

    private fun loadAccounts() {
        accounts = WalletCore.getAllAccounts()
        rvAdapter.reloadData()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun onDestroy() {
        super.onDestroy()
        recyclerView.onDestroy()
        recyclerView.adapter = null
        recyclerView.removeAllViews()
    }
}
