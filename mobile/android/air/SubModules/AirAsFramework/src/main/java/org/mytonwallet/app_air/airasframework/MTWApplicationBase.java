package org.mytonwallet.app_air.airasframework;

import android.app.Application;

import org.mytonwallet.app_air.airasframework.airLauncher.AirLauncher;
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications;

public abstract class MTWApplicationBase extends Application {

    @Override
    public void onCreate() {
        super.onCreate();
        AirPushNotifications.disableNotificationDelegation(this);
        AirLauncher.scheduleWidgetUpdates(getApplicationContext());
    }
}
