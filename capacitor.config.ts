import type { CapacitorConfig } from '@capacitor/cli';
import type { KeyboardResize } from '@capacitor/keyboard';

const { APP_ENV = 'production' } = process.env;

const COMMON_PLUGINS = [
  '@capacitor-community/bluetooth-le',
  '@capacitor-mlkit/barcode-scanning',
  '@capacitor/app',
  '@capacitor/app-launcher',
  '@capacitor/clipboard',
  '@capacitor/dialog',
  '@capacitor/filesystem',
  '@capacitor/haptics',
  '@capacitor/keyboard',
  '@capacitor/push-notifications',
  '@capacitor/share',
  '@capacitor/status-bar',
  '@capgo/capacitor-native-biometric',
  '@capgo/native-audio',
  '@mauricewegner/capacitor-navigation-bar',
  '@mytonwallet/air-app-launcher',
  '@mytonwallet/capacitor-usb-hid',
  '@mytonwallet/native-bottom-sheet',
  'capacitor-native-settings',
  'capacitor-plugin-safe-area',
  'capacitor-secure-storage-plugin',
  'cordova-plugin-inappbrowser',
];

const IOS_PLUGINS = [
  '@capacitor/splash-screen',
];

const config: CapacitorConfig = {
  appId: 'org.mytonwallet.app',
  appName: 'MyTonWallet',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
    hostname: 'mytonwallet.local',
  },
  android: {
    path: 'mobile/android',
    includePlugins: COMMON_PLUGINS,
    webContentsDebuggingEnabled: APP_ENV !== 'production',
  },
  ios: {
    path: 'mobile/ios',
    includePlugins: COMMON_PLUGINS.concat(IOS_PLUGINS),
    scheme: 'MyTonWallet',
    webContentsDebuggingEnabled: APP_ENV !== 'production',
    // This parameter fixes a problem occurring with Capacitor 7. Without it, the Delegated Bottom Sheet steals the
    // focus from the main WebView for a second at the application start. This focus behavior broke the app logic that
    // expected the main WebView to be focused instead of the Sheet. With the parameter, both the contexts are out of
    // focus at the app start, and after ~60ms the main WebView gets the focus, which is ok for the app.
    initialFocus: false,
  },
  plugins: {
    SplashScreen: {
      launchAutoHide: false,
    },
    CapacitorHttp: {
      enabled: true,
    },
    PushNotifications: {
      presentationOptions: [],
    },
    Keyboard: {
      // Needed to disable the automatic focus scrolling on iOS. The scroll is controlled manually by focusScroll.ts
      // for a better focus scroll control.
      resize: 'none' as KeyboardResize,
    },
  },
};

export default config;
