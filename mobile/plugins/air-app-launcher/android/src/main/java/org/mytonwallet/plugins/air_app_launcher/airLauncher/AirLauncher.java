package org.mytonwallet.plugins.air_app_launcher.airLauncher;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.util.Log;
import android.view.ViewGroup;

import org.mytonwallet.app_air.airasframework.AirAsFrameworkApplication;
import org.mytonwallet.app_air.airasframework.MainWindow;
import org.mytonwallet.app_air.airasframework.splash.SplashVC;
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider;
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink;
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkNavigator;
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkParser;

public class AirLauncher {
  private static final int PENDING_SOAR_NO = 0;
  private static final int PENDING_SOAR_FROM_LEGACY = 1;
  private static final int PENDING_SOAR = 2;
  @SuppressLint("StaticFieldLeak")
  private static AirLauncher airLauncher;
  private final Activity activity;
  int pendingSoarIntoAir = PENDING_SOAR_NO;
  private boolean isOnTheAir = false;
  private CapacitorGlobalStorageProvider capacitorGlobalStorageProvider;
  private boolean storageProviderReady = false;

  public AirLauncher(Activity activity) {
    this.activity = activity;
    initGlobalStorageProvider();
  }

  public static AirLauncher getInstance() {
    return airLauncher;
  }

  public static void setInstance(AirLauncher instance) {
    airLauncher = instance;
  }

  private void initGlobalStorageProvider() {
    Context applicationContext = activity.getApplicationContext();
    Log.i("MTWAirApplication", "Initializing CapacitorGlobalStorageProvider");

    capacitorGlobalStorageProvider = new CapacitorGlobalStorageProvider(applicationContext, success -> {
      Log.i("MTWAirApplication", "CapacitorGlobalStorageProvider Initialized");
      storageProviderReady = true;
      AirAsFrameworkApplication.Companion.onCreate(
        applicationContext,
        capacitorGlobalStorageProvider,
        (ViewGroup) activity.getWindow().getDecorView().getRootView()
      );
      if (pendingSoarIntoAir != PENDING_SOAR_NO)
        soarIntoAir(pendingSoarIntoAir == PENDING_SOAR_FROM_LEGACY);
    });
  }

  public boolean getIsOnTheAir() {
    return isOnTheAir;
  }

  public void soarIntoAir(Boolean fromLegacy) {
    if (isOnTheAir)
      return;

    if (!storageProviderReady) {
      pendingSoarIntoAir = fromLegacy ? PENDING_SOAR_FROM_LEGACY : PENDING_SOAR;
      return;
    }
    pendingSoarIntoAir = PENDING_SOAR_NO;

    isOnTheAir = true;

    if (fromLegacy) {
      capacitorGlobalStorageProvider.setEmptyObject("tokenPriceHistory.bySlug", IGlobalStorageProvider.PERSIST_NO);
      LaunchConfig.setShouldStartOnAir(activity, true);
    }

    Log.i("MTWAirApplication", "CapacitorGlobalStorageProvider Ready — Opening Air");
    openAir();
  }

  private void openAir() {
    Intent intent = new Intent(activity, MainWindow.class);
    intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);
    activity.startActivity(intent);
    activity.finish();
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
