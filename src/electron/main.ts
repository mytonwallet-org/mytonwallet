import { app, nativeImage } from 'electron';
import contextMenu from 'electron-context-menu';
import path from 'path';

import { IS_PRODUCTION } from '../config';
import { setupApplicationMenu } from './appMenu';
import { initDeeplink } from './deeplink';
import { setupSecrets } from './secrets';
import { IS_LINUX, IS_MAC_OS, MTW_GTK_VERSION } from './utils';
import { setupWalletConnectPayCollectHandlers } from './walletConnectPayCollect';
import { createWindow, setupCloseHandlers, setupElectronActionHandlers } from './window';

// Chromium switches that no fuse covers. Each lets whoever launches the app run their own code in the
// wallet page, through DevTools or by serving a substitute bundle on the genuine origin.
const FORBIDDEN_SWITCHES = [
  'remote-debugging-port',
  'remote-debugging-pipe',
  'remote-debugging-io-pipes',
  'ignore-certificate-errors',
  'ignore-certificate-errors-spki-list',
  'host-resolver-rules',
  'host-rules',
  'renderer-cmd-prefix',
  'utility-cmd-prefix',
  'gpu-launcher',
  'browser-subprocess-path',
];

// Runs before Chromium starts the DevTools server and before any window or request
if (app.isPackaged && FORBIDDEN_SWITCHES.some((name) => app.commandLine.hasSwitch(name))) {
  process.exit(1);
}

// Must be set before app is ready
if (IS_LINUX) {
  app.commandLine.appendSwitch('gtk-version', MTW_GTK_VERSION);
  if (process.env.XDG_SESSION_TYPE === 'wayland' || process.env.WAYLAND_DISPLAY) {
    app.commandLine.appendSwitch('enable-features', 'UseOzonePlatform');
    app.commandLine.appendSwitch('ozone-platform', 'wayland');
  }
}

initDeeplink();

contextMenu({
  showLearnSpelling: false,
  showLookUpSelection: false,
  showSearchWithGoogle: false,
  showCopyImage: false,
  showSelectAll: true,
  showInspectElement: !IS_PRODUCTION,
});

app.on('ready', () => {
  if (IS_MAC_OS) {
    app.dock!.setIcon(nativeImage.createFromPath(path.resolve(__dirname, '../public/icon-electron-macos.png')));
  }

  setupApplicationMenu();
  createWindow();
  setupElectronActionHandlers();
  setupWalletConnectPayCollectHandlers();
  setupCloseHandlers();
  setupSecrets();
});
