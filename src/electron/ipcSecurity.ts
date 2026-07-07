import type { IpcMainInvokeEvent } from 'electron';

import { checkIsWebContentsUrlAllowed, mainWindow } from './utils';

type IpcSenderEvent = Pick<IpcMainInvokeEvent, 'sender'>;

export function checkIsIpcSenderAllowed(event: IpcSenderEvent): boolean {
  if (!mainWindow || event.sender !== mainWindow.webContents) {
    return false;
  }

  try {
    return checkIsWebContentsUrlAllowed(event.sender.getURL());
  } catch {
    return false;
  }
}

export function validateIpcSender(event: IpcSenderEvent): void {
  if (checkIsIpcSenderAllowed(event)) {
    return;
  }

  throw new Error('Blocked Electron IPC sender');
}
