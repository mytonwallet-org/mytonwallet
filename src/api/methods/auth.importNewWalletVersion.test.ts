import type { ApiAccountWithChain, ApiTonWallet } from '../types';
import { ApiCommonError, ApiTransactionError } from '../types';

const mockGetOtherVersionWallet = jest.fn();
const mockGetTelegramWalletInfo = jest.fn();

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    ton: {
      getOtherVersionWallet: (...args: unknown[]) => mockGetOtherVersionWallet(...args),
    },
  },
}));

jest.mock('../chains/ton', () => ({}));
jest.mock('../chains/ton/wallet', () => ({
  getIsTestnetSubwalletId: jest.fn((network, version) => (
    network === 'testnet' && (version === 'W5' || version === 'telegram') ? true : undefined
  )),
  getTelegramWalletInfo: (...args: unknown[]) => mockGetTelegramWalletInfo(...args),
}));

jest.mock('../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  fetchStoredAccounts: jest.fn(),
  getAccountChains: jest.fn((account) => account.byChain),
  getNewAccountId: jest.fn(),
  removeAccountValue: jest.fn(),
  removeNetworkAccountsValue: jest.fn(),
  setAccountValue: jest.fn(),
  updateStoredAccount: jest.fn(),
  updateStoredWallet: jest.fn(),
}));
jest.mock('../common/mnemonic', () => ({}));
jest.mock('../common/tokens', () => ({}));
jest.mock('../db', () => ({ tokenRepository: { clear: jest.fn() } }));
jest.mock('../environment', () => ({ getEnvironment: jest.fn().mockReturnValue({}) }));
jest.mock('../storages', () => ({ storage: { removeItem: jest.fn() } }));
jest.mock('./accounts', () => ({ activateAccount: jest.fn(), deactivateAllAccounts: jest.fn() }));
jest.mock('./dapps', () => ({}));
jest.mock('./other', () => ({}));
jest.mock('./polling', () => ({ addPollingAccount: jest.fn() }));

import {
  fetchStoredAccounts,
  fetchStoredChainAccount,
  getNewAccountId,
  setAccountValue,
} from '../common/accounts';
import { importNewWalletVersion } from './auth';

const PUBLIC_KEY_HEX = '1a4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c295';

const currentAccount: ApiAccountWithChain<'ton'> = {
  type: 'bip39',
  byChain: {
    ton: {
      address: 'old-address',
      publicKey: PUBLIC_KEY_HEX,
      version: 'W5',
      index: 0,
    },
  },
};

const telegramWallet: ApiTonWallet = {
  address: 'telegram-address',
  publicKey: PUBLIC_KEY_HEX,
  version: 'telegram',
  index: 0,
};

describe('importNewWalletVersion', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.mocked(fetchStoredChainAccount).mockResolvedValue(currentAccount);
    jest.mocked(fetchStoredAccounts).mockResolvedValue({});
    jest.mocked(getNewAccountId).mockResolvedValue('1-mainnet');
    jest.mocked(setAccountValue).mockResolvedValue(undefined);
    mockGetOtherVersionWallet.mockReturnValue(telegramWallet);
    mockGetTelegramWalletInfo.mockResolvedValue({
      isTelegramWallet: true,
      publicKey: Buffer.from(PUBLIC_KEY_HEX, 'hex'),
      subwalletId: 0x7FFF7F11,
      isPublicKeyMismatch: false,
    });
  });

  it('imports a verified Telegram Wallet candidate', async () => {
    await expect(importNewWalletVersion('0-mainnet', 'telegram')).resolves.toEqual({
      isNew: true,
      accountId: '1-mainnet',
      byChain: { ton: telegramWallet },
    });

    expect(mockGetOtherVersionWallet).toHaveBeenCalledWith(
      'mainnet',
      currentAccount.byChain.ton,
      'telegram',
      undefined,
    );
    expect(mockGetTelegramWalletInfo).toHaveBeenCalledWith(
      'mainnet',
      'telegram-address',
      expect.any(Uint8Array),
      undefined,
    );
    expect(Buffer.from(mockGetTelegramWalletInfo.mock.calls[0][2]).toString('hex')).toBe(PUBLIC_KEY_HEX);
    expect(setAccountValue).toHaveBeenCalledWith('1-mainnet', 'accounts', {
      ...currentAccount,
      byChain: { ton: telegramWallet },
    });
  });

  it('rejects creating another wallet version from a Telegram Wallet source before writing an account', async () => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      ...currentAccount,
      byChain: { ton: telegramWallet },
    });

    await expect(importNewWalletVersion('0-mainnet', 'W5')).resolves.toEqual({
      error: ApiCommonError.UnsupportedVersion,
    });

    expect(mockGetOtherVersionWallet).not.toHaveBeenCalled();
    expect(fetchStoredAccounts).not.toHaveBeenCalled();
    expect(getNewAccountId).not.toHaveBeenCalled();
    expect(setAccountValue).not.toHaveBeenCalled();
  });

  it('rejects a Telegram contract mismatch before writing an account', async () => {
    mockGetTelegramWalletInfo.mockResolvedValue({
      isTelegramWallet: false,
      publicKey: Buffer.from(PUBLIC_KEY_HEX, 'hex'),
      subwalletId: 0x7FFF7F11,
      isPublicKeyMismatch: false,
    });

    await expect(importNewWalletVersion('0-mainnet', 'telegram')).resolves.toEqual({
      error: ApiTransactionError.TelegramWalletContractMismatch,
    });

    expect(fetchStoredAccounts).not.toHaveBeenCalled();
    expect(getNewAccountId).not.toHaveBeenCalled();
    expect(setAccountValue).not.toHaveBeenCalled();
  });

  it('rejects a rotated Telegram Wallet key before writing an account', async () => {
    mockGetTelegramWalletInfo.mockResolvedValue({
      isTelegramWallet: true,
      publicKey: Buffer.alloc(32, 1),
      subwalletId: 0x7FFF7F11,
      isPublicKeyMismatch: true,
    });

    await expect(importNewWalletVersion('0-mainnet', 'telegram')).resolves.toEqual({
      error: ApiTransactionError.TelegramWalletPublicKeyMismatch,
    });

    expect(fetchStoredAccounts).not.toHaveBeenCalled();
    expect(getNewAccountId).not.toHaveBeenCalled();
    expect(setAccountValue).not.toHaveBeenCalled();
  });
});
