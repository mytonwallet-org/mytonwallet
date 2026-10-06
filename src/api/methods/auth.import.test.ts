import { mnemonicValidate } from '@ton/crypto';
import * as bip39 from 'bip39';
import nacl from 'tweetnacl';

import { ApiCommonError, ApiTransactionError } from '../types';

import { ApiServerError } from '../errors';
import { activateAccount } from './accounts';
import { resetAgentV2 } from './agentV2Lifecycle';
import { importMnemonic, resetAccounts } from './auth';
import { isBackendAuthTokenValid } from './other';

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    solana: {
      getWalletFromBip39Mnemonic: jest.fn(),
    },
    ton: {
      getWalletFromBip39Mnemonic: jest.fn(),
      // The native-mnemonic group proxies the same module the `../chains/ton` mock below provides, so the
      // assertions can keep driving those jest.fn()s directly.
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      nativeMnemonic: require('../chains/ton'),
    },
    arc: {
      getDefaultDerivation: jest.fn().mockReturnValue({ path: 'arc-path', index: 0 }),
      getWalletFromBip39Mnemonic: jest.fn(),
    },
  },
}));

jest.mock('../chains/ton', () => ({
  __esModule: true,
  validateMnemonic: jest.fn(),
  isTelegramRotationMnemonic: jest.fn(),
  getWalletFromTelegramRotationMnemonic: jest.fn(),
  getKeyPairFromStoredMnemonic: jest.fn(),
  buildBackendAuthToken: jest.fn((secretKey: Uint8Array) => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const nacl = require('tweetnacl');

    return Buffer.from(nacl.sign.detached(
      new TextEncoder().encode('MyTonWallet_AuthToken_n6i0k4w8pb'),
      secretKey,
    )).toString('base64');
  }),
  getWalletFromMnemonic: jest.fn(),
  generateMnemonic: jest.fn(),
}));

jest.mock('../common/mnemonic', () => ({
  validateBip39Mnemonic: jest.fn(),
  encryptMnemonic: jest.fn().mockResolvedValue('encrypted'),
  decryptMnemonic: jest.fn().mockResolvedValue(['word']),
  generateBip39Mnemonic: jest.fn(),
  getMnemonic: jest.fn(),
}));

jest.mock('../common/accounts', () => ({
  getNewAccountId: jest.fn(),
  setAccountValue: jest.fn(),
  getAccountChains: jest.fn().mockReturnValue({}),
  fetchStoredAccount: jest.fn(),
  fetchStoredAccounts: jest.fn(),
  fetchStoredChainAccount: jest.fn(),
  removeAccountValue: jest.fn(),
  removeNetworkAccountsValue: jest.fn(),
  updateStoredAccount: jest.fn(),
  updateStoredWallet: jest.fn(),
}));

jest.mock('./accounts', () => ({
  activateAccount: jest.fn(),
  deactivateAllAccounts: jest.fn(),
}));

jest.mock('./polling', () => ({
  addPollingAccount: jest.fn(),
  removeAllPollingAccounts: jest.fn(),
  removeNetworkPollingAccounts: jest.fn(),
  removePollingAccount: jest.fn(),
}));

