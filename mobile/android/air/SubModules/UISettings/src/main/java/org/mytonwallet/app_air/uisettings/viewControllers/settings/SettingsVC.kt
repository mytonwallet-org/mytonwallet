package org.mytonwallet.app_air.uisettings.viewControllers.settings

import android.content.Context
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.core.view.doOnLayout
import androidx.core.view.setPadding
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.AccountDialogHelpers
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState.Default
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisettings.viewControllers.appInfo.AppInfoVC
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.AppearanceVC
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.AssetsAndActivitiesVC
import org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.ConnectedAppsVC
import org.mytonwallet.app_air.uisettings.viewControllers.debugMenu.DebugMenuVC
import org.mytonwallet.app_air.uisettings.viewControllers.language.LanguageVC
import org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings.NotificationSettingsVC
import org.mytonwallet.app_air.uisettings.viewControllers.security.SecurityVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.ISettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsAccountCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsSpaceCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsVersionCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.uisettings.viewControllers.settings.views.SettingsHeaderView
import org.mytonwallet.app_air.uisettings.viewControllers.userResponsibility.UserResponsibilityVC
import org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.WalletVersionsVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage.Builder
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.WalletEvent.AccountChangedInApp
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference

class SettingsVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver, WalletCore.UpdatesObserver,
    WProtectedView {
    override val TAG = "Settings"

    private val moreButtonRipple = WRippleDrawable.create(20f.dp)

    companion object {
        val TIP_URLS = mapOf(
            "en" to "MyTonWalletTips",
            "ru" to "MyTonWalletTipsRu"
        )
        val HEADER_CELL = WCell.Type(1)
        val SECTION_HEADER_CELL = WCell.Type(2)
        val ACCOUNT_CELL = WCell.Type(3)
        val ITEMS_CELL = WCell.Type(4)
        val VERSION_CELL = WCell.Type(5)
    }

    override val topBarConfiguration: ReversedCornerView.Config
        get() = super.topBarConfiguration.copy(blurRootView = recyclerView, forceSeparator = true)
    override val topBlurViewGuideline: View
        get() = headerView

    private val px104 = 104.dp
    private val px52 = 52.dp

    override val isSwipeBackAllowed: Boolean = false

    private val settingsVM = SettingsVM()
    private var pendingReload = false

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                HEADER_CELL,
                SECTION_HEADER_CELL,
                ACCOUNT_CELL,
                ITEMS_CELL,
                VERSION_CELL
            )
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
        btn.background = moreButtonRipple
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
                        LocaleController.getString("Sign Out")
                    ) {
                        window?.let { window ->
                            AccountStore.activeAccount?.let { account ->
                                AccountDialogHelpers.presentSignOut(window, account)
                            }
                        }
                    }
                ),
                popupWidth = WRAP_CONTENT,
                positioning = WMenuPopup.Positioning.ALIGNED
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
            recyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            recyclerView.paddingBottom
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
            toEnd(qrButton, 56f)
        }

        updateTheme()

        WalletCore.doOnBridgeReady {
            settingsVM.fillOtherAccounts(async = false)
            settingsVM.updateSettingsSection()
            reloadData()
        }
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        if (pendingReload) {
            updatePadding()
            rvAdapter.reloadData()
            pendingReload = false
        }
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        headerView.viewDidAppear()
    }

    override fun viewDidEnterForeground() {
        super.viewDidEnterForeground()
        if (pendingReload) {
            updatePadding()
            rvAdapter.reloadData()
            pendingReload = false
        }
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        headerView.viewWillDisappear()
    }

    override fun updateTheme() {
        super.updateTheme()
        recyclerView.setBackgroundColor(WColor.SecondaryBackground.color)
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
        moreButtonRipple.rippleColor = WColor.BackgroundRipple.color

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
        reloadData()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        updatePadding()
        if (headerView.parent == headerCell)
            headerCell?.setConstraints {
                toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private var isReparenting = false

    private fun updateScroll(dy: Int) {
        headerView.updateScroll(dy)
        if (isReparenting) return
        if (dy > 0) {
            if (headerView.parent == headerCell) {
                isReparenting = true
                try {
                    topReversedCornerView?.alpha = 1f
                    headerCell?.removeView(headerView)
                    view.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                    navigationBar?.bringToFront()
                    topBlurViewGuideline.bringToFront()
                    moreButton.bringToFront()
                    qrButton.bringToFront()
                } finally {
                    isReparenting = false
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
                    PresentationConfig(
                        overFullScreen = false,
                        isBottomSheet = true,
                        aboveKeyboard = true
                    )
                )
                nav.setRoot(
                    WalletContextManager.delegate?.getAddAccountVC(MBlockchainNetwork.MAINNET) as WViewController
                )
                window?.present(nav)
            }

            SettingsItem.Identifier.ACCOUNT -> {
                val newAccountId = item.account?.accountId ?: return
                WalletCore.activateAccount(
                    newAccountId,
                    notifySDK = true
                ) { res, err ->
                    if (res == null || err != null) {
                        // Should not happen!
                        Logger.e(
                            Logger.LogTag.ACCOUNT,
                            Builder()
                                .append(
                                    "activateAccount: Failed in settings err=$err",
                                    LogMessage.MessagePartPrivacy.PUBLIC
                                ).build()
                        )
                    } else {
                        WalletCore.notifyEvent(
                            AccountChangedInApp(
                                persistedAccountsModified = false
                            )
                        )
                    }
                }
            }

            SettingsItem.Identifier.SHOW_ALL_WALLETS -> {
                val navVC = WNavigationController(
                    window!!, PresentationConfig(
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
                    Default(
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

            SettingsItem.Identifier.HELP_CENTER -> {
                openUrl(
                    item.title,
                    "https://help.mytonwallet.io/"
                )
            }

            SettingsItem.Identifier.USE_RESPONSIBILITY -> {
                push(UserResponsibilityVC(context))
            }

            SettingsItem.Identifier.WALLET_VERSIONS -> {
                push(WalletVersionsVC(context))
            }

            SettingsItem.Identifier.ASK_A_QUESTION -> {
                openExternalUrl("https://t.me/mysupport")
            }

            SettingsItem.Identifier.MTW_FEATURES -> {
                openExternalUrl("https://t.me/${TIP_URLS[LocaleController.activeLanguage.langCode] ?: TIP_URLS["en"]}")
            }

            SettingsItem.Identifier.MTW_CARDS_NFT -> {
                openUrl(
                    item.title,
                    ExplorerHelpers.getMtwCardsUrl(MBlockchainNetwork.MAINNET)
                )
            }

            SettingsItem.Identifier.INSTALL_ON_DESKTOP -> {
                openExternalUrl("https://mytonwallet.io/get/desktop")
            }

            SettingsItem.Identifier.ABOUT_MTW -> {
                push(AppInfoVC(context))
            }

            else -> {}
        }
    }

    private fun reloadData() {
        if (view.isAttachedToWindow) {
            updatePadding()
            rvAdapter.reloadData()
        } else {
            pendingReload = true
        }
    }

    private fun updatePadding() {
        view.doOnLayout {
            val additionalPadding =
                (SettingsHeaderView.HEIGHT_NORMAL - SettingsHeaderView.HEIGHT_COLLAPSED).dp
            val contentHeight = settingsVM.contentHeight()
            val topInset = (navigationController?.getSystemBars()?.top ?: 0)
            val bottomInset = (navigationController?.getSystemBars()?.bottom ?: 0)
            val recyclerViewPaddingBottom =
                (view.height - contentHeight - topInset + additionalPadding)
                    .coerceAtLeast(bottomInset)
            recyclerView.setPadding(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                recyclerView.paddingTop,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                recyclerViewPaddingBottom
            )
        }
    }

    private fun openUrl(title: String, url: String) {
        val nav = WNavigationController(window!!)
        nav.setRoot(
            InAppBrowserVC(
                context,
                null,
                InAppBrowserConfig(
                    url,
                    injectDappConnect = false,
                    injectDarkModeStyles = false,
                    title = title
                )
            )
        )
        window?.present(nav)
    }

    private fun openExternalUrl(url: String) {
        val intent = Intent(Intent.ACTION_VIEW)
        intent.setData(url.toUri())
        window?.startActivity(intent)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return settingsVM.settingsSections.size + 2
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> 1
            settingsVM.settingsSections.size + 1 -> 1
            else -> 1 + settingsVM.settingsSections[section - 1].children.size
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            0 -> HEADER_CELL
            settingsVM.settingsSections.size + 1 -> VERSION_CELL
            else -> {
                if (indexPath.row == 0)
                    SECTION_HEADER_CELL
                else when (settingsVM.settingsSections.getOrNull(indexPath.section - 1)?.children?.getOrNull(
                    indexPath.row - 1
                )?.identifier) {
                    SettingsItem.Identifier.ACCOUNT -> ACCOUNT_CELL
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

            SECTION_HEADER_CELL -> {
                HeaderCell(context)
            }

            ACCOUNT_CELL -> {
                SettingsAccountCell(context)
            }

            ITEMS_CELL -> {
                SettingsItemCell(context)
            }

            VERSION_CELL -> {
                SettingsVersionCell(window!!) {
                    navigationController?.tabBarController?.navigationController?.push(
                        DebugMenuVC(context)
                    )
                }
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
                        SettingsHeaderView.HEIGHT_NORMAL.dp
                cellLayoutParams.height = newHeight
                cellHolder.cell.layoutParams = cellLayoutParams
                return
            }

            settingsVM.settingsSections.size + 1 -> {}

            else -> {
                val section = settingsVM.settingsSections.getOrNull(indexPath.section - 1) ?: return
                if (indexPath.row > section.children.size)
                    return
                if (indexPath.row == 0) {
                    val cell = cellHolder.cell as HeaderCell
                    cell.configure(
                        section.title,
                        WColor.Tint,
                        topRounding = HeaderCell.TopRounding.NORMAL
                    )
                    return
                }
                val itemIndex = indexPath.row - 1
                val item =
                    section.children[itemIndex]
                val cell = (cellHolder.cell as ISettingsItemCell)
                cell.configure(
                    item,
                    settingsVM.subtitleFor(item),
                    false,
                    itemIndex == section.children.size - 1
                ) {
                    itemSelected(item)
                }
                return
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return when (indexPath.section) {
            0, settingsVM.settingsSections.size + 1 -> null

            else -> {
                if (indexPath.row == 0)
                    return settingsVM.settingsSections.getOrNull(indexPath.section - 1)?.title
                val item =
                    settingsVM.settingsSections.getOrNull(indexPath.section - 1)?.children?.getOrNull(indexPath.row - 1)
                when (item?.identifier) {
                    SettingsItem.Identifier.ACCOUNT -> {
                        item.account?.accountId
                    }

                    else -> {
                        item?.identifier?.name
                    }
                }
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                headerView.configure()
                settingsVM.fillOtherAccounts(
                    async = walletEvent.fromHome,
                    onComplete = {
                        reloadData()
                    })
                settingsVM.updateSettingsSection()
            }

            WalletEvent.AccountNameChanged -> {
                headerView.configure()
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    reloadData()
                })
            }

            WalletEvent.AccountsReordered, is WalletEvent.AccountRemoved -> {
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    reloadData()
                })
            }

            WalletEvent.BalanceChanged -> {
                headerView.configureDescriptionLabel()
            }

            WalletEvent.NotActiveAccountBalanceChanged -> {
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    reloadData()
                })
            }

            WalletEvent.BaseCurrencyChanged -> {
                headerView.configureDescriptionLabel()
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    reloadData()
                })
            }

            WalletEvent.TokensChanged -> {
                headerView.configureDescriptionLabel()
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    reloadData()
                })
            }

            WalletEvent.StakingDataUpdated -> {
                headerView.configureDescriptionLabel()
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    reloadData()
                })
            }

            WalletEvent.DappsCountUpdated -> {
                settingsVM.updateSettingsSection()
                reloadData()
            }

            is WalletEvent.ByChainUpdated -> {
                settingsVM.fillOtherAccounts(async = true, onComplete = {
                    reloadData()
                })
                headerView.configure()
            }

            else -> {}
        }
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        when (update) {
            is ApiUpdate.ApiUpdateWalletVersions -> {
                settingsVM.updateSettingsSection()
                reloadData()
            }

            else -> {}
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletVersions::class.java,
            this
        )
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.removeAllViews()
    }
}
