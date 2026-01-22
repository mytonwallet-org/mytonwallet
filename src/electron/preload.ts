import type { IpcRendererEvent } from 'electron';
import { contextBridge, ipcRenderer } from 'electron';

import type { AppLayout } from '../global/types';
import type { ElectronApi, ElectronEvent } from './types';
import { ElectronAction } from './types';

const electronApi: ElectronApi = {
  close: () => ipcRenderer.invoke(ElectronAction.CLOSE),
  minimize: () => ipcRenderer.invoke(ElectronAction.MINIMIZE),
  maximize: () => ipcRenderer.invoke(ElectronAction.MAXIMIZE),
  unmaximize: () => ipcRenderer.invoke(ElectronAction.UNMAXIMIZE),
  getIsMaximized: () => ipcRenderer.invoke(ElectronAction.GET_IS_MAXIMIZED),

  installUpdate: () => ipcRenderer.invoke(ElectronAction.INSTALL_UPDATE),
  handleDoubleClick: () => ipcRenderer.invoke(ElectronAction.HANDLE_DOUBLE_CLICK),

  toggleDeeplinkHandler: (isEnabled: boolean) => ipcRenderer.invoke(ElectronAction.TOGGLE_DEEPLINK_HANDLER, isEnabled),

  getIsTouchIdSupported: () => ipcRenderer.invoke(ElectronAction.GET_IS_TOUCH_ID_SUPPORTED),
  encryptPassword: (password: string) => ipcRenderer.invoke(ElectronAction.ENCRYPT_PASSWORD, password),
  decryptPassword: (encrypted: string) => ipcRenderer.invoke(ElectronAction.DECRYPT_PASSWORD, encrypted),
  setBiometricPrompt: (prompt: string) => ipcRenderer.invoke(ElectronAction.SET_BIOMETRIC_PROMPT, prompt),

  setIsTrayIconEnabled: (value: boolean) => ipcRenderer.invoke(ElectronAction.SET_IS_TRAY_ICON_ENABLED, value),
  getIsTrayIconEnabled: () => ipcRenderer.invoke(ElectronAction.GET_IS_TRAY_ICON_ENABLED),
  setIsAutoUpdateEnabled: (value: boolean) => ipcRenderer.invoke(ElectronAction.SET_IS_AUTO_UPDATE_ENABLED, value),
  getIsAutoUpdateEnabled: () => ipcRenderer.invoke(ElectronAction.GET_IS_AUTO_UPDATE_ENABLED),
  changeAppLayout: (layout: AppLayout) => ipcRenderer.invoke(ElectronAction.CHANGE_APP_LAYOUT, layout),

  restoreStorage: () => ipcRenderer.invoke(ElectronAction.RESTORE_STORAGE),

  on: (eventName: ElectronEvent, callback) => {
    const subscription = (event: IpcRendererEvent, ...args: any) => callback(...args);

    ipcRenderer.on(eventName, subscription);

    return () => {
      ipcRenderer.removeListener(eventName, subscription);
    };
  },
};

contextBridge.exposeInMainWorld('electron', electronApi);
