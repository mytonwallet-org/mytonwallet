import { encodeRlp, Transaction, Wallet } from 'ethers';

import type { EvmTransactionParams } from './types';

import { getEvmProvider } from '../../../chains/evm/util/client';
import { resolveWalletConnectEvmSerializedTx } from './evmTransaction';

jest.mock('../../../chains', () => {
  const sdk = { normalizeAddress: (address: string) => address.toLowerCase() };

  return { __esModule: true, default: { ethereum: sdk, polygon: sdk } };
});
jest.mock('../../../chains/evm/util/client', () => ({ getEvmProvider: jest.fn() }));

const SIGNER = new Wallet(`0x${'11'.repeat(32)}`);
const RECIPIENT = '0x2222222222222222222222222222222222222222';
const POLYGON_MAINNET_ID = 137;

const provider = {
  getFeeData: jest.fn(),
  getTransactionCount: jest.fn(),
  estimateGas: jest.fn(),
};

function transaction(chainId: number) {
  return Transaction.from({
    chainId,
    to: RECIPIENT,
    value: 10n ** 18n,
    nonce: 5,
    gasLimit: 21_000n,
    maxFeePerGas: 100n,
    maxPriorityFeePerGas: 10n,
  });
}

function resolve(raw: string | EvmTransactionParams) {
  return resolveWalletConnectEvmSerializedTx({
    raw,
    chain: 'polygon',
    network: 'mainnet',
    caip2: `eip155:${POLYGON_MAINNET_ID}`,
    signerAddress: SIGNER.address,
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(getEvmProvider).mockReturnValue(provider as never);
  provider.getFeeData.mockResolvedValue({ maxFeePerGas: 200n, maxPriorityFeePerGas: 20n, gasPrice: 150n });
  provider.getTransactionCount.mockResolvedValue(5);
  provider.estimateGas.mockResolvedValue(21_000n);
});

describe('resolveWalletConnectEvmSerializedTx for a transaction the dApp serialized', () => {
  it.each([
    ['the chain id of Ethereum', transaction(1).unsignedSerialized],
    ['the chain id of Polygon testnet', transaction(80002).unsignedSerialized],
    ['a chain id the wallet does not know', transaction(777_777).unsignedSerialized],
    // A legacy transaction of six fields carries no chain id
    ['no chain id', encodeRlp(['0x05', '0x3b9aca00', '0x5208', RECIPIENT, '0x0de0b6b3a7640000', '0x'])],
  ])('rejects %s on a Polygon mainnet session', async (_name, raw) => {
    await expect(resolve(raw)).rejects.toThrow('Invalid transaction fields');
    expect(getEvmProvider).not.toHaveBeenCalled();
  });

  it('rejects an already signed transaction', async () => {
    const signed = await SIGNER.signTransaction(transaction(POLYGON_MAINNET_ID));

    await expect(resolve(signed)).rejects.toThrow('Invalid transaction fields');
    expect(getEvmProvider).not.toHaveBeenCalled();
  });

  it('keeps a transaction for the session chain and bumps its fees', async () => {
    const resolved = Transaction.from(await resolve(transaction(POLYGON_MAINNET_ID).unsignedSerialized));

    expect(resolved.chainId).toBe(BigInt(POLYGON_MAINNET_ID));
    expect(resolved.isSigned()).toBe(false);
    expect(resolved.to).toBe(RECIPIENT);
    expect(resolved.value).toBe(10n ** 18n);
    expect(resolved.maxFeePerGas).toBe(110n);
  });

  it('keeps a legacy transaction that carries the session chain id', async () => {
    const legacy = Transaction.from({
      type: 0, chainId: POLYGON_MAINNET_ID, to: RECIPIENT, value: 1n, nonce: 5, gasLimit: 21_000n, gasPrice: 100n,
    });
    const resolved = Transaction.from(await resolve(legacy.unsignedSerialized));

    expect(resolved.type).toBe(0);
    expect(resolved.chainId).toBe(BigInt(POLYGON_MAINNET_ID));
    expect(resolved.gasPrice).toBe(110n);
  });
});

describe('resolveWalletConnectEvmSerializedTx for transaction params', () => {
  const params: EvmTransactionParams = { from: SIGNER.address, to: RECIPIENT, value: '0x1', gas: '0x5208' };

  it.each([
    ['the hex chain id of Ethereum', '0x1'],
    ['the hex chain id of Polygon testnet', '0x13882'],
    ['the decimal chain id of Ethereum', 1],
    ['a chain id that is not a number', 'polygon'],
    ['a bigint chain id of another chain', 2n ** 60n],
    ['a chain id of an unsupported type', { chainId: 137 }],
  ])('rejects params that name %s on a Polygon mainnet session', async (_name, chainId) => {
    await expect(resolve({ ...params, chainId: chainId as string })).rejects.toThrow('Invalid transaction fields');
    expect(getEvmProvider).not.toHaveBeenCalled();
  });

  it.each([
    ['no chain id', undefined],
    ['an empty chain id', ''],
    // eslint-disable-next-line no-null/no-null -- dApps send JSON
    ['a null chain id', null],
    ['the bigint chain id of Polygon', 137n],
    ['the hex chain id of Polygon', '0x89'],
    ['the decimal chain id of Polygon', '137'],
  ])('builds a Polygon mainnet transaction from params that name %s', async (_name, chainId) => {
    const resolved = Transaction.from(await resolve({ ...params, chainId: chainId as string }));

    expect(resolved.chainId).toBe(BigInt(POLYGON_MAINNET_ID));
    expect(resolved.to).toBe(RECIPIENT);
    expect(resolved.value).toBe(1n);
  });
});
