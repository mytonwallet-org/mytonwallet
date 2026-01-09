package org.mytonwallet.app_air.airasframework.splash

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.core.graphics.createBitmap
import androidx.core.net.toUri
import org.mytonwallet.app_air.airasframework.AirAsFrameworkApplication
import org.mytonwallet.app_air.airasframework.MainWindow
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.sqscan.screen.QrScannerDialog
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicreatewallet.viewControllers.addAccountOptions.AddAccountOptionsVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.importViewWallet.ImportViewWalletVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.intro.IntroVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded.WalletAddedVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.wordCheck.WordCheckVC
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uisend.send.SendVC.InitialValues
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.uitonconnect.TonConnectController
import org.mytonwallet.app_air.uitonconnect.viewControllers.connect.TonConnectRequestConnectVC
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSend.TonConnectRequestSendVC
import org.mytonwallet.app_air.uitransaction.viewControllers.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.NftAccentColors
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.WalletContextManagerDelegate
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AutoLockHelper
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.helpers.LaunchConfig
import org.mytonwallet.app_air.walletcontext.helpers.WordCheckMode
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.MAIN_NETWORK
import org.mytonwallet.app_air.walletcore.TEST_NETWORK
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.api.resetAccounts
import org.mytonwallet.app_air.walletcore.api.swapGetAssets
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkNavigator
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkParser
import org.mytonwallet.app_air.walletcore.helpers.TonConnectHelper
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.moshi.ApiConnectionType
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.DApp.StartSseConnection
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.DApp.StartSseConnection.Request
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.uihome.home.HomeVC
import org.mytonwallet.uihome.tabs.TabsVC
import org.mytonwallet.uihome.walletsTabs.WalletsTabsVC
import java.io.UnsupportedEncodingException
import java.net.URLEncoder

