package org.mytonwallet.app_air.walletbasecontext.utils

import android.content.Context
import android.content.pm.PackageInfo

object ApplicationContextHolder {
    lateinit var applicationContext: Context
        private set

    var density = 1f
        private set

    private const val SMALL_SCREEN_WIDTH_DP = 360

    val screenWidth by lazy {
        applicationContext.resources.displayMetrics.widthPixels
    }

    val isSmallScreen: Boolean by lazy {
        val widthDp = screenWidth / density
        widthDp <= SMALL_SCREEN_WIDTH_DP
    }

    /** Font size that adapts to screen width. 15sp on small screens, 16sp otherwise. */
    val adaptiveFontSize: Float
        get() = if (isSmallScreen) 15f else 16f

    /** Icon size that adapts to screen width. 40dp on small screens, 44dp otherwise. */
    val adaptiveIconSize: Int
        get() = if (isSmallScreen) 40 else 44

    /** Content start position after icon. 12 (start) + iconSize + 12 (gap) */
    val adaptiveContentStart: Float
        get() = 12f + adaptiveIconSize + 12f

    /** Icon top margin to keep it vertically centered. 10dp on small screens, 8dp otherwise. */
    val adaptiveIconTopMargin: Float
        get() = if (isSmallScreen) 10f else 8f

    fun update(applicationContext: Context) {
        ApplicationContextHolder.applicationContext = applicationContext
        density = applicationContext.density()
    }

    val packageInfo: PackageInfo
        get() {
        val packageManager = applicationContext.packageManager
        val packageName = applicationContext.packageName
        return packageManager.getPackageInfo(packageName, 0)
    }

    // version from app.gradle
    val getAppVersion get() = packageInfo.versionName
}
