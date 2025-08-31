/*
 * This file is a part of X-Android
 * Copyright © Vyacheslav Krylov 2014
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package me.vkryl.android;

import android.content.Context;
import android.os.Build;

import androidx.annotation.IntDef;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

import me.vkryl.core.StringUtils;

public class AppInstallationUtil {
  public static final String
    VENDOR_GOOGLE_PLAY = "com.android.vending",
    VENDOR_GALAXY_STORE = "com.sec.android.app.samsungapps",
    VENDOR_HUAWEI_APPGALLERY = "com.huawei.appmarket",
    VENDOR_AMAZON_APPSTORE = "com.amazon.venezia",
    VENDOR_MEMU_PLAYER_1 = "com.microvirt.download",
    VENDOR_MEMU_PLAYER_2 = "com.microvirt.tools";

  @Retention(RetentionPolicy.SOURCE)
  @IntDef({
    InstallerId.UNKNOWN,
    InstallerId.GOOGLE_PLAY,
    InstallerId.GALAXY_STORE,
    InstallerId.HUAWEI_APPGALLERY,
    InstallerId.AMAZON_APPSTORE,
    InstallerId.MEMU_EMULATOR
  })
  public @interface InstallerId {
    int
      UNKNOWN = 0,
      GOOGLE_PLAY = 1,
      GALAXY_STORE = 2,
      HUAWEI_APPGALLERY = 3,
      AMAZON_APPSTORE = 4,
      MEMU_EMULATOR = 5
    ;
  }

  private static Integer installerId;

  public static synchronized @InstallerId int getInstallerId (Context context) {
    if (installerId == null) {
      installerId = getInstallerIdImpl(context);
    }
    return installerId;
  }

  private static @InstallerId int toInstallerId (String packageName) {
    if (!StringUtils.isEmpty(packageName)) {
      //noinspection ConstantConditions
      switch (packageName) {
        case VENDOR_GOOGLE_PLAY:
          return InstallerId.GOOGLE_PLAY;
        case VENDOR_GALAXY_STORE:
          return InstallerId.GALAXY_STORE;
        case VENDOR_HUAWEI_APPGALLERY:
          return InstallerId.HUAWEI_APPGALLERY;
        case VENDOR_AMAZON_APPSTORE:
          return InstallerId.AMAZON_APPSTORE;
        case VENDOR_MEMU_PLAYER_1:
        case VENDOR_MEMU_PLAYER_2:
          return InstallerId.MEMU_EMULATOR;
      }
    }
    return InstallerId.UNKNOWN;
  }

  private static @InstallerId int getInstallerIdImpl (Context context) {
    final String installerPackageName = getInstallerPackageName(context);
    return toInstallerId(installerPackageName);
  }

  // Checks initiator and installer id for current app installation

  @Nullable
  public static String getInitiatorPackageName (Context context) {
    final String packageName = context.getPackageName();
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      try {
        android.content.pm.InstallSourceInfo sourceInfo = context.getPackageManager().getInstallSourceInfo(packageName);
        String initiatingId = sourceInfo.getInitiatingPackageName();
        if (!StringUtils.isEmpty(initiatingId)) {
          return initiatingId;
        }
      } catch (Throwable t) {
        android.util.Log.e("x-core", "Unable to determine initiator package name", t);
        t.printStackTrace();
      }
    }
    return null;
  }

  @Nullable
  @SuppressWarnings("deprecation")
  public static String getInstallerPackageName (Context context) {
    final String packageName = context.getPackageName();
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      try {
        android.content.pm.InstallSourceInfo sourceInfo = context.getPackageManager().getInstallSourceInfo(packageName);
        String installerId = sourceInfo.getInstallingPackageName();
        if (!StringUtils.isEmpty(installerId)) {
          return installerId;
        }
        String initiatingId = sourceInfo.getInitiatingPackageName();
        if (!StringUtils.isEmpty(initiatingId)) {
          return initiatingId;
        }
      } catch (Throwable t) {
        android.util.Log.e("x-core", "Unable to determine installer package via modern API", t);
        t.printStackTrace();
      }
    }
    try {
      String installerPackageName = context.getPackageManager().getInstallerPackageName(packageName);
      if (StringUtils.isEmpty(installerPackageName)) {
        return null;
      }
      return installerPackageName;
    } catch (Throwable t) {
      android.util.Log.e("x-core", "Unable to determine installer package", t);
      return null;
    }
  }

  @NonNull
  public static String prettifyPackageName (@NonNull String packageName) {
    @InstallerId int installerId = toInstallerId(packageName);
    switch (installerId) {
      case InstallerId.UNKNOWN:
        return packageName;
      case InstallerId.GOOGLE_PLAY:
        return "Google Play";
      case InstallerId.GALAXY_STORE:
        return "Galaxy Store";
      case InstallerId.HUAWEI_APPGALLERY:
        return "Huawei AppGallery";
      case InstallerId.AMAZON_APPSTORE:
        return "Amazon AppStore";
      case InstallerId.MEMU_EMULATOR:
        return "MEmu Emulator";
    }
    throw new UnsupportedOperationException();
  }

  // Checks whether app is installed from unofficial source (e.g. directly via an APK)

  public static boolean isAppSideLoaded (Context context) {
    //noinspection SwitchIntDef
    switch (getInstallerId(context)) {
      case InstallerId.UNKNOWN:
      case InstallerId.MEMU_EMULATOR:
        return true;
    }
    return false;
  }

  // Checks whether app is installed by emulator software

  public static boolean isInstalledByEmulatorSoftware (Context context) {
    return getInstallerId(context) == InstallerId.MEMU_EMULATOR;
  }

  // Do not allow in-app updates from Google Play, if we are installed from market that doesn't allow it

  public static boolean allowInAppGooglePlayUpdates (Context context) {
    switch (getInstallerId(context)) {
      case InstallerId.UNKNOWN:
      case InstallerId.GOOGLE_PLAY:
      case InstallerId.MEMU_EMULATOR: {
        //noinspection ObsoleteSdkInt
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP;
      }
      case InstallerId.GALAXY_STORE:
      case InstallerId.HUAWEI_APPGALLERY:
      case InstallerId.AMAZON_APPSTORE:
        return false;
      default:
        throw new UnsupportedOperationException();
    }
  }

  // Do not allow in-app updates via Telegram channel, unless it's a direct APK installation

  public static boolean allowInAppTelegramUpdates (Context context) {
    switch (getInstallerId(context)) {
      case InstallerId.UNKNOWN:
      case InstallerId.MEMU_EMULATOR:
        return true;

      case InstallerId.AMAZON_APPSTORE:
      case InstallerId.GALAXY_STORE:
      case InstallerId.GOOGLE_PLAY:
      case InstallerId.HUAWEI_APPGALLERY:
        return false;

      default:
        throw new UnsupportedOperationException();
    }
  }

  // Do not allow non-store URLs for compliance

  public static class DownloadUrl {
    public final @InstallerId int installerId;
    public final String url;

    public DownloadUrl (String url) {
      this(AppInstallationUtil.InstallerId.UNKNOWN, url);
    }

    public DownloadUrl (int installerId, String url) {
      this.installerId = installerId;
      this.url = url;
    }
  }

  public static class PublicMarketUrls {
    public final String defaultDownloadUrl;
    public final String googlePlayUrl;
    public final String galaxyStoreUrl;
    public final String huaweiAppGalleryUrl;
    public final String amazonAppStoreUrl;

    public PublicMarketUrls (String defaultDownloadUrl,
                             String googlePlayUrl,
                             String galaxyStoreUrl,
                             String huaweiAppGalleryUrl,
                             String amazonAppStoreUrl) {
      this.defaultDownloadUrl = defaultDownloadUrl;
      this.googlePlayUrl = googlePlayUrl;
      this.galaxyStoreUrl = galaxyStoreUrl;
      this.huaweiAppGalleryUrl = huaweiAppGalleryUrl;
      this.amazonAppStoreUrl = amazonAppStoreUrl;
    }

    public DownloadUrl toDownloadUrl (@InstallerId int installerId, @Nullable String serverSuggestedDownloadUrl) {
      switch (installerId) {
        case InstallerId.UNKNOWN: // primary distribution channel, no need to force URL.
        case InstallerId.MEMU_EMULATOR:
          break;
        case InstallerId.GOOGLE_PLAY:
          if (!StringUtils.isEmpty(googlePlayUrl)) {
            return new DownloadUrl(installerId, googlePlayUrl);
          }
          break;

        case InstallerId.GALAXY_STORE:
          if (!StringUtils.isEmpty(galaxyStoreUrl)) {
            return new DownloadUrl(installerId, galaxyStoreUrl);
          }
          break;
        case InstallerId.HUAWEI_APPGALLERY:
          if (!StringUtils.isEmpty(huaweiAppGalleryUrl)) {
            return new DownloadUrl(installerId, huaweiAppGalleryUrl);
          }
          break;
        case InstallerId.AMAZON_APPSTORE:
          if (!StringUtils.isEmpty(amazonAppStoreUrl)) {
            return new DownloadUrl(installerId, amazonAppStoreUrl);
          }
          break;
      }
      if (!StringUtils.isEmpty(serverSuggestedDownloadUrl)) {
        return new DownloadUrl(InstallerId.UNKNOWN, serverSuggestedDownloadUrl);
      }
      if (!StringUtils.isEmpty(defaultDownloadUrl)) {
        return new DownloadUrl(InstallerId.UNKNOWN, defaultDownloadUrl);
      }
      throw new UnsupportedOperationException();
    }
  }
}
