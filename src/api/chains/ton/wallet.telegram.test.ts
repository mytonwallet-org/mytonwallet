import { beginCell } from '@ton/core';
import * as bip39 from 'bip39';
import nacl from 'tweetnacl';

const mockGetAddressInfo = jest.fn();
const mockRunMethodWithError = jest.fn();
const mockGetWalletInfos = jest.fn();

jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'),
  getTonClient: () => ({
    getAddressInfo: mockGetAddressInfo,
    runMethodWithError: mockRunMethodWithError,
  }),
}));

jest.mock('./toncenter', () => ({ getWalletInfos: (...args: unknown[]) => mockGetWalletInfos(...args) }));

import { ApiTransactionError } from '../../types';

import * as HDKey from '../../../lib/ed25519-hd-key';
import {
  getTelegramWalletTrampolineCode,
} from './contracts/TelegramWallet';
import { getWalletFromTelegramRotationMnemonic } from './auth';
import { TON_BIP39_PATH } from './constants';
import {
  getTelegramWalletInfo,
  getWalletVersionInfos,
  publicKeyToAddress,
} from './wallet';

const PUBLIC_KEY = Buffer.from('1a4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c295', 'hex');
const ROTATED_PUBLIC_KEY = Buffer.from('2b4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c295', 'hex');
const TELEGRAM_ADDRESS = publicKeyToAddress('mainnet', PUBLIC_KEY, 'telegram', false);
const TELEGRAM_TESTNET_ADDRESS = publicKeyToAddress('testnet', PUBLIC_KEY, 'telegram', true);
const TELEGRAM_MAINNET_SUBWALLET_ID = 0x7FFF7F11;
const TELEGRAM_TESTNET_SUBWALLET_ID = 0x7FFF7FFD;
const TELEGRAM_CODE = getTelegramWalletTrampolineCode().toBoc().toString('base64');
const UNKNOWN_CODE = beginCell().storeUint(0xdeadbeef, 32).endCell().toBoc().toString('base64');
const ROTATION_ANCHOR_HALF = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon'
  + ' about';
const ROTATION_SIGNING_HALF = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';

let telegramPublicKey = PUBLIC_KEY;
let telegramSubwalletId = TELEGRAM_MAINNET_SUBWALLET_ID;

function bip39HalfToTonPublicKey(phrase: string) {
  const seed = bip39.mnemonicToSeedSync(phrase).toString('hex');
  const { key } = HDKey.derivePath(TON_BIP39_PATH.replace('{index}', '0'), seed);

  return nacl.sign.keyPair.fromSeed(key).publicKey;
}

function publicKeyToStackValue(publicKey: Uint8Array) {
  return BigInt(`0x${Buffer.from(publicKey).toString('hex')}`);
}

function mockTelegramGetters() {
  mockRunMethodWithError.mockImplementation((_address, method: string) => {
    const value = method === 'get_public_key'
      ? publicKeyToStackValue(telegramPublicKey)
      : BigInt(telegramSubwalletId);

    return Promise.resolve({
      exit_code: 0,
      stack: {
        readBigNumber: () => value,
      },
    });
  });
}

describe('getTelegramWalletInfo', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    telegramPublicKey = PUBLIC_KEY;
    telegramSubwalletId = TELEGRAM_MAINNET_SUBWALLET_ID;
    mockTelegramGetters();
  });

  it('reports contract mismatch when the address is not the Telegram Wallet trampoline contract', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: UNKNOWN_CODE, state: 'active' });

    await expect(getTelegramWalletInfo('mainnet', TELEGRAM_ADDRESS, PUBLIC_KEY, false)).resolves.toMatchObject({
      isTelegramWallet: false,
      isPublicKeyMismatch: false,
    });
  });

  it('reports key mismatch when Telegram Wallet storage was rotated away from the imported key', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });
    telegramPublicKey = ROTATED_PUBLIC_KEY;

    await expect(getTelegramWalletInfo('mainnet', TELEGRAM_ADDRESS, PUBLIC_KEY, false)).resolves.toMatchObject({
      isTelegramWallet: true,
      isPublicKeyMismatch: true,
      publicKey: ROTATED_PUBLIC_KEY,
    });
  });

  it('reloads the public key instead of using the generic cached wallet public key', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });

    await expect(getTelegramWalletInfo('mainnet', TELEGRAM_ADDRESS, PUBLIC_KEY, false)).resolves.toMatchObject({
      isTelegramWallet: true,
      isPublicKeyMismatch: false,
      publicKey: PUBLIC_KEY,
    });

    telegramPublicKey = ROTATED_PUBLIC_KEY;

    await expect(getTelegramWalletInfo('mainnet', TELEGRAM_ADDRESS, PUBLIC_KEY, false)).resolves.toMatchObject({
      isTelegramWallet: true,
      isPublicKeyMismatch: true,
      publicKey: ROTATED_PUBLIC_KEY,
    });
  });
});

