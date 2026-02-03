package org.mytonwallet.app_air.walletcontext.helpers;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;

import androidx.core.content.pm.PackageInfoCompat;

import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage;

public class LaunchConfig {

    private static final String LAUNCHER_PREF_NAME = "Launcher";
    private static final String LAUNCHER_PREF_START_ON_AIR_KEY = "isOnAir";
    private static final String LAUNCHER_PREF_FIRST_LAUNCH_DATE_KEY = "firstLaunchDate";
    private static final String LAUNCHER_PREF_LAST_LAUNCH_DATE_KEY = "lastLaunchDate";
    private static final String LAUNCHER_PREF_FIRST_LAUNCH_VERSION_KEY = "firstLaunchVersion";
    private static final String LAUNCHER_PREF_LAST_LAUNCH_VERSION_KEY = "lastLaunchVersion";

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
        editor.apply();
    }

    public static void recordAppOpened(Context context) {
        long currentTime = System.currentTimeMillis();
        String versionString = getVersionString(context);

        SharedPreferences prefs = context.getSharedPreferences(
            LAUNCHER_PREF_NAME,
            Context.MODE_PRIVATE
        );
        SharedPreferences.Editor editor = prefs.edit();

        boolean isFirstLaunch = !prefs.contains(LAUNCHER_PREF_FIRST_LAUNCH_DATE_KEY);
        if (isFirstLaunch) {
            editor.putLong(LAUNCHER_PREF_FIRST_LAUNCH_DATE_KEY, currentTime);
            editor.putString(LAUNCHER_PREF_FIRST_LAUNCH_VERSION_KEY, versionString);
        }
        editor.putLong(LAUNCHER_PREF_LAST_LAUNCH_DATE_KEY, currentTime);
        editor.putString(LAUNCHER_PREF_LAST_LAUNCH_VERSION_KEY, versionString);
        editor.apply();
    }

    public static String getVersionString(Context context) {
        return getVersionName(context) + "-" + getBuildNumber(context);
    }

    private static PackageInfo getPackageInfo(Context context) {
        try {
            return context.getPackageManager()
                .getPackageInfo(context.getPackageName(), 0);
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    public static String getVersionName(Context context) {
        PackageInfo packageInfo = getPackageInfo(context);
        return packageInfo != null && packageInfo.versionName != null
            ? packageInfo.versionName : "";
    }

    public static String getBuildNumber(Context context) {
        PackageInfo packageInfo = getPackageInfo(context);
        return packageInfo != null
            ? String.valueOf(PackageInfoCompat.getLongVersionCode(packageInfo)) : "";
    }
}
