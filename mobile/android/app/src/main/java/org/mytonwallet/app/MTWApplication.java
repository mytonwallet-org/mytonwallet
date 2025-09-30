package org.mytonwallet.app;

import android.app.Application;

import com.capacitorjs.plugins.statusbar.StatusBarPluginDelegate;

import org.mytonwallet.plugins.air_app_launcher.airLauncher.AirLauncher;

public class MTWApplication extends Application implements StatusBarPluginDelegate {

  private String currentStatusBar;

  @Override
  public void onCreate() {
    super.onCreate();
    System.loadLibrary("native-utils");
    AirLauncher.scheduleWidgetUpdates(getApplicationContext());
  }

  @Override
  public void didUpdateStatusBar(String newStatusBar) {
    currentStatusBar = newStatusBar;
  }

  public String getCurrentStatusBar() {
    return currentStatusBar;
  }
}
