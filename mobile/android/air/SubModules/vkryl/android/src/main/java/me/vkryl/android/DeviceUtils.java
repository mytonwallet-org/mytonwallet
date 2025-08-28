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

import android.app.Activity;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Build;

public final class DeviceUtils {
  private DeviceUtils () { }

  /**
   * Detects if app is currently running on emulator, or real device.
   * @return 0 if current device is a real device, non-zero value in other cases
   */
  public static long detectEmulator (Activity activity, boolean allowUnsafe) {
    final Context context = activity.getApplicationContext();
    return EmulatorDetector.runTests(context, allowUnsafe);
  }

  @SuppressWarnings("deprecation")
  public static boolean isApplicationInstalled (Context context, String packageName, boolean allowPastInstallations) {
    try {
      int flags = 0;
      if (allowPastInstallations) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
          flags |= PackageManager.MATCH_UNINSTALLED_PACKAGES;
        } else {
          flags |= PackageManager.GET_UNINSTALLED_PACKAGES;
        }
      }
      ApplicationInfo info = context.getPackageManager().getApplicationInfo(packageName, flags);
      return info != null;
    } catch (Throwable t) {
      return false;
    }
  }

  public static boolean isTestLabDevice (Context context) {
    try {
      String testLabSetting = android.provider.Settings.System.getString(context.getContentResolver(), "firebase.test.lab");
      return "true".equals(testLabSetting);
    } catch (Throwable ignored) { }
    return false;
  }
}
