import type { ApiNetwork } from '../src/api/types';

import { DEFAULT_WALLET_VERSION } from '../src/config';

jest.mock('../src/api/chains/ton/wallet', () => {
  const actual = jest.requireActual('../src/api/chains/ton/wallet');
  const { ApiServerError: ApiServerErrorActual } = jest.requireActual('../src/api/errors');

  return {
    ...actual,
    pickBestWallet: jest.fn(() => {
      throw new ApiServerErrorActual('offline');
    }),
    pickBestWalletVersion: jest.fn(() => {
      throw new ApiServerErrorActual('offline');
    }),
  };
});

jest.mock('tonweb-mnemonic', () => ({
  mnemonicToKeyPair: jest.fn(() => ({
    publicKey: new Uint8Array(32).fill(7),
    secretKey: new Uint8Array(64).fill(9),
  })),
  validateMnemonic: jest.fn(() => true),
  generateMnemonic: jest.fn(() => ([])),
}));

jest.mock('../src/api/chains/solana/wallet', () => {
  const actual = jest.requireActual('../src/api/chains/solana/wallet');
  const { ApiServerError: ApiServerErrorActual } = jest.requireActual('../src/api/errors');

  return {
    ...actual,
    getWalletBalance: jest.fn(() => {
      throw new ApiServerErrorActual('offline');
    }),
    getWalletLastTransaction: jest.fn(() => {
      throw new ApiServerErrorActual('offline');
    }),
  };
});

jest.mock('../src/api/chains/evm/wallet', () => {
  const actual = jest.requireActual('../src/api/chains/evm/wallet');
  const { ApiServerError: ApiServerErrorActual } = jest.requireActual('../src/api/errors');

  return {
    ...actual,
    getWalletBalance: jest.fn(() => {
      throw new ApiServerErrorActual('offline');
    }),
    getWalletLastTransaction: jest.fn(() => {
      throw new ApiServerErrorActual('offline');
    }),
  };
});

import { getWalletFromBip39Mnemonic as getEvmWalletFromBip39Mnemonic } from '../src/api/chains/evm/auth';
import { getWalletBalance as getEvmWalletBalance } from '../src/api/chains/evm/wallet';
import { getWalletFromBip39Mnemonic as getSolanaWalletFromBip39Mnemonic } from '../src/api/chains/solana/auth';
import { getWalletBalance as getSolanaWalletBalance } from '../src/api/chains/solana/wallet';
import { getWalletFromBip39Mnemonic, getWalletFromMnemonic, getWalletFromPrivateKey } from '../src/api/chains/ton/auth';

describe('Offline wallet import fallbacks', () => {
  const mnemonicBip39 = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
    .split(' ');

  test('TON: getWalletFromMnemonic falls back to default version when network calls fail', async () => {
    const wallet = await getWalletFromMnemonic('mainnet' as ApiNetwork, Array(24).fill('abandon'));
    expect(wallet.version).toBe(DEFAULT_WALLET_VERSION);
    expect(wallet.address).toBeTruthy();
    expect(wallet.publicKey).toBeTruthy();
  });

  test('TON: getWalletFromPrivateKey falls back to default version when network calls fail', async () => {
    const wallet = await getWalletFromPrivateKey('mainnet' as ApiNetwork, '00'.repeat(32));
    expect(wallet.version).toBe(DEFAULT_WALLET_VERSION);
    expect(wallet.address).toBeTruthy();
    expect(wallet.publicKey).toBeTruthy();
  });

  test('TON: getWalletFromBip39Mnemonic falls back when network calls fail', async () => {
    const wallets = await getWalletFromBip39Mnemonic('mainnet' as ApiNetwork, mnemonicBip39);
    expect(wallets.length).toBeGreaterThan(0);
    expect(wallets[0].version).toBe(DEFAULT_WALLET_VERSION);
    expect(wallets[0].derivation?.index).toBe(0);
  });

  test('Solana: getWalletFromBip39Mnemonic falls back to default derivation when RPC fails', async () => {
    const wallets = await getSolanaWalletFromBip39Mnemonic('mainnet' as ApiNetwork, mnemonicBip39);
    expect(wallets.length).toBeGreaterThan(0);
    expect(wallets[0].address).toBeTruthy();
    expect(wallets[0].derivation?.index).toBe(0);
  });

  test('Solana: getWalletFromBip39Mnemonic falls back on non-ApiServerError RPC failures', async () => {
    (getSolanaWalletBalance as jest.Mock).mockImplementationOnce(() => {
      throw new TypeError('Failed to fetch');
    });

    const wallets = await getSolanaWalletFromBip39Mnemonic('mainnet' as ApiNetwork, mnemonicBip39);
    expect(wallets.length).toBeGreaterThan(0);
    expect(wallets[0].address).toBeTruthy();
    expect(wallets[0].derivation?.index).toBe(0);
  });

  test('EVM: getWalletFromBip39Mnemonic falls back to default derivation when RPC fails', async () => {
    const wallets = await getEvmWalletFromBip39Mnemonic('ethereum', 'mainnet' as ApiNetwork, mnemonicBip39);
    expect(wallets.length).toBeGreaterThan(0);
    expect(wallets[0].address).toBeTruthy();
    expect(wallets[0].derivation?.index).toBe(0);
  });

  test('EVM: getWalletFromBip39Mnemonic falls back on non-ApiServerError RPC failures', async () => {
    (getEvmWalletBalance as jest.Mock).mockImplementationOnce(() => {
      throw new TypeError('Failed to fetch');
    });

    const wallets = await getEvmWalletFromBip39Mnemonic('ethereum', 'mainnet' as ApiNetwork, mnemonicBip39);
    expect(wallets.length).toBeGreaterThan(0);
    expect(wallets[0].address).toBeTruthy();
    expect(wallets[0].derivation?.index).toBe(0);
  });

  test('TON: non-ApiServerError is not swallowed by offline fallback', async () => {
    const { pickBestWallet } = await import('../src/api/chains/ton/wallet');
    (pickBestWallet as unknown as jest.Mock).mockImplementationOnce(() => {
      throw new Error('boom');
    });

    await expect(getWalletFromMnemonic('mainnet' as ApiNetwork, Array(24).fill('abandon')))
      .rejects
      .toThrow('boom');
  });
});
