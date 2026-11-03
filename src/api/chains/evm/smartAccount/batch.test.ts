import { ApiTransactionError } from '../../../types';

import { getEvmProvider } from '../util/client';
import { getEvmDelegationAddress } from '../approvals';
import { estimateMaxCostFromPrepareResult, prepareAlchemyCalls } from './alchemyWallet';
import { estimateBatchUserOpFee } from './batch';

jest.mock('../approvals', () => ({ getEvmDelegationAddress: jest.fn() }));
jest.mock('../util/client', () => ({ getEvmProvider: jest.fn() }));
jest.mock('./alchemyWallet', () => ({
  estimateMaxCostFromPrepareResult: jest.fn(),
  prepareAlchemyCalls: jest.fn(),
}));

const ADDRESS = '0x1111111111111111111111111111111111111111';
const ROUTER = '0x2222222222222222222222222222222222222222';
const GAS = 60_000_000_000_000n;
const VALUE = 520_545_380_000_000_000n;
const provider = { getBalance: jest.fn() };

beforeEach(() => {
  jest.mocked(getEvmProvider).mockReturnValue(provider as never);
  jest.mocked(getEvmDelegationAddress).mockResolvedValue(undefined);
  jest.mocked(prepareAlchemyCalls).mockResolvedValue({} as never);
  jest.mocked(estimateMaxCostFromPrepareResult).mockReturnValue(GAS);
});

describe('estimateBatchUserOpFee', () => {
  const estimate = () => estimateBatchUserOpFee('ethereum', 'mainnet', ADDRESS, [{ to: ROUTER, value: VALUE }]);

  it('refuses a batch whose native value leaves less than its gas', async () => {
    provider.getBalance.mockResolvedValue(VALUE + GAS - 1n);

    await expect(estimate()).resolves.toEqual({ error: ApiTransactionError.InsufficientBalance });
  });

  it('prices a batch the balance covers with its value and gas', async () => {
    provider.getBalance.mockResolvedValue(VALUE + GAS);

    await expect(estimate()).resolves.toEqual({ maxCost: GAS });
  });
});
