package org.mytonwallet.app_air.airasframework;

import android.app.Application;

import org.mytonwallet.app_air.airasframework.airLauncher.AirLauncher;

public abstract class MTWApplicationBase extends Application {

    @Override
    public void onCreate() {
        super.onCreate();
        AirLauncher.scheduleWidgetUpdates(getApplicationContext());
    }
}
