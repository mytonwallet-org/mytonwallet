package org.mytonwallet.app_air.walletbasecontext.utils

import android.content.Context
import android.content.pm.PackageInfo

object ApplicationContextHolder {
    lateinit var applicationContext: Context
        private set

    var density = 1f
        private set

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
