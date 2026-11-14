import { ARBITRUM_USDC_MAINNET } from '../../../config';
import { getEvmProvider } from './util/client';
import depositFixture from '../../../../tests/fixtures/perpsDeposit.json';
import { PERPS_CCTP_EXTENSION_ADDRESS } from '../../common/perps';
import { submitBatchUserOp, validateEvmSwapCalls } from './smartAccount/batch';
import { getEvmDelegationAddress } from './approvals';
import { estimatePerpsDepositNetworkFee, submitPerpsCctpDepositTransfer } from './perps';

jest.mock('./approvals', () => ({ getEvmDelegationAddress: jest.fn() }));
jest.mock('./smartAccount/batch', () => ({
  estimateBatchUserOpFee: jest.fn(),
  submitBatchUserOp: jest.fn(),
  validateEvmSwapCalls: jest.fn(),
}));
jest.mock('./util/client', () => ({ getEvmProvider: jest.fn() }));

const WALLET = depositFixture.permitData.values.from;
const ALCHEMY_DELEGATE = '0x77021100bD87b7008e5E1989d0Eb38555D0D0000';
const getFeeData = jest.fn();
const getBalance = jest.fn();
let now = 0;

beforeEach(() => {
  jest.resetAllMocks();
  // Each test starts after the previous one's cached gas price has expired.
  now += 60_000;
  jest.spyOn(Date, 'now').mockImplementation(() => now);
  jest.mocked(getEvmProvider).mockReturnValue({ getFeeData, getBalance } as never);
  getFeeData.mockResolvedValue({ maxFeePerGas: 40_000_000n, gasPrice: 20_000_000n });
  getBalance.mockResolvedValue(10n ** 18n);
  jest.mocked(getEvmDelegationAddress).mockResolvedValue(ALCHEMY_DELEGATE);
});

test('deposit network fee is refused on a chain that takes no deposits', async () => {
  await expect(estimatePerpsDepositNetworkFee('base', 'mainnet', WALLET)).rejects.toThrow('No Perps deposits on base');
  expect(getEvmProvider).not.toHaveBeenCalled();
});

test.each([
  ['a delegated wallet', ALCHEMY_DELEGATE, 300_000n],
  ['a wallet that installs its delegation', undefined, 360_000n],
  ['a wallet delegated elsewhere', '0x1234567890123456789012345678901234567890', 360_000n],
])('deposit network fee of %s is its userOp gas at the max fee per gas', async (_, delegate, gas) => {
  jest.mocked(getEvmDelegationAddress).mockResolvedValue(delegate);

  expect(await estimatePerpsDepositNetworkFee('arbitrum', 'mainnet', WALLET)).toBe(gas * 40_000_000n);
  expect(getEvmProvider).toHaveBeenCalledWith('mainnet', 'arbitrum');
  expect(getEvmDelegationAddress).toHaveBeenCalledWith('arbitrum', 'mainnet', WALLET);
});

test('a provider without EIP-1559 fee data prices the deposit at its gas price', async () => {
  getFeeData.mockResolvedValue({ maxFeePerGas: undefined, gasPrice: 20_000_000n });

  expect(await estimatePerpsDepositNetworkFee('arbitrum', 'mainnet', WALLET)).toBe(300_000n * 20_000_000n);
});

test('fee data is cached for 30 seconds per network and wallet, and a failed gas price is not cached', async () => {
  getFeeData.mockRejectedValueOnce(new Error('rpc down'));
  await expect(estimatePerpsDepositNetworkFee('arbitrum', 'mainnet', WALLET)).rejects.toThrow('rpc down');

  await estimatePerpsDepositNetworkFee('arbitrum', 'mainnet', WALLET);
  getFeeData.mockResolvedValue({ maxFeePerGas: 50_000_000n, gasPrice: 25_000_000n });
  now += 29_000;
  expect(await estimatePerpsDepositNetworkFee('arbitrum', 'mainnet', WALLET)).toBe(300_000n * 40_000_000n);
  expect(await estimatePerpsDepositNetworkFee('arbitrum', 'testnet', WALLET)).toBe(300_000n * 50_000_000n);
  now += 2_000;
  expect(await estimatePerpsDepositNetworkFee('arbitrum', 'mainnet', WALLET)).toBe(300_000n * 50_000_000n);
  expect(getFeeData).toHaveBeenCalledTimes(4);
  expect(getEvmDelegationAddress).toHaveBeenCalledTimes(3);
});

test('a submitted deposit reports its transaction hash', async () => {
  jest.mocked(validateEvmSwapCalls).mockReturnValue(undefined);
  jest.mocked(submitBatchUserOp).mockResolvedValue({ userOpHash: '0xuserop', txHash: '0xdeposit', success: true });

  expect(await submitPerpsCctpDepositTransfer({ network: 'mainnet', address: WALLET, privateKey: '0x01' }, [
    { to: PERPS_CCTP_EXTENSION_ADDRESS, value: 0n, data: '0x' },
  ])).toEqual({ txHash: '0xdeposit' });
  expect(submitBatchUserOp).toHaveBeenCalledWith(
    'arbitrum', 'mainnet', WALLET, '0x01', expect.any(Array), undefined,
  );
});

test('a deposit without enough ETH for its userOp is submitted gasless', async () => {
  getBalance.mockResolvedValue(0n);
  jest.mocked(validateEvmSwapCalls).mockReturnValue(undefined);
  jest.mocked(submitBatchUserOp).mockResolvedValue({ userOpHash: '0xuserop', txHash: '0xdeposit', success: true });

  await submitPerpsCctpDepositTransfer({ network: 'mainnet', address: WALLET, privateKey: '0x01' }, [
    { to: PERPS_CCTP_EXTENSION_ADDRESS, value: 0n, data: '0x' },
  ]);

  expect(submitBatchUserOp).toHaveBeenCalledWith(
    'arbitrum',
    'mainnet',
    WALLET,
    '0x01',
    expect.any(Array),
    { needsGasless: true, gasToken: ARBITRUM_USDC_MAINNET.tokenAddress },
  );
});
