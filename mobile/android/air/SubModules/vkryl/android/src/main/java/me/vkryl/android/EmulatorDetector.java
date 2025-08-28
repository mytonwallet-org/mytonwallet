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

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Build;
import android.os.Environment;
import android.telephony.TelephonyManager;

import androidx.annotation.IntDef;
import androidx.core.content.ContextCompat;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import me.vkryl.core.ArrayUtils;
import me.vkryl.core.BitwiseUtils;
import me.vkryl.core.StringUtils;

class EmulatorDetector {
  private interface Test<T> {
    boolean runTest (T data);
  }

  private static int testDetails;

  static long runTests (Context context, boolean allowUnsafe) {
    List<Test<Context>> advancedTests = new ArrayList<>();
    Collections.addAll(advancedTests,
      DeviceUtils::isTestLabDevice,
      EmulatorDetector::runBasicTests,
      AppInstallationUtil::isInstalledByEmulatorSoftware,
      EmulatorDetector::runPackageNameTest,
      EmulatorDetector::runBstTest,
      EmulatorDetector::runTelephonyTests,
      EmulatorDetector::runPopularEmulatorsTest,
      EmulatorDetector::runQemuDriversTest,
      EmulatorDetector::runPipesTest,
      EmulatorDetector::runX86EmulatorTest,
      EmulatorDetector::runEmuInputDevicesTest
    );
    if (allowUnsafe) {
      advancedTests.add(EmulatorDetector::runIpTest);
    }
    int index = 0;
    for (Test<Context> test : advancedTests) {
      testDetails = 0;
      int testId = ++index;
      try {
        boolean result = test.runTest(context);
        if (result) {
          return BitwiseUtils.mergeLong(testDetails, testId);
        }
      } catch (Throwable ignored) { }
    }
    return 0;
  }

  private static boolean runBasicTests (Context context) {
    int rating = 0;

    if (Build.PRODUCT.contains("sdk") ||
      Build.PRODUCT.contains("Andy") ||
      Build.PRODUCT.contains("ttVM_Hdragon") ||
      Build.PRODUCT.contains("google_sdk") ||
      Build.PRODUCT.contains("Droid4X") ||
      Build.PRODUCT.contains("nox") ||
      Build.PRODUCT.contains("sdk_x86") ||
      Build.PRODUCT.contains("sdk_google") ||
      Build.PRODUCT.contains("vbox86p")) {
      rating++;
    }

    if (Build.MANUFACTURER.equals("unknown") ||
      Build.MANUFACTURER.equals("Genymotion") ||
      Build.MANUFACTURER.contains("Andy") ||
      Build.MANUFACTURER.contains("MIT") ||
      Build.MANUFACTURER.contains("nox") ||
      Build.MANUFACTURER.contains("TiantianVM")){
      rating++;
    }

    if (Build.BRAND.equals("generic") ||
      Build.BRAND.equals("generic_x86") ||
      Build.BRAND.equals("TTVM") ||
      Build.BRAND.contains("Andy")) {
      rating++;
    }

    if (Build.DEVICE.contains("generic") ||
      Build.DEVICE.contains("generic_x86") ||
      Build.DEVICE.contains("Andy") ||
      Build.DEVICE.contains("ttVM_Hdragon") ||
      Build.DEVICE.contains("Droid4X") ||
      Build.DEVICE.contains("nox") ||
      Build.DEVICE.contains("generic_x86_64") ||
      Build.DEVICE.contains("vbox86p")) {
      rating++;
    }

    if (Build.MODEL.equals("sdk") ||
      Build.MODEL.equals("google_sdk") ||
      Build.MODEL.contains("Droid4X") ||
      Build.MODEL.contains("TiantianVM") ||
      Build.MODEL.contains("Andy") ||
      Build.MODEL.equals("Android SDK built for x86_64") ||
      Build.MODEL.equals("Android SDK built for x86")) {
      rating++;
    }

    if (Build.HARDWARE.equals("goldfish") ||
      Build.HARDWARE.equals("vbox86") ||
      Build.HARDWARE.contains("nox") ||
      Build.HARDWARE.contains("ttVM_x86")) {
      rating++;
    }

    if (Build.FINGERPRINT.contains("generic/sdk/generic") ||
      Build.FINGERPRINT.contains("generic_x86/sdk_x86/generic_x86") ||
      Build.FINGERPRINT.contains("Andy") ||
      Build.FINGERPRINT.contains("ttVM_Hdragon") ||
      Build.FINGERPRINT.contains("generic_x86_64") ||
      Build.FINGERPRINT.contains("generic/google_sdk/generic") ||
      Build.FINGERPRINT.contains("vbox86p") ||
      Build.FINGERPRINT.contains("generic/vbox86p/vbox86p")) {
      rating++;
    }

    return rating > 3;
  }

