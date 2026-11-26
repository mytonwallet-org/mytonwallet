import { encodeRlp, Transaction, Wallet } from 'ethers';

import { ApiCommonError } from '../../types';

import { fetchPrivateKeyString } from './auth';
import { signTransfer } from './sign';

jest.mock('./auth', () => ({
  fetchPrivateKeyString: jest.fn(),
  getSignerFromPrivateKey: (_network: string, privateKey: string) => {
    const { Wallet: EthersWallet } = jest.requireActual<typeof import('ethers')>('ethers');
    return new EthersWallet(privateKey);
  },
}));

const PRIVATE_KEY = `0x${'11'.repeat(32)}`;
const WALLET_ADDRESS = new Wallet(PRIVATE_KEY).address;
const RECIPIENT = '0x2222222222222222222222222222222222222222';
const POLYGON_MAINNET_ID = 137;
const POLYGON_TESTNET_ID = 80002;

function unsignedTx(chainId: number): string {
  return Transaction.from({
    chainId, to: RECIPIENT, value: 10n ** 18n, nonce: 5, gasLimit: 21_000n, maxFeePerGas: 1n, maxPriorityFeePerGas: 1n,
  }).unsignedSerialized;
}

function unsignedLegacyTx(chainId: number): string {
  return Transaction.from({
    type: 0, chainId, to: RECIPIENT, value: 10n ** 18n, nonce: 5, gasLimit: 21_000n, gasPrice: 1_000_000_000n,
  }).unsignedSerialized;
}

const LEGACY_FIELDS = ['0x05', '0x3b9aca00', '0x5208', RECIPIENT, '0x0de0b6b3a7640000', '0x'];

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(fetchPrivateKeyString).mockResolvedValue(PRIVATE_KEY);
});

describe('signTransfer for a transaction a dApp serialized', () => {
  it.each([
    ['the chain id of Ethereum', unsignedTx(1)],
    ['the chain id of Polygon testnet', unsignedTx(POLYGON_TESTNET_ID)],
    ['a chain id the wallet does not know', unsignedTx(777_777)],
    ['a legacy transaction for Ethereum', unsignedLegacyTx(1)],
    // Six fields carry no chain id, so the signature is valid on every chain
    ['a legacy transaction with no chain id', encodeRlp(LEGACY_FIELDS)],
    ['a legacy transaction with chain id 0', encodeRlp([...LEGACY_FIELDS, '0x', '0x', '0x'])],
  ])('refuses %s on Polygon mainnet', async (_name, transaction) => {
    const result = await signTransfer('polygon', '0-mainnet', transaction, 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });

  it('refuses the mainnet chain id for a testnet account', async () => {
    const result = await signTransfer('polygon', '0-testnet', unsignedTx(POLYGON_MAINNET_ID), 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });

  it.each([
    ['0-mainnet', POLYGON_MAINNET_ID, unsignedTx(POLYGON_MAINNET_ID)],
    ['0-testnet', POLYGON_TESTNET_ID, unsignedTx(POLYGON_TESTNET_ID)],
    ['0-mainnet as a legacy transaction', POLYGON_MAINNET_ID, unsignedLegacyTx(POLYGON_MAINNET_ID)],
  ])('signs the chain id of Polygon for account %s', async (name, chainId, transaction) => {
    const [accountId] = name.split(' ');
    const result = await signTransfer('polygon', accountId, transaction, 'token');

    if (!Array.isArray(result)) throw new Error('Expected a signed transfer');
    const signedTx = Transaction.from(result[0].payload.signedTx as string);

    expect(signedTx.chainId).toBe(BigInt(chainId));
    expect(signedTx.from).toBe(WALLET_ADDRESS);
    expect(result[0].payload.signature).toBe(signedTx.signature!.serialized);
  });
});