describe('getWalletVersionInfos Telegram filtering', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetWalletInfos.mockImplementation((_network, addresses: string[]) => Promise.resolve(Object.fromEntries(
      addresses.map((address) => [address, {
        address,
        balance: 0n,
        isInitialized: true,
        lastTxId: undefined,
        seqno: 0,
      }]),
    )));
    telegramPublicKey = PUBLIC_KEY;
    telegramSubwalletId = TELEGRAM_MAINNET_SUBWALLET_ID;
    mockTelegramGetters();
  });

  it('filters out the Telegram candidate when its trampoline contract is not deployed', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: '', state: 'uninitialized' });

    await expect(getWalletVersionInfos('mainnet', PUBLIC_KEY, ['telegram'])).resolves.toEqual([]);
  });

  it('filters out the Telegram candidate when the on-chain key mismatches the imported key', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });
    telegramPublicKey = ROTATED_PUBLIC_KEY;

    await expect(getWalletVersionInfos('mainnet', PUBLIC_KEY, ['telegram'])).resolves.toEqual([]);
  });

  it('keeps the Telegram candidate when trampoline, subwallet id and public key all match', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });

    const [candidate] = await getWalletVersionInfos('mainnet', PUBLIC_KEY, ['telegram']);

    expect(candidate).toMatchObject({ address: TELEGRAM_ADDRESS, version: 'telegram' });
    expect(candidate.isTestnetSubwalletId).toBeUndefined();
  });

  it('keeps the testnet Telegram candidate when its testnet subwallet id matches', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });
    telegramSubwalletId = TELEGRAM_TESTNET_SUBWALLET_ID;

    await expect(getWalletVersionInfos('testnet', PUBLIC_KEY, ['telegram'])).resolves.toMatchObject([
      {
        address: TELEGRAM_TESTNET_ADDRESS,
        version: 'telegram',
        isTestnetSubwalletId: true,
      },
    ]);
  });
});

describe('getWalletFromTelegramRotationMnemonic', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    telegramSubwalletId = TELEGRAM_MAINNET_SUBWALLET_ID;
    mockTelegramGetters();
  });

  it('builds the Telegram Wallet address from the anchor half and validates the current signing half', async () => {
    const anchorPublicKey = bip39HalfToTonPublicKey(ROTATION_ANCHOR_HALF);
    const signingPublicKey = bip39HalfToTonPublicKey(ROTATION_SIGNING_HALF);
    const mnemonic = `${ROTATION_ANCHOR_HALF} ${ROTATION_SIGNING_HALF}`.split(' ');
    telegramPublicKey = Buffer.from(signingPublicKey);
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });

    await expect(getWalletFromTelegramRotationMnemonic('mainnet', mnemonic)).resolves.toEqual({
      address: publicKeyToAddress('mainnet', anchorPublicKey, 'telegram', undefined),
      publicKey: Buffer.from(anchorPublicKey).toString('hex'),
      version: 'telegram',
      index: 0,
      derivation: { path: TON_BIP39_PATH, index: 0 },
    });
  });

  it('rejects a stale Telegram rotation signing half before import', async () => {
    const mnemonic = `${ROTATION_ANCHOR_HALF} ${ROTATION_SIGNING_HALF}`.split(' ');
    telegramPublicKey = PUBLIC_KEY;
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });

    await expect(getWalletFromTelegramRotationMnemonic('mainnet', mnemonic)).resolves.toEqual({
      error: ApiTransactionError.TelegramWalletPublicKeyMismatch,
    });
  });
});
