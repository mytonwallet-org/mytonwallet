import type { TransactionRequest } from 'ethers';
import { Interface, isError } from 'ethers';

import type { ExplainedTransferFee } from '../../../util/fee/transferFee';
import type {
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiFetchEstimateDieselResult,
  ApiNetwork,
  ApiNft,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  ApiSubmitGaslessTransferOptions,
  ApiSubmitGaslessTransferResult,
  ApiTransferPayload,
  EVMChain,
} from '../../types';
import type { EvmMetaTransaction } from './smartAccount/types';
import { ApiCommonError, ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { raceWithAbortSignal, throwIfAborted } from '../../../util/abortSignal';
import { parseAccountId } from '../../../util/account';
import { bigintMin, bigintMultiplyToNumber } from '../../../util/bigint';
import { getChainConfig } from '../../../util/chain';
import { SECOND } from '../../../util/dateFormat';
import { explainApiTransferFee, getDieselTokenAmount, isDieselAvailable } from '../../../util/fee/transferFee';
import { logDebugError } from '../../../util/logs';
import { fetchEvmWallet } from './util/account';
import { type EvmProvider, getEvmProvider } from './util/client';
import { fetchStoredChainAccount } from '../../common/accounts';
import { DIESEL_NOT_AVAILABLE } from '../../common/other';
import { getTokenByAddress } from '../../common/tokens';
import { bytesToBase64 } from '../../common/utils';
import { handleServerError } from '../../errors';
import { estimateBatchUserOpFee, submitBatchUserOp } from './smartAccount/batch';
import { isPimlicoGasToken } from './smartAccount/constants';
import { isValidAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { EVM_MAX_TRANSFER_FEE_MULTIPLIER } from './constants';
import { estimateEvmFee, estimateEvmGas } from './fee';
import { getErc20Balance, getWalletBalance } from './wallet';

const ERC20_TRANSFER_ABI = ['function transfer(address to, uint256 amount) returns (bool)'];
const ERC721_TRANSFER_ABI = ['function safeTransferFrom(address from, address to, uint256 tokenId)'];
const ERC1155_TRANSFER_ABI = [
  'function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes data)',
];
const erc20Interface = new Interface(ERC20_TRANSFER_ABI);
const erc721Interface = new Interface(ERC721_TRANSFER_ABI);
const erc1155Interface = new Interface(ERC1155_TRANSFER_ABI);

const FEE_ESTIMATE_CACHE_TTL = 5 * SECOND;

/** A native balance at or above this skips the diesel quote. 0.0001 ETH */
const MAX_BALANCE_WITH_CHECK_DIESEL = 100_000_000_000_000n;

/** Native fee used when the node rejects `estimateGas` because the wallet cannot pay gas */
const EVM_GASLESS_FALLBACK_NATIVE_FEE = 100_000n * 1_000_000_000n;

/** Swap diesel as a percentage of the transfer probe that prices it, since swap calls use more gas */
const SWAP_DIESEL_PROBE_PERCENT = 150n;

type FeeEstimateCacheEntry = {
  fee?: bigint;
  expiresAt?: number;
  inFlight?: Promise<bigint>;
};

const feeEstimateCache = new Map<string, FeeEstimateCacheEntry>();

export async function checkTransactionDraft(
  chain: EVMChain,
  options: ApiCheckTransactionDraftOptions,
  signal?: AbortSignal,
): Promise<ApiCheckTransactionDraftResult> {
  const {
    accountId, amount, toAddress, tokenAddress, payload,
  } = options;
  const { network } = parseAccountId(accountId);

  const provider = getEvmProvider(network, chain);
  const result: ApiCheckTransactionDraftResult = {};

  try {
    if (!isValidAddress(toAddress)) {
      return { error: ApiTransactionDraftError.InvalidToAddress };
    }

    result.resolvedAddress = toAddress;

    const { address } = await fetchEvmWallet(accountId, chain);

    const tokenBalance = tokenAddress
      ? await raceWithAbortSignal(() => getErc20Balance(network, chain, address, tokenAddress), signal)
      : undefined;
    const probeAmount = getDraftProbeAmount({ amount, tokenBalance });

    const feeEstimateTransaction = buildTransaction({
      from: address,
      to: toAddress,
      amount: probeAmount,
      tokenAddress,
      payload,
    });

    const feeCacheKey = buildFeeEstimateCacheKey({
      chain,
      network,
      from: address,
      to: toAddress,
      amount: tokenAddress ? probeAmount : undefined,
      tokenAddress,
      payload,
    });

    const feePromise = signal
      ? estimateEvmFee(provider, feeEstimateTransaction, signal)
      : getCachedEvmFeeEstimate(provider, feeCacheKey, feeEstimateTransaction);
    const { nativeBalance, fee } = await readDraftNativeFunding(chain, network, address, feePromise, signal);

    result.diesel = DIESEL_NOT_AVAILABLE;

    if (tokenAddress && tokenBalance !== undefined && nativeBalance < fee) {
      const { draft, isEnoughBalanceForGasless } = await checkTransactionDraftWithGasless({
        chain,
        draft: result,
        fee,
        network,
        accountId,
        address,
        tokenAddress,
        payload,
        amount,
        toAddress,
        allowGasless: options.allowGasless,
        nativeBalance,
        tokenBalance,
        signal,
      });

      if (isEnoughBalanceForGasless) {
        return draft;
      }
    }

    const nativeTokenSlug = getChainConfig(chain).nativeToken.slug;
    const fullFee = getEvmDraftFullFee({
      amount,
      nativeBalance,
      fee,
      tokenAddress,
    });

    result.explainedFee = explainApiTransferFee({
      fee: fullFee,
      realFee: fullFee,
      diesel: result.diesel,
      tokenSlug: nativeTokenSlug,
    });

    if (amount !== undefined) {
      const requiredNative = tokenBalance === undefined ? amount + fee : fee;
      const isEnoughToken = tokenBalance === undefined || tokenBalance >= amount;

      if (nativeBalance < requiredNative || !isEnoughToken) {
        result.error = ApiTransactionDraftError.InsufficientBalance;
      }
    }

    return result;
  } catch (err) {
    if (signal) throw err;
    logDebugError(`evm:${chain}:checkTransactionDraft`, err);

    return {
      ...handleServerError(err),
      ...result,
    };
  }
}

type CheckTransactionDraftWithGaslessParams = {
  chain: EVMChain;
  draft: ApiCheckTransactionDraftResult;
  fee: bigint;
  network: ApiNetwork;
  accountId: string;
  address: string;
  tokenAddress: string;
  payload?: ApiTransferPayload;
  amount?: bigint;
  toAddress: string;
  allowGasless?: boolean;
  nativeBalance: bigint;
  tokenBalance: bigint;
  signal?: AbortSignal;
};

async function checkTransactionDraftWithGasless(params: CheckTransactionDraftWithGaslessParams) {
  let isEnoughBalanceForGasless = false;

  params.draft.diesel = DIESEL_NOT_AVAILABLE;

  if (params.allowGasless) {
    params.draft.diesel = await getDiesel({
      chain: params.chain,
      network: params.network,
      accountId: params.accountId,
      address: params.address,
      tokenAddress: params.tokenAddress,
      payload: params.payload,
      amount: params.amount,
      toAddress: params.toAddress,
      nativeBalance: params.nativeBalance,
      tokenBalance: params.tokenBalance,
      nativeFee: params.fee,
      signal: params.signal,
    });
  }

  if (isDieselAvailable(params.draft.diesel)) {
    const dieselFee = getDieselTokenAmount(params.draft.diesel);

    isEnoughBalanceForGasless = params.tokenBalance >= dieselFee;

    if (isEnoughBalanceForGasless && (params.amount ?? 0n) + dieselFee > params.tokenBalance) {
      params.draft.error = ApiTransactionDraftError.InsufficientBalance;
    }
  }

  if (isEnoughBalanceForGasless && isDieselAvailable(params.draft.diesel)) {
    params.draft.explainedFee = buildGaslessExplainedFee(params.draft.diesel.realFee);
  }

  return {
    draft: params.draft,
    isEnoughBalanceForGasless,
  };
}

export function buildTransaction(options: {
  from: string;
  to: string;
  amount: bigint;
  tokenAddress?: string;
  payload?: ApiTransferPayload;
  nft?: ApiNft;
}): TransactionRequest {
  const {
    from, to, amount, tokenAddress, payload, nft,
  } = options;

  if (nft) {
    const [contractAddress, tokenId] = nft.address.split('/');

    if (nft.interface === 'ERC1155') {
      return {
        from,
        to: contractAddress,
        value: 0n,
        data: erc1155Interface.encodeFunctionData('safeTransferFrom', [from, to, BigInt(tokenId), 1n, '0x']),
      };
    }

    return {
      from,
      to: contractAddress,
      value: 0n,
      data: erc721Interface.encodeFunctionData('safeTransferFrom', [from, to, BigInt(tokenId)]),
    };
  }

  if (tokenAddress) {
    const data = erc20Interface.encodeFunctionData('transfer', [to, amount]);

    return {
      from,
      to: tokenAddress,
      value: 0n,
      data,
    };
  }

  const data = encodePayload(payload);

  return {
    from,
    to,
    value: amount,
    ...(data !== undefined && { data }),
  };
}

export async function submitGasfullTransfer(
  chain: EVMChain,
  options: ApiSubmitGasfullTransferOptions,
): Promise<ApiSubmitGasfullTransferResult | { error: string }> {
  const {
    accountId, enclaveToken = '', toAddress, amount, tokenAddress, payload, noFeeCheck,
  } = options;

  const { network } = parseAccountId(accountId);

  try {
    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address } = account.byChain[chain];
    const provider = getEvmProvider(network, chain);

    const transaction = buildTransaction({
      from: address,
      to: toAddress,
      amount,
      tokenAddress,
      payload,
    });

    if (!noFeeCheck) {
      // The caller's `fee` is a placeholder-recipient preview, or absent, so the gate prices the real transaction.
      const [nativeBalance, { gasLimit, fee }] = await Promise.all([
        getWalletBalance(chain, network, address),
        estimateEvmGas(provider, transaction),
      ]);
      const requiredNative = tokenAddress ? fee : fee + amount;

      if (nativeBalance < requiredNative) {
        return { error: ApiTransactionError.InsufficientBalance };
      }

      transaction.gasLimit = gasLimit;
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);

    const response = await signer.sendTransaction(transaction);

    return { txId: response.hash, msgHashForCexSwap: response.hash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitGasfullTransfer`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function submitGaslessTransfer(
  chain: EVMChain,
  options: ApiSubmitGaslessTransferOptions,
): Promise<ApiSubmitGaslessTransferResult | { error: string }> {
  const {
    accountId, enclaveToken = '', toAddress, amount, tokenAddress, payload,
  } = options;
  const { network } = parseAccountId(accountId);

  try {
    if (!isEvmGaslessToken(network, chain, tokenAddress)) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address } = await fetchEvmWallet(accountId, chain);
    const tokenBalance = await getErc20Balance(network, chain, address, tokenAddress);

    if (tokenBalance < amount) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const calls = [toEvmMetaTransaction(buildTransaction({
      from: address,
      to: toAddress,
      amount,
      tokenAddress,
      payload,
    }))];
    const quoted = await estimateBatchUserOpFee(chain, network, address, calls, {
      needsGasless: true,
      gasToken: tokenAddress,
    });

    if ('error' in quoted) {
      return { error: quoted.error };
    }

    if (tokenBalance < amount + quoted.maxCost) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const submitted = await submitBatchUserOp(
      chain, network, address, privateKey, calls, { needsGasless: true, gasToken: tokenAddress },
    );

    if ('error' in submitted) {
      return { error: submitted.error };
    }

    return { txId: submitted.txHash, msgHashForCexSwap: submitted.txHash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitGaslessTransfer`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function fetchEstimateDiesel(
  chain: EVMChain,
  accountId: string,
  tokenAddress: string,
): Promise<ApiFetchEstimateDieselResult> {
  const { network } = parseAccountId(accountId);

  try {
    const { address } = await fetchEvmWallet(accountId, chain);
    const [nativeBalance, tokenBalance] = await Promise.all([
      getWalletBalance(chain, network, address),
      getErc20Balance(network, chain, address, tokenAddress),
    ]);
    const provider = getEvmProvider(network, chain);
    const fee = await estimateEvmFee(provider, buildTransaction({
      from: address,
      to: address,
      amount: getDraftProbeAmount({ tokenBalance }),
      tokenAddress,
    })).catch((err: unknown) => {
      if (!isError(err, 'INSUFFICIENT_FUNDS')) throw err;

      return EVM_GASLESS_FALLBACK_NATIVE_FEE;
    });

    return await getDiesel({
      chain,
      network,
      accountId,
      address,
      tokenAddress,
      toAddress: address,
      nativeBalance,
      tokenBalance,
      nativeFee: fee,
    });
  } catch (err) {
    logDebugError(`evm:${chain}:fetchEstimateDiesel`, err);

    return DIESEL_NOT_AVAILABLE;
  }
}

type GetDieselParams = {
  chain: EVMChain;
  network: ApiNetwork;
  accountId: string;
  address: string;
  tokenAddress: string;
  payload?: ApiTransferPayload;
  amount?: bigint;
  toAddress: string;
  nativeBalance: bigint;
  tokenBalance: bigint;
  nativeFee: bigint;
  /** A swap already knows its native fee, so a small native balance still gets a quote */
  ignoresBalanceCeiling?: boolean;
  signal?: AbortSignal;
};

/** Decides whether the transfer must be gasless and fetches the diesel estimate from the backend */
async function getDiesel(params: GetDieselParams): Promise<ApiFetchEstimateDieselResult> {
  if (!isEvmGaslessToken(params.network, params.chain, params.tokenAddress)) return DIESEL_NOT_AVAILABLE;

  const isAboveCeiling = !params.ignoresBalanceCeiling && params.nativeBalance >= MAX_BALANCE_WITH_CHECK_DIESEL;

  if (isAboveCeiling || params.nativeBalance >= params.nativeFee || params.tokenBalance === 0n) {
    return DIESEL_NOT_AVAILABLE;
  }

  const account = await fetchStoredChainAccount(params.accountId, params.chain);

  if (account.type === 'ledger' || account.type === 'view') return DIESEL_NOT_AVAILABLE;

  try {
    const calls = [toEvmMetaTransaction(buildTransaction({
      from: params.address,
      to: params.toAddress,
      amount: getDraftProbeAmount({ amount: params.amount, tokenBalance: params.tokenBalance }),
      tokenAddress: params.tokenAddress,
      payload: params.payload,
    }))];
    const quoted = await raceWithAbortSignal(
      () => estimateBatchUserOpFee(
        params.chain,
        params.network,
        params.address,
        calls,
        { needsGasless: true, gasToken: params.tokenAddress },
      ),
      params.signal,
    );

    if ('error' in quoted || quoted.maxCost <= 0n) return DIESEL_NOT_AVAILABLE;

    const diesel: ApiFetchEstimateDieselResult = {
      status: 'available',
      amount: quoted.maxCost,
      nativeAmount: 0n,
      remainingFee: 0n,
      realFee: quoted.maxCost,
    };
    const tokenAmount = getDieselTokenAmount(diesel);

    if (tokenAmount === 0n) {
      return diesel;
    }

    return params.tokenBalance >= tokenAmount ? diesel : DIESEL_NOT_AVAILABLE;
  } catch (err) {
    throwIfAborted(params.signal);
    logDebugError(`evm:${params.chain}:getDiesel`, err);

    return DIESEL_NOT_AVAILABLE;
  }
}

/** Diesel for a swap whose native fee the wallet cannot pay. The fee is the swap estimate, not a transfer probe. */
export async function estimateEvmSwapDiesel(
  chain: EVMChain,
  accountId: string,
  tokenAddress: string,
  nativeFee: bigint,
): Promise<ApiFetchEstimateDieselResult> {
  const { network } = parseAccountId(accountId);

  // Every swap quote refresh calls this, so a quote that cannot be gasless reads no token balance
  if (!isEvmGaslessToken(network, chain, tokenAddress)) return DIESEL_NOT_AVAILABLE;

  try {
    const { address } = await fetchEvmWallet(accountId, chain);
    const nativeBalance = await getWalletBalance(chain, network, address);

    if (nativeBalance >= nativeFee) return DIESEL_NOT_AVAILABLE;

    const tokenBalance = await getErc20Balance(network, chain, address, tokenAddress);
    const diesel = await getDiesel({
      chain,
      network,
      accountId,
      address,
      tokenAddress,
      toAddress: address,
      nativeBalance,
      tokenBalance,
      nativeFee,
      ignoresBalanceCeiling: true,
    });

    if (!isDieselAvailable(diesel)) return diesel;

    const amount = diesel.amount * SWAP_DIESEL_PROBE_PERCENT / 100n;

    return tokenBalance >= amount ? { ...diesel, amount } : DIESEL_NOT_AVAILABLE;
  } catch (err) {
    logDebugError(`evm:${chain}:estimateEvmSwapDiesel`, err);

    return DIESEL_NOT_AVAILABLE;
  }
}

function isEvmGaslessToken(network: ApiNetwork, chain: EVMChain, tokenAddress: string) {
  if (network !== 'mainnet' || !isPimlicoGasToken(network, chain, tokenAddress)) return false;

  return !!getTokenByAddress(tokenAddress, chain)?.isGaslessEnabled;
}

function toEvmMetaTransaction(transaction: TransactionRequest): EvmMetaTransaction {
  const { to, value, data } = transaction;

  if (typeof to !== 'string') {
    throw new Error('Transfer target is missing');
  }

  return {
    to,
    value: typeof value === 'bigint' ? value : 0n,
    data: typeof data === 'string' ? data : '0x',
  };
}

function buildGaslessExplainedFee(tokenFee: bigint): ExplainedTransferFee {
  const terms = {
    token: tokenFee,
    native: 0n,
  };

  return {
    isGasless: true,
    canTransferFullBalance: false,
    realFee: {
      precision: 'exact',
      terms,
      nativeSum: 0n,
    },
    fullFee: {
      precision: 'exact',
      terms,
      nativeSum: 0n,
    },
  };
}

async function readDraftNativeFunding(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  feePromise: Promise<bigint>,
  signal?: AbortSignal,
) {
  try {
    const [nativeBalance, fee] = await Promise.all([
      raceWithAbortSignal(() => getWalletBalance(chain, network, address), signal),
      feePromise,
    ]);

    return { nativeBalance, fee };
  } catch (err) {
    if (!isError(err, 'INSUFFICIENT_FUNDS')) throw err;

    const nativeBalance = await raceWithAbortSignal(() => getWalletBalance(chain, network, address), signal);

    return { nativeBalance, fee: EVM_GASLESS_FALLBACK_NATIVE_FEE };
  }
}

async function getCachedEvmFeeEstimate(
  provider: EvmProvider,
  cacheKey: string,
  txRequest: TransactionRequest,
): Promise<bigint> {
  const now = Date.now();
  const cached = feeEstimateCache.get(cacheKey);

  if (cached?.fee !== undefined && cached.expiresAt !== undefined && cached.expiresAt > now) {
    return cached.fee;
  }

  if (cached?.inFlight) {
    return cached.inFlight;
  }

  const inFlight = estimateEvmFee(provider, txRequest).then((fee) => {
    feeEstimateCache.set(cacheKey, {
      fee,
      expiresAt: Date.now() + FEE_ESTIMATE_CACHE_TTL,
    });
    return fee;
  }).catch((err) => {
    feeEstimateCache.delete(cacheKey);
    throw err;
  });

  feeEstimateCache.set(cacheKey, { inFlight });

  return inFlight;
}

function buildFeeEstimateCacheKey({
  chain,
  network,
  from,
  to,
  amount,
  tokenAddress,
  payload,
}: {
  chain: EVMChain;
  network: ApiNetwork;
  from: string;
  to: string;
  amount: bigint | undefined;
  tokenAddress?: string;
  payload?: ApiTransferPayload;
}) {
  return JSON.stringify({
    chain,
    network,
    from,
    to,
    tokenAddress,
    // Native transfer gas does not depend on the sent value, so amount is omitted from the cache key.
    amount: tokenAddress ? amount?.toString() : undefined,
    payload: normalizePayloadForFeeCacheKey(payload),
  });
}

function normalizePayloadForFeeCacheKey(payload?: ApiTransferPayload) {
  if (!payload) return undefined;

  if (payload.type === 'comment') {
    return {
      type: payload.type,
      text: payload.text,
    };
  }

  if (payload.type === 'base64') {
    return {
      type: payload.type,
      data: payload.data,
    };
  }

  return {
    type: payload.type,
    data: bytesToBase64(payload.data),
  };
}

export async function sendSignedTransaction(
  chain: EVMChain,
  serializedTransaction: string,
  network: ApiNetwork,
): Promise<string> {
  const provider = getEvmProvider(network, chain);

  const normalized = serializedTransaction.startsWith('0x') ? serializedTransaction : `0x${serializedTransaction}`;

  const response = await provider.broadcastTransaction(normalized);

  return response.hash;
}

/**
 * `estimateGas` reverts a token transfer above the balance, so the probe is clamped to it and a shortfall is priced;
 * one unit, not zero, prices the recipient's balance write. Native gas ignores the value, so zero keeps the fee stable.
 */
function getDraftProbeAmount({ amount, tokenBalance }: { amount?: bigint; tokenBalance?: bigint }): bigint {
  if (tokenBalance === undefined) {
    return 0n;
  }

  return bigintMin(amount ?? 1n, tokenBalance);
}

function getEvmDraftFullFee({
  amount,
  nativeBalance,
  fee,
  tokenAddress,
}: {
  amount: bigint | undefined;
  nativeBalance: bigint;
  fee: bigint;
  tokenAddress?: string;
}): bigint {
  if (tokenAddress || amount === undefined) {
    return fee;
  }

  const reservedFee = bigintMultiplyToNumber(fee, EVM_MAX_TRANSFER_FEE_MULTIPLIER);

  if (nativeBalance - amount <= reservedFee) {
    return reservedFee;
  }

  return fee;
}

function encodePayload(payload: ApiTransferPayload | undefined): string | undefined {
  if (!payload) return undefined;

  if (payload.type === 'comment') {
    return `0x${Buffer.from(payload.text, 'utf-8').toString('hex')}`;
  }
  if (payload.type === 'binary') {
    return `0x${Buffer.from(payload.data).toString('hex')}`;
  }
  if (payload.type === 'base64') {
    return `0x${Buffer.from(payload.data, 'base64').toString('hex')}`;
  }

  return undefined;
}
