import type { MenuItemConstructorOptions } from 'electron';
import { Menu } from 'electron';

import { APP_NAME } from '../config';
import { IS_MAC_OS } from './utils';

// Without an explicit menu, Electron builds the default one from `app.getName()`, pinned to the
// legacy "MyTonWallet" string as the storage/keychain identity key (see `config.yml`) that must
// never change. So the user-visible labels take the display name from `APP_NAME` instead.
export function setupApplicationMenu() {
  if (!IS_MAC_OS) {
    return; // On Windows/Linux the main window is frameless and removes its menu bar (see `window.ts`)
  }

  const template: MenuItemConstructorOptions[] = [
    {
      label: APP_NAME,
      submenu: [
        { role: 'about', label: `About ${APP_NAME}` },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide', label: `Hide ${APP_NAME}` },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit', label: `Quit ${APP_NAME}` },
      ],
    },
    { role: 'fileMenu' },
    { role: 'editMenu' },
    { role: 'viewMenu' },
    { role: 'windowMenu' },
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}
