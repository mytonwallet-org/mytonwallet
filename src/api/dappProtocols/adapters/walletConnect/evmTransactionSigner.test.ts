import { Transaction } from 'ethers';

import type { EvmTransactionParams } from './types';

import { getEvmProvider } from '../../../chains/evm/util/client';
import { resolveWalletConnectEvmSerializedTx } from './evmTransaction';

jest.mock('../../../../util/logs', () => ({ logDebugError: jest.fn() }));
jest.mock('../../../chains', () => ({
  __esModule: true,
  default: { ethereum: { normalizeAddress: jest.requireActual('../../../chains/evm/address').normalizeAddress } },
}));
jest.mock('../../../chains/evm/util/client', () => ({ getEvmProvider: jest.fn() }));

const SIGNER = '0x11A43B91414B2c7083888D8f4E963988ddEe12A3';
const OTHER_SENDER = '0x52908400098527886E0F7030069857D2E4169EE7';
const RECIPIENT = '0x2222222222222222222222222222222222222222';

const provider = {
  getFeeData: jest.fn(),
  getTransactionCount: jest.fn(),
  estimateGas: jest.fn(),
};

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(getEvmProvider).mockReturnValue(provider as never);
  provider.getFeeData.mockResolvedValue({ maxFeePerGas: 200n, maxPriorityFeePerGas: 20n, gasPrice: 150n });
  provider.getTransactionCount.mockResolvedValue(7);
  provider.estimateGas.mockResolvedValue(21_000n);
});

function resolve(from: string | undefined) {
  return resolveWalletConnectEvmSerializedTx({
    raw: { from, to: RECIPIENT, value: '0x1' } as EvmTransactionParams,
    chain: 'ethereum',
    network: 'mainnet',
    caip2: 'eip155:1',
    signerAddress: SIGNER,
  });
}

it('refuses a sender other than the signing wallet before any provider call', async () => {
  await expect(resolve(OTHER_SENDER.toLowerCase())).rejects.toThrow('`from` is not the wallet that signs');

  expect(getEvmProvider).not.toHaveBeenCalled();
});

it.each([
  ['the signing wallet in lowercase', SIGNER.toLowerCase()],
  ['missing', undefined],
])('takes the nonce and the gas of the signing wallet when the sender is %s', async (_name, from) => {
  const serialized = await resolve(from);

  expect(provider.getTransactionCount).toHaveBeenCalledTimes(1);
  expect(provider.getTransactionCount).toHaveBeenCalledWith(SIGNER, 'pending');
  expect(provider.estimateGas).toHaveBeenCalledTimes(1);
  expect(provider.estimateGas).toHaveBeenCalledWith(expect.objectContaining({ from: SIGNER }));
  expect(Transaction.from(serialized).nonce).toBe(7);
});
