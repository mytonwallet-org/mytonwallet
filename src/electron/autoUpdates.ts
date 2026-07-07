import { app, ipcMain, net } from 'electron';
import type { UpdateInfo } from 'electron-updater';
import { autoUpdater } from 'electron-updater';

import { ElectronAction, ElectronEvent } from './types';

import { PRODUCTION_URL } from '../config';
import getIsAppUpdateNeeded from '../util/getIsAppUpdateNeeded';
import { pause } from '../util/schedulers';
import { validateIpcSender } from './ipcSecurity';
import {
  forceQuit, IS_MAC_OS, IS_PREVIEW, IS_WINDOWS, mainWindow, store,
} from './utils';

export const AUTO_UPDATE_SETTING_KEY = 'autoUpdate';

const ELECTRON_APP_VERSION_URL = 'electronVersion.txt';
const CHECK_UPDATE_INTERVAL = 5 * 60 * 1000;

let isUpdateCheckStarted = false;

export function setupAutoUpdates() {
  if (isUpdateCheckStarted) {
    return;
  }

  isUpdateCheckStarted = true;
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;

  void checkForUpdates();

  ipcMain.handle(ElectronAction.INSTALL_UPDATE, (event) => {
    validateIpcSender(event);

    if (IS_MAC_OS || IS_WINDOWS) {
      forceQuit.enable();
    }

    return autoUpdater.quitAndInstall();
  });

  autoUpdater.on('error', (error: Error) => {
    mainWindow.webContents.send(ElectronEvent.UPDATE_ERROR, error);
  });
  autoUpdater.on('update-downloaded', (info: UpdateInfo) => {
    mainWindow.webContents.send(ElectronEvent.UPDATE_DOWNLOADED, info);
  });
}

export function getIsAutoUpdateEnabled() {
  return !IS_PREVIEW && store.get(AUTO_UPDATE_SETTING_KEY);
}

async function checkForUpdates(): Promise<void> {
  while (true) {
    if (await shouldPerformAutoUpdate()) {
      if (getIsAutoUpdateEnabled()) {
        void autoUpdater.checkForUpdates();
      } else {
        mainWindow.webContents.send(ElectronEvent.UPDATE_DOWNLOADED);
      }
    }

    await pause(CHECK_UPDATE_INTERVAL);
  }
}

function shouldPerformAutoUpdate(): Promise<boolean> {
  return new Promise((resolve) => {
    const request = net.request(`${PRODUCTION_URL}/${ELECTRON_APP_VERSION_URL}?${Date.now()}`);

    request.on('response', (response) => {
      let contents = '';

      response.on('end', () => {
        resolve(getIsAppUpdateNeeded(contents, app.getVersion(), true));
      });

      response.on('data', (data: Buffer) => {
        contents = `${contents}${String(data)}`;
      });

      response.on('error', () => {
        resolve(false);
      });
    });

    request.on('error', () => {
      resolve(false);
    });

    request.end();
  });
}
