import { app, BrowserWindow, ipcMain, shell, systemPreferences } from 'electron';
import windowStateKeeper from 'electron-window-state';
import path from 'path';

import type { AppLayout } from '../global/types';
import { ElectronAction } from './types';

import { BASE_URL, DEFAULT_LANDSCAPE_WINDOW_SIZE, DEFAULT_PORTRAIT_WINDOW_SIZE, IS_PRODUCTION } from '../config';
import { AUTO_UPDATE_SETTING_KEY, getIsAutoUpdateEnabled, setupAutoUpdates } from './autoUpdates';
import { processDeeplink } from './deeplink';
import { captureStorage, restoreStorage } from './storageUtils';
import tray from './tray';
import {
  checkIsWebContentsUrlAllowed,
  forceQuit,
  IS_FIRST_RUN,
  IS_LINUX,
  IS_MAC_OS,
  IS_PREVIEW,
  IS_WINDOWS,
  mainWindow,
  setMainWindow,
  store,
  WINDOW_STATE_FILE,
} from './utils';

const ALLOWED_DEVICE_ORIGINS = ['http://localhost:4321', 'file://', BASE_URL];

export function createWindow() {
  const windowState = windowStateKeeper({
    file: WINDOW_STATE_FILE,
    defaultWidth: 980,
    defaultHeight: 788,
  });

  const window = new BrowserWindow({
    show: false,
    x: windowState.x,
    y: windowState.y,

    minWidth: 360,
    minHeight: 690,
    width: windowState.width,
    height: windowState.height,

    titleBarStyle: 'hidden',
    title: 'MyTonWallet',
    frame: false,

    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      devTools: !IS_PRODUCTION,
      backgroundThrottling: false,
    },

    ...(IS_LINUX && {
      icon: path.join(__dirname, '../public/icon-256x256.png'),
    }),

    ...(IS_MAC_OS && {
      trafficLightPosition: { x: 19, y: 17 },
    }),
  });

  setMainWindow(window);

  mainWindow.on('page-title-updated', (event: Electron.Event) => {
    event.preventDefault();
  });

  windowState.manage(mainWindow);

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.webContents.session.setDevicePermissionHandler(({ deviceType, origin }) => {
    return deviceType === 'hid' && ALLOWED_DEVICE_ORIGINS.includes(origin);
  });

  window.webContents.on('will-navigate', (event, newUrl) => {
    if (!checkIsWebContentsUrlAllowed(newUrl)) {
      event.preventDefault();
    }
  });

  if (!IS_MAC_OS) {
    setupWindowsTitleBar();
  }

  if ((IS_WINDOWS || IS_LINUX) && tray.isEnabled) {
    tray.create();
  }

  mainWindow.webContents.once('dom-ready', async () => {
    processDeeplink();

    if (IS_PRODUCTION) {
      setupAutoUpdates();
    }

    if (!IS_FIRST_RUN && getIsAutoUpdateEnabled() === undefined) {
      store.set(AUTO_UPDATE_SETTING_KEY, true);
      await captureStorage();
      loadWindowUrl();
    }

    mainWindow.show();
  });

  loadWindowUrl();
}

function loadWindowUrl(): void {
  if (!app.isPackaged) {
    void mainWindow.loadURL('http://localhost:4321');
    mainWindow.webContents.openDevTools();
  } else if (getIsAutoUpdateEnabled()) {
    void mainWindow.loadURL(BASE_URL);
  } else if (getIsAutoUpdateEnabled() === undefined && IS_FIRST_RUN) {
    store.set(AUTO_UPDATE_SETTING_KEY, true);
    void mainWindow.loadURL(BASE_URL);
  } else {
    void mainWindow.loadURL(`file://${__dirname}/index.html`);
  }
}

export function setupElectronActionHandlers() {
  ipcMain.handle(ElectronAction.HANDLE_DOUBLE_CLICK, () => {
    const doubleClickAction = systemPreferences.getUserDefault('AppleActionOnDoubleClick', 'string');

    if (doubleClickAction === 'Minimize') {
      mainWindow.minimize();
    } else if (doubleClickAction === 'Maximize') {
      if (!mainWindow.isMaximized()) {
        mainWindow.maximize();
      } else {
        mainWindow.unmaximize();
      }
    }
  });

  ipcMain.handle(ElectronAction.SET_IS_TRAY_ICON_ENABLED, (_, isTrayIconEnabled: boolean) => {
    if (isTrayIconEnabled) {
      tray.enable();
    } else {
      tray.disable();
    }
  });

  ipcMain.handle(ElectronAction.GET_IS_TRAY_ICON_ENABLED, () => tray.isEnabled);

  ipcMain.handle(ElectronAction.SET_IS_AUTO_UPDATE_ENABLED, async (_, isAutoUpdateEnabled: boolean) => {
    if (IS_PREVIEW) {
      return;
    }

    store.set(AUTO_UPDATE_SETTING_KEY, isAutoUpdateEnabled);
    await captureStorage();
    loadWindowUrl();
  });

  ipcMain.handle(ElectronAction.GET_IS_AUTO_UPDATE_ENABLED, () => {
    return store.get(AUTO_UPDATE_SETTING_KEY, true);
  });

  ipcMain.handle(ElectronAction.CHANGE_APP_LAYOUT, (_, layout: AppLayout) => {
    mainWindow.setBounds(layout === 'portrait' ? DEFAULT_PORTRAIT_WINDOW_SIZE : DEFAULT_LANDSCAPE_WINDOW_SIZE);
  });

  ipcMain.handle(ElectronAction.RESTORE_STORAGE, () => restoreStorage());
}

export function setupCloseHandlers() {
  mainWindow.on('close', (event: Electron.Event) => {
    if (forceQuit.isEnabled) {
      app.exit(0);
      return;
    }

    if (mainWindow.isFullScreen()) {
      event.preventDefault();
      mainWindow.once('leave-full-screen', () => {
        mainWindow.close();
      });
      mainWindow.setFullScreen(false);
    } else if (IS_MAC_OS || (IS_WINDOWS && tray.isEnabled)) {
      event.preventDefault();
      mainWindow.hide();
    }
  });

  app.on('window-all-closed', () => {
    if (!IS_MAC_OS) {
      app.quit();
    }
  });

  app.on('before-quit', (event: Electron.Event) => {
    if (IS_MAC_OS && !forceQuit.isEnabled) {
      event.preventDefault();
      forceQuit.enable();
      app.quit();
    }
  });

  app.on('activate', () => {
    const hasActiveWindow = BrowserWindow.getAllWindows().length > 0;

    if (!hasActiveWindow) {
      createWindow();
    }

    if (IS_MAC_OS && hasActiveWindow) {
      forceQuit.disable();
      mainWindow.show();
    }
  });
}

function setupWindowsTitleBar() {
  mainWindow.removeMenu();

  ipcMain.handle(ElectronAction.CLOSE, () => mainWindow.close());
  ipcMain.handle(ElectronAction.MINIMIZE, () => mainWindow.minimize());
  ipcMain.handle(ElectronAction.MAXIMIZE, () => mainWindow.maximize());
  ipcMain.handle(ElectronAction.UNMAXIMIZE, () => mainWindow.unmaximize());
  ipcMain.handle(ElectronAction.GET_IS_MAXIMIZED, () => mainWindow.isMaximized());
}
