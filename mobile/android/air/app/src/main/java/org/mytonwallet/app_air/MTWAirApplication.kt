package org.mytonwallet.app_air

import android.app.Application
import org.mytonwallet.app_air.airasframework.AirAsFrameworkApplication

class MTWAirApplication : Application() {
    override fun onCreate() {
        try {
            System.loadLibrary("native-utils")
        } catch (_: Throwable) {
        }

        super.onCreate()

        AirAsFrameworkApplication.onCreate(applicationContext)
    }
}