  private static final String[] PACKAGE_NAMES = {
    "com.google.android.launcher.layouts.genymotion",
    "com.bluestacks",
    "com.bignox.app",
    "com.vphone.launcher"
  };

  private static boolean runPackageNameTest (Context context) {
    final PackageManager packageManager = context.getPackageManager();
    for (final String packageName : PACKAGE_NAMES) {
      final Intent tryIntent = packageManager.getLaunchIntentForPackage(packageName);
      if (tryIntent != null) {
        //noinspection QueryPermissionsNeeded
        final List<ResolveInfo> resolveInfos = packageManager.queryIntentActivities(tryIntent, PackageManager.MATCH_DEFAULT_ONLY);
        if (!resolveInfos.isEmpty()) {
          return true;
        }
      }
    }
    return false;
  }

  private static boolean runBstTest (Context context) {
    File sharedFolder = new File(Environment
      .getExternalStorageDirectory().toString()
      + File.separatorChar
      + "windows"
      + File.separatorChar
      + "BstSharedFolder");
    return sharedFolder.exists();
  }

  private static final String[] OPENGL_RENDERERS = {
    "android emulator", "bluestacks", "genymotion",
    "translator", "droid4x", "koplayer", "ldplayer",
    "primeos", "smartgaga"
    // "andy", "nox", "memu", "mumu",
  };

  public static boolean isEmulatedOpenGLRenderer (String renderer) {
    if (StringUtils.isEmpty(renderer)) {
      return false;
    }
    renderer = renderer.toLowerCase();
    for (String knownRenderer : OPENGL_RENDERERS) {
      if (renderer.toLowerCase().contains(knownRenderer)) {
        return true;
      }
    }
    return false;
  }

