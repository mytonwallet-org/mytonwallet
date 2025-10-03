package org.mytonwallet.plugins.air_app_launcher.airLauncher;

import android.app.Activity;
import android.appwidget.AppWidgetManager;
import android.content.Context;
import android.content.Intent;
import android.util.Log;
import android.view.ViewGroup;

import org.mytonwallet.app_air.airasframework.AirAsFrameworkApplication;
import org.mytonwallet.app_air.airasframework.MainWindow;
import org.mytonwallet.app_air.airasframework.WidgetConfigurationWindow;
import org.mytonwallet.app_air.airasframework.splash.SplashVC;
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations;
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider;
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage;
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage;
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink;
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkNavigator;
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkParser;

abstract class PendingTask {
  private PendingTask() {
  }

  public static final class ToAir extends PendingTask {
    private final boolean fromLegacy;

    public ToAir(boolean fromLegacy) {
      this.fromLegacy = fromLegacy;
    }

    public boolean isFromLegacy() {
      return fromLegacy;
    }
  }

  public static final class ToWidgetConfigurations extends PendingTask {
    private final int requestCode;
    private final int appWidgetId;

    public ToWidgetConfigurations(int requestCode, int appWidgetId) {
      this.requestCode = requestCode;
      this.appWidgetId = appWidgetId;
    }

    public int getRequestCode() {
      return requestCode;
    }

    public int getAppWidgetId() {
      return appWidgetId;
    }
  }
}

public class AirLauncher {
  private static AirLauncher airLauncher;
  private final Context applicationContext;
  PendingTask pendingAirTask;
  private boolean isOnTheAir = false;
  private CapacitorGlobalStorageProvider capacitorGlobalStorageProvider;
  private boolean storageProviderReady = false;

  public AirLauncher(Activity currentActivity) {
    this.applicationContext = currentActivity.getApplicationContext();
    initGlobalStorageProvider(currentActivity);
  }

  public static AirLauncher getInstance() {
    return airLauncher;
  }

  public static void setInstance(AirLauncher instance) {
    airLauncher = instance;
  }

  public static void scheduleWidgetUpdates(Context applicationContext) {
    WidgetsConfigurations.INSTANCE.scheduleWidgetUpdates(applicationContext);
  }

  public static void reloadWidgets(Context applicationContext) {
    WidgetsConfigurations.INSTANCE.reloadWidgets(applicationContext);
  }

  private void initGlobalStorageProvider(Activity currentActivity) {
    Log.i("MTWAirApplication", "Initializing CapacitorGlobalStorageProvider");

    capacitorGlobalStorageProvider = new CapacitorGlobalStorageProvider(applicationContext, success -> {
      Log.i("MTWAirApplication", "CapacitorGlobalStorageProvider Initialized");
      storageProviderReady = true;
      AirAsFrameworkApplication.Companion.onCreate(
        applicationContext,
        capacitorGlobalStorageProvider,
        // The bridge will be moved to MainWindow's view after it has been presented.
        (ViewGroup) currentActivity.getWindow().getDecorView().getRootView()
      );
      if (pendingAirTask != null) {
        if (pendingAirTask instanceof PendingTask.ToAir task) {
          soarIntoAir(currentActivity, task.isFromLegacy());
        } else if (pendingAirTask instanceof PendingTask.ToWidgetConfigurations task) {
          presentWidgetConfiguration(currentActivity, task.getRequestCode(), task.getAppWidgetId());
        }
        pendingAirTask = null;
      }
    });
  }

  public boolean getIsOnTheAir() {
    return isOnTheAir;
  }

  public void switchingToClassic() {
    isOnTheAir = false;
  }

  public void soarIntoAir(Activity currentActivity, Boolean fromLegacy) {
    if (isOnTheAir)
      return;

    if (!storageProviderReady) {
      pendingAirTask = new PendingTask.ToAir(fromLegacy);
      return;
    }
    pendingAirTask = null;

    isOnTheAir = true;

    if (fromLegacy) {
      capacitorGlobalStorageProvider.setEmptyObject("tokenPriceHistory.bySlug", IGlobalStorageProvider.PERSIST_NO);
      LaunchConfig.setShouldStartOnAir(currentActivity, true);
      // Just-in-case. These might contain outdated data after adding widget when using Classic app!
      WSecureStorage.INSTANCE.clearCache();
      WGlobalStorage.INSTANCE.clearCachedData();
    }

    Log.i("MTWAirApplication", "CapacitorGlobalStorageProvider Ready — Opening Air");
    openAir(currentActivity);
  }

  public void presentWidgetConfiguration(Activity currentActivity, int requestCode, int appWidgetId) {
    if (!storageProviderReady) {
      pendingAirTask = new PendingTask.ToWidgetConfigurations(requestCode, appWidgetId);
      return;
    }

    Intent intent = new Intent(currentActivity, WidgetConfigurationWindow.class);
    intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId);
    intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);
    currentActivity.startActivityForResult(intent, requestCode);
  }

  private void openAir(Activity currentActivity) {
    Intent intent = new Intent(currentActivity, MainWindow.class);
    intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);
    currentActivity.startActivity(intent);
    currentActivity.finish();
  }

  public void handle(Intent intent) {
    Deeplink deeplink = DeeplinkParser.Companion.parse(intent);
    if (deeplink != null) {
      DeeplinkNavigator deeplinkNavigator = SplashVC.Companion.getSharedInstance();
      if (deeplinkNavigator != null) {
        deeplinkNavigator.handle(deeplink);
      } else {
        SplashVC.Companion.setPendingDeeplink(deeplink);
      }
    }
  }

}
