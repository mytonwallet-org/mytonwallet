package org.mytonwallet.app;

import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsControllerCompat;

abstract public class BaseActivity extends AppCompatActivity {

  @Override
  public void onCreate(@Nullable Bundle savedInstanceState) {
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
  }

  protected void makeStatusBarTransparent() {
    Window window = getWindow();
    View decorView = window.getDecorView();
    decorView.setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    window.setStatusBarColor(android.graphics.Color.TRANSPARENT);
  }

  protected void makeNavigationBarTransparent() {
    Window window = getWindow();

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      WindowCompat.setDecorFitsSystemWindows(window, false);
      window.setNavigationBarColor(Color.TRANSPARENT);
      window.setNavigationBarContrastEnforced(false);
    } else {
      window.setFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS, WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
    }
  }

  protected void updateStatusBarStyle() {
    String style = ((MTWApplication) getApplicationContext()).getCurrentStatusBar();
    if (style == null || style.equals("DEFAULT"))
      return;

    Window window = getWindow();
    View decorView = window.getDecorView();

    WindowInsetsControllerCompat windowInsetsControllerCompat = WindowCompat.getInsetsController(window, decorView);
    windowInsetsControllerCompat.setAppearanceLightStatusBars(!style.equals("DARK"));
    windowInsetsControllerCompat.setAppearanceLightNavigationBars(!style.equals("DARK"));
  }

}
