import { beginCell, SendMode } from '@ton/core';
import nacl from 'tweetnacl';

import type { ApiAccountWithChain } from '../../../types';
import { ApiTransactionError } from '../../../types';

const mockGetTelegramWalletInfo = jest.fn();
const mockFetchPrivateKey = jest.fn();
const mockCreateTransfer = jest.fn();

jest.mock('../auth', () => ({
  fetchPrivateKey: (...args: unknown[]) => mockFetchPrivateKey(...args),
}));
jest.mock('../wallet', () => ({
  getIsTestnetSubwalletId: jest.fn((network, version) => (
    network === 'testnet' && version === 'telegram' ? true : undefined
  )),
  getTelegramWalletInfo: (...args: unknown[]) => mockGetTelegramWalletInfo(...args),
  getTonWallet: jest.fn(() => ({
    createTransfer: (...args: unknown[]) => mockCreateTransfer(...args),
  })),
}));

import { checkTelegramWalletSigner, getSigner } from './signer';

const PUBLIC_KEY = Buffer.from('1a4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c295', 'hex');
const ANCHOR_KEY_PAIR = nacl.sign.keyPair.fromSeed(new Uint8Array(Array(32).fill(1)));
const SIGNING_KEY_PAIR = nacl.sign.keyPair.fromSeed(new Uint8Array(Array(32).fill(2)));

describe('checkTelegramWalletSigner', () => {
  const wallet = {
    address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
    publicKey: PUBLIC_KEY.toString('hex'),
    version: 'telegram',
    index: 0,
  } as const;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('rejects signing when the stored address is not a Telegram Wallet trampoline contract', async () => {
    mockGetTelegramWalletInfo.mockResolvedValue({
      isTelegramWallet: false,
      publicKey: PUBLIC_KEY,
      subwalletId: 0x7FFF7F11,
      isPublicKeyMismatch: false,
    });

    await expect(checkTelegramWalletSigner('mainnet', wallet, PUBLIC_KEY))
      .resolves.toEqual({ error: ApiTransactionError.TelegramWalletContractMismatch });
  });

  it('rejects signing when the on-chain public key no longer matches the imported key', async () => {
    mockGetTelegramWalletInfo.mockResolvedValue({
      isTelegramWallet: true,
      publicKey: Buffer.alloc(32, 1),
      subwalletId: 0x7FFF7F11,
      isPublicKeyMismatch: true,
    });

    await expect(checkTelegramWalletSigner('mainnet', wallet, PUBLIC_KEY))
      .resolves.toEqual({ error: ApiTransactionError.TelegramWalletPublicKeyMismatch });
  });

  it('checks testnet Telegram wallets against the testnet subwallet id', async () => {
    mockGetTelegramWalletInfo.mockResolvedValue({
      isTelegramWallet: true,
      publicKey: PUBLIC_KEY,
      subwalletId: 0x7FFF7FFD,
      isPublicKeyMismatch: false,
    });

    await expect(checkTelegramWalletSigner('testnet', wallet, PUBLIC_KEY)).resolves.toBeUndefined();
    expect(mockGetTelegramWalletInfo).toHaveBeenCalledWith('testnet', wallet.address, PUBLIC_KEY, true);
  });
});

describe('Telegram Wallet signer public key selection', () => {
  const account = {
    type: 'bip39',
    byChain: {
      ton: {
        address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
        publicKey: Buffer.from(ANCHOR_KEY_PAIR.publicKey).toString('hex'),
        version: 'telegram',
        index: 0,
      },
    },
  } satisfies ApiAccountWithChain<'ton'>;

  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateTransfer.mockReturnValue(beginCell().endCell());
    mockFetchPrivateKey.mockResolvedValue(SIGNING_KEY_PAIR.secretKey);
    mockGetTelegramWalletInfo.mockImplementation((_network, _address, publicKey: Uint8Array) => Promise.resolve({
      isTelegramWallet: true,
      publicKey: SIGNING_KEY_PAIR.publicKey,
      subwalletId: 0x7FFF7F11,
      isPublicKeyMismatch: Buffer.from(publicKey).toString('hex')
        !== Buffer.from(SIGNING_KEY_PAIR.publicKey).toString('hex'),
    }));
  });

  it('checks a rotated Telegram Wallet against the signing public key, not the anchor public key', async () => {
    const signer = getSigner('0-mainnet', account, 'enclave-token');

    const result = await signer.signTransactions([{
      messages: [],
      seqno: 7,
      sendMode: SendMode.PAY_GAS_SEPARATELY | SendMode.IGNORE_ERRORS,
    }]);

    expect(result).toHaveLength(1);
    expect(mockCreateTransfer).toHaveBeenCalled();
    expect(mockGetTelegramWalletInfo).toHaveBeenCalledWith(
      'mainnet',
      account.byChain.ton.address,
      SIGNING_KEY_PAIR.publicKey,
      undefined,
    );
  });
});
