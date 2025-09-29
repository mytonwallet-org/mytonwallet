package org.mytonwallet.plugins.air_app_launcher;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;

import androidx.webkit.WebViewCompat;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations;
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage;
import org.mytonwallet.plugins.air_app_launcher.airLauncher.AirLauncher;

@CapacitorPlugin(name = "AirAppLauncher")
public class AirAppLauncherPlugin extends Plugin {

  private AirLauncher airLauncher;

  public boolean isChromeVersionSupported(Context context) {
    PackageInfo webViewPackage = WebViewCompat.getCurrentWebViewPackage(context);

    if (webViewPackage != null) {
      String versionName = webViewPackage.versionName;
      String majorStr = versionName.split("\\.")[0];
      int majorVersion = Integer.parseInt(majorStr);

      return majorVersion >= 86;
    }
    return false;
  }

  @PluginMethod
  public void switchToAir(PluginCall call) {
    new Handler(Looper.getMainLooper()).post(() -> {
      if (!isChromeVersionSupported(getActivity())) {
        Toast.makeText(getActivity(), "MyTonWallet Air needs Chrome 86+ to work.", Toast.LENGTH_SHORT).show();
        return;
      }
      if (airLauncher == null)
        airLauncher = new AirLauncher(getActivity());
      AirLauncher.setInstance(airLauncher);
      airLauncher.soarIntoAir(getActivity(), true);
    });
  }

  @PluginMethod
  public void setLanguage(PluginCall call) {
    new Handler(Looper.getMainLooper()).post(() -> {
      WBaseStorage.INSTANCE.init(getActivity());
      WBaseStorage.INSTANCE.setActiveLanguage(call.getString("langCode"));
      WidgetsConfigurations.INSTANCE.reloadWidgets(getActivity());
    });
  }

  @PluginMethod
  public void setBaseCurrency(PluginCall call) {
    new Handler(Looper.getMainLooper()).post(() -> {
      WBaseStorage.INSTANCE.init(getActivity());
      WBaseStorage.INSTANCE.setBaseCurrency(call.getString("currency"));
      WidgetsConfigurations.INSTANCE.reloadWidgets(getActivity());
    });
  }
}
