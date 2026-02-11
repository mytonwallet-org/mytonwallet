import { app, nativeImage } from 'electron';
import contextMenu from 'electron-context-menu';
import path from 'path';

import { IS_PRODUCTION } from '../config';
import { initDeeplink } from './deeplink';
import { setupSecrets } from './secrets';
import { IS_LINUX, IS_MAC_OS, MTW_GTK_VERSION } from './utils';
import { createWindow, setupCloseHandlers, setupElectronActionHandlers } from './window';

// Must be set before app is ready
if (IS_LINUX) {
  app.commandLine.appendSwitch('gtk-version', MTW_GTK_VERSION);
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

  createWindow();
  setupElectronActionHandlers();
  setupCloseHandlers();
  setupSecrets();
});
