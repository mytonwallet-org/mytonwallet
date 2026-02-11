package org.mytonwallet.app_air.airasframework

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.view.ViewGroup
import com.facebook.drawee.backends.pipeline.Fresco
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager.setNftAccentColor
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.helpers.LaunchConfig
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.util.Date

class AirAsFrameworkApplication {

    companion object {
        fun onCreate(
            applicationContext: Context,
            globalStorageProvider: IGlobalStorageProvider,
            bridgeHostView: ViewGroup
        ) {
            Logger.initialize(applicationContext)

            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "**** APP START **** ${Date()} " +
                    "version=${LaunchConfig.getVersionName(applicationContext)} " +
                    "build=${LaunchConfig.getBuildNumber(applicationContext)} " +
                    "device=${Build.MODEL} " +
                    "Android=${Build.VERSION.RELEASE}"
            )

            Logger.i(Logger.LogTag.AIR_APPLICATION, "onCreate: Initializing basic required objects")
            val start = System.currentTimeMillis()

            var t = System.currentTimeMillis()
            ApplicationContextHolder.update(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "ApplicationContextHolder.update: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            WSecureStorage.init(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "WSecureStorage.init: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            WCacheStorage.init(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "WCacheStorage.init: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            WGlobalStorage.init(globalStorageProvider)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "WGlobalStorage.init: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            WBaseStorage.init(applicationContext)
            WBaseStorage.setActiveLanguage(WGlobalStorage.getLangCode())
            WBaseStorage.setBaseCurrency(WGlobalStorage.getBaseCurrency())
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "WBaseStorage.init: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            FontManager.init(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "FontManager.init: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            initTheme(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "initTheme: ${System.currentTimeMillis() - t}ms"
            )

            LocaleController.init(applicationContext, WGlobalStorage.getLangCode())

            t = System.currentTimeMillis()
            Fresco.initialize(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "Fresco.initialize: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            ActivityStore.loadFromCache()
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "ActivityStore.loadFromCache: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            BalanceStore.loadFromCache()
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "BalanceStore.loadFromCache: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            TokenStore.loadFromCache()
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "TokenStore.loadFromCache: ${System.currentTimeMillis() - t}ms"
            )

            t = System.currentTimeMillis()
            ValueAnimator.setFrameDelay(8)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "ValueAnimator.setFrameDelay: ${System.currentTimeMillis() - t}ms"
            )

            /*t = System.currentTimeMillis()
            LauncherIconController.tryFixLauncherIconIfNeeded(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "LauncherIconController.tryFixLauncherIconIfNeeded: ${System.currentTimeMillis() - t}ms"
            )*/

            t = System.currentTimeMillis()
            DevicePerformanceClassifier.init(applicationContext)
            Logger.i(
                Logger.LogTag.AIR_APPLICATION,
                "DevicePerformanceClassifier.init: ${System.currentTimeMillis() - t}ms"
            )

            val end = System.currentTimeMillis()
            Logger.i(Logger.LogTag.AIR_APPLICATION, "onCreate: Total initialization time=${end - start}ms")

            Logger.i(Logger.LogTag.AIR_APPLICATION, "onCreate: Setting up bridge")
            WalletCore.setupBridge(applicationContext, bridgeHostView, forcedRecreation = true) {
                Logger.i(Logger.LogTag.AIR_APPLICATION, "onCreate: Bridge ready")
            }
        }

        fun initTheme(applicationContext: Context) {
            val selectedTheme = WGlobalStorage.getActiveTheme()
            val roundedToolbarsActive = WGlobalStorage.getAreRoundedToolbarsActive()
            val sideGuttersActive = WGlobalStorage.getAreSideGuttersActive()
            val roundedCornersActive = WGlobalStorage.getAreRoundedCornersActive()
            when (selectedTheme) {
                ThemeManager.THEME_LIGHT -> {
                    ThemeManager.init(
                        theme = ThemeManager.THEME_LIGHT,
                        roundedToolbarsActive = roundedToolbarsActive,
                        sideGuttersActive = sideGuttersActive,
                        roundedCornersActive = roundedCornersActive
                    )
                }

                ThemeManager.THEME_DARK -> {
                    ThemeManager.init(
                        theme = ThemeManager.THEME_DARK,
                        roundedToolbarsActive = roundedToolbarsActive,
                        sideGuttersActive = sideGuttersActive,
                        roundedCornersActive = roundedCornersActive
                    )
                }

                ThemeManager.THEME_SYSTEM -> {
                    val nightModeFlags =
                        applicationContext.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                    when (nightModeFlags) {
                        Configuration.UI_MODE_NIGHT_YES -> ThemeManager.init(
                            theme = ThemeManager.THEME_DARK,
                            roundedToolbarsActive = roundedToolbarsActive,
                            sideGuttersActive = sideGuttersActive,
                            roundedCornersActive = roundedCornersActive
                        )

                        Configuration.UI_MODE_NIGHT_NO -> ThemeManager.init(
                            theme = ThemeManager.THEME_LIGHT,
                            roundedToolbarsActive = roundedToolbarsActive,
                            sideGuttersActive = sideGuttersActive,
                            roundedCornersActive = roundedCornersActive
                        )

                        Configuration.UI_MODE_NIGHT_UNDEFINED -> ThemeManager.init(
                            theme = ThemeManager.THEME_LIGHT,
                            roundedToolbarsActive = roundedToolbarsActive,
                            sideGuttersActive = sideGuttersActive,
                            roundedCornersActive = roundedCornersActive
                        )
                    }
                }
            }
            val accountId = WalletCore.nextAccountId ?: AccountStore.activeAccountId
            ?: WGlobalStorage.getActiveAccountId()
            updateAccentColor(accountId)
        }

        fun updateAccentColor(accountId: String?) {
            accountId?.let {
                WGlobalStorage.getNftAccentColorIndex(accountId)?.let {
                    setNftAccentColor(it)
                    return
                }
            }
        }
    }
}
