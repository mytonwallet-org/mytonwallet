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
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AutoLockHelper
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications

class MainWindow : WWindow() {
    private val splashVC by lazy {
        val vc = SplashVC(this)
        WalletContextManager.setDelegate(vc)
        vc
    }

    override fun getKeyNavigationController(): WNavigationController {
        val navigationController = WNavigationController(this)
        navigationController.setRoot(splashVC)
        return navigationController
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Logger.d(Logger.LogTag.AIR_APPLICATION, "MainWindow Created")
        super.onCreate(savedInstanceState)

        if (!WGlobalStorage.isInitialized) {
            return
        }

        AirAsFrameworkApplication.initTheme(applicationContext)

        WalletCore.incBridgeUsers()
        restartBridge(forcedRecreation = false)

        AutoLockHelper.start(WGlobalStorage.getAppLock().period)

        checkPushNotifications()
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

        WGlobalStorage.clearUiCacheData()
        val langCode = WGlobalStorage.getLangCode()
        if (LocaleController.init(this, langCode)) {
            WalletContextManager.delegate?.restartApp()
            WBaseStorage.setActiveLanguage(langCode)
            WidgetsConfigurations.reloadWidgets(this)
        }

        AirAsFrameworkApplication.initTheme(applicationContext)
        updateTheme()
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
    }

    var lastWidgetUpdate: Long = 0
    override fun onPause() {
        super.onPause()
        val currentDt = System.currentTimeMillis()
        if (currentDt - lastWidgetUpdate > 60 * 1000) {
            lastWidgetUpdate = currentDt
            WidgetsConfigurations.reloadWidgets(applicationContext)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        destroyBridge()
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
