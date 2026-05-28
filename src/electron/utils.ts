import type { BrowserWindow } from 'electron';
import { app } from 'electron';
import { Conf } from 'electron-conf/main';
import fs from 'fs';

import { BASE_URL, BETA_URL, PRODUCTION_URL } from '../config';

const ALLOWED_URL_ORIGINS = [BASE_URL, BETA_URL, PRODUCTION_URL].map((url) => new URL(url).origin);

export let mainWindow: BrowserWindow;
export const store = new Conf();

export const WINDOW_STATE_FILE = 'window-state.json';

export const IS_MAC_OS = process.platform === 'darwin';
export const IS_WINDOWS = process.platform === 'win32';
export const IS_LINUX = process.platform === 'linux';
export const IS_PREVIEW = process.env.IS_PREVIEW === 'true';
export const IS_FIRST_RUN = !fs.existsSync(`${app.getPath('userData')}/${WINDOW_STATE_FILE}`);
export const MTW_GTK_VERSION = process.env.MTW_GTK_VERSION ?? '3'; // GTK version (3) to use on Linux

export function checkIsWebContentsUrlAllowed(url: string): boolean {
  if (!app.isPackaged) {
    return true;
  }

  const parsedUrl = new URL(url);

  const localContentsPathname = IS_WINDOWS
    ? encodeURI(`/${__dirname.replace(/\\/g, '/')}/index.html`)
    : encodeURI(`${__dirname}/index.html`);

  if (parsedUrl.pathname === localContentsPathname) {
    return true;
  }

  return ALLOWED_URL_ORIGINS.includes(parsedUrl.origin);
}

export function setMainWindow(window: BrowserWindow) {
  mainWindow = window;
}

export function focusMainWindow() {
  if (!mainWindow) {
    return;
  }

  if (!mainWindow.isVisible()) {
    mainWindow.show();
  }

  if (mainWindow.isMinimized()) {
    mainWindow.restore();
  }

  mainWindow.focus();
}

export const forceQuit = {
  value: false,

  enable() {
    this.value = true;
  },

  disable() {
    this.value = false;
  },

  get isEnabled(): boolean {
    return this.value;
  },
};
