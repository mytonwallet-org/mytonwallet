package org.mytonwallet.app_air.airasframework

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations
import org.mytonwallet.app_air.uiwidgets.configurations.actionsWidget.ActionsWidgetConfigurationVC
import org.mytonwallet.app_air.uiwidgets.configurations.priceWidget.PriceWidgetConfigurationVC
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AutoLockHelper
import org.mytonwallet.app_air.walletcore.WalletCore

class WidgetConfigurationWindow : WWindow() {
    override fun getKeyNavigationController(): WNavigationController {
        val navigationController = WNavigationController(this)
        val appWidgetManager = AppWidgetManager.getInstance(this)
        val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0)
        val appWidgetInfo = appWidgetManager.getAppWidgetInfo(appWidgetId)
        val onResult = { ok: Boolean ->
            val result = Intent()
            result.putExtra("ok", ok)
            setResult(RESULT_OK, result)
            finish()
        }
        val configurationVC = when (appWidgetInfo.provider.className) {
            "org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget" -> {
                ActionsWidgetConfigurationVC(this, appWidgetId, onResult)
            }

            "org.mytonwallet.app_air.widgets.priceWidget.PriceWidget" -> {
                PriceWidgetConfigurationVC(this, appWidgetId, onResult)
            }

            else -> {
                throw Error()
            }
        }
        navigationController.setRoot(configurationVC)
        return navigationController
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Logger.d(Logger.LogTag.AIR_APPLICATION, "onCreate: WidgetConfigurationWindow created")
        super.onCreate(savedInstanceState)

        if (!WGlobalStorage.isInitialized) {
            finish()
            return
        }

        // Update base storage data
        WBaseStorage.setActiveLanguage(WGlobalStorage.getLangCode())
        WBaseStorage.setBaseCurrency(WGlobalStorage.getBaseCurrency())
        WidgetsConfigurations.reloadWidgets(applicationContext)

        AirAsFrameworkApplication.initTheme(applicationContext)

        WalletCore.incBridgeUsers()
        restartBridge(forcedRecreation = false)
    }

    fun restartBridge(forcedRecreation: Boolean) {
        WalletCore.setupBridge(
            applicationContext,
            windowView,
            forcedRecreation = forcedRecreation,
            isOnAirApp = false
        ) {
            setAppFocusedState()
        }
    }

    fun destroyBridge() {
        WalletCore.decBridgeUsers()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)

        AirAsFrameworkApplication.initTheme(applicationContext)
        updateTheme()
    }

    override fun onResume() {
        super.onResume()
        AutoLockHelper.appResumed()
    }

    override fun onDestroy() {
        super.onDestroy()
        destroyBridge()
    }
}
