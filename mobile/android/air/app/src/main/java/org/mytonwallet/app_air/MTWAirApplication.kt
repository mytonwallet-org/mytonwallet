package org.mytonwallet.app_air

import android.app.Application
import org.mytonwallet.app_air.airasframework.AirAsFrameworkApplication

class MTWAirApplication : Application() {
    override fun onCreate() {
        System.loadLibrary("native-utils")

        super.onCreate()

        AirAsFrameworkApplication.onCreate(applicationContext)
    }
}
