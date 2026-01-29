package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationOnScreen
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers.Companion.presentMenu
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Positioning
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import java.lang.ref.WeakReference

class WAutoCompleteAddressView(
    context: Context
) : WView(context), WRecyclerViewAdapter.WRecyclerViewDataSource,
    WThemedView {

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val ACCOUNT_CELL = WCell.Type(2)
    }

    var onSelected: ((account: MAccount?, savedAddress: MSavedAddress?) -> Unit)? = null
    var viewController: WeakReference<WViewController>? = null

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(HEADER_CELL, ACCOUNT_CELL)
    )
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    var autoCompleteConfig: AddressInputLayout.AutoCompleteConfig? = null

    private val recyclerView: WRecyclerView by lazy {
        WRecyclerView(context).apply {
            adapter = rvAdapter
            layoutManager = LinearLayoutManager(
                context, LinearLayoutManager.VERTICAL, false
            ).apply {
                isSmoothScrollbarEnabled = true
            }
            overScrollMode = OVER_SCROLL_NEVER
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(recyclerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints {
            allEdges(recyclerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        rvAdapter.reloadData()
    }

    fun search(query: String, autoselect: Boolean = false) {
        if (isEnabled) {
            updateSuggestions(query, autoselect)
        }
    }


    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        cancelSearch()
    }

    private fun cancelSearch() {
        coroutineScope.coroutineContext.cancelChildren()
    }

    private fun updateSuggestions(keyword: String, autoSelect: Boolean = false) {
        cancelSearch()

        coroutineScope.launch {
            val network = AccountStore.activeAccount?.network ?: return@launch
            val accounts: List<MAccount> = if (autoCompleteConfig?.accountAddresses == true) {
                withContext(Dispatchers.IO) {
                    WalletCore.getAllAccounts().filter { account ->
                        account.name.contains(keyword, ignoreCase = true) ||
                            account.byChain.values.any {
                                it.address.contains(keyword, ignoreCase = true) ||
                                    it.domain?.contains(keyword, ignoreCase = true) == true
                            }
                    }.sortedBy { it.name }
                }
            } else {
                emptyList()
            }
            val savedAddresses: List<MSavedAddress> = withContext(Dispatchers.IO) {
                (AddressStore.addressData?.savedAddresses ?: emptyList()).filter { savedAddress ->
                    savedAddress.address.contains(keyword, true) ||
                        savedAddress.name.contains(keyword, true)

                }.sortedBy { it.name }
            }

            sections[0].children = buildSavedAddressItems(keyword, network, savedAddresses)
            sections[1].children = buildAccountItems(keyword, network, accounts)

            rvAdapter.reloadData()

            if (!autoSelect) {
                return@launch
            }
            if (savedAddresses.size == 1) {
                val candidate = savedAddresses.first()
                if (keyword.equals(candidate.address, true) ||
                    keyword.equals(candidate.name, true)
                ) {
                    onSelected?.invoke(null, candidate)
                    return@launch
                }
            }
            if (accounts.size == 1) {
                val candidate = accounts.first()
                if (candidate.byChain.values.any {
                        keyword.equals(it.address, true) ||
                            keyword.equals(it.domain, true)
                    } || keyword.equals(candidate.name, true)
                ) {
                    onSelected?.invoke(candidate, null)
                    return@launch
                }
            }
            if (savedAddresses.size + accounts.size == 1) {
                onSelected?.invoke(accounts.firstOrNull(), savedAddresses.firstOrNull())
            }
        }
    }

    private fun buildSavedAddressItems(
        keyword: String,
        network: MBlockchainNetwork,
        addresses: List<MSavedAddress>
    ): List<AutoCompleteAddressItem> {
        val items = mutableListOf<AutoCompleteAddressItem>()
        addresses.forEach { address ->
            items.add(
                AutoCompleteAddressItem(
                    identifier = AutoCompleteAddressItem.Identifier.ACCOUNT,
                    title = address.name,
                    network = network,
                    savedAddress = address,
                    keyword = keyword
                )
            )
        }
        if (items.isNotEmpty()) {
            items.add(
                0, AutoCompleteAddressItem(
                    identifier = AutoCompleteAddressItem.Identifier.HEADER,
                    title = LocaleController.getString("Saved Wallets"),
                    network = network
                )
            )
        }
        return items
    }

    private fun buildAccountItems(
        keyword: String,
        network: MBlockchainNetwork,
        accounts: List<MAccount>
    ): List<AutoCompleteAddressItem> {
        val items = mutableListOf<AutoCompleteAddressItem>()
        for (account in accounts) {
            if (account.accountId == AccountStore.activeAccountId) continue

            val balanceAmount = BalanceStore.totalBalanceInBaseCurrency(account.accountId)
            val balance = balanceAmount?.toString(
                WalletCore.baseCurrency.decimalsCount,
                WalletCore.baseCurrency.sign,
                WalletCore.baseCurrency.decimalsCount,
                true
            )

            items.add(
                AutoCompleteAddressItem(
                    identifier = AutoCompleteAddressItem.Identifier.ACCOUNT,
                    title = account.name,
                    network = network,
                    account = account,
                    value = balance,
                    keyword = keyword
                )
            )
        }
        if (items.isNotEmpty()) {
            items.add(
                0, AutoCompleteAddressItem(
                    identifier = AutoCompleteAddressItem.Identifier.HEADER,
                    title = LocaleController.getString("My Wallets"),
                    network = network
                )
            )
        }

        return items
    }

    val sections = listOf(
        AutoCompleteAddressSection(
            section = AutoCompleteAddressSection.Section.SAVED,
            children = emptyList()
        ),
        AutoCompleteAddressSection(
            section = AutoCompleteAddressSection.Section.ADDED,
            children = emptyList()
        )
    )

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return sections.size
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return sections[section].children.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return if (indexPath.row == 0) {
            HEADER_CELL
        } else {
            ACCOUNT_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> WAutoCompleteAddressHeaderCell(context)
            ACCOUNT_CELL -> WAutoCompleteAddressCell(context)
            else -> throw Error()
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val cell = cellHolder.cell as IAutoCompleteAddressItemCell
        val children = sections[indexPath.section].children
        val item = children[indexPath.row]
        val onLongClick = if (indexPath.section == 0 && indexPath.row > 0) {
            {
                val contentView = (cellHolder.cell as? WAutoCompleteAddressCell)?.contentView
                if (contentView != null && item.savedAddress != null) {
                    onAddressClicked(
                        contentView,
                        item.network,
                        item.savedAddress
                    )
                }
            }
        } else {
            null
        }
        cell.configure(
            item,
            indexPath.row == children.size - 1,
            onTap = {
                onSelected?.invoke(item.account, item.savedAddress)
            },
            onLongClick = onLongClick
        )
    }

    private fun onAddressClicked(
        view: View,
        network: MBlockchainNetwork,
        savedAddress: MSavedAddress
    ) {
        val viewControllerRef = this.viewController ?: return
        val viewController = viewControllerRef.get() ?: return

        val blockchain = MBlockchain.valueOfOrNull(savedAddress.chain) ?: return
        val addressText = savedAddress.name
        val windowBackgroundStyle =
            WMenuPopup.BackgroundStyle.Cutout(view.frameAsPath(ViewConstants.BIG_RADIUS.dp))

        val keyboardHeight = viewController.window?.imeInsets?.bottom ?: 0
        val windowHeight = viewController.navigationController?.height ?: 0
        val availableHeight = windowHeight - keyboardHeight
        val viewLocation = view.getLocationOnScreen()
        val positioning =
            if (keyboardHeight > 0 && viewLocation.y - view.height / 2 > availableHeight / 2) {
                Positioning.ABOVE
            } else {
                Positioning.BELOW
            }

        presentMenu(
            viewControllerRef,
            view,
            addressText,
            blockchain,
            network,
            savedAddress.address,
            xOffset = 0,
            yOffset = 0,
            positioning = positioning,
            centerHorizontally = true,
            showTemporaryViewOption = true,
            windowBackgroundStyle = windowBackgroundStyle
        )
    }
}
