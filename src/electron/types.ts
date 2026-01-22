import type { AppLayout } from '../global/types';

export enum ElectronEvent {
  DEEPLINK = 'deeplink',
  UPDATE_ERROR = 'update-error',
  UPDATE_DOWNLOADED = 'update-downloaded',
}

export enum ElectronAction {
  CLOSE = 'close',
  MINIMIZE = 'minimize',
  MAXIMIZE = 'maximize',
  UNMAXIMIZE = 'unmaximize',
  GET_IS_MAXIMIZED = 'get-is-maximized',

  INSTALL_UPDATE = 'install-update',
  HANDLE_DOUBLE_CLICK = 'handle-double-click',

  TOGGLE_DEEPLINK_HANDLER = 'toggle-deeplink-handler',

  GET_IS_TOUCH_ID_SUPPORTED = 'get-is-touch-id-supported',
  ENCRYPT_PASSWORD = 'encrypt-password',
  DECRYPT_PASSWORD = 'decrypt-password',
  SET_BIOMETRIC_PROMPT = 'set-biometric-prompt',

  SET_IS_TRAY_ICON_ENABLED = 'set-is-tray-icon-enabled',
  GET_IS_TRAY_ICON_ENABLED = 'get-is-tray-icon-enabled',
  SET_IS_AUTO_UPDATE_ENABLED = 'set-is-auto-update-enabled',
  GET_IS_AUTO_UPDATE_ENABLED = 'get-is-auto-update-enabled',
  CHANGE_APP_LAYOUT = 'change-app-layout',

  RESTORE_STORAGE = 'restore-storage',
}

export interface ElectronApi {
  close: VoidFunction;
  minimize: VoidFunction;
  maximize: VoidFunction;
  unmaximize: VoidFunction;
  getIsMaximized: () => Promise<boolean>;

  installUpdate: () => Promise<void>;
  handleDoubleClick: () => Promise<void>;

  toggleDeeplinkHandler: (isEnabled: boolean) => Promise<void>;

  getIsTouchIdSupported: () => Promise<boolean>;
  encryptPassword: (password: string) => Promise<string>;
  decryptPassword: (encrypted: string) => Promise<string | undefined>;
  setBiometricPrompt: (prompt: string) => Promise<void>;

  setIsTrayIconEnabled: (value: boolean) => Promise<void>;
  getIsTrayIconEnabled: () => Promise<boolean>;
  setIsAutoUpdateEnabled: (value: boolean) => Promise<void>;
  getIsAutoUpdateEnabled: () => Promise<boolean>;
  changeAppLayout: (layout: AppLayout) => Promise<void>;

  restoreStorage: () => Promise<void>;

  on: (eventName: ElectronEvent, callback: any) => VoidFunction;
}

declare global {
  interface Window {
    electron?: ElectronApi;
  }
}
