package org.mytonwallet.app_air.uisettings.viewControllers.walletVersions

import android.content.Context
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
import org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.cells.WalletVersionCell
import org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.cells.WalletVersionsHeaderCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.api.importNewWalletVersion
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.utils.jsonObject
import java.lang.ref.WeakReference

class WalletVersionsVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, WalletCore.EventObserver {
    override val TAG = "WalletVersions"

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val VERSION_CELL = WCell.Type(2)
    }

    override val shouldDisplayBottomBar = true

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(HEADER_CELL, VERSION_CELL))

    val walletVersionsData = AccountStore.walletVersionsData

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

        setNavTitle(LocaleController.getString("Wallet Versions"))
        setupNavBar(true)
        if (navigationController?.viewControllers?.size == 1) {
            navigationBar?.addCloseButton()
        }

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

    private fun handleTap(identifier: String) {
        val selectedVersion = walletVersionsData?.versions?.firstOrNull {
            it.version == identifier
        } ?: return importVersion(identifier)

        // Check if wallet already imported
        for (accountId in WGlobalStorage.accountIds()) {
            val accountObj = WGlobalStorage.getAccount(accountId)
            if (accountObj != null) {
                val account = MAccount(accountId, accountObj)
                if (account.tonAddress == selectedVersion.address) {
                    WalletCore.activateAccount(accountId, notifySDK = true) { res, err ->
                        if (res != null && err == null) {
                            navigationController?.popToRoot()
                            WalletCore.notifyEvent(
                                WalletEvent.AccountChangedInApp(
                                    persistedAccountsModified = false
                                )
                            )
                        }
                    }
                    return
                }
            }
        }

        importVersion(identifier)
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 2
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> 1
            else -> {
                walletVersionsData?.versions?.size ?: 0
            }
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            0 -> HEADER_CELL
            else -> VERSION_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                WalletVersionsHeaderCell(context)
            }

            else -> {
                WalletVersionCell(context).apply {
                    onTap = { identifier ->
                        handleTap(identifier)
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
        when (indexPath.section) {
            1 -> {
                (cellHolder.cell as WalletVersionCell).configure(
                    walletVersionsData!!.versions[indexPath.row],
                    indexPath.row == (walletVersionsData.versions.size - 1)
                )
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            else -> {}
        }
    }

    private fun importVersion(version: String) {
        view.lockView()
        WalletCore.importNewWalletVersion(
            AccountStore.activeAccount!!,
            version
        ) { importedAccount, err ->
            if (err != null) {
                view.unlockView()
                showError(err)
                return@importNewWalletVersion
            }
            val importedAccountId = importedAccount?.accountId ?: run {
                view.unlockView()
                return@importNewWalletVersion
            }

            Logger.d(
                Logger.LogTag.ACCOUNT,
                LogMessage.Builder()
                    .append(
                        importedAccountId,
                        LogMessage.MessagePartPrivacy.PUBLIC
                    )
                    .append(
                        "WalletVersion Imported",
                        LogMessage.MessagePartPrivacy.PUBLIC
                    )
                    .append(
                        "Address: ${importedAccount.tonAddress}",
                        LogMessage.MessagePartPrivacy.REDACTED
                    ).build()
            )
            WGlobalStorage.addAccount(
                accountId = importedAccountId,
                accountType = importedAccount.accountType.value,
                importedAccount.byChain.jsonObject,
                name = importedAccount.name,
                importedAt = importedAccount.importedAt
            )
            AirPushNotifications.subscribe(importedAccount, ignoreIfLimitReached = true)
            WalletCore.activateAccount(
                accountId = importedAccountId,
                notifySDK = true
            ) { _, err ->
                if (err != null) {
                    // Should not happen
                    Logger.e(
                        Logger.LogTag.ACCOUNT,
                        LogMessage.Builder()
                            .append(
                                "Activation failed in wallet-versions: $err",
                                LogMessage.MessagePartPrivacy.PUBLIC
                            ).build()
                    )
                    return@activateAccount
                }
                if ((navigationController?.viewControllers?.size ?: 0) > 1)
                    navigationController?.pop(false)
                WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
            }
        }
    }

}