class SplashVC(context: Context) : WViewController(context),
    WalletContextManagerDelegate,
    DeeplinkNavigator,
    WalletCore.UpdatesObserver {
    override val TAG = "Splash"

    override val shouldDisplayTopBar = false

    companion object {
        // Pending deeplink url when launching the app using a deeplink, before creating Splash instance
        var pendingDeeplink: Deeplink? = null
        var sharedInstance: DeeplinkNavigator? = null
    }

    private var appIsUnlocked = false
    private var _isWalletReady = false

    // Pending deeplink to run after the wallet is ready
    private var nextDeeplink: Deeplink? = null
    private var openingSingleWalletWithAddress: String? = null

    init {
        sharedInstance = this
        if (pendingDeeplink != null) {
            nextDeeplink = pendingDeeplink
            pendingDeeplink = null
        }
    }

    override fun setupViews() {
        super.setupViews()
        // Handle possible deep-links right after screen load (like switch to classic on first app launch)
        handleDeeplinkIfRequired()
        updateTheme()
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappLoading::class.java, this)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
    }

    // Presents the view controllers even before bridge becomes ready, to reduce the app start-up time
    var preloadedScreen: WCacheStorage.InitialScreen? = null
    fun preloadScreens() {
        preloadedScreen = null
        view.post { // insets should be loaded first
            if (WalletCore.isBridgeReady)
                return@post // Bridge got ready during view.post process!
            WCacheStorage.getInitialScreen()?.let {
                when (it) {
                    WCacheStorage.InitialScreen.INTRO -> {
                        if (WGlobalStorage.accountIds().isNotEmpty())
                            return@post
                        presentIntro()
                        preloadedScreen = WCacheStorage.InitialScreen.INTRO
                    }

                    WCacheStorage.InitialScreen.HOME -> {
                        return@post
                    }

                    WCacheStorage.InitialScreen.LOCK -> {
                        if (WGlobalStorage.accountIds().isEmpty())
                            return@post
                        presentTabsAndLockScreen(true)
                        preloadedScreen = WCacheStorage.InitialScreen.LOCK
                    }
                }
            }
        }
    }

    fun bridgeIsReady() {
        Logger.i(Logger.LogTag.AIR_APPLICATION, "Bridge Ready, Activating account")
        val accountIds = WGlobalStorage.accountIds()
        if (accountIds.isEmpty()) {
            // Reset and make sure nothing is cached (to handle corrupted global storage conditions)
            resetToIntro()
            return
        }
        var activeAccountId = WGlobalStorage.getActiveAccountId()
        if (nextDeeplink?.accountAddress != null) {
            // Switch to the deeplink account
            activeAccountId = AccountStore.accountIdByAddress(nextDeeplink?.accountAddress)
            if (activeAccountId == null) {
                // Account not found, Ignore the deeplink
                nextDeeplink = null
            }
        }
        activateAccount(
            accountIds = accountIds,
            activeAccountId = activeAccountId,
            isActivatedInSDK = false
        )
        AccountStore.removeTemporaryAccounts()
    }

    // Activates an account. Handles corrupted storage data.
    fun activateAccount(
        accountIds: Array<String>,
        activeAccountId: String?,
        isActivatedInSDK: Boolean
    ) {
        val activatingAccountId = activeAccountId ?: accountIds.first()
        WalletCore.activateAccount(
            activatingAccountId,
            notifySDK = !isActivatedInSDK
        ) { res, err ->
            if (res == null || err != null) {
                /* Should not happen normally,
                    Probably failed it's due to partial account removal somehow,
                    Let's recover. */

                // Cancel any deep-links
                nextDeeplink = null

                // Remove the corrupted account from the queue
                val nextTryAccountIds = accountIds.filter { it != activeAccountId }.toTypedArray()
                if (nextTryAccountIds.isNotEmpty()) {
                    // Try the next accessible accountId
                    val nextTryAccountId = nextTryAccountIds.first()
                    Logger.d(
                        Logger.LogTag.ACCOUNT,
                        "Failed to load $activatingAccountId account on splash, trying $nextTryAccountId"
                    )
                    AccountStore.removeAccount(
                        activatingAccountId,
                        null,
                        null,
                        onCompletion = { _, _ ->
                            activateAccount(
                                accountIds = nextTryAccountIds,
                                activeAccountId = nextTryAccountId,
                                isActivatedInSDK = false
                            )
                        })
                } else {
                    // No more accounts left, let's reset
                    Logger.d(Logger.LogTag.ACCOUNT, "Reset accounts on splash error")
                    StakingStore.wipeData()
                    resetToIntro()
                }
            } else {
                // Everything is fine, let's go!
                WalletCore.swapGetAssets(true)
                if (preloadedScreen == null)
                    presentTabsAndLockScreen(WGlobalStorage.isPasscodeSet())
            }
            WalletCore.checkPendingBridgeTasks()
        }
    }

    private fun presentIntro() {
        if (preloadedScreen == WCacheStorage.InitialScreen.INTRO)
            return
        val navigationController = WNavigationController(window!!)
        navigationController.setRoot(IntroVC(context))
        window!!.replace(navigationController, false)
        Logger.i(Logger.LogTag.AIR_APPLICATION, "Presented Intro")
    }

    private fun presentTabsAndLockScreen(presentLockScreen: Boolean) {
        val tabsNav = WNavigationController(window!!)
        tabsNav.setRoot(TabsVC(context))
        if (!presentLockScreen)
            appIsUnlocked = true
        window!!.replace(tabsNav, false, onCompletion = {
            Logger.i(Logger.LogTag.AIR_APPLICATION, "Presented tabsNav")
            if (presentLockScreen) {
                if (!appIsUnlocked)
                    presentLockScreen()
            }
        })
    }

    private fun resetToIntro() {
        WalletCore.resetAccounts { _, _ ->
            WGlobalStorage.deleteAllWallets()
            WSecureStorage.deleteAllWalletValues()
            appIsUnlocked = true
            presentIntro()
        }
    }

    override fun restartApp() {
        // Make sure we are on splash screen
        if ((window?.navigationControllers?.size ?: 1) > 1) {
            for (i in (window?.navigationControllers!!.size - 2) downTo 1) {
                window?.dismissNav(i)
            }
            window?.dismissLastNav {
                restartApp()
            }
            window?.navigationControllers[0]?.visibility = View.INVISIBLE
            return
        }
        // Reset app
        window?.forceStatusBarLight = null
        window?.forceBottomBarLight = null
        window?.updateLayoutDirection()
        (window as? MainWindow)?.restartBridge(forcedRecreation = true)
    }

    override fun getAddAccountVC(): WViewController {
        return AddAccountOptionsVC(context, isOnIntro = false)
    }

    override fun getWalletAddedVC(isNew: Boolean): Any {
        return WalletAddedVC(context, isNew)
    }

    override fun getWordCheckVC(
        words: Array<String>,
        initialWordIndices: List<Int>,
        mode: WordCheckMode
    ): Any {
        return WordCheckVC(context, words, initialWordIndices, mode)
    }

    override fun getImportLedgerVC(): Any {
        return LedgerConnectVC(context, LedgerConnectVC.Mode.AddAccount)
    }

    override fun getAddViewAccountVC(): Any {
        return ImportViewWalletVC(context, false)
    }

    override fun getWalletsTabsVC(viewMode: MWalletSettingsViewMode): Any {
        return WalletsTabsVC(
            context,
            viewMode
        )
    }

    override fun themeChanged(animated: Boolean) {
        val context = window?.applicationContext ?: return

        val applyTheme = {
            AirAsFrameworkApplication.initTheme(context)
            window?.updateTheme()
        }

        if (animated) {
            animateThemeChange { applyTheme() }
        } else {
            applyTheme()
        }
    }

    override fun protectedModeChanged() {
        window?.updateProtectedView()
    }

    override fun lockScreen() {
        if (!appIsUnlocked || !WGlobalStorage.isPasscodeSet())
            return
        presentLockScreen()
    }

    private fun presentLockScreen() {
        // Make sure to dismiss all popups or dialogs when presenting lock screen
        PopupHelpers.dismissAllPopups()
        activeDialog?.dismiss()
        window?.topViewController?.activeDialog?.dismiss()
        view.hideKeyboard()
        appIsUnlocked = false
        val passcodeConfirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.Default(
                LocaleController.getString("Unlock"),
                LocaleController.getString(
                    (if (WGlobalStorage.isBiometricActivated() &&
                        BiometricHelpers.canAuthenticate(window!!)
                    )
                        "Enter passcode or use fingerprint" else "Enter Passcode")
                ),
                showNavBar = false,
                light = !NftAccentColors.veryBrightColors.contains(WColor.Tint.color),
                showMotionBackgroundDrawable = true,
                animated = true,
                startWithBiometrics = true,
                isUnlockScreen = true
            ),
            task = {
                // After unlock:
                window?.forceStatusBarLight = null
                window?.forceBottomBarLight = null
                window?.dismissLastNav(
                    WWindow.DismissAnimation.SCALE_IN,
                    onCompletion = {
                        appIsUnlocked = true
                        handleDeeplinkIfRequired()
                        window?.doPendingTasks()
                    })
            },
            allowedToCancel = false
        )
        val navigationController = WNavigationController(window!!)
        navigationController.setRoot(passcodeConfirmVC)
        window!!.present(navigationController)
    }

    override fun isAppUnlocked(): Boolean {
        return appIsUnlocked
    }

    override fun handleDeeplink(deeplink: String): Boolean {
        nextDeeplink = DeeplinkParser.parse(deeplink.toUri())
        val isAValidDeeplink = nextDeeplink != null
        handleDeeplinkIfRequired()
        return isAValidDeeplink
    }

    override fun openASingleWallet(addressByChainString: Map<String, String>, name: String?) {
        if (addressByChainString.isEmpty()) {
            showAlertOverTopVC(
                LocaleController.getString("Error"),
                LocaleController.getString("\$no_valid_view_addresses")
            )
            return
        }

        val addressByChain = mutableMapOf<MBlockchain, String>()
        addressByChainString.forEach { (chainStr, address) ->
            try {
                val blockchain = MBlockchain.valueOf(chainStr)
                addressByChain[blockchain] = address
            } catch (_: IllegalArgumentException) {
            }
        }

        if (addressByChain.isEmpty()) {
            showAlertOverTopVC(
                LocaleController.getString("Error"),
                LocaleController.getString("\$no_valid_view_addresses")
            )
            return
        }

        if (openingSingleWalletWithAddress == addressByChainString.values.firstOrNull())
            return

        openingSingleWalletWithAddress = addressByChainString.values.firstOrNull()
        val accountIds = WGlobalStorage.accountIds()
        accountIds.forEach { existingAccountId ->
            val existingAccount = AccountStore.accountById(existingAccountId)
            if (existingAccount?.addressByChain?.entries?.containsAll(addressByChainString.entries) == true) {
                WalletCore.activateAccount(
                    accountId = existingAccountId,
                    notifySDK = true,
                    isPushedTemporary = true
                ) { _, err ->
                    if (err != null) {
                        openingSingleWalletWithAddress = null
                        return@activateAccount
                    }
                    window?.dismissToRoot {
                        WalletCore.notifyEvent(
                            WalletEvent.AccountChangedInApp(
                                persistedAccountsModified = false
                            )
                        )
                        tabsVC?.view?.viewController?.get()
                            ?.push(
                                HomeVC(
                                    context,
                                    MScreenMode.SingleWallet(existingAccountId)
                                )
                            )
                        openingSingleWalletWithAddress = null
                    }
                }
                return
            }
        }
        importTemporaryAccount(addressByChain, name)
    }

    override fun walletIsReady() {
        _isWalletReady = true
        handleDeeplinkIfRequired()
        window?.doPendingTasks()
    }

    override fun isWalletReady(): Boolean {
        return _isWalletReady
    }

    override fun appResumed() {
        handleDeeplinkIfRequired()
    }

    private fun handleDeeplinkIfRequired() {
        if (window?.presentPendingPresentationNav() == true) {
            nextDeeplink = null
            return
        }
        nextDeeplink?.let { handle(it) }
    }

    override fun switchToLegacy() {
        Handler(Looper.getMainLooper()).post {
            LaunchConfig.setShouldStartOnAir(context, false)
            window?.startActivity(WalletContextManager.getMainActivityIntent(context))
            AutoLockHelper.stop()
            window?.finish()
            sharedInstance = null
            WalletContextManager.setDelegate(null)
        }
    }

    override fun bindQrCodeButton(
        context: Context,
        button: View,
        onResult: (String) -> Unit,
        parseDeepLinks: Boolean
    ) {
        button.setOnClickListener {
            QrScannerDialog.build(context) {
                val text = it.trim()
                var address = text
                if (parseDeepLinks) {
                    val deeplink = runCatching { DeeplinkParser.parse(text.toUri()) }.getOrNull()
                    if (deeplink is Deeplink.Invoice) {
                        address = deeplink.address
                    }
                }
                onResult(address)
            }.show()
        }
    }

    private fun showAlertOverTopVC(title: String?, text: CharSequence) {
        window?.topViewController?.apply {
            executeWithLowPriority {
                showAlert(title, text)
            }
        }
    }

    override fun handle(deeplink: Deeplink) {
        if (deeplink is Deeplink.SwitchToLegacy) {
            switchToLegacy()
            return
        }
        if (!_isWalletReady) {
            nextDeeplink = deeplink
            return
        }
        val isHandled = handleInstantDeeplinks(deeplink)
        if (isHandled) {
            nextDeeplink = null
            return
        }
        if (!isAppUnlocked() || window?.isPaused == true) {
            nextDeeplink = deeplink
            return
        }
        if (window?.presentPendingPresentationNav() == true) {
            nextDeeplink = null
            return
        }
        handleWalletReadyDeeplinks(deeplink)
    }

    private val tabsVC: TabsVC?
        get() {
            return window?.navigationControllers?.firstOrNull()?.viewControllers?.firstOrNull() as? TabsVC
        }

    private fun handleInstantDeeplinks(deeplink: Deeplink): Boolean {
        when (deeplink) {
            is Deeplink.TonConnect2 -> {
                if (deeplink.isConnectRequest &&
                    AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW
                ) {
                    return false // Will show a dialog after unlock!
                }
                val uri = try {
                    encodeUriParams(deeplink.requestUri).toString()
                } catch (_: Throwable) {
                    //Logger.e(Logger.LogTag.DEEPLINK, "Encode error: ${t.toString()}")
                    return true
                }
                //Logger.d(Logger.LogTag.DEEPLINK, uri)
                WalletCore.call(
                    StartSseConnection(
                        Request(
                            url = uri,
                            deviceInfo = TonConnectHelper.deviceInfo,
                            identifier = TonConnectHelper.generateId()
                        )
                    )
                ) { returnStrategy, err ->
                    if (err != null) {
                        //Logger.e(Logger.LogTag.DEEPLINK, "Error: $err")
                        return@call
                    }
                    //Logger.d(Logger.LogTag.DEEPLINK, "Strategy: $returnStrategy")
                }
                return true
            }

            else -> {}
        }
        return false
    }

    private fun handleWalletReadyDeeplinks(deeplink: Deeplink) {
        if (deeplink.accountAddress != null) {
            val accountId =
                AccountStore.accountIdByAddress(deeplink.accountAddress) ?: run {
                    nextDeeplink = null
                    return
                }
            val prevAccountId = AccountStore.activeAccountId
            if (accountId != prevAccountId) {
                val accountExistsInStorage = WGlobalStorage.accountIds().contains(accountId)
                if (!accountExistsInStorage) {
                    // Account is already removed, ignore the deeplink!
                    nextDeeplink = null
                    return
                }
                // Switch to the deeplink account first
                _isWalletReady = false
                WalletCore.activateAccount(
                    accountId,
                    notifySDK = true
                ) { res, err ->
                    if (res == null || err != null) {
                        // Switch account failed, Switch back!
                        prevAccountId?.let {
                            nextDeeplink = null
                            WalletCore.activateAccount(
                                prevAccountId,
                                notifySDK = true
                            ) { res, err ->
                                if (res == null || err != null) {
                                    // Should not happen!
                                    Logger.e(
                                        Logger.LogTag.ACCOUNT,
                                        LogMessage.Builder()
                                            .append(
                                                "Switch to deeplink account failed",
                                                LogMessage.MessagePartPrivacy.PUBLIC
                                            ).build()
                                    )
                                    throw Exception("Switch-Back Account Failure")
                                }
                                WalletCore.notifyEvent(
                                    WalletEvent.AccountChangedInApp(
                                        persistedAccountsModified = false
                                    )
                                )
                            }
                        }
                    } else {
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
        val account = AccountStore.activeAccount
        if (account == null) {
            // Ignore deeplinks when the wallet is not ready yet
            nextDeeplink = null
            return
        }

        when (deeplink) {
            is Deeplink.Invoice -> {
                if (AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW) {
                    nextDeeplink = null
                    return
                }

                val error = LocaleController.getStringOrNull(
                    when {
                        deeplink.hasUnsupportedParams ->
                            "\$unsupported_deeplink_parameter"

                        deeplink.expiry != null && (System.currentTimeMillis() / 1000 > deeplink.expiry!!) ->
                            "\$transfer_link_expired"

                        deeplink.comment != null && deeplink.binary != null ->
                            "\$transfer_text_and_bin_exclusive"

                        else -> null
                    }
                )

                error?.let {
                    showAlertOverTopVC(
                        LocaleController.getString("Error"),
                        error
                    )
                    nextDeeplink = null
                    return
                }

                val token =
                    deeplink.jetton?.let {
                        TokenStore.getToken(deeplink.jetton, true)
                    } ?: deeplink.token?.let {
                        TokenStore.getToken(deeplink.token, false)
                    } ?: TokenStore.getToken(TONCOIN_SLUG)

                val amountString = CoinUtils.toDecimalString(deeplink.amount, token?.decimals)

                val navVC = WNavigationController(window!!)
                navVC.setRoot(
                    SendVC(
                        context, token?.slug, InitialValues(
                            address = deeplink.address,
                            amount = amountString,
                            binary = deeplink.binary,
                            comment = deeplink.comment,
                            init = deeplink.init
                        )
                    )
                )
                window?.present(navVC)
            }

            is Deeplink.TonConnect2 -> {
                if (deeplink.isConnectRequest &&
                    AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW
                ) {
                    window?.topViewController?.showAlert(
                        LocaleController.getString("Error"),
                        LocaleController.getString("Action is not possible on a view-only wallet.")
                    )
                    nextDeeplink = null
                    return
                }
                // Already handled
            }

            is Deeplink.Swap -> {
                if (!account.supportsSwap) {
                    showAlertOverTopVC(
                        null,
                        if (WalletCore.activeNetwork == TEST_NETWORK)
                            LocaleController.getString("Swap is not supported in Testnet.")
                        else if (AccountStore.activeAccount?.isHardware == true)
                            LocaleController.getString("Swap is not yet supported by Ledger.")
                        else
                            LocaleController.getString("Swap is not supported on this account.")
                    )
                    nextDeeplink = null
                    return
                }
                val fromToken = TokenStore.getToken(deeplink.from)
                val toToken = TokenStore.getToken(deeplink.to)
                val swapVC = SwapVC(
                    context,
                    if (fromToken != null) MApiSwapAsset.from(fromToken) else null,
                    if (toToken != null) MApiSwapAsset.from(toToken) else null,
                    deeplink.amountIn
                )
                val navVC = WNavigationController(window!!)
                navVC.setRoot(swapVC)
                window?.present(navVC)
            }

            is Deeplink.Receive -> {
                val navVC = WNavigationController(window!!)
                navVC.setRoot(ReceiveVC(context, MBlockchain.ton, false))
                window?.present(navVC)
            }

            is Deeplink.BuyWithCard -> {
                if (!account.supportsBuyWithCard) {
                    showAlertOverTopVC(
                        null,
                        LocaleController.getString("Buying with card is not supported for this account.")
                    )
                    nextDeeplink = null
                    return
                }
                val navVC = WNavigationController(window!!)
                navVC.setRoot(ReceiveVC(context, MBlockchain.ton, true))
                window?.present(navVC)
            }

            is Deeplink.Stake -> {
                if (WalletCore.activeNetwork != MAIN_NETWORK) {
                    showAlertOverTopVC(
                        null,
                        LocaleController.getString("Staking is not supported in Testnet.")
                    )
                    nextDeeplink = null
                    return
                }
                val navVC = WNavigationController(window!!)
                navVC.setRoot(EarnRootVC(context))
                window?.present(navVC)
            }

            is Deeplink.Explore -> {
                tabsVC?.switchToExplore()
            }

            is Deeplink.Url -> {
                val inAppBrowserVC = InAppBrowserVC(
                    context,
                    null,
                    deeplink.config
                )
                val nav = WNavigationController(window!!)
                nav.setRoot(inAppBrowserVC)
                window?.present(nav)
            }

            is Deeplink.Jetton -> {
                presentToken(deeplink.slug)
            }

            is Deeplink.TokenBySlug -> {
                presentToken(deeplink.slug)
            }

            is Deeplink.TokenByAddress -> {
                WalletCore.call(
                    ApiMethod.Tokens.BuildTokenSlug(deeplink.chain, deeplink.address)
                ) { tokenSlug, _ ->
                    tokenSlug?.let {
                        presentToken(tokenSlug)
                    }
                }
            }

            is Deeplink.StakeTx -> {
                if (AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW) {
                    nextDeeplink = null
                    return
                }
                val nav = WNavigationController(window!!)
                nav.setRoot(EarnRootVC(context))
                window?.present(nav)
                // TODO:: Handle and use deeplink.stakingId
            }

            is Deeplink.Transaction -> {
                val chain = deeplink.chain
                    ?: AccountStore.activeAccount?.addressByChain?.entries?.firstOrNull { it.value == deeplink.accountAddress }?.key
                if (chain == null) {
                    nextDeeplink = null
                    return
                }
                val address =
                    deeplink.accountAddress ?: AccountStore.activeAccount?.addressByChain[chain]
                if (address == null) {
                    nextDeeplink = null
                    return
                }
                val accountId = AccountStore.activeAccountId
                WalletCore.call(
                    ApiMethod.WalletData.FetchTransactionById(
                        chain,
                        WalletCore.activeNetwork,
                        deeplink.txId,
                        address
                    )
                ) { activities, err ->
                    if (activities.isNullOrEmpty()) {
                        if (!deeplink.isPushNotification)
                            showAlertOverTopVC(
                                null,
                                err?.parsed?.toLocalized
                                    ?: LocaleController.getString("Transaction not found")
                            )
                        return@call
                    }
                    if (activities.size > 1)
                        return@call // Not handled yet
                    if (AccountStore.activeAccountId != accountId)
                        return@call // Account changed
                    val transactionNav = WNavigationController(
                        window!!, WNavigationController.PresentationConfig(
                            overFullScreen = false,
                            isBottomSheet = true
                        )
                    )
                    transactionNav.setRoot(TransactionVC(context, activities.first()))
                    window!!.present(transactionNav)
                }
            }

            is Deeplink.View -> {
                openASingleWallet(deeplink.addressByChain, name = null)
            }

            is Deeplink.SwitchToLegacy -> {
                // Already handled!
            }
        }

        nextDeeplink = null
    }

    private fun encodeUriParams(uri: Uri): Uri {
        val builder = Uri.Builder()
            .scheme(uri.scheme)
            .authority(uri.authority)

        for (param in uri.queryParameterNames) {
            val value = uri.getQueryParameter(param)
            if (value != null) {
                try {
                    val encodedValue = URLEncoder.encode(value, "UTF-8")
                    builder.appendQueryParameter(param, encodedValue)
                } catch (e: UnsupportedEncodingException) {
                    e.printStackTrace()
                }
            }
        }

        return builder.build()
    }

    private fun importTemporaryAccount(addressByChain: Map<MBlockchain, String>, name: String?) {
        WalletCore.call(
            ApiMethod.Auth.ImportViewAccount(MAIN_NETWORK, addressByChain),
            callback = { result, error ->
                if (result == null || error != null) {
                    error?.parsed?.toLocalized?.let {
                        showAlertOverTopVC(
                            LocaleController.getString("Error"),
                            it
                        )
                    }
                    openingSingleWalletWithAddress = null
                    return@call
                }
                WGlobalStorage.setTemporaryAccountId(result.accountId, false)
                WGlobalStorage.addAccount(
                    accountId = result.accountId,
                    accountType = MAccount.AccountType.VIEW.value,
                    address = result.byChain["ton"]?.address,
                    tronAddress = result.byChain["tron"]?.address,
                    name = name,
                    importedAt = null,
                    isTemporary = true
                )
                WalletCore.activateAccount(
                    accountId = result.accountId,
                    notifySDK = false,
                    isPushedTemporary = true
                ) { _, err ->
                    if (err != null) {
                        openingSingleWalletWithAddress = null
                        return@activateAccount
                    }
                    window?.dismissToRoot {
                        WalletCore.notifyEvent(
                            WalletEvent.AccountChangedInApp(
                                persistedAccountsModified = false
                            )
                        )
                        val homeVC = HomeVC(
                            context,
                            MScreenMode.SingleWallet(result.accountId)
                        )
                        tabsVC?.view?.viewController?.get()?.push(homeVC)
                        openingSingleWalletWithAddress = null
                    }
                }
            })
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun animateThemeChange(onThemeChanged: () -> Unit) {
        window?.let { window ->
            val rootView = window.windowView

            val bitmap = createBitmap(rootView.width, rootView.height)
            val canvas = Canvas(bitmap)
            rootView.draw(canvas)

            val snapshotView = ImageView(context).apply {
                id = View.generateViewId()
                setImageBitmap(bitmap)
                scaleType = ImageView.ScaleType.FIT_XY
                setOnTouchListener { _, _ -> true }
            }

            rootView.addView(
                snapshotView, ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )

            onThemeChanged()

            snapshotView.fadeOut(duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION) {
                rootView.removeView(snapshotView)
                bitmap.recycle()
            }
        } ?: onThemeChanged()
    }

    private fun presentTonConnectLoading() {
        window?.let { window ->
            val tonConnectRequestVC = TonConnectRequestConnectVC(window)
            val isLoadingVCAdded =
                TonConnectController.setLoadingConnectRequestViewController(
                    tonConnectRequestVC
                )
            if (isLoadingVCAdded) {
                val navVC = WNavigationController(
                    window, WNavigationController.PresentationConfig(
                        overFullScreen = false,
                        isBottomSheet = true
                    )
                )
                navVC.setRoot(tonConnectRequestVC)
                if (isAppUnlocked())
                    window.present(navVC)
                else
                    window.presentOnWalletReady(navVC)
            }
        }
    }

    private fun presentTonSendLoading(connectionType: ApiConnectionType) {
        window?.let { window ->
            if (!window.isAnimating &&
                window.pendingPresentationNav?.viewControllers?.firstOrNull() !is TonConnectRequestSendVC
            ) {
                val tonConnectRequestSendVC = TonConnectRequestSendVC(window, connectionType)
                val isLoadingVCAdded =
                    TonConnectController.setLoadingSendRequestViewController(
                        tonConnectRequestSendVC
                    )
                if (isLoadingVCAdded) {
                    val navVC = WNavigationController(window)
                    navVC.setRoot(tonConnectRequestSendVC)
                    if (isAppUnlocked())
                        window.present(navVC)
                    else
                        window.presentOnWalletReady(navVC)
                }
            }
        }
    }

    private fun presentToken(tokenSlug: String) {
        val token = TokenStore.getToken(tokenSlug) ?: run {
            showAlertOverTopVC(
                null,
                LocaleController.getString("\$unknown_token_address")
            )
            return
        }
        val account = AccountStore.activeAccount ?: return
        val tokenVC = TokenVC(
            context,
            account,
            token
        )
        (window?.topViewController as? TabsVC)?.let { tabsVC ->
            (tabsVC.activeNavigationController?.viewControllers?.firstOrNull() as? HomeVC)?.let { homeVC ->
                homeVC.push(tokenVC)
                return
            }
        }
        val nav = WNavigationController(window!!)
        nav.setRoot(tokenVC)
        window?.present(nav)
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        when (update) {
            is ApiUpdate.ApiUpdateDappLoading -> {
                when (update.connectionType) {
                    ApiConnectionType.CONNECT -> {
                        presentTonConnectLoading()
                    }

                    ApiConnectionType.SEND_TRANSACTION, ApiConnectionType.SIGN_DATA -> {
                        presentTonSendLoading(update.connectionType)
                    }
                }
            }

            else -> {}
        }
    }
}