  private static boolean runTelephonyTests (Context context) {
    if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
      return false;
    }
    PackageManager packageManager = context.getPackageManager();
    if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) {
      return false;
    }

    TelephonyManager telephonyManager = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
    List<Test<TelephonyManager>> tests = Arrays.asList(
      EmulatorDetector::testOperatorName,
      EmulatorDetector::testPhoneNumber,
      EmulatorDetector::testDeviceId,
      EmulatorDetector::testSubscriberId
    );
    int index = 0;
    for (Test<TelephonyManager> test : tests) {
      try {
        boolean result = test.runTest(telephonyManager);
        if (result) {
          testDetails = index;
          return true;
        }
      } catch (Throwable ignored) { }
      index++;
    }
    return false;
  }

  private static final String OPERATOR_NAME = "android";

  private static boolean testOperatorName (TelephonyManager telephonyManager) {
    String operatorName = telephonyManager.getNetworkOperatorName();
    return !StringUtils.isEmpty(operatorName) && OPERATOR_NAME.equals(operatorName);
  }

  private static final String[] PHONE_NUMBERS = {
    "15555215554", "15555215556", "15555215558", "15555215560", "15555215562", "15555215564",
    "15555215566", "15555215568", "15555215570", "15555215572", "15555215574", "15555215576",
    "15555215578", "15555215580", "15555215582", "15555215584"
  };

  @SuppressWarnings("deprecation")
  private static boolean testPhoneNumber (TelephonyManager telephonyManager) {
    //noinspection MissingPermission,HardwareIds
    String phoneNumber = telephonyManager.getLine1Number();
    return !StringUtils.isEmpty(phoneNumber) && ArrayUtils.contains(PHONE_NUMBERS, phoneNumber);
  }

  private static final String[] DEVICE_IDS = {
    "000000000000000",
    "e21833235b6eef10",
    "012345678912345"
  };

  @SuppressWarnings("deprecation")
  private static boolean testDeviceId (TelephonyManager telephonyManager) {
    //noinspection MissingPermission,HardwareIds
    String deviceId = telephonyManager.getDeviceId();
    return !StringUtils.isEmpty(deviceId) && ArrayUtils.contains(DEVICE_IDS, deviceId.toLowerCase());
  }

  private static final String[] SUBSCRIBER_IDS = {
    "310260000000000"
  };

  private static boolean testSubscriberId (TelephonyManager telephonyManager) {
    //noinspection MissingPermission,HardwareIds
    String subscriberId = telephonyManager.getSubscriberId();
    return !StringUtils.isEmpty(subscriberId) && ArrayUtils.contains(SUBSCRIBER_IDS, subscriberId);
  }

  // QEMU Drivers

  private static final String[] QEMU_DRIVERS = {"goldfish"};

  private static boolean runQemuDriversTest (Context context) {
    File[] driverFiles = new File[] {
      new File("/proc/tty/drivers"),
      new File("/proc/cpuinfo")
    };
    for (File driverFile : driverFiles) {
      if (driverFile.exists() && driverFile.canRead()) {
        byte[] data = new byte[1024];
        try (InputStream is = new FileInputStream(driverFile)) {
          int bytesRead;
          while ((bytesRead = is.read(data)) != -1) {
            String driverData = new String(data, 0, bytesRead);
            for (String knownQemuDriver : QEMU_DRIVERS) {
              if (driverData.contains(knownQemuDriver)) {
                return true;
              }
            }
          }
        } catch (Throwable ignored) { }
      }
    }
    return false;
  }

  @Retention(RetentionPolicy.SOURCE)
  @IntDef({
    EmulatorType.GENYMOTION,
    EmulatorType.ANDY,
    EmulatorType.NOX,
    EmulatorType.BLUESTACKS,
    EmulatorType.PIPES,
    EmulatorType.X86
  })
  private @interface EmulatorType {
    int GENYMOTION = 1, ANDY = 2, NOX = 3, BLUESTACKS = 4, PIPES = 5, X86 = 6;
  }

  private static boolean testFiles (Context context, String[] targets, @EmulatorType int type) {
    for (String pipe : targets) {
      File qemuFile;
      if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
        if ((pipe.contains("/") && type == EmulatorType.NOX) || type == EmulatorType.BLUESTACKS) {
          qemuFile = new File(Environment.getExternalStorageDirectory() + pipe);
        } else {
          qemuFile = new File(pipe);
        }
      } else {
        qemuFile = new File(pipe);
      }
      if (qemuFile.exists()) {
        return true;
      }
    }
    return false;
  }

  private static final String[] GENYMOTION_FILES = {
    "/dev/socket/genyd",
    "/dev/socket/baseband_genyd"
  };

  private static final String[] ANDY_FILES = {
    "fstab.andy",
    "ueventd.andy.rc"
  };

  private static final String[] NOX_FILES = {
    "fstab.nox",
    "init.nox.rc",
    "ueventd.nox.rc",
    "/BigNoxGameHD",
    "/YSLauncher"
  };

  private static final String[] BLUESTACKS_FILES = {
    "/Android/data/com.bluestacks.home",
    "/Android/data/com.bluestacks.settings"
  };

  private static boolean runPopularEmulatorsTest (Context context) {
    return
      testFiles(context, GENYMOTION_FILES, EmulatorType.GENYMOTION) ||
      testFiles(context, ANDY_FILES, EmulatorType.ANDY) ||
      testFiles(context, NOX_FILES, EmulatorType.NOX) ||
      testFiles(context, BLUESTACKS_FILES, EmulatorType.BLUESTACKS);
  }

  private static final String[] PIPES = {
    "/dev/socket/qemud",
    "/dev/qemu_pipe"
  };

  private static boolean runPipesTest (Context context) {
    return testFiles(context, PIPES, EmulatorType.PIPES);
  }

  private static final String[] X86_FILES = {
    "ueventd.android_x86.rc",
    "x86.prop",
    "ueventd.ttVM_x86.rc",
    "init.ttVM_x86.rc",
    "fstab.ttVM_x86",
    "fstab.vbox86",
    "init.vbox86.rc",
    "ueventd.vbox86.rc"
  };

  private static boolean runX86EmulatorTest (Context context) {
    return testQEmuProps(context) && testFiles(context, X86_FILES, EmulatorType.X86);
  }

  // IP Address

  private static final String IP = "10.0.2.15";

  private static boolean runIpTest (Context context) {
    if (ContextCompat.checkSelfPermission(context, Manifest.permission.INTERNET) != PackageManager.PERMISSION_GRANTED) {
      return false;
    }
    boolean ipDetected = false;
    String[] args = {"/system/bin/netcfg"};
    StringBuilder stringBuilder = new StringBuilder();
    try {
      ProcessBuilder builder = new ProcessBuilder(args);
      builder.directory(new File("/system/bin/"));
      builder.redirectErrorStream(true);
      Process process = builder.start();
      try (InputStream in = process.getInputStream()) {
        byte[] re = new byte[1024];
        int bytesRead;
        while ((bytesRead = in.read(re)) != -1) {
          stringBuilder.append(new String(re, 0, bytesRead));
        }
      }
    } catch (Throwable t) {
      t.printStackTrace();
    }

    String netData = stringBuilder.toString();

    if (!StringUtils.isEmpty(netData)) {
      String[] array = netData.split("\n");
      for (String lan :
        array) {
        if ((lan.contains("wlan0") || lan.contains("tunl0") || lan.contains("eth0")) && lan.contains(IP)) {
          ipDetected = true;
          break;
        }
      }
    }
    return ipDetected;
  }

  // QEMU Properties

  private static class Property {
    public String name;
    public String seekValue;

    public Property (String name, String seekValue) {
      this.name = name;
      this.seekValue = seekValue;
    }
  }

  private static final Property[] QEMU_PROPERTIES = {
    new Property("init.svc.qemud", null),
    new Property("init.svc.qemu-props", null),
    new Property("qemu.hw.mainkeys", null),
    new Property("qemu.sf.fake_camera", null),
    new Property("qemu.sf.lcd_density", null),
    new Property("ro.bootloader", "unknown"),
    new Property("ro.bootmode", "unknown"),
    new Property("ro.hardware", "goldfish"),
    new Property("ro.kernel.android.qemud", null),
    new Property("ro.kernel.qemu.gles", null),
    new Property("ro.kernel.qemu", "1"),
    new Property("ro.product.device", "generic"),
    new Property("ro.product.model", "sdk"),
    new Property("ro.product.name", "sdk"),
    new Property("ro.serialno", null)
  };

  private static final int MIN_PROPERTIES_THRESHOLD = 5;

  private static String getSystemProperty (Context context, String property) {
    try {
      ClassLoader classLoader = context.getClassLoader();
      //noinspection PrivateApi
      Class<?> systemProperties = classLoader.loadClass("android.os.SystemProperties");

      Method get = systemProperties.getMethod("get", String.class);

      Object[] params = new Object[1];
      params[0] = property;

      return (String) get.invoke(systemProperties, params);
    } catch (Exception exception) {
      // empty catch
    }
    return null;
  }

  private static boolean testQEmuProps (Context context) {
    int foundProps = 0;
    for (Property property : QEMU_PROPERTIES) {
      String propertyValue = getSystemProperty(context, property.name);
      if (propertyValue != null && (property.seekValue == null || propertyValue.contains(property.seekValue))) {
        foundProps++;
      }
    }
    return foundProps >= MIN_PROPERTIES_THRESHOLD;
  }

  // EMU Input devices

  private static final String NAME_PREFIX = "N: Name=\"";
  private static final String INPUT_DEVICES_FILE = "/proc/bus/input/devices";
  private static final String[] RESTRICTED_DEVICES = {
    "bluestacks", "memuhyperv", "virtualbox"
  };

  private static boolean runEmuInputDevicesTest (Context context) {
    final List<String> deviceNames = getEmuInputDevicesNames();

    if (deviceNames != null && !deviceNames.isEmpty()) {
      for (String deviceName : deviceNames) {
        for (String restrictedDeviceName : RESTRICTED_DEVICES) {
          if (deviceName.toLowerCase().contains(restrictedDeviceName)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  private static List<String> getEmuInputDevicesNames () {
    final File devicesFile = new File(INPUT_DEVICES_FILE);

    if (!devicesFile.canRead()) {
      return null;
    }

    final List<String> lines = new ArrayList<>();
    try (final BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(devicesFile)))) {
      String line;
      while ((line = r.readLine()) != null) {
        if (line.startsWith(NAME_PREFIX)) {
          final String name = line.substring(NAME_PREFIX.length(), line.length() - 1);
          if (!StringUtils.isEmpty(name)) {
            lines.add(name);
          }
        }
      }
    } catch (Throwable ignored) { }
    return lines;
  }
}
