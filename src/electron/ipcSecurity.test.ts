jest.mock('./utils', () => ({
  checkIsWebContentsUrlAllowed: jest.fn(),
  mainWindow: {
    webContents: {
      getURL: jest.fn(() => 'https://web.mywallet.io'),
    },
  },
}));

import { checkIsIpcSenderAllowed, validateIpcSender } from './ipcSecurity';
import { checkIsWebContentsUrlAllowed, mainWindow } from './utils';

const checkIsWebContentsUrlAllowedMock = jest.mocked(checkIsWebContentsUrlAllowed);

describe('ipcSecurity', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('allows IPC from the main window at an allowed URL', () => {
    checkIsWebContentsUrlAllowedMock.mockReturnValue(true);

    const isAllowed = checkIsIpcSenderAllowed({ sender: mainWindow.webContents } as any);

    expect(isAllowed).toBe(true);
    expect(checkIsWebContentsUrlAllowedMock).toHaveBeenCalledWith('https://web.mywallet.io');
  });

  it('rejects IPC from another sender before checking URL allowlist', () => {
    const sender = { getURL: jest.fn(() => 'https://web.mywallet.io') };

    const isAllowed = checkIsIpcSenderAllowed({ sender } as any);

    expect(isAllowed).toBe(false);
    expect(checkIsWebContentsUrlAllowedMock).not.toHaveBeenCalled();
  });

  it('rejects IPC from the main window at a disallowed URL', () => {
    checkIsWebContentsUrlAllowedMock.mockReturnValue(false);

    expect(() => validateIpcSender({ sender: mainWindow.webContents } as any)).toThrow('Blocked Electron IPC sender');
  });

  it('rejects IPC when URL allowlist checking fails', () => {
    checkIsWebContentsUrlAllowedMock.mockImplementation(() => {
      throw new Error('Invalid URL');
    });

    expect(() => validateIpcSender({ sender: mainWindow.webContents } as any)).toThrow('Blocked Electron IPC sender');
  });
});
