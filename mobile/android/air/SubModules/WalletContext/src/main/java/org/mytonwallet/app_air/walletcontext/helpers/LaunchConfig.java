package org.mytonwallet.app_air.walletcontext.helpers;

import android.content.Context;
import android.content.SharedPreferences;

import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage;

public class LaunchConfig {

    private static final String LAUNCHER_PREF_NAME = "Launcher";
    private static final String LAUNCHER_PREF_START_ON_AIR_KEY = "isOnAir";

    public static boolean shouldStartOnAir(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(
            LAUNCHER_PREF_NAME,
            Context.MODE_PRIVATE
        );
        if (!prefs.contains(LAUNCHER_PREF_START_ON_AIR_KEY)) {
            WSecureStorage.INSTANCE.init(context);
            boolean isFreshInstall = WSecureStorage.INSTANCE.isFreshInstall();
            setShouldStartOnAir(context, isFreshInstall);
        }
        return prefs.getBoolean(LAUNCHER_PREF_START_ON_AIR_KEY, false);
    }

    public static void setShouldStartOnAir(Context context, boolean newValue) {
        SharedPreferences.Editor editor = context.getSharedPreferences(
            LAUNCHER_PREF_NAME,
            Context.MODE_PRIVATE
        ).edit();
        editor.putBoolean(LAUNCHER_PREF_START_ON_AIR_KEY, newValue);
        editor.apply(); // asynchronous save (similar to Kotlin’s `edit { }`)
    }
}
