package org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSendDetails

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListDecorator
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.WAddressActionView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers.Companion.presentMenu
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.Adapter
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.takeIfNotBlank
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
class TonConnectRequestSendDetailsVC(
    context: Context,
    private val items: List<BaseListItem>
) : WViewController(context), WalletCore.EventObserver {
    override val TAG = "TonConnectRequestSendDetails"

    private val rvAdapter = Adapter().apply {
        onAddressClick = { anchorView, view, item ->
            onAddressClicked(anchorView, view, item)
        }
    }

    override val shouldDisplayBottomBar = true

    private val recyclerView = RecyclerView(context).apply {
        id = View.generateViewId()
        adapter = rvAdapter
        addItemDecoration(CustomListDecorator())
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
    }

    override fun setupViews() {
        super.setupViews()
        WalletCore.registerObserver(this)

        setupNavBar(true)
        setNavTitle(LocaleController.getString("Transfer Info"), false)

        navigationBar?.addCloseButton()

        view.addView(recyclerView, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0))
        view.setConstraints {
            toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            topToBottom(recyclerView, navigationBar!!)
            toBottom(recyclerView)
        }

        rvAdapter.submitList(rebuildItems().toList())
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

        view.setConstraints({
            toBottomPx(recyclerView, max(ime, nav))
        })
    }

    override fun onDestroy() {
        WalletCore.unregisterObserver(this)
        super.onDestroy()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountSavedAddressesChanged,
            is WalletEvent.ByChainUpdated -> rvAdapter.submitList(rebuildItems().toList())

            else -> {}
        }
    }

    private fun rebuildItems(): List<BaseListItem> {
        return items.map { item ->
            when (item) {
                is TonConnectItem.Address -> item.copy(
                    addressName = resolveAddressName(item.address, item.chain)
                )

                else -> item
            }
        }
    }

    private fun resolveAddressName(address: String, chain: String): String? {
        val localName = AddressStore.getAddress(address, chain)
            ?.name?.trim()?.takeIfNotBlank()
        val domain = AddressStore.getDomain(address, chain)
            ?.trim()?.takeIfNotBlank()
        return localName ?: domain
    }

    private fun onAddressClicked(
        anchorView: View,
        view: WAddressActionView,
        item: TonConnectItem.Address
    ) {
        val account =
            AccountStore.accountById(item.accountId) ?: AccountStore.activeAccount ?: return
        val blockchain = MBlockchain.valueOfOrNull(item.chain) ?: return

        presentMenu(
            viewController = WeakReference(this),
            view = view,
            title = item.addressName,
            blockchain = blockchain,
            network = account.network,
            address = item.address,
            centerHorizontally = true,
            showTemporaryViewOption = true,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout(
                anchorView.frameAsPath(
                    roundRadius = ViewConstants.BLOCK_RADIUS.dp,
                    topOffset = 40.dp.toFloat()
                )
            )
        ) { displayProgress ->
            view.setAccentFadeProgress(displayProgress)
        }
    }
}
