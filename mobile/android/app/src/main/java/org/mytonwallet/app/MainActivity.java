package org.mytonwallet.app;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.webkit.WebView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.core.splashscreen.SplashScreen;
import androidx.webkit.WebViewCompat;

import org.mytonwallet.app_air.airasframework.airLauncher.AirLauncher;
import org.mytonwallet.app_air.airasframework.airLauncher.LaunchConfig;

/*
  Application entry point.
    - Triggers AirLauncher.
    - Only passes deeplink data into active activity and finishes itself if any activities are already open.
    - Plays splash-screen for MTW Air (This flow may be enhanced later)
 */
public class MainActivity extends BaseActivity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    Log.i("MTWAirApplication", "Main Activity Created");
    boolean shouldAnimateSplash = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
      Build.VERSION.SDK_INT > Build.VERSION_CODES.TIRAMISU;
    SplashScreen splashScreen = shouldAnimateSplash ? SplashScreen.installSplashScreen(this) : null;
    super.onCreate(savedInstanceState);

    if (!isWebViewAvailable()) {
      showWebViewUnavailableDialog();
      return;
    }

    LaunchConfig.recordAppOpened(this);
    Activity activity = this;

    AirLauncher airLauncher = AirLauncher.getInstance();

    // Do not let MainActivity open again if MTW Air is already on, just pass deeplink to handle, if required.
    if (airLauncher != null && airLauncher.getIsOnTheAir()) {
      airLauncher.handle(activity, getIntent());
      finish();
      return;
    }

    makeStatusBarTransparent();
    makeNavigationBarTransparent();

    airLauncher = new AirLauncher(this);
    AirLauncher.setInstance(airLauncher);
    airLauncher.handle(getIntent());
    if (splashScreen != null) {
      splashScreen.setKeepOnScreenCondition(() -> !AirLauncher.getInstance().getIsOnTheAir());
    }
    airLauncher.soarIntoAir(this);
  }

  @Override
  protected void onNewIntent(@NonNull Intent intent) {
    super.onNewIntent(intent);
  }

  private boolean isWebViewAvailable() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      if (WebViewCompat.getCurrentWebViewPackage(this) == null) {
        return false;
      }
    }
    try {
      new WebView(this).destroy();
      return true;
    } catch (Throwable t) {
      Log.e("MTWAirApplication", "WebView unavailable", t);
      return false;
    }
  }

  private void showWebViewUnavailableDialog() {
    new AlertDialog.Builder(this)
      .setTitle("WebView not available")
      .setMessage("This application needs Android System WebView to run. Please install or enable it from the Play Store, then reopen the app.")
      .setCancelable(false)
      .setPositiveButton("Open Play Store", (dialog, which) -> {
        openWebViewInStore();
        finish();
      })
      .setNegativeButton("Close", (dialog, which) -> finish())
      .show();
  }

  private void openWebViewInStore() {
    Intent intent = new Intent(Intent.ACTION_VIEW,
      Uri.parse("market://details?id=com.google.android.webview"));
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    try {
      startActivity(intent);
    } catch (ActivityNotFoundException e) {
      Intent web = new Intent(Intent.ACTION_VIEW,
        Uri.parse("https://play.google.com/store/apps/details?id=com.google.android.webview"));
      web.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      try {
        startActivity(web);
      } catch (ActivityNotFoundException ignored) {
      }
    }
  }
}
