import type { BrowserWindow } from 'electron';
import { app, Menu, nativeImage, Tray } from 'electron';
import path from 'path';

import { forceQuit, IS_WINDOWS, mainWindow, store } from './utils';

const TRAY_ICON_SETTINGS_KEY = 'trayIcon';
const WINDOW_BLUR_TIMEOUT = 800;

interface TrayHelper {
  instance?: Tray;
  lastFocusedWindow?: BrowserWindow;
  lastFocusedWindowTimer?: NodeJS.Timeout;
  handleWindowFocus: () => void;
  handleWindowBlur: () => void;
  handleWindowClose: () => void;
  setupListeners: () => void;
  removeListeners: () => void;
  create: () => void;
  enable: () => void;
  disable: () => void;
  isEnabled: boolean;
}

const tray: TrayHelper = {
  handleWindowFocus() {
    clearTimeout(this.lastFocusedWindowTimer as unknown as NodeJS.Timeout);
    this.lastFocusedWindow = mainWindow;
  },

  handleWindowBlur() {
    this.lastFocusedWindowTimer = setTimeout(() => {
      if (this.lastFocusedWindow === mainWindow) {
        this.lastFocusedWindow = undefined;
      }
    }, WINDOW_BLUR_TIMEOUT);
  },

  handleWindowClose() {
    this.lastFocusedWindow = undefined;
  },

  setupListeners() {
    this.handleWindowFocus = this.handleWindowFocus.bind(this);
    this.handleWindowBlur = this.handleWindowBlur.bind(this);
    this.handleWindowClose = this.handleWindowClose.bind(this);

    mainWindow.on('focus', this.handleWindowFocus);
    mainWindow.on('blur', this.handleWindowBlur);
    mainWindow.on('close', this.handleWindowClose);
  },

  removeListeners() {
    mainWindow.removeListener('focus', this.handleWindowFocus);
    mainWindow.removeListener('blur', this.handleWindowBlur);
    mainWindow.removeListener('close', this.handleWindowClose);
  },

  create() {
    if (this.instance) {
      return;
    }

    this.setupListeners();

    let defaultIconPath = path.resolve(__dirname, '../public/icon-32x32.png');
    if (IS_WINDOWS) {
      defaultIconPath = path.resolve(__dirname, '../public/icon-electron-windows.ico');
    }

    const icon = nativeImage.createFromPath(defaultIconPath);
    const title = app.getName();

    this.instance = new Tray(icon);

    const handleOpenFromTray = () => {
      if (!mainWindow.isVisible()) {
        mainWindow.show();
      } else {
        mainWindow.focus();
      }
    };

    const handleCloseFromTray = () => {
      forceQuit.enable();
      app.quit();
    };

    const handleTrayClick = () => {
      if (this.lastFocusedWindow) {
        mainWindow.hide();
        this.lastFocusedWindow = undefined;
      } else {
        handleOpenFromTray();
      }
    };

    const contextMenu = Menu.buildFromTemplate([
      { label: `Open ${title}`, click: handleOpenFromTray },
      { label: `Quit ${title}`, click: handleCloseFromTray },
    ]);

    this.instance.on('click', handleTrayClick);
    this.instance.setContextMenu(contextMenu);
    this.instance.setToolTip(title);
    this.instance.setTitle(title);
  },

  enable() {
    store.set(TRAY_ICON_SETTINGS_KEY, true);
    this.create();
  },

  disable() {
    store.set(TRAY_ICON_SETTINGS_KEY, false);
    this.instance?.destroy();
    this.instance = undefined;
    this.removeListeners();
  },

  get isEnabled(): boolean {
    return store.get(TRAY_ICON_SETTINGS_KEY, true) as boolean;
  },
};

export default tray;
