const mockHandlers: Record<string, (...args: any[]) => any> = {};
const mockHandle = jest.fn((action: string, handler: (...args: any[]) => any) => {
  mockHandlers[action] = handler;
});
const mockEncryptString = jest.fn((password: string) => Buffer.from(`encrypted:${password}`));
const mockDecryptString = jest.fn((_buffer: Buffer) => 'password');
const mockPromptTouchID = jest.fn((_prompt: string) => Promise.resolve());

jest.mock('electron', () => ({
  ipcMain: {
    handle: (action: string, handler: (...args: any[]) => any) => mockHandle(action, handler),
  },
  safeStorage: {
    decryptString: (buffer: Buffer) => mockDecryptString(buffer),
    encryptString: (password: string) => mockEncryptString(password),
    isEncryptionAvailable: jest.fn(() => true),
  },
  systemPreferences: {
    canPromptTouchID: jest.fn(() => true),
    promptTouchID: (prompt: string) => mockPromptTouchID(prompt),
  },
}));

jest.mock('./ipcSecurity', () => ({
  validateIpcSender: jest.fn(),
}));

import { ElectronAction } from './types';

import { NATIVE_BIOMETRICS_PROMPT_KEY } from '../config';
import { validateIpcSender } from './ipcSecurity';
import { setupSecrets } from './secrets';

const validateIpcSenderMock = jest.mocked(validateIpcSender);
const event = {} as any;

describe('secrets', () => {
  beforeEach(() => {
    Object.keys(mockHandlers).forEach((key) => {
      delete mockHandlers[key];
    });
    jest.clearAllMocks();
    setupSecrets();
  });

  it('rejects empty passwords before encryption', () => {
    expect(() => mockHandlers[ElectronAction.ENCRYPT_PASSWORD](event, '')).toThrow('Invalid Electron password');

    expect(mockEncryptString).not.toHaveBeenCalled();
  });

  it('validates the sender before encrypting passwords', () => {
    validateIpcSenderMock.mockImplementationOnce(() => {
      throw new Error('Blocked Electron IPC sender');
    });

    expect(() => mockHandlers[ElectronAction.ENCRYPT_PASSWORD](event, 'password')).toThrow(
      'Blocked Electron IPC sender',
    );

    expect(mockEncryptString).not.toHaveBeenCalled();
  });

  it('returns undefined for malformed encrypted passwords before Touch ID', async () => {
    await expect(mockHandlers[ElectronAction.DECRYPT_PASSWORD](event, 'not-base64')).resolves.toBeUndefined();

    expect(mockPromptTouchID).not.toHaveBeenCalled();
    expect(mockDecryptString).not.toHaveBeenCalled();
  });

  it('validates the sender before prompting Touch ID', async () => {
    const encrypted = Buffer.from('encrypted:password').toString('base64');

    validateIpcSenderMock.mockImplementationOnce(() => {
      throw new Error('Blocked Electron IPC sender');
    });

    await expect(mockHandlers[ElectronAction.DECRYPT_PASSWORD](event, encrypted)).rejects.toThrow(
      'Blocked Electron IPC sender',
    );

    expect(mockPromptTouchID).not.toHaveBeenCalled();
    expect(mockDecryptString).not.toHaveBeenCalled();
  });

  it('uses the fallback biometric prompt for invalid prompt input', async () => {
    const encrypted = Buffer.from('encrypted:password').toString('base64');

    await mockHandlers[ElectronAction.SET_BIOMETRIC_PROMPT](event, '');
    await expect(mockHandlers[ElectronAction.DECRYPT_PASSWORD](event, encrypted)).resolves.toBe('password');

    expect(mockPromptTouchID).toHaveBeenCalledWith(NATIVE_BIOMETRICS_PROMPT_KEY);
    expect(mockDecryptString).toHaveBeenCalledWith(expect.any(Buffer));
  });
});
