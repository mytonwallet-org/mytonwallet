package org.mytonwallet.plugins.air_app_launcher.airLauncher;

import android.content.Context;

public class LaunchConfig {

  public static boolean shouldStartOnAir(Context context) {
    return org.mytonwallet.app_air.walletcontext.helpers.LaunchConfig.shouldStartOnAir(context);
  }

  public static void setShouldStartOnAir(Context context, boolean newValue) {
    org.mytonwallet.app_air.walletcontext.helpers.LaunchConfig.setShouldStartOnAir(context, newValue);
  }
}
