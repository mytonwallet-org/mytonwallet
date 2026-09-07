import { Interface } from 'ethers';

import { ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { fetchEvmWallet } from './util/account';
import { getEvmProvider } from './util/client';
import { fetchStoredChainAccount } from '../../common/accounts';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { checkTransactionDraft, submitGasfullTransfer } from './transfer';
import { getErc20Balance, getWalletBalance } from './wallet';

jest.mock('./util/client', () => ({ getEvmProvider: jest.fn() }));
jest.mock('./util/account', () => ({ fetchEvmWallet: jest.fn() }));
jest.mock('./wallet', () => ({ getWalletBalance: jest.fn(), getErc20Balance: jest.fn() }));
jest.mock('../../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('./auth', () => ({ fetchPrivateKeyString: jest.fn(), getSignerFromPrivateKey: jest.fn() }));
jest.mock('../../../util/logs', () => ({ logDebugError: jest.fn() }));

const ACCOUNT_ID = '0-mainnet';
const CHAIN = 'base';
const WALLET = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const RECIPIENT = '0x93fa28647b06ab40554d6905e4e9d8e8bb24380c';
const USDC = '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913';
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
