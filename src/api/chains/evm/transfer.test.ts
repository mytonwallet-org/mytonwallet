import { Interface } from 'ethers';

import { ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { fetchEvmWallet } from './util/account';
import { getEvmProvider } from './util/client';
import { fetchStoredChainAccount } from '../../common/accounts';
import { getTokenByAddress } from '../../common/tokens';
import { estimateBatchUserOpFee, submitBatchUserOp } from './smartAccount/batch';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import {
  checkTransactionDraft,
  estimateEvmSwapDiesel,
  fetchEstimateDiesel,
  submitGasfullTransfer,
  submitGaslessTransfer,
} from './transfer';
import { getErc20Balance, getWalletBalance } from './wallet';

jest.mock('./util/client', () => ({ getEvmProvider: jest.fn() }));
jest.mock('./util/account', () => ({ fetchEvmWallet: jest.fn() }));
jest.mock('./wallet', () => ({ getWalletBalance: jest.fn(), getErc20Balance: jest.fn() }));
jest.mock('../../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('../../common/tokens', () => ({ getTokenByAddress: jest.fn() }));
jest.mock('./auth', () => ({ fetchPrivateKeyString: jest.fn(), getSignerFromPrivateKey: jest.fn() }));
jest.mock('./smartAccount/batch', () => ({ estimateBatchUserOpFee: jest.fn(), submitBatchUserOp: jest.fn() }));
jest.mock('../../../util/logs', () => ({ logDebugError: jest.fn() }));

const ACCOUNT_ID = '0-mainnet';
const CHAIN = 'base';
const WALLET = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const RECIPIENT = '0x93fa28647b06ab40554d6905e4e9d8e8bb24380c';
const USDC = '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913';
const ARBITRUM = 'arbitrum';
const ARBITRUM_USDC = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831';
const DIESEL_FEE = 40_000n;
const GAS_LIMIT = 50_000n;
const MAX_FEE_PER_GAS = 10n;
const FEE = GAS_LIMIT * MAX_FEE_PER_GAS;

const erc20 = new Interface(['function transfer(address to, uint256 amount) returns (bool)']);
const estimateGas = jest.fn();
const getFeeData = jest.fn();
const sendTransaction = jest.fn();

// The fee cache is keyed by the probe, so every draft here passes a signal to bypass it and see a fresh estimate.
const signal = new AbortController().signal;

function lastEstimatedRequest() {
  return estimateGas.mock.calls.at(-1)![0];
}

function decodeTokenProbe() {
  const request = lastEstimatedRequest();
  const [to, amount] = erc20.decodeFunctionData('transfer', request.data);

  return { contract: request.to, to: String(to).toLowerCase(), amount };
}

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(getEvmProvider).mockReturnValue({ estimateGas, getFeeData } as never);
  jest.mocked(fetchEvmWallet).mockResolvedValue({ address: WALLET } as never);
  jest.mocked(getWalletBalance).mockResolvedValue(10n * FEE);
  jest.mocked(getErc20Balance).mockResolvedValue(1_000_000n);
  estimateGas.mockResolvedValue(GAS_LIMIT);
  getFeeData.mockResolvedValue({ maxFeePerGas: MAX_FEE_PER_GAS, gasPrice: MAX_FEE_PER_GAS });
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({
    type: 'bip39', byChain: { [CHAIN]: { address: WALLET } },
  } as never);
  jest.mocked(fetchPrivateKeyString).mockResolvedValue('0x01');
  jest.mocked(getSignerFromPrivateKey).mockReturnValue({ connect: () => ({ sendTransaction }) } as never);
  sendTransaction.mockResolvedValue({ hash: '0xtx' });
});

