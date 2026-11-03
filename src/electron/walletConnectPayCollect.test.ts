const mockHandlers: Record<string, (...args: any[]) => any> = {};
const mockBrowserWindow = jest.fn();

jest.mock('electron', () => ({
  BrowserWindow: function BrowserWindow(...args: any[]) {
    return mockBrowserWindow(...args);
  },
  dialog: {},
  ipcMain: {
    handle: (action: string, handler: (...args: any[]) => any) => {
      mockHandlers[action] = handler;
    },
  },
  nativeTheme: { shouldUseDarkColors: false },
}));

jest.mock('./ipcSecurity', () => ({
  validateIpcSender: jest.fn(),
}));

jest.mock('./utils', () => ({
  focusMainWindow: jest.fn(),
  mainWindow: {},
}));

jest.mock('../util/walletConnectPay', () => ({
  checkIsKycUrlAllowed: jest.fn(() => true),
  parseWalletConnectPayDataCollectionMessage: jest.fn(),
}));

import { ElectronAction } from './types';

import { validateIpcSender } from './ipcSecurity';
import { setupWalletConnectPayCollectHandlers } from './walletConnectPayCollect';

const validateIpcSenderMock = jest.mocked(validateIpcSender);
const event = {} as any;
const KYC_URL = 'https://pay.walletconnect.com/kyc';

function blockSender() {
  validateIpcSenderMock.mockImplementationOnce(() => {
    throw new Error('Blocked Electron IPC sender');
  });
}

describe('walletConnectPayCollect', () => {
  beforeEach(() => {
    Object.keys(mockHandlers).forEach((key) => {
      delete mockHandlers[key];
    });
    jest.clearAllMocks();
    setupWalletConnectPayCollectHandlers();
  });

  it('validates the sender before opening the collect window', async () => {
    blockSender();

    const error = await mockHandlers[ElectronAction.OPEN_WALLET_CONNECT_PAY_COLLECT](event, KYC_URL, undefined)
      .catch((err: Error) => err);

    expect(mockBrowserWindow).not.toHaveBeenCalled();
    expect(error).toEqual(new Error('Blocked Electron IPC sender'));
    expect(validateIpcSenderMock).toHaveBeenCalledWith(event);
  });

  it('opens the collect window for an allowed sender', () => {
    mockBrowserWindow.mockReturnValueOnce({
      close: jest.fn(),
      isDestroyed: jest.fn(() => false),
      on: jest.fn(),
      webContents: {
        setWindowOpenHandler: jest.fn(),
        on: jest.fn(),
        removeListener: jest.fn(),
        loadURL: jest.fn(() => new Promise(() => {})),
      },
    });

    void mockHandlers[ElectronAction.OPEN_WALLET_CONNECT_PAY_COLLECT](event, KYC_URL, undefined);

    expect(validateIpcSenderMock).toHaveBeenCalledWith(event);
    expect(mockBrowserWindow).toHaveBeenCalledTimes(1);
  });

  it('validates the sender before closing the collect window', () => {
    blockSender();

    expect(() => mockHandlers[ElectronAction.CLOSE_WALLET_CONNECT_PAY_COLLECT](event)).toThrow(
      'Blocked Electron IPC sender',
    );
    expect(validateIpcSenderMock).toHaveBeenCalledWith(event);
  });

  it('closes the collect window for an allowed sender', () => {
    expect(() => mockHandlers[ElectronAction.CLOSE_WALLET_CONNECT_PAY_COLLECT](event)).not.toThrow();
    expect(validateIpcSenderMock).toHaveBeenCalledWith(event);
  });
});
