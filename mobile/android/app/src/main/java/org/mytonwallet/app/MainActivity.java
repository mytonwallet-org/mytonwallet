package org.mytonwallet.app;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;
import android.view.View;
import android.webkit.WebView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.core.splashscreen.SplashScreen;
import androidx.interpolator.view.animation.FastOutSlowInInterpolator;
import androidx.webkit.WebViewCompat;

import org.mytonwallet.plugins.air_app_launcher.airLauncher.AirLauncher;
import org.mytonwallet.plugins.air_app_launcher.airLauncher.LaunchConfig;

/*
  Application entry point.
    - Decides to open LegacyActivity or trigger AirLauncher.
    - Only passes deeplink data into active activity and finishes itself if any activities are already open.
    - Plays splash-screen for MTW Air (This flow may be enhanced later)
 */
public class MainActivity extends BaseActivity {
  private final int DELAY = 300;
  private boolean keep = true;

  @Override
  public void onCreate(Bundle savedInstanceState) {
    Log.i("MTWAirApplication", "Main Activity Created");
    super.onCreate(savedInstanceState);

    if (!isWebViewAvailable()) {
      showWebViewUnavailableDialog();
      return;
    }

    LaunchConfig.recordAppOpened(this);
    Activity activity = this;
    boolean shouldStartOnAir = LaunchConfig.shouldStartOnAir(activity);

    AirLauncher airLauncher = AirLauncher.getInstance();
    if (!shouldStartOnAir) {
      if (airLauncher != null) {
        airLauncher.switchingToClassic();
        AirLauncher.setInstance(null);
      }
      // Open LegacyActivity and pass all the data there
      Intent intent = new Intent(activity, LegacyActivity.class);
      intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
      intent.setAction(getIntent().getAction());
      intent.setData(getIntent().getData());
      if (getIntent().getExtras() != null)
        intent.putExtras(getIntent().getExtras());
      activity.startActivity(intent);
      overridePendingTransition(0, 0);
      activity.finish();
      return;
    }

    // Do not let MainActivity open again if MTW Air is already on, just pass deeplink to handle, if required.
    if (airLauncher != null && airLauncher.getIsOnTheAir()) {
      airLauncher.handle(activity, getIntent());
      finish();
      return;
    }

    makeStatusBarTransparent();
    makeNavigationBarTransparent();
    updateStatusBarStyle();

    airLauncher = new AirLauncher(this);
    AirLauncher.setInstance(airLauncher);
    airLauncher.handle(getIntent());

    // Splash-Screen doesn't work as expected on Android 12
    if (Build.VERSION.SDK_INT == Build.VERSION_CODES.S) {
      splashScreenAnimatedEnded();
      return;
    }

    boolean isGramApp = getPackageName().startsWith("io.gramwallet.");
    SplashScreen splashScreen = SplashScreen.installSplashScreen(this);
    splashScreen.setKeepOnScreenCondition(() -> keep);
    splashScreen.setOnExitAnimationListener(splashScreenView -> {
      AnimatorSet animationSet = new AnimatorSet();

      View view = splashScreenView.getView();
      ObjectAnimator opacity = ObjectAnimator.ofFloat(view, View.ALPHA, 0.0f);

      animationSet.setInterpolator(new FastOutSlowInInterpolator());
      if (isGramApp) {
        animationSet.setDuration(200L);
        animationSet.playTogether(opacity);
      } else {
        ObjectAnimator scaleY = ObjectAnimator.ofFloat(view, View.SCALE_Y, 4f);
        ObjectAnimator scaleX = ObjectAnimator.ofFloat(view, View.SCALE_X, 4f);
        animationSet.setDuration(350L);
        animationSet.playTogether(scaleX, scaleY, opacity);
      }

      animationSet.addListener(new AnimatorListenerAdapter() {
        @Override
        public void onAnimationEnd(Animator animation) {
          splashScreenView.remove();
          splashScreenAnimatedEnded();
        }
      });

      animationSet.start();
    });

    Handler handler = new Handler();
    handler.postDelayed(() -> keep = false, isGramApp ? 0L : DELAY);
  }

  private void splashScreenAnimatedEnded() {
    Log.i("MTWAirApplication", "Splash animation ended");
    updateStatusBarStyle();
    AirLauncher.getInstance().soarIntoAir(this, false);
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