jest.mock('../common/tokens', () => ({ sendUpdateTokens: jest.fn() }));
jest.mock('../db', () => ({ tokenRepository: { clear: jest.fn() } }));
jest.mock('../environment', () => ({ getEnvironment: jest.fn().mockReturnValue({}) }));
jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
    mutateItem: jest.fn(),
    removeItem: jest.fn(),
  },
}));
jest.mock('./agentV2Lifecycle', () => ({ resetAgentV2: jest.fn() }));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const ton = require('../chains/ton') as {
  validateMnemonic: jest.Mock;
  isTelegramRotationMnemonic: jest.Mock;
  getWalletFromTelegramRotationMnemonic: jest.Mock;
  getKeyPairFromStoredMnemonic: jest.Mock;
  buildBackendAuthToken: (secretKey: Uint8Array) => string;
  getWalletFromMnemonic: jest.Mock;
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const chains = require('../chains').default as {
  ton: { getWalletFromBip39Mnemonic: jest.Mock };
  arc: { getWalletFromBip39Mnemonic: jest.Mock };
  solana: { getWalletFromBip39Mnemonic: jest.Mock };
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { validateBip39Mnemonic } = require('../common/mnemonic') as { validateBip39Mnemonic: jest.Mock };
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { setAccountValue, getNewAccountId } = require('../common/accounts') as {
  setAccountValue: jest.Mock;
  getNewAccountId: jest.Mock;
};

// A phrase that validates as both a TON-native and a BIP39 mnemonic (~1/256): the only tiebreaker between the two
// derivations, which yield different addresses, is whether the TON derivation has on-chain history.
const DUAL_VALID = ['dual', 'valid', 'phrase'];

const BIP39_TELEGRAM_ROTATION_COLLISION = [
  'pipe', 'liberty', 'decade', 'town', 'device', 'catch', 'bacon', 'dry', 'appear', 'silly', 'evil', 'genuine',
  'fit', 'oxygen', 'movie', 'shed', 'panda', 'misery', 'chimney', 'edge', 'vague', 'safe', 'prevent', 'young',
];
const TON_NATIVE_TELEGRAM_ROTATION_COLLISION = [
  'able', 'about', 'abandon', 'able', 'able', 'abuse', 'absorb', 'absurd', 'above', 'access', 'absorb', 'about',
  'achieve', 'acid', 'abuse', 'able', 'absurd', 'abstract', 'ability', 'above', 'about', 'abuse', 'achieve',
  'absurd',
];
const ROTATION_ANCHOR_KEY_PAIR = nacl.sign.keyPair();
const ROTATION_SIGNING_KEY_PAIR = nacl.sign.keyPair();

// Let any promise that the aborted import left detached (a sibling network branch still running) settle, so the
// assertion sees writes that happen after the error is returned rather than racing them.
const flushPromises = () => new Promise((resolve) => {
  setTimeout(resolve, 0);
});

describe('importMnemonic', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    validateBip39Mnemonic.mockReturnValue(true);
    ton.validateMnemonic.mockResolvedValue(true);
    ton.isTelegramRotationMnemonic.mockReturnValue(false);
    ton.getWalletFromTelegramRotationMnemonic.mockResolvedValue({
      address: 'EQ-telegram-rotation',
      publicKey: Buffer.from(ROTATION_ANCHOR_KEY_PAIR.publicKey).toString('hex'),
      version: 'telegram',
      index: 0,
      derivation: { path: 'ton-path', index: 0 },
    });
    ton.getKeyPairFromStoredMnemonic.mockResolvedValue(ROTATION_SIGNING_KEY_PAIR);
    chains.ton.getWalletFromBip39Mnemonic.mockResolvedValue([
      { address: 'EQ-bip39', publicKey: 'pk', version: 'W5', index: 0 },
    ]);
    chains.arc.getWalletFromBip39Mnemonic.mockResolvedValue([]);
    chains.solana.getWalletFromBip39Mnemonic.mockResolvedValue([
      { address: 'solana-address', publicKey: 'solana-pk', index: 0 },
    ]);
    getNewAccountId.mockImplementation((network: string) => Promise.resolve(`0-${network}`));
    setAccountValue.mockResolvedValue(undefined);
  });

  it('aborts with a server error and persists nothing when the history probe cannot reach the node', async () => {
    ton.getWalletFromMnemonic.mockRejectedValue(new ApiServerError('node unreachable'));

    const result = await importMnemonic(['mainnet'], DUAL_VALID);

    // A failed probe must surface as a retriable error, never fall through to a silent BIP39 import at a
    // different address than the user's funded TON wallet.
    expect(result).toEqual({ error: ApiCommonError.ServerError });
    expect(setAccountValue).not.toHaveBeenCalled();
    expect(ton.getWalletFromMnemonic).toHaveBeenCalledWith('mainnet', DUAL_VALID, false);
  });

  it('persists no account on any network when the probe fails for one of several networks', async () => {
    ton.getWalletFromMnemonic.mockImplementation((network: string) => (
      network === 'testnet'
        ? Promise.reject(new ApiServerError('node unreachable'))
        : Promise.resolve({ address: 'EQ-ton', publicKey: 'pk', version: 'W5', index: 0 })
    ));

    const result = await importMnemonic(['mainnet', 'testnet'], DUAL_VALID);
    await flushPromises();

    // The multi-network import derives every network before writing, so a transient failure on one network
    // cannot leave a ghost account behind on the other (which a retry would duplicate). Flushing first defeats
    // the version where the surviving branch persists after the error.
    expect(result).toEqual({ error: ApiCommonError.ServerError });
    expect(setAccountValue).not.toHaveBeenCalled();
  });

  it('imports the TON derivation when its address has on-chain history', async () => {
    ton.getWalletFromMnemonic.mockResolvedValue({
      address: 'EQ-ton', publicKey: 'pk', version: 'W5', index: 0, lastTxId: 'tx1',
    });

    await importMnemonic(['mainnet'], DUAL_VALID);

    expect(setAccountValue).toHaveBeenCalledWith('0-mainnet', 'accounts', expect.objectContaining({ type: 'ton' }));
  });

  it('keeps a discovered Telegram Wallet import TON-only instead of grouping other chains with it', async () => {
    ton.validateMnemonic.mockResolvedValue(false);
    const telegramWallet = {
      address: 'EQ-telegram',
      publicKey: 'telegram-public-key',
      version: 'telegram',
      index: 0,
      derivation: { path: 'ton-path', index: 0 },
    };
    const arcWallet = {
      address: 'arc-address',
      publicKey: 'arc-public-key',
      index: 0,
      derivation: { path: 'arc-path', index: 0 },
    };
    chains.ton.getWalletFromBip39Mnemonic.mockResolvedValue([telegramWallet]);
    chains.arc.getWalletFromBip39Mnemonic.mockResolvedValue([arcWallet]);

    await importMnemonic(['mainnet'], ['bip39', 'phrase']);

    expect(setAccountValue).toHaveBeenCalledWith('0-mainnet', 'accounts', {
      type: 'bip39',
      byChain: { ton: { ...telegramWallet, authToken: expect.any(String), chain: 'ton' } },
    });
    expect(setAccountValue.mock.calls[0][2].byChain).not.toHaveProperty('arc');
  });

  it('imports a Telegram rotation mnemonic as a TON-only Telegram Wallet account', async () => {
    const mnemonic = Array.from({ length: 24 }, (_, i) => `word${i}`);
    validateBip39Mnemonic.mockReturnValue(false);
    ton.validateMnemonic.mockResolvedValue(false);
    ton.isTelegramRotationMnemonic.mockReturnValue(true);

    await importMnemonic(['mainnet'], mnemonic);

    expect(ton.getWalletFromTelegramRotationMnemonic).toHaveBeenCalledWith('mainnet', mnemonic);
    expect(chains.ton.getWalletFromBip39Mnemonic).not.toHaveBeenCalled();
    expect(chains.arc.getWalletFromBip39Mnemonic).not.toHaveBeenCalled();
    expect(chains.solana.getWalletFromBip39Mnemonic).not.toHaveBeenCalled();
    expect(setAccountValue).toHaveBeenCalledWith('0-mainnet', 'accounts', {
      type: 'bip39',
      byChain: {
        ton: {
          address: 'EQ-telegram-rotation',
          publicKey: Buffer.from(ROTATION_ANCHOR_KEY_PAIR.publicKey).toString('hex'),
          authToken: expect.any(String),
          version: 'telegram',
          index: 0,
          derivation: { path: 'ton-path', index: 0 },
        },
      },
    });
  });

  it('stores a rotated Telegram Wallet backend auth token signed by the signing half', async () => {
    const mnemonic = Array.from({ length: 24 }, (_, i) => `word${i}`);
    const anchorPublicKey = Buffer.from(ROTATION_ANCHOR_KEY_PAIR.publicKey).toString('hex');
    const signingPublicKey = Buffer.from(ROTATION_SIGNING_KEY_PAIR.publicKey).toString('hex');
    validateBip39Mnemonic.mockReturnValue(false);
    ton.validateMnemonic.mockResolvedValue(false);
    ton.isTelegramRotationMnemonic.mockReturnValue(true);
    expect(isBackendAuthTokenValid(
      ton.buildBackendAuthToken(ROTATION_SIGNING_KEY_PAIR.secretKey),
      signingPublicKey,
    )).toBe(true);

    await importMnemonic(['mainnet'], mnemonic);

    expect(ton.getKeyPairFromStoredMnemonic).toHaveBeenCalled();
    const savedAccount = setAccountValue.mock.calls[0][2];
    const authToken = savedAccount.byChain.ton.authToken;
    expect(authToken).toEqual(expect.any(String));
    expect(savedAccount.byChain.ton.publicKey).toBe(anchorPublicKey);
    expect(isBackendAuthTokenValid(authToken, signingPublicKey)).toBe(true);
    expect(isBackendAuthTokenValid(authToken, anchorPublicKey)).toBe(false);
  });

  it('rejects a stale Telegram rotation signing half before writing an account', async () => {
    const mnemonic = Array.from({ length: 24 }, (_, i) => `word${i}`);
    validateBip39Mnemonic.mockReturnValue(false);
    ton.validateMnemonic.mockResolvedValue(false);
    ton.isTelegramRotationMnemonic.mockReturnValue(true);
    ton.getWalletFromTelegramRotationMnemonic.mockResolvedValue({
      error: ApiTransactionError.TelegramWalletPublicKeyMismatch,
    });

    const result = await importMnemonic(['mainnet'], mnemonic);

    expect(result).toEqual({ error: ApiTransactionError.TelegramWalletPublicKeyMismatch });
    expect(setAccountValue).not.toHaveBeenCalled();
    expect(activateAccount).not.toHaveBeenCalled();
    expect(chains.ton.getWalletFromBip39Mnemonic).not.toHaveBeenCalled();
  });

  it('falls back to ordinary BIP39 import when a 24-word mnemonic only looks like Telegram rotation', async () => {
    const firstHalf = BIP39_TELEGRAM_ROTATION_COLLISION.slice(0, 12).join(' ');
    const secondHalf = BIP39_TELEGRAM_ROTATION_COLLISION.slice(12).join(' ');

    expect(bip39.validateMnemonic(BIP39_TELEGRAM_ROTATION_COLLISION.join(' '))).toBe(true);
    expect(bip39.validateMnemonic(firstHalf)).toBe(true);
    expect(bip39.validateMnemonic(secondHalf)).toBe(true);

    ton.validateMnemonic.mockResolvedValue(false);
    ton.isTelegramRotationMnemonic.mockReturnValue(true);
    ton.getWalletFromTelegramRotationMnemonic.mockResolvedValue({
      error: ApiTransactionError.TelegramWalletContractMismatch,
    });

    await importMnemonic(['mainnet'], BIP39_TELEGRAM_ROTATION_COLLISION);

    expect(ton.getWalletFromTelegramRotationMnemonic)
      .toHaveBeenCalledWith('mainnet', BIP39_TELEGRAM_ROTATION_COLLISION);
    expect(chains.ton.getWalletFromBip39Mnemonic)
      .toHaveBeenCalledWith('mainnet', BIP39_TELEGRAM_ROTATION_COLLISION, undefined);
    expect(setAccountValue).toHaveBeenCalledWith('0-mainnet', 'accounts', {
      type: 'bip39',
      byChain: {
        ton: {
          address: 'EQ-bip39',
          publicKey: 'pk',
          version: 'W5',
          index: 0,
          chain: 'ton',
        },
        solana: {
          address: 'solana-address',
          publicKey: 'solana-pk',
          index: 0,
          chain: 'solana',
        },
      },
    });
  });

  it('falls back to TON-native import when a native mnemonic only looks like Telegram rotation', async () => {
    const firstHalf = TON_NATIVE_TELEGRAM_ROTATION_COLLISION.slice(0, 12).join(' ');
    const secondHalf = TON_NATIVE_TELEGRAM_ROTATION_COLLISION.slice(12).join(' ');

    expect(await mnemonicValidate(TON_NATIVE_TELEGRAM_ROTATION_COLLISION)).toBe(true);
    expect(bip39.validateMnemonic(TON_NATIVE_TELEGRAM_ROTATION_COLLISION.join(' '))).toBe(false);
    expect(bip39.validateMnemonic(firstHalf)).toBe(true);
    expect(bip39.validateMnemonic(secondHalf)).toBe(true);

    validateBip39Mnemonic.mockReturnValue(false);
    ton.validateMnemonic.mockResolvedValue(true);
    ton.isTelegramRotationMnemonic.mockReturnValue(true);
    ton.getWalletFromTelegramRotationMnemonic.mockResolvedValue({
      error: ApiTransactionError.TelegramWalletContractMismatch,
    });
    ton.getWalletFromMnemonic.mockResolvedValue({
      address: 'EQ-ton-native',
      publicKey: 'ton-native-pk',
      version: 'W5',
      index: 0,
    });

    await importMnemonic(['mainnet'], TON_NATIVE_TELEGRAM_ROTATION_COLLISION);

    expect(ton.getWalletFromTelegramRotationMnemonic)
      .toHaveBeenCalledWith('mainnet', TON_NATIVE_TELEGRAM_ROTATION_COLLISION);
    expect(ton.getWalletFromMnemonic)
      .toHaveBeenCalledWith('mainnet', TON_NATIVE_TELEGRAM_ROTATION_COLLISION);
    expect(chains.ton.getWalletFromBip39Mnemonic).not.toHaveBeenCalled();
    expect(setAccountValue).toHaveBeenCalledWith('0-mainnet', 'accounts', {
      type: 'ton',
      byChain: {
        ton: {
          address: 'EQ-ton-native',
          publicKey: 'ton-native-pk',
          version: 'W5',
          index: 0,
        },
      },
    });
  });

  it.each([
    {
      name: 'Solana diagnostic',
      error: new Error('Solana error #8100002; Decode this error by running `npx @solana/errors decode -- 8100002`'),
    },
    { name: 'fetch failure', error: new TypeError('Load failed') },
    { name: 'non-Error exception', error: 'Unexpected provider response' },
  ])('hides $name without importing partial accounts', async ({ error }) => {
    ton.validateMnemonic.mockResolvedValue(false);
    chains.solana.getWalletFromBip39Mnemonic.mockImplementation((network: string) => (
      network === 'testnet'
        ? Promise.reject(error)
        : Promise.resolve([{ address: 'solana-address', publicKey: 'solana-pk', index: 0 }])
    ));

    const result = await importMnemonic(['mainnet', 'testnet'], DUAL_VALID);
    await flushPromises();

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(setAccountValue).not.toHaveBeenCalled();
    expect(activateAccount).not.toHaveBeenCalled();
  });
});

describe('resetAccounts', () => {
  it('clears Agent V2 state even when the runtime is disabled', async () => {
    const previousNoExtraFeatures = process.env.NO_EXTRA_FEATURES;
    delete process.env.NO_EXTRA_FEATURES;

    try {
      await resetAccounts();
    } finally {
      if (previousNoExtraFeatures === undefined) delete process.env.NO_EXTRA_FEATURES;
      else process.env.NO_EXTRA_FEATURES = previousNoExtraFeatures;
    }

    expect(resetAgentV2).toHaveBeenCalledTimes(1);
  });
});
