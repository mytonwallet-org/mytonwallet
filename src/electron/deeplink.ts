import { app, ipcMain } from 'electron';
import path from 'path';

import { ElectronAction, ElectronEvent } from './types';

import {
  focusMainWindow, IS_LINUX, IS_MAC_OS, IS_WINDOWS, mainWindow,
} from './utils';

const TON_PROTOCOL = 'ton';
const TONCONNECT_PROTOCOL = 'tc';
const TONCONNECT_PROTOCOL_SELF = 'mytonwallet-tc';
const SELF_PROTOCOL = 'mtw';
const WALLETCONNECT_PROTOCOL = 'wc';

let deeplinkUrl: string | undefined;

export function initDeeplink() {
  if (process.defaultApp) {
    if (process.argv.length >= 2) {
      app.setAsDefaultProtocolClient(TONCONNECT_PROTOCOL, process.execPath, [path.resolve(process.argv[1])]);
      app.setAsDefaultProtocolClient(TONCONNECT_PROTOCOL_SELF, process.execPath, [path.resolve(process.argv[1])]);
      app.setAsDefaultProtocolClient(SELF_PROTOCOL, process.execPath, [path.resolve(process.argv[1])]);
      app.setAsDefaultProtocolClient(WALLETCONNECT_PROTOCOL, process.execPath, [path.resolve(process.argv[1])]);
    }
  } else {
    app.setAsDefaultProtocolClient(TONCONNECT_PROTOCOL);
    app.setAsDefaultProtocolClient(TONCONNECT_PROTOCOL_SELF);
    app.setAsDefaultProtocolClient(SELF_PROTOCOL);
    app.setAsDefaultProtocolClient(WALLETCONNECT_PROTOCOL);
  }

  ipcMain.handle(ElectronAction.TOGGLE_DEEPLINK_HANDLER, (event, isEnabled: boolean) => {
    if (!isEnabled) {
      app.removeAsDefaultProtocolClient(TON_PROTOCOL);
      return;
    }

    if (process.defaultApp) {
      if (process.argv.length >= 2) {
        app.setAsDefaultProtocolClient(TON_PROTOCOL, process.execPath, [path.resolve(process.argv[1])]);
      }
    } else {
      app.setAsDefaultProtocolClient(TON_PROTOCOL);
    }
  });

  const gotTheLock = app.requestSingleInstanceLock();

  if (!gotTheLock) {
    app.quit();

    return;
  }

  app.on('will-finish-launching', () => {
    app.on('open-url', (event: Electron.Event, url: string) => {
      event.preventDefault();
      deeplinkUrl = url;
      processDeeplink();
      focusMainWindow();
    });
  });

  if (IS_WINDOWS || IS_LINUX) {
    deeplinkUrl = findDeeplink(process.argv);
  }

  app.on('second-instance', (_, argv: string[]) => {
    if (IS_MAC_OS) {
      deeplinkUrl = argv[0];
    } else {
      deeplinkUrl = findDeeplink(argv);
    }

    processDeeplink();
    focusMainWindow();
  });
}

export function processDeeplink() {
  if (!mainWindow || !deeplinkUrl) {
    return;
  }

  if (getIsDeeplink(deeplinkUrl)) {
    mainWindow.webContents.send(ElectronEvent.DEEPLINK, {
      url: deeplinkUrl,
    });
  }
  deeplinkUrl = undefined;
}

function findDeeplink(args: string[]) {
  return args.find((arg) => getIsDeeplink(arg));
}

function getIsDeeplink(url: string) {
  return url.startsWith(`${TON_PROTOCOL}://`)
    || url.startsWith(`${TONCONNECT_PROTOCOL}://`)
    || url.startsWith(`${TONCONNECT_PROTOCOL_SELF}://`)
    || url.startsWith(`${SELF_PROTOCOL}://`)
    || url.startsWith(`${WALLETCONNECT_PROTOCOL}:`);
}