describe('checkTransactionDraft', () => {
  it('probes a token transfer with one unit when no amount is given', async () => {
    await checkTransactionDraft(CHAIN, { accountId: ACCOUNT_ID, toAddress: RECIPIENT, tokenAddress: USDC }, signal);

    expect(decodeTokenProbe()).toEqual({ contract: USDC, to: RECIPIENT, amount: 1n });
  });

  it('caps a token probe at the wallet balance and reports the shortfall with a fee', async () => {
    jest.mocked(getErc20Balance).mockResolvedValue(700n);

    const result = await checkTransactionDraft(CHAIN, {
      accountId: ACCOUNT_ID, toAddress: RECIPIENT, tokenAddress: USDC, amount: 1_000n,
    }, signal);

    expect(decodeTokenProbe().amount).toBe(700n);
    expect(result.error).toBe(ApiTransactionDraftError.InsufficientBalance);
    expect(result.explainedFee?.fullFee?.nativeSum).toBe(FEE);
  });

  it('probes with zero when the wallet holds none of the token', async () => {
    jest.mocked(getErc20Balance).mockResolvedValue(0n);

    await checkTransactionDraft(CHAIN, { accountId: ACCOUNT_ID, toAddress: RECIPIENT, tokenAddress: USDC }, signal);

    expect(decodeTokenProbe().amount).toBe(0n);
  });

  it('probes a native transfer with zero value whatever the amount', async () => {
    await checkTransactionDraft(CHAIN, { accountId: ACCOUNT_ID, toAddress: RECIPIENT, amount: 123n }, signal);

    expect(lastEstimatedRequest()).toMatchObject({ to: RECIPIENT, value: 0n });
  });
});

describe('submitGasfullTransfer', () => {
  const tokenTransfer = { accountId: ACCOUNT_ID, toAddress: RECIPIENT, tokenAddress: USDC, amount: 1_000n };

  it('refuses a token transfer the wallet cannot pay gas for, whatever fee the caller claims', async () => {
    jest.mocked(getWalletBalance).mockResolvedValue(FEE - 1n);

    const result = await submitGasfullTransfer(CHAIN, { ...tokenTransfer, fee: 1n });

    expect(result).toEqual({ error: ApiTransactionError.InsufficientBalance });
    expect(sendTransaction).not.toHaveBeenCalled();
  });

  it('sends a token transfer with the gas it priced once the wallet covers it', async () => {
    jest.mocked(getWalletBalance).mockResolvedValue(FEE);

    const result = await submitGasfullTransfer(CHAIN, tokenTransfer);

    expect(result).toEqual({ txId: '0xtx', msgHashForCexSwap: '0xtx' });
    expect(sendTransaction).toHaveBeenCalledWith(expect.objectContaining({ to: USDC, gasLimit: GAS_LIMIT }));
  });

  it('requires the amount on top of the gas for a native transfer', async () => {
    const nativeTransfer = { accountId: ACCOUNT_ID, toAddress: RECIPIENT, amount: 1_000n };
    jest.mocked(getWalletBalance).mockResolvedValue(FEE + 999n);

    expect(await submitGasfullTransfer(CHAIN, nativeTransfer)).toEqual({
      error: ApiTransactionError.InsufficientBalance,
    });

    jest.mocked(getWalletBalance).mockResolvedValue(FEE + 1_000n);

    expect(await submitGasfullTransfer(CHAIN, nativeTransfer)).toEqual({ txId: '0xtx', msgHashForCexSwap: '0xtx' });
  });
});

