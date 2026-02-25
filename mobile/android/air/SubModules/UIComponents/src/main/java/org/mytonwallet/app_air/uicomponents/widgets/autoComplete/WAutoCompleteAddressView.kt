package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.view.children
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
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
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
    ).apply {
        setHasStableIds(true)
    }

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
            itemAnimator = null
        }
    }

    private var lastKeyword: String = ""

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
            pendingSections = null

            val network = AccountStore.activeAccount?.network ?: return@launch
            val accounts: List<MAccount> = if (autoCompleteConfig?.accountAddresses == true) {
                withContext(Dispatchers.IO) {
                    WalletCore.getAllAccounts()
                        .filter { it.accountId != AccountStore.activeAccountId }
                        .filter { account ->
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

            val newSections = createSections(
                buildSavedAddressItems(keyword, network, savedAddresses),
                buildAccountItems(keyword, network, accounts)
            )

            sections = checkAndPrepareForDisappearAnimation(keyword, newSections)
            lastKeyword = keyword

            rvAdapter.reloadData()

            if (autoSelect) {
                autoSelectIfOnlyOne(keyword, savedAddresses, accounts)
            }
        }
    }

    private fun checkAndPrepareForDisappearAnimation(
        keyword: String,
        newSections: List<AutoCompleteAddressSection>
    ): List<AutoCompleteAddressSection> {
        if (!WGlobalStorage.getAreAnimationsActive()) {
            return newSections
        }
        val savedAddressItems = newSections[0].children
        val accountItems = newSections[1].children
        val prevSavedAddressItems = sections[0].children
        // If keyword the same but saved addresses count is changed -> user remove them
        if (keyword != lastKeyword || prevSavedAddressItems.isEmpty() || prevSavedAddressItems.size == savedAddressItems.size) {
            return newSections
        }

        // mark no more exists as DISAPPEARING to animate them
        val newIds = savedAddressItems.map { it.listId }.toSet()
        val animatedSavedAddressItems = prevSavedAddressItems.map {
            it.copy(
                animationState = if (!newIds.contains(it.listId)) {
                    AutoCompleteAddressItem.AnimationState.DISAPPEARING
                } else {
                    AutoCompleteAddressItem.AnimationState.IDLE
                }
            )
        }.toMutableList()
        // if we remove last element -> we need to animate rounding
        if (animatedSavedAddressItems.last().animationState == AutoCompleteAddressItem.AnimationState.DISAPPEARING) {
            val lastIdleIndex =
                animatedSavedAddressItems.indexOfLast { it.animationState == AutoCompleteAddressItem.AnimationState.IDLE }
            if (lastIdleIndex != -1) {
                animatedSavedAddressItems[lastIdleIndex] =
                    animatedSavedAddressItems[lastIdleIndex].copy(animationState = AutoCompleteAddressItem.AnimationState.CORNER_ROUNDING)
            }
        }
        // before commit actual data, need to wait remove animation is finished
        pendingSections = newSections
        return createSections(animatedSavedAddressItems, accountItems)
    }

    private fun autoSelectIfOnlyOne(
        keyword: String,
        savedAddresses: List<MSavedAddress>,
        accounts: List<MAccount>
    ) {
        if (savedAddresses.size == 1) {
            val candidate = savedAddresses.first()
            if (keyword.equals(candidate.address, true) ||
                keyword.equals(candidate.name, true)
            ) {
                onSelected?.invoke(null, candidate)
                return
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
                return
            }
        }
        if (savedAddresses.size + accounts.size == 1) {
            onSelected?.invoke(accounts.firstOrNull(), savedAddresses.firstOrNull())
        }
    }

    private fun buildSavedAddressItems(
        keyword: String,
        network: MBlockchainNetwork,
        addresses: List<MSavedAddress>
    ): List<AutoCompleteAddressItem> {
        val items = mutableListOf<AutoCompleteAddressItem>()
        addresses.forEachIndexed { index, address ->
            items.add(
                AutoCompleteAddressItem(
                    listId = address.address,
                    title = address.name,
                    network = network,
                    savedAddress = address,
                    keyword = keyword,
                    isFirst = index == 0,
                    isLast = index == addresses.size - 1
                )
            )
        }
        if (items.isNotEmpty()) {
            items.add(
                0, AutoCompleteAddressItem(
                    listId = "savedAddressesHeader",
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
        accounts.forEachIndexed { index, account ->
            val balanceAmount = BalanceStore.totalBalanceInBaseCurrency(account.accountId)
            val balance = balanceAmount?.toString(
                WalletCore.baseCurrency.decimalsCount,
                WalletCore.baseCurrency.sign,
                WalletCore.baseCurrency.decimalsCount,
                true
            )

            items.add(
                AutoCompleteAddressItem(
                    listId = account.accountId,
                    title = account.name,
                    network = network,
                    account = account,
                    value = balance,
                    keyword = keyword,
                    isFirst = index == 0,
                    isLast = index == accounts.size - 1
                )
            )
        }
        if (items.isNotEmpty()) {
            items.add(
                0, AutoCompleteAddressItem(
                    listId = "walletsHeader",
                    title = LocaleController.getString("My Wallets"),
                    network = network
                )
            )
        }

        return items
    }

    private var sections: List<AutoCompleteAddressSection> =
        createSections(emptyList(), emptyList())
    private var pendingSections: List<AutoCompleteAddressSection>? = null

    private fun createSections(
        savedItems: List<AutoCompleteAddressItem>,
        addedItems: List<AutoCompleteAddressItem>
    ): List<AutoCompleteAddressSection> = listOf(
        AutoCompleteAddressSection(
            section = AutoCompleteAddressSection.Section.SAVED,
            children = savedItems
        ),
        AutoCompleteAddressSection(
            section = AutoCompleteAddressSection.Section.ADDED,
            children = addedItems
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
            onTap = {
                onSelected?.invoke(item.account, item.savedAddress)
            },
            changeAnimationFinishListener = ::onChangeAnimationFinis,
            onLongClick = onLongClick
        )
    }

    private fun onChangeAnimationFinis() {
        val pendingSections = this.pendingSections ?: return
        if (!hasActiveAnimation()) {
            sections = pendingSections
            this.pendingSections = null
            rvAdapter.reloadData()
            return
        }
    }

    private fun hasActiveAnimation(): Boolean {
        return recyclerView.children
            .map { recyclerView.getChildViewHolder(it) }
            .filterIsInstance(WCell.Holder::class.java)
            .map { it.cell }
            .filterIsInstance(IAutoCompleteAddressItemCell::class.java)
            .any { it.hasActiveAnimation() }
    }

    override fun recyclerViewCellItemId(
        rv: RecyclerView,
        indexPath: IndexPath
    ): String {
        return sections[indexPath.section].children[indexPath.row].listId
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
            WMenuPopup.BackgroundStyle.Cutout(view.frameAsPath(ViewConstants.BLOCK_RADIUS.dp))

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
