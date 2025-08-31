package org.mytonwallet.app;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.app.Activity;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.splashscreen.SplashScreen;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import androidx.interpolator.view.animation.FastOutSlowInInterpolator;

import org.mytonwallet.plugins.air_app_launcher.airLauncher.AirLauncher;
import org.mytonwallet.plugins.air_app_launcher.airLauncher.LaunchConfig;

/*
  Application entry point.
    - Decides to open LegacyActivity or trigger AirLauncher.
    - Only passes deeplink data into active activity and finishes itself if any activities are already open.
    - Plays splash-screen for MTW Air (This flow may be enhanced later)
 */
public class MainActivity extends AppCompatActivity {
  private final int DELAY = 300;
  private boolean keep = true;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    Log.i("MTWAirApplication", "Main Activity Created");
    super.onCreate(savedInstanceState);
    getApplication().setTheme(R.style.AppTheme_NoActionBar);
    setTheme(R.style.AppTheme_NoActionBar);

    int backgroundColor;
    int currentNightMode = getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
    if (currentNightMode == Configuration.UI_MODE_NIGHT_YES) {
      backgroundColor = 0xFF242426;
    } else {
      backgroundColor = 0xFFFFFFFF;
    }
    getWindow().getDecorView().setBackgroundColor(backgroundColor);

    Activity activity = this;
    boolean shouldStartOnAir = LaunchConfig.shouldStartOnAir(activity);

    if (!shouldStartOnAir) {
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
    AirLauncher airLauncher = AirLauncher.getInstance();
    if (airLauncher != null && airLauncher.getIsOnTheAir()) {
      airLauncher.handle(getIntent());
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

    SplashScreen splashScreen = SplashScreen.installSplashScreen(this);
    splashScreen.setKeepOnScreenCondition(() -> keep);
    splashScreen.setOnExitAnimationListener(splashScreenView -> {
      AnimatorSet animationSet = new AnimatorSet();

      View view = splashScreenView.getView();
      ObjectAnimator scaleY = ObjectAnimator.ofFloat(view, View.SCALE_Y, 4f);
      ObjectAnimator scaleX = ObjectAnimator.ofFloat(view, View.SCALE_X, 4f);
      ObjectAnimator opacity = ObjectAnimator.ofFloat(view, View.ALPHA, 0.0f);

      animationSet.setInterpolator(new FastOutSlowInInterpolator());
      animationSet.setDuration(350L);
      animationSet.playTogether(scaleX, scaleY, opacity);

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
    handler.postDelayed(() -> keep = false, DELAY);
  }

  private void splashScreenAnimatedEnded() {
    Log.i("MTWAirApplication", "Splash animation ended");
    updateStatusBarStyle();
    AirLauncher.getInstance().soarIntoAir(false);
  }

  private void makeStatusBarTransparent() {
    Window window = getWindow();
    View decorView = window.getDecorView();
    decorView.setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    window.setStatusBarColor(android.graphics.Color.TRANSPARENT);
  }

  private void makeNavigationBarTransparent() {
    Window window = getWindow();

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      WindowCompat.setDecorFitsSystemWindows(window, false);
      window.setNavigationBarColor(Color.TRANSPARENT);
      window.setNavigationBarContrastEnforced(false);
    } else {
      window.setFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS, WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
    }
  }

  private void updateStatusBarStyle() {
    String style = ((MTWApplication) getApplicationContext()).getCurrentStatusBar();
    if (style == null || style.equals("DEFAULT"))
      return;

    Window window = getWindow();
    View decorView = window.getDecorView();

    WindowInsetsControllerCompat windowInsetsControllerCompat = WindowCompat.getInsetsController(window, decorView);
    windowInsetsControllerCompat.setAppearanceLightStatusBars(!style.equals("DARK"));
    windowInsetsControllerCompat.setAppearanceLightNavigationBars(!style.equals("DARK"));
  }

  @Override
  protected void onNewIntent(@NonNull Intent intent) {
    super.onNewIntent(intent);
  }
}
