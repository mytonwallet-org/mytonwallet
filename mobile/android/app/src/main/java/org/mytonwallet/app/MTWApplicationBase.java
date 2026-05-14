package org.mytonwallet.app;

import android.app.Application;

import org.mytonwallet.plugins.air_app_launcher.airLauncher.AirLauncher;

public abstract class MTWApplicationBase extends Application {

  private String currentStatusBar;

  @Override
  public void onCreate() {
    super.onCreate();
    AirLauncher.scheduleWidgetUpdates(getApplicationContext());
  }

  // Used by LegacyActivity (mytonwallet flavor) to mirror Capacitor's
  // StatusBar plugin into the host. Set via the mytonwallet-flavor subclass's
  // StatusBarPluginDelegate hook; always null on gram (no Capacitor /
  // no LegacyActivity).
  public String getCurrentStatusBar() {
    return currentStatusBar;
  }

  protected void setCurrentStatusBar(String newStatusBar) {
    currentStatusBar = newStatusBar;
  }
}
