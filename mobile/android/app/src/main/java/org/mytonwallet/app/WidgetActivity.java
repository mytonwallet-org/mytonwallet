package org.mytonwallet.app;

import android.app.ComponentCaller;
import android.appwidget.AppWidgetManager;
import android.content.Intent;
import android.content.res.Configuration;
import android.os.Bundle;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.mytonwallet.plugins.air_app_launcher.airLauncher.AirLauncher;

import java.util.Objects;

public class WidgetActivity extends BaseActivity {
  private static final int CONFIGURATION_REQUEST = 12;
  private static final String IS_CONFIGURING_KEY = "isConfiguring";
  int appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID;

  @Override
  public void onCreate(@Nullable Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    int backgroundColor;
    int currentNightMode = getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
    if (currentNightMode == Configuration.UI_MODE_NIGHT_YES) {
      backgroundColor = 0xFF181818;
    } else {
      backgroundColor = 0xFFF4F4F5;
    }
    getWindow().getDecorView().setBackgroundColor(backgroundColor);

    setResult(RESULT_CANCELED);

    AirLauncher airLauncher = AirLauncher.getInstance();
    if (airLauncher == null) {
      airLauncher = new AirLauncher(this);
      AirLauncher.setInstance(airLauncher);
    }

    Bundle extras = getIntent().getExtras();
    if (extras != null) {
      appWidgetId = extras.getInt(
        AppWidgetManager.EXTRA_APPWIDGET_ID,
        AppWidgetManager.INVALID_APPWIDGET_ID
      );
    }

    if (savedInstanceState != null && savedInstanceState.getBoolean(IS_CONFIGURING_KEY)) {
      finalizeWidget();
      return;
    }

    if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
      finish();
      return;
    }

    airLauncher.presentWidgetConfiguration(this, CONFIGURATION_REQUEST, appWidgetId);
  }

  @Override
  protected void onSaveInstanceState(@NonNull Bundle outState) {
    super.onSaveInstanceState(outState);
    outState.putBoolean(IS_CONFIGURING_KEY, true);
  }

  @Override
  protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
    super.onActivityResult(requestCode, resultCode, data);
    onResult(requestCode, resultCode, data);
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode, @Nullable Intent data, @NonNull ComponentCaller caller) {
    super.onActivityResult(requestCode, resultCode, data, caller);
    onResult(requestCode, resultCode, data);
  }

  private void onResult(int requestCode, int resultCode, @Nullable Intent data) {
    if (requestCode == CONFIGURATION_REQUEST && resultCode == RESULT_OK) {
      boolean ok = Objects.requireNonNull(data).getBooleanExtra("ok", false);
      if (ok)
        finalizeWidget();
      else
        finish();
    } else {
      finish();
    }
  }

  private void finalizeWidget() {
    AirLauncher.scheduleWidgetUpdates(getApplicationContext());

    Intent resultValue = new Intent();
    resultValue.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId);
    setResult(RESULT_OK, resultValue);
    finish();
  }
}
