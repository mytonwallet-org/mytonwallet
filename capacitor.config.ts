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
      // Needed to disable the automatic focus scrolling on iOS.
      // The scroll is controlled manually by focusScroll.ts for a better focus scroll control.
      resize: 'none' as KeyboardResize,
      // There is an Android bug that prevents the keyboard from resizing the WebView when the app is in full screen
      // (i.e. if StatusBar plugin is used to overlay the status bar).
      // This setting, if set to true, add a workaround that resizes the WebView even
      // when the app is in full screen. Only available for Android
      // https://capacitorjs.com/docs/apis/keyboard#configuration
      // This is necessary since Cap7, otherwise input will be hidden by the keyboard.
      resizeOnFullScreen: true,
    },
  },
};

export default config;
