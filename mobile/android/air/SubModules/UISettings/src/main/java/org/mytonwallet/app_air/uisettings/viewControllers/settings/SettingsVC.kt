package org.mytonwallet.app_air.uisettings.viewControllers.settings

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.AccountDialogHelpers
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.AppearanceVC
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.AssetsAndActivitiesVC
import org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.ConnectedAppsVC
import org.mytonwallet.app_air.uisettings.viewControllers.language.LanguageVC
import org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings.NotificationSettingsVC
import org.mytonwallet.app_air.uisettings.viewControllers.security.SecurityVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.ISettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsAccountCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsShowAllAccountsCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsSpaceCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsVersionCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.uisettings.viewControllers.settings.views.SettingsHeaderView
import org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.WalletVersionsVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference

class SettingsVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver, WalletCore.UpdatesObserver,
    WProtectedView {

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val ACCOUNT_CELL = WCell.Type(2)
        val SHOW_ALL_WALLETS_CELL = WCell.Type(3)
        val ITEMS_CELL = WCell.Type(4)
        val VERSION_CELL = WCell.Type(5)
    }

    override val topBarConfiguration: ReversedCornerView.Config
        get() = super.topBarConfiguration.copy(forceSeparator = true)
    override val topBlurViewGuideline: View
        get() = headerView

    private val px104 = 104.dp

    private val px52 = 52.dp

    override val isSwipeBackAllowed: Boolean = false

    private val settingsVM = SettingsVM()

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(HEADER_CELL, ACCOUNT_CELL, SHOW_ALL_WALLETS_CELL, ITEMS_CELL, VERSION_CELL)
        ).apply {
            setHasStableIds(true)
        }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            updateBlurViews(recyclerView)
            updateScroll(if ((recyclerView.layoutManager as LinearLayoutManagerAccurateOffset).findFirstVisibleItemPosition() < 2) recyclerView.computeVerticalScrollOffset() else 10000)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                adjustScrollingPosition()
            } else {
                updateBlurViews(recyclerView)
            }
        }
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.addOnScrollListener(scrollListener)
        rv.setItemAnimator(null)
        rv.clipToPadding = false
        rv
    }

    private var headerCell: SettingsSpaceCell? = null
    private val headerView: SettingsHeaderView by lazy {
        val v = SettingsHeaderView(this, navigationController?.getSystemBars()?.top ?: 0)
        v
    }

    private val qrButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.setPadding(8.dp)
        btn.setOnClickListener {
            val navVC = WNavigationController(window!!)
            navVC.setRoot(
                ReceiveVC(
                    context,
                    AccountStore.activeAccount?.firstChain ?: MBlockchain.ton
                )
            )
            window?.present(navVC)
        }
        btn
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.setPadding(8.dp)
        btn.setOnClickListener {
            WMenuPopup.present(
                btn,
                listOf(
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.uisettings.R.drawable.ic_edit,
                        LocaleController.getString("Rename Wallet")
                    ) {
                        renameWalletPressed()
                    },
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_exit,
                        LocaleController.getString("Log Out")
                    ) {
                        window?.let { window ->
                            AccountStore.activeAccount?.let { account ->
                                AccountDialogHelpers.presentSignOut(window, account)
                            }
                        }
                    }
                ),
                popupWidth = WRAP_CONTENT,
                aboveView = true
            )
        }
        btn
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateWalletVersions::class.java, this)

        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationController?.getSystemBars()?.bottom ?: 0
        )

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            headerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    SettingsHeaderView.HEIGHT_NORMAL.dp
            )
        )
        view.addView(qrButton, LayoutParams(40.dp, 40.dp))
        view.addView(moreButton, LayoutParams(40.dp, 40.dp))

        view.setConstraints {
            allEdges(recyclerView)
            toTop(headerView)
            toStart(headerView)
            toEnd(headerView)
            toTopPx(
                moreButton,
                (navigationController?.getSystemBars()?.top ?: 0) + ViewConstants.GAP.dp
            )
            toEnd(moreButton, 8f)
            toTopPx(
                qrButton,
                (navigationController?.getSystemBars()?.top ?: 0) + ViewConstants.GAP.dp
            )
            toEnd(qrButton, 64f)
        }

        updateTheme()

        WalletCore.doOnBridgeReady {
            settingsVM.fillOtherAccounts(async = false)
            settingsVM.updateWalletConfigSection()
            settingsVM.updateWalletDataSection()
            rvAdapter.reloadData()
        }
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        headerView.viewDidAppear()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        headerView.viewWillDisappear()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.updateTheme()
        if (headerView.parent == headerCell)
            headerView.updateTheme()

        val moreDrawable =
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.uisettings.R.drawable.ic_more
            )?.apply {
                setTint(WColor.SecondaryText.color)
            }

        moreButton.setImageDrawable(moreDrawable)
        moreButton.addRippleEffect(WColor.BackgroundRipple.color, 20f.dp)

        val qrDrawable =
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.uisettings.R.drawable.ic_qr
            )?.apply {
                setTint(WColor.SecondaryText.color)
            }
        qrButton.setImageDrawable(qrDrawable)
    }

    override fun updateProtectedView() {
        rvAdapter.reloadData()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationController?.getSystemBars()?.bottom ?: 0
        )
        if (headerView.parent == headerCell)
            headerCell?.setConstraints {
                toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun updateScroll(dy: Int) {
        headerView.updateScroll(dy)
        if (dy > 0) {
            if (headerView.parent == headerCell) {
                view.post {
                    if (headerView.parent == headerCell) {
                        topReversedCornerView?.alpha = 1f
                        headerCell?.removeView(headerView)
                        view.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                        navigationBar?.bringToFront()
                        topBlurViewGuideline.bringToFront()
                        moreButton.bringToFront()
                        qrButton.bringToFront()
                    }
                }
            }
        } else {
            if (headerView.parent == view && headerCell != null) {
                view.post {
                    if (headerView.parent == view && headerCell != null) {
                        topReversedCornerView?.alpha = 0f
                        view.removeView(headerView)
                        headerCell?.addView(
                            headerView,
                            ViewGroup.LayoutParams(
                                MATCH_PARENT,
                                (navigationController?.getSystemBars()?.top ?: 0) +
                                    SettingsHeaderView.HEIGHT_NORMAL.dp
                            )
                        )
                        headerCell?.setConstraints {
                            toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                        }
                    }
                }
            }
        }
    }

    private fun adjustScrollingPosition(): Boolean {
        val scrollOffset = recyclerView.computeVerticalScrollOffset()
        if (scrollOffset in 0..px104) {
            val canGoDown = recyclerView.canScrollVertically(1)
            if (!canGoDown)
                return true
            val adjustment = if (scrollOffset < px52) -scrollOffset else px104 - scrollOffset
            if (adjustment != 0) {
                recyclerView.smoothScrollBy(0, adjustment)
                return true
            }
        }
        return false
    }

    private fun renameWalletPressed() {
        AccountStore.activeAccount?.let { account ->
            AccountDialogHelpers.presentRename(this, account)
        }
    }

    private fun itemSelected(item: SettingsItem) {
        when (item.identifier) {
            SettingsItem.Identifier.ADD_ACCOUNT -> {
                val nav = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig(
                        overFullScreen = false,
                        isBottomSheet = true,
                        aboveKeyboard = true
                    )
                )
                nav.setRoot(WalletContextManager.delegate?.getAddAccountVC() as WViewController)
                window?.present(nav)
            }

            SettingsItem.Identifier.ACCOUNT -> {
                val newAccountId = item.accounts!!.first().accountId
                WalletCore.activateAccount(
                    newAccountId,
                    notifySDK = true
                ) { res, err ->
                    if (res == null || err != null) {
                        // Should not happen!
                        Logger.e(
                            Logger.LogTag.ACCOUNT,
                            LogMessage.Builder()
                                .append(
                                    "Activation failed in settings: $err",
                                    LogMessage.MessagePartPrivacy.PUBLIC
                                ).build()
                        )
                    } else {
                        WalletCore.notifyEvent(WalletEvent.AccountChangedInApp(accountsModified = false))
                    }
                }
            }

            SettingsItem.Identifier.SHOW_ALL_WALLETS -> {
                val navVC = WNavigationController(
                    window!!, WNavigationController.PresentationConfig(
                        overFullScreen = false,
                        isBottomSheet = true
                    )
                )
                navVC.setRoot(
                    WalletContextManager.delegate?.getWalletsTabsVC(
                        MWalletSettingsViewMode.LIST
                    ) as WViewController
                )
                window?.present(navVC)
            }

            SettingsItem.Identifier.NOTIFICATION_SETTINGS -> {
                navigationController?.tabBarController?.navigationController?.push(
                    NotificationSettingsVC(context)
                )
            }

            SettingsItem.Identifier.APPEARANCE -> {
                navigationController?.tabBarController?.navigationController?.push(
                    AppearanceVC(context)
                )
            }

            SettingsItem.Identifier.ASSETS_AND_ACTIVITY -> {
                navigationController?.tabBarController?.navigationController?.push(
                    AssetsAndActivitiesVC(context)
                )
            }

            SettingsItem.Identifier.LANGUAGE -> {
                navigationController?.tabBarController?.navigationController?.push(
                    LanguageVC(context)
                )
            }

            SettingsItem.Identifier.CONNECTED_APPS -> {
                navigationController?.tabBarController?.navigationController?.push(
                    ConnectedAppsVC(context)
                )
            }

            SettingsItem.Identifier.SECURITY -> {
                val nav = navigationController?.tabBarController?.navigationController
                val passcodeConfirmVC = PasscodeConfirmVC(
                    context,
                    PasscodeViewState.Default(
                        LocaleController.getString("Locked"),
                        LocaleController.getString(
                            if (WGlobalStorage.isBiometricActivated() &&
                                BiometricHelpers.canAuthenticate(window!!)
                            )
                                "Enter passcode or use fingerprint" else "Enter Passcode"
                        ),
                        LocaleController.getString("Security")
                    ),
                    task = { passcode ->
                        nav?.push(SecurityVC(context, passcode), onCompletion = {
                            nav.removePrevViewControllerOnly()
                        })
                    }
                )
                nav?.push(passcodeConfirmVC)
            }

            SettingsItem.Identifier.QUESTION_AND_ANSWERS -> {
                val nav = WNavigationController(window!!)
                nav.setRoot(
                    InAppBrowserVC(
                        context,
                        null,
                        InAppBrowserConfig(
                            "https://help.mytonwallet.io/intro/frequently-asked-questions",
                            injectTonConnectBridge = false,
                            injectDarkModeStyles = false,
                            title = item.title
                        )
                    )
                )
                window?.present(nav)
            }

            SettingsItem.Identifier.TERMS -> {
                val nav = WNavigationController(window!!)
                nav.setRoot(
                    InAppBrowserVC(
                        context,
                        null,
                        InAppBrowserConfig(
                            "https://mytonwallet.io/terms-of-use",
                            injectTonConnectBridge = false,
                            injectDarkModeStyles = true,
                            title = item.title
                        )
                    )
                )
                window?.present(nav)
            }

            SettingsItem.Identifier.WALLET_VERSIONS -> {
                navigationController?.push(WalletVersionsVC(context))
            }

            else -> {}
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return settingsVM.settingsSections.size + 2
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> 1
            settingsVM.settingsSections.size + 1 -> 1
            else -> settingsVM.settingsSections[section - 1].children.size
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            0 -> HEADER_CELL
            settingsVM.settingsSections.size + 1 -> VERSION_CELL
            else -> {
                when (settingsVM.settingsSections[indexPath.section - 1].children[indexPath.row].identifier) {
                    SettingsItem.Identifier.ACCOUNT -> ACCOUNT_CELL
                    SettingsItem.Identifier.SHOW_ALL_WALLETS -> SHOW_ALL_WALLETS_CELL
                    else -> ITEMS_CELL
                }
            }
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                if (headerCell == null)
                    headerCell = SettingsSpaceCell(context)
                headerCell!!
            }

            ACCOUNT_CELL -> {
                SettingsAccountCell(context)
            }

            SHOW_ALL_WALLETS_CELL -> {
                SettingsShowAllAccountsCell(context)
            }

            ITEMS_CELL -> {
                SettingsItemCell(context)
            }

            VERSION_CELL -> {
                SettingsVersionCell(context)
            }

            else -> {
                throw Error()
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
                val cellLayoutParams = RecyclerView.LayoutParams(MATCH_PARENT, 0)
                val newHeight =
                    (navigationController?.getSystemBars()?.top ?: 0) +
                        SettingsHeaderView.HEIGHT_NORMAL.dp +
                        (if (ThemeManager.uiMode.hasRoundedCorners) 0 else ViewConstants.GAP.dp)
                cellLayoutParams.height = newHeight
                cellHolder.cell.layoutParams = cellLayoutParams
                return
            }

            settingsVM.settingsSections.size + 1 -> {}

            else -> {
                val item =
                    settingsVM.settingsSections[indexPath.section - 1].children[indexPath.row]
                val cell = (cellHolder.cell as ISettingsItemCell)
                cell.configure(
                    item,
                    settingsVM.valueFor(item),
                    indexPath.row == 0,
                    indexPath.row == settingsVM.settingsSections[indexPath.section - 1].children.size - 1
                ) {
                    itemSelected(item)
                }
                return
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        when (indexPath.section) {
            0, settingsVM.settingsSections.size + 1 -> {}

            else -> {
                val item =
                    settingsVM.settingsSections[indexPath.section - 1].children[indexPath.row]
                return item.accounts?.first()?.accountId
            }
        }
        return super.recyclerViewCellItemId(rv, indexPath)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                headerView.configure()
                settingsVM.fillOtherAccounts(async = walletEvent.fromHome, onComplete = {
                    rvAdapter.reloadData()
                })
                settingsVM.updateWalletDataSection()
            }

            WalletEvent.AccountNameChanged -> {
                headerView.configure()
            }

            WalletEvent.AccountsReordered -> {
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    rvAdapter.reloadData()
                })
            }

            WalletEvent.BalanceChanged -> {
                headerView.configureDescriptionLabel()
            }

            WalletEvent.NotActiveAccountBalanceChanged -> {
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    rvAdapter.reloadData()
                })
            }

            WalletEvent.BaseCurrencyChanged -> {
                headerView.configureDescriptionLabel()
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    rvAdapter.reloadData()
                })
            }

            WalletEvent.TokensChanged -> {
                headerView.configureDescriptionLabel()
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    rvAdapter.reloadData()
                })
            }

            WalletEvent.StakingDataUpdated -> {
                headerView.configureDescriptionLabel()
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    rvAdapter.reloadData()
                })
            }

            WalletEvent.DappsCountUpdated -> {
                settingsVM.updateWalletConfigSection()
                rvAdapter.reloadData()
            }

            else -> {}
        }
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        when (update) {
            is ApiUpdate.ApiUpdateWalletVersions -> {
                settingsVM.updateWalletDataSection()
                rvAdapter.reloadData()
            }

            else -> {}
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateWalletVersions::class.java, this)
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.removeAllViews()
    }
}