describe('gasless transfer', () => {
  const transfer = {
    accountId: ACCOUNT_ID,
    toAddress: RECIPIENT,
    tokenAddress: ARBITRUM_USDC,
    amount: 1_000n,
    allowGasless: true,
  };

  beforeEach(() => {
    jest.mocked(getWalletBalance).mockResolvedValue(0n);
    jest.mocked(getErc20Balance).mockResolvedValue(1_000_000n);
    jest.mocked(getTokenByAddress).mockReturnValue({ isGaslessEnabled: true } as never);
    jest.mocked(estimateBatchUserOpFee).mockResolvedValue({ maxCost: DIESEL_FEE });
    jest.mocked(submitBatchUserOp).mockResolvedValue({
      txHash: '0xuserop', userOpHash: '0xop', success: true,
    });
  });

  it('prices a token transfer in the token when ETH cannot cover gas', async () => {
    const result = await checkTransactionDraft(ARBITRUM, transfer, signal);

    expect(result.error).toBeUndefined();
    expect(result.diesel).toMatchObject({
      status: 'available', amount: DIESEL_FEE, nativeAmount: 0n, remainingFee: 0n, realFee: DIESEL_FEE,
    });
    expect(result.explainedFee).toMatchObject({
      isGasless: true,
      canTransferFullBalance: false,
      realFee: { terms: { token: DIESEL_FEE, native: 0n }, nativeSum: 0n },
      fullFee: { terms: { token: DIESEL_FEE, native: 0n }, nativeSum: 0n },
    });
    expect(estimateBatchUserOpFee).toHaveBeenCalledWith(
      ARBITRUM,
      'mainnet',
      WALLET,
      [expect.objectContaining({ to: ARBITRUM_USDC, value: 0n })],
      { needsGasless: true, gasToken: ARBITRUM_USDC },
    );
  });

  it('keeps the native fee when the wallet can pay gas', async () => {
    jest.mocked(getWalletBalance).mockResolvedValue(FEE);

    const result = await checkTransactionDraft(ARBITRUM, transfer, signal);

    expect(estimateBatchUserOpFee).not.toHaveBeenCalled();
    expect(result.explainedFee?.isGasless).toBe(false);
    expect(result.explainedFee?.fullFee?.nativeSum).toBe(FEE);
  });

  it('keeps the native fee when the token is not gasless', async () => {
    jest.mocked(getTokenByAddress).mockReturnValue({ isGaslessEnabled: false } as never);

    const result = await checkTransactionDraft(ARBITRUM, transfer, signal);

    expect(estimateBatchUserOpFee).not.toHaveBeenCalled();
    expect(result.error).toBe(ApiTransactionDraftError.InsufficientBalance);
    expect(result.explainedFee?.isGasless).toBe(false);
  });

  it('keeps the native fee when the wallet already holds a meaningful ETH balance', async () => {
    jest.mocked(getWalletBalance).mockResolvedValue(10n ** 18n);
    estimateGas.mockResolvedValue(2n * 10n ** 17n);

    const result = await checkTransactionDraft(ARBITRUM, transfer, signal);

    expect(estimateBatchUserOpFee).not.toHaveBeenCalled();
    expect(result.error).toBe(ApiTransactionDraftError.InsufficientBalance);
    expect(result.explainedFee?.isGasless).toBe(false);
  });

  it('reports the token shortfall and still prices the diesel fee', async () => {
    jest.mocked(getErc20Balance).mockResolvedValue(1_000n);
    jest.mocked(estimateBatchUserOpFee).mockResolvedValue({ maxCost: 200n });

    const result = await checkTransactionDraft(ARBITRUM, { ...transfer, amount: 900n }, signal);

    expect(result.error).toBe(ApiTransactionDraftError.InsufficientBalance);
    expect(result.explainedFee?.isGasless).toBe(true);
    expect(result.explainedFee?.fullFee?.terms.token).toBe(200n);
  });

  it('quotes diesel after the node rejects the gas estimate for an empty wallet', async () => {
    const insufficientFunds = Object.assign(new Error('insufficient funds'), { code: 'INSUFFICIENT_FUNDS' });
    estimateGas.mockRejectedValue(insufficientFunds);

    const result = await checkTransactionDraft(ARBITRUM, transfer, signal);

    expect(result.explainedFee?.isGasless).toBe(true);
    expect(estimateBatchUserOpFee).toHaveBeenCalledTimes(1);
  });

  it('does not offer diesel to a view-only wallet', async () => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      type: 'view', byChain: { [ARBITRUM]: { address: WALLET } },
    } as never);

    const result = await checkTransactionDraft(ARBITRUM, transfer, signal);

    expect(estimateBatchUserOpFee).not.toHaveBeenCalled();
    expect(result.explainedFee?.isGasless).toBe(false);
  });

  it('returns the same diesel quote without a recipient', async () => {
    const diesel = await fetchEstimateDiesel(ARBITRUM, ACCOUNT_ID, ARBITRUM_USDC);

    expect(diesel).toMatchObject({ status: 'available', amount: DIESEL_FEE, realFee: DIESEL_FEE });
    expect(estimateBatchUserOpFee).toHaveBeenCalledWith(
      ARBITRUM,
      'mainnet',
      WALLET,
      [expect.objectContaining({ to: ARBITRUM_USDC })],
      { needsGasless: true, gasToken: ARBITRUM_USDC },
    );
  });

  it('submits the token transfer as a gasless user operation', async () => {
    const result = await submitGaslessTransfer(ARBITRUM, { ...transfer, dieselAmount: DIESEL_FEE });

    expect(result).toEqual({ txId: '0xuserop', msgHashForCexSwap: '0xuserop' });
    expect(submitBatchUserOp).toHaveBeenCalledWith(
      ARBITRUM,
      'mainnet',
      WALLET,
      '0x01',
      [expect.objectContaining({
        to: ARBITRUM_USDC,
        data: erc20.encodeFunctionData('transfer', [RECIPIENT, 1_000n]),
      })],
      { needsGasless: true, gasToken: ARBITRUM_USDC },
    );
  });

  it('quotes diesel for a swap whose native fee exceeds a balance above the transfer ceiling', async () => {
    jest.mocked(getWalletBalance).mockResolvedValue(10n ** 18n);

    const diesel = await estimateEvmSwapDiesel(ARBITRUM, ACCOUNT_ID, ARBITRUM_USDC, 2n * 10n ** 18n);

    expect(diesel).toMatchObject({ status: 'available', amount: DIESEL_FEE * 3n / 2n, realFee: DIESEL_FEE });
  });

  it('offers no swap diesel when the token balance covers the transfer probe but not the swap margin', async () => {
    jest.mocked(getWalletBalance).mockResolvedValue(0n);
    jest.mocked(getErc20Balance).mockResolvedValue(DIESEL_FEE * 5n / 4n);

    const diesel = await estimateEvmSwapDiesel(ARBITRUM, ACCOUNT_ID, ARBITRUM_USDC, FEE);

    expect(diesel).toMatchObject({ status: 'not-available' });
  });

  it('skips the token balance and paymaster quote of a swap whose native fee the wallet covers', async () => {
    jest.mocked(getWalletBalance).mockResolvedValue(FEE);

    const diesel = await estimateEvmSwapDiesel(ARBITRUM, ACCOUNT_ID, ARBITRUM_USDC, FEE);

    expect(diesel).toMatchObject({ status: 'not-available' });
    expect(getErc20Balance).not.toHaveBeenCalled();
    expect(estimateBatchUserOpFee).not.toHaveBeenCalled();
  });

  it('reads no balance for a swap selling a token that is not gasless', async () => {
    jest.mocked(getTokenByAddress).mockReturnValue({ isGaslessEnabled: false } as never);

    const diesel = await estimateEvmSwapDiesel(ARBITRUM, ACCOUNT_ID, ARBITRUM_USDC, FEE);

    expect(diesel).toMatchObject({ status: 'not-available' });
    expect(getWalletBalance).not.toHaveBeenCalled();
    expect(getErc20Balance).not.toHaveBeenCalled();
  });

  it('refuses a gasless send the token balance cannot cover with the paymaster fee', async () => {
    jest.mocked(getErc20Balance).mockResolvedValue(1_000n);

    const result = await submitGaslessTransfer(ARBITRUM, { ...transfer, amount: 900n, dieselAmount: DIESEL_FEE });

    expect(result).toEqual({ error: ApiTransactionError.InsufficientBalance });
    expect(submitBatchUserOp).not.toHaveBeenCalled();
  });
});
