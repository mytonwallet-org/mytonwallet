package org.mytonwallet.app_air.airasframework

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.MotionEvent
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.airasframework.splash.SplashVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.ShakeDetector
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uisettings.viewControllers.debugMenu.DebugMenuVC
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AutoLockHelper
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.uihome.tabletTabs.TabletTabsVC
import org.mytonwallet.uihome.tabs.PhoneTabsVC

class MainWindow : WWindow() {
    private var isBridgeUser = false
    private val splashVC by lazy {
        val vc = SplashVC(this)
        WalletContextManager.setDelegate(vc)
        vc
    }

    companion object {
        const val ADDITIONAL_TABLET_PADDING =
            ViewConstants.TABLET_PANELS_OVERLAP_WIDTH.toInt() + ViewConstants.TABLET_CONTENT_START_PADDING.toInt()
    }

    override fun getKeyNavigationController(): WNavigationController {
        val navigationController =
            WNavigationController(this, WNavigationController.PresentationConfig())
        navigationController.setRoot(splashVC)
        return navigationController
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Logger.d(Logger.LogTag.AIR_APPLICATION, "MainWindow Created")
        super.onCreate(savedInstanceState)

        isWideLayout = calcWideLayout()
        ViewConstants.ADDITIONAL_TABLET_PADDING =
            if (isWideLayout) ADDITIONAL_TABLET_PADDING.dp else 0
        windowView.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, or, ob ->
            if (r - l != or - ol || b - t != ob - ot)
                swapTabContainerIfNeeded()
            else
                isConfiguring = false
        }

        if (!WGlobalStorage.isInitialized) {
            return
        }

        AirAsFrameworkApplication.initTheme(applicationContext)

        WalletCore.incBridgeUsers()
        isBridgeUser = true
        restartBridge(forcedRecreation = false)

        AutoLockHelper.start(WGlobalStorage.getAppLock().period)

        ShakeDetector.onShake = { presentDebugMenuIfAllowed() }

        checkPushNotifications()
    }

    private fun presentDebugMenuIfAllowed() {
        if (!WGlobalStorage.getIsShakeToDebugEnabled()) return
        if (WalletContextManager.delegate?.get()?.isAppUnlocked() != true) return
        val topVC = topViewController ?: return
        if (topVC is PasscodeConfirmVC) return
        if (topVC.isLockedScreen) return
        if (topVC is DebugMenuVC) return
        val nav = WNavigationController(
            this,
            WNavigationController.PresentationConfig.PreferredFullScreen
        )
        nav.setRoot(DebugMenuVC(this))
        present(nav, animated = true)
    }

    fun restartBridge(forcedRecreation: Boolean) {
        splashVC.preloadScreens()
        WalletCore.setupBridge(
            applicationContext,
            windowView,
            forcedRecreation = forcedRecreation
        ) {
            // Bridge ready now!
            splashVC.bridgeIsReady()
            setAppFocusedState()
        }
    }

    fun destroyBridge() {
        WalletCore.decBridgeUsers()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)

        if (!WGlobalStorage.isInitialized) {
            return
        }

        WGlobalStorage.clearUiCacheData()
        val langCode = WGlobalStorage.getLangCode()
        if (LocaleController.init(this, langCode)) {
            WalletContextManager.delegate?.get()?.restartApp()
            WBaseStorage.setActiveLanguage(langCode)
            WGlobalStorage.setLangCode(langCode)
            WidgetsConfigurations.reloadWidgets(this)
            AirAsFrameworkApplication.initTheme(applicationContext)
            updateTheme()
            return
        }

        AirAsFrameworkApplication.initTheme(applicationContext)
        updateTheme()
    }

    private fun swapTabContainerIfNeeded() {
        PopupHelpers.dismissMenuPopups()
        val nowWide = calcWideLayout()
        if (isWideLayout == nowWide) {
            reapplyPresentedNavsLayout()
            return
        }
        isWideLayout = nowWide
        isConfiguring = true

        // Swap the root tab container (phone <-> tablet) if it changed direction.
        (navigationControllers.firstOrNull()?.viewControllers?.firstOrNull())?.let { currentContainer ->
            when (currentContainer) {
                is PhoneTabsVC -> if (nowWide) {
                    // Tablet has no minimized-nav support; restore it as a presented nav first.
                    currentContainer.maximize(animated = false)
                    val transfer = currentContainer.exportStacks()
                    val tabletContainer = TabletTabsVC(this)
                    tabletContainer.adoptStacksBeforeSetup(transfer)
                    navigationControllers.first().replaceRoot(tabletContainer)
                }

                is TabletTabsVC -> if (!nowWide) {
                    val transfer = currentContainer.exportStacks()
                    val phoneContainer = PhoneTabsVC(this)
                    phoneContainer.adoptStacksBeforeSetup(transfer)
                    navigationControllers.first().replaceRoot(phoneContainer)
                }

                else -> {}
            }
        }

        ViewConstants.ADDITIONAL_TABLET_PADDING = if (nowWide) ADDITIONAL_TABLET_PADDING.dp else 0
        // Re-layout any presented navs (bottom sheet <-> centered window, PreferredFullScreen, dim
        // overlays, behind-screen visibility) for the new layout.
        reapplyPresentedNavsLayout()
        notifyInsetsUpdated()
        WalletCore.notifyEvent(WalletEvent.WideLayoutChanged)
    }

    override fun dispatchTouchEvent(event: MotionEvent?): Boolean {
        triggerTouchEvent()
        return super.dispatchTouchEvent(event)
    }

    private var lastTouchEventTimestamp: Long = 0
    private fun triggerTouchEvent() {
        val now = System.currentTimeMillis()
        if (now < lastTouchEventTimestamp + 5000) return
        lastTouchEventTimestamp = now
        AutoLockHelper.resetTimer()
    }

    override fun onResume() {
        super.onResume()
        AutoLockHelper.appResumed()
        if (WGlobalStorage.getIsShakeToDebugEnabled()) {
            ShakeDetector.onAppResume()
        }
    }

    var lastWidgetUpdate: Long = 0
    override fun onPause() {
        super.onPause()
        if (WGlobalStorage.getIsShakeToDebugEnabled()) {
            ShakeDetector.onAppPause()
        }
        val currentDt = System.currentTimeMillis()
        if (currentDt - lastWidgetUpdate > 60 * 1000) {
            lastWidgetUpdate = currentDt
            WidgetsConfigurations.reloadWidgets(applicationContext)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ShakeDetector.onShake = null
        if (isBridgeUser) {
            isBridgeUser = false
            destroyBridge()
        }
    }

    private fun checkPushNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            // Permission already granted
            AirPushNotifications.register(subscribePreviousAccountsIfEmpty = false)
        } else {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS)) { _, grantResults ->
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    AirPushNotifications.register(subscribePreviousAccountsIfEmpty = true)
                }
            }
        }
    }

}
