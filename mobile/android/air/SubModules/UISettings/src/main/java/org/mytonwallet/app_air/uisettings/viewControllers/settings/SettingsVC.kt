package org.mytonwallet.app_air.uisettings.viewControllers.settings

import android.content.Context
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.net.toUri
import androidx.core.view.doOnLayout
import androidx.core.view.isGone
import androidx.core.view.setPadding
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setConstraints
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.helpers.AccountDialogHelpers
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState.Default
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.PortfolioVC
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
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsSection
import org.mytonwallet.app_air.uisettings.viewControllers.settings.views.SettingsHeaderView
import org.mytonwallet.app_air.uisettings.viewControllers.subwallets.SubWalletsVC
import org.mytonwallet.app_air.uisettings.viewControllers.userResponsibility.UserResponsibilityVC
import org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.WalletVersionsVC
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage.Builder
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
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
import org.mytonwallet.app_air.walletcore.models.MAccount
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
            val receiveVC = ReceiveVC.createIfAvailable(
                context,
                AccountStore.activeAccount?.firstChain
            ) ?: return@setOnClickListener
            val navVC = WNavigationController(window!!, PresentationConfig.PreferredFullScreen)
            navVC.setRoot(receiveVC)
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
                        LocaleController.getString("Remove Wallet")
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

        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            recyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
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
            toStartPx(headerView, additionalTabletPadding + systemBarStartInset)
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
            updateQrButtonVisibility()
            settingsVM.fillOtherAccounts(async = false)
            settingsVM.updateSettingsSection()
            settingsVM.updateHelpSection()
            reloadData()
        }
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        if (pendingReload) {
            visibleSections = computeVisibleSections()
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
            visibleSections = computeVisibleSections()
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

        val moreDrawable = context.getDrawableCompat(
            org.mytonwallet.app_air.uisettings.R.drawable.ic_more
        )?.apply {
            setTint(WColor.SecondaryText.color)
        }

        moreButton.setImageDrawable(moreDrawable)
        moreButtonRipple.rippleColor = WColor.BackgroundRipple.color

        val qrDrawable = context.getDrawableCompat(
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
        val topInset = navigationController?.getSystemBars()?.top ?: 0
        view.setConstraints {
            toTopPx(moreButton, topInset + ViewConstants.GAP.dp)
            toTopPx(qrButton, topInset + ViewConstants.GAP.dp)
        }
        headerView.updateTopInset(topInset)
        rvAdapter.notifyItemChanged(0)
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

    private fun updateQrButtonVisibility() {
        qrButton.isGone = AccountStore.activeAccount?.supportsReceiveScreen != true
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
                    view.setConstraints {
                        toStartPx(headerView, additionalTabletPadding + systemBarStartInset)
                    }
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
                        style = WNavigationController.PresentationStyle.BottomSheet
                    )
                )
                nav.setRoot(
                    WalletContextManager.delegate?.get()
                        ?.getAddAccountVC(MBlockchainNetwork.MAINNET) as WViewController
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
                        style = WNavigationController.PresentationStyle.BottomSheet
                    )
                )
                navVC.setRoot(
                    WalletContextManager.delegate?.get()?.getWalletsTabsVC(
                        MWalletSettingsViewMode.LIST
                    ) as WViewController
                )
                window?.present(navVC)
            }

            SettingsItem.Identifier.NOTIFICATION_SETTINGS -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    NotificationSettingsVC(context)
                )
            }

            SettingsItem.Identifier.PORTFOLIO -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    PortfolioVC(context)
                )
            }

            SettingsItem.Identifier.APPEARANCE -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    AppearanceVC(context)
                )
            }

            SettingsItem.Identifier.ASSETS_AND_ACTIVITY -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    AssetsAndActivitiesVC(context)
                )
            }

            SettingsItem.Identifier.LANGUAGE -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    LanguageVC(context)
                )
            }

            SettingsItem.Identifier.CONNECTED_APPS -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    ConnectedAppsVC(context)
                )
            }

            SettingsItem.Identifier.SECURITY -> {
                pushProtectedScreen("Security") { passcode -> SecurityVC(context, passcode) }
            }

            SettingsItem.Identifier.HELP_CENTER -> {
                val url = context.getString(BaseR.string.app_help_url)
                if (url.isNotEmpty()) openUrl(item.title.toString(), url)
            }

            SettingsItem.Identifier.USE_RESPONSIBILITY -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    UserResponsibilityVC(context)
                )
            }

            SettingsItem.Identifier.SUBWALLETS -> {
                pushProtectedScreen("Subwallets") { passcode -> SubWalletsVC(context, passcode) }
            }

            SettingsItem.Identifier.WALLET_VERSIONS -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    WalletVersionsVC(context)
                )
            }

            SettingsItem.Identifier.ASK_A_QUESTION -> {
                val url = context.getString(BaseR.string.app_support_telegram_url)
                if (url.isNotEmpty()) openExternalUrl(url)
            }

            SettingsItem.Identifier.MTW_FEATURES -> {
                val lang = LocaleController.activeLanguage.langCode
                val usernameRes = if (lang == "ru") BaseR.string.app_tips_telegram_username_ru
                else BaseR.string.app_tips_telegram_username_en
                val username = context.getString(usernameRes)
                    .ifEmpty { context.getString(BaseR.string.app_tips_telegram_username_en) }
                if (username.isNotEmpty()) openExternalUrl("https://t.me/$username")
            }

            SettingsItem.Identifier.MTW_CARDS_NFT -> {
                openUrl(
                    item.title.toString(),
                    ExplorerHelpers.getMtwCardsUrl(MBlockchainNetwork.MAINNET)
                )
            }

            SettingsItem.Identifier.INSTALL_ON_DESKTOP -> {
                val url = context.getString(BaseR.string.app_desktop_install_url)
                if (url.isNotEmpty()) openExternalUrl(url)
            }

            SettingsItem.Identifier.ABOUT_MTW -> {
                navigationController?.tabBarController?.mainNavigationController?.push(
                    AppInfoVC(context)
                )
            }

            else -> {}
        }
    }

    private var visibleSections: List<SettingsSection> = settingsVM.settingsSections

    private fun computeVisibleSections(): List<SettingsSection> {
        val sections = settingsVM.settingsSections
        return if (window?.isWideLayout == true)
            sections.filter { it.section != SettingsSection.Section.ACCOUNTS }
        else
            sections
    }

    private fun reloadData() {
        if (view.isAttachedToWindow) {
            visibleSections = computeVisibleSections()
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
            val bottomInset = (navigationController?.bottomInset ?: 0)
            val recyclerViewPaddingBottom =
                (view.height - contentHeight - topInset + additionalPadding)
                    .coerceAtLeast(bottomInset)
            recyclerView.setPaddingLocalized(
                ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
                recyclerView.paddingTop,
                ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
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
        window?.startActivityCatching(Intent(Intent.ACTION_VIEW, url.toUri()))
    }

    private fun pushProtectedScreen(
        destinationTitle: String,
        destinationBuilder: (String) -> WViewController
    ) {
        val nav = navigationController?.tabBarController?.mainNavigationController
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
                LocaleController.getString(destinationTitle)
            ),
            task = { passcode ->
                nav?.push(destinationBuilder(passcode), onCompletion = {
                    nav.removePrevViewControllerOnly()
                })
            }
        )
        nav?.push(passcodeConfirmVC)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return visibleSections.size + 2
    }

    private fun sectionHasHeader(section: SettingsSection): Boolean {
        return section.title.isNotEmpty()
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        val sections = visibleSections
        return when (section) {
            0 -> 1
            sections.size + 1 -> 1
            else -> {
                val settingsSection = sections[section - 1]
                val headerCount = if (sectionHasHeader(settingsSection)) 1 else 0
                headerCount + settingsSection.children.size
            }
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        val sections = visibleSections
        return when (indexPath.section) {
            0 -> HEADER_CELL
            sections.size + 1 -> VERSION_CELL
            else -> {
                val settingsSection = sections[indexPath.section - 1]
                val hasHeader = sectionHasHeader(settingsSection)
                if (hasHeader && indexPath.row == 0)
                    SECTION_HEADER_CELL
                else {
                    val itemIndex = if (hasHeader) indexPath.row - 1 else indexPath.row
                    when (settingsSection.children.getOrNull(itemIndex)?.identifier) {
                        SettingsItem.Identifier.ACCOUNT -> ACCOUNT_CELL
                        else -> ITEMS_CELL
                    }
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
                    navigationController?.tabBarController?.mainNavigationController?.push(
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
        val sections = visibleSections
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

            sections.size + 1 -> {}

            else -> {
                val section = sections.getOrNull(indexPath.section - 1) ?: return
                val hasHeader = sectionHasHeader(section)
                if (hasHeader && indexPath.row == 0) {
                    val cell = cellHolder.cell as HeaderCell
                    cell.configure(
                        section.title,
                        WColor.Tint,
                        topRounding = HeaderCell.TopRounding.NORMAL
                    )
                    return
                }
                val itemIndex = if (hasHeader) indexPath.row - 1 else indexPath.row
                if (itemIndex > section.children.size - 1)
                    return
                val item =
                    section.children[itemIndex]
                val cell = (cellHolder.cell as ISettingsItemCell)
                cell.configure(
                    item,
                    settingsVM.subtitleFor(item),
                    !hasHeader && itemIndex == 0,
                    itemIndex == section.children.size - 1,
                    true
                ) {
                    itemSelected(item)
                }
                return
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        val sections = visibleSections
        return when (indexPath.section) {
            0, sections.size + 1 -> null

            else -> {
                val section = sections.getOrNull(indexPath.section - 1)
                val hasHeader = section != null && sectionHasHeader(section)
                if (hasHeader && indexPath.row == 0)
                    return section.title
                val itemIndex = if (hasHeader) indexPath.row - 1 else indexPath.row
                val item = section?.children?.getOrNull(itemIndex)
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
                updateQrButtonVisibility()
                headerView.configure()
                settingsVM.fillOtherAccounts(
                    async = walletEvent.fromHome,
                    onComplete = {
                        reloadData()
                    })
                settingsVM.updateSettingsSection()
            }

            is WalletEvent.AccountNameChanged -> {
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

            WalletEvent.ConfigReceived -> {
                val itemsChanged = settingsVM.updateHelpSection()
                if (itemsChanged)
                    reloadData()
            }

            WalletEvent.WideLayoutChanged -> {
                if (headerView.parent == view) {
                    view.setConstraints {
                        toStartPx(headerView, additionalTabletPadding + systemBarStartInset)
                    }
                }
                reloadData()
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
