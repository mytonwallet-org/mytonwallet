import { Cell, internal, SendMode } from '@ton/core';

import type { DieselStatus } from '../../../global/types';
import type { DappProtocolType } from '../../dappProtocols';
import type {
  ApiAccountWithChain,
  ApiAnyDisplayError,
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiFetchEstimateDieselResult,
  ApiNetwork,
  ApiParsedPayload,
  ApiSignedTransfer,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  ApiSubmitGaslessTransferOptions,
  ApiSubmitGaslessTransferResult,
  ApiToken,
  ApiWalletInfo,
} from '../../types';
import type {
  AnyTonTransferPayload,
  ApiCheckMultiTransactionDraftResult,
  ApiEmulationWithFallbackResult,
  ApiSubmitMultiTransferResult,
  PreparedTransactionToSign,
  TonTransferParams,
} from './types';
import type { Signer } from './util/signer';
import type { TonWallet } from './util/tonCore';
import { ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { DEFAULT_FEE, DIESEL_ADDRESS, STON_PTON_ADDRESS } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { bigintMultiplyToNumber } from '../../../util/bigint';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import { getToncoinAmountForTransfer } from '../../../util/fee/getTonOperationFees';
import { getDieselTokenAmount, isDieselAvailable } from '../../../util/fee/transferFee';
import { omit, pick, split } from '../../../util/iteratees';
import { logDebug, logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { getMaxMessagesInTransaction } from '../../../util/ton/transfer';
import { parsePayloadSlice } from './util/metadata';
import { sendExternal } from './util/sendExternal';
import { getSigner } from './util/signer';
import {
  commentToBytes,
  getOurFeePayload,
  getTonClient,
  getWalletPublicKey,
  isExpiredTransactionError,
  isSeqnoMismatchError,
  packBytesAsSnakeCell,
  packBytesAsSnakeForEncryptedData,
  parseAddress,
  parseBase64,
  parseStateInitCell,
} from './util/tonCore';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { callBackendGet } from '../../common/backend';
import { DIESEL_NOT_AVAILABLE } from '../../common/other';
import { withoutTransferConcurrency } from '../../common/preventTransferConcurrency';
import { getTokenByAddress } from '../../common/tokens';
import { MINUTE, SEC } from '../../constants';
import { ApiServerError, handleServerError } from '../../errors';
import { checkHasTransaction } from './activities';
import { resolveAddress } from './address';
import { ATTEMPTS, FEE_FACTOR, LEDGER_VESTING_SUBWALLET_ID, TRANSFER_TIMEOUT_SEC } from './constants';
import { emulateTransaction } from './emulation';
import {
  buildTokenTransfer,
  calculateTokenBalanceWithMintless,
  getTokenBalanceWithMintless,
} from './tokens';
import { getContractInfo, getTonWallet, getWalletBalance, getWalletInfo, getWalletSeqno } from './wallet';

/** Transaction options only available in TON */
type CustomTransactionOptions<T> = Omit<T, 'payload'> & {
  payload?: AnyTonTransferPayload;
  forwardAmount?: bigint;
};

const WAIT_TRANSFER_TIMEOUT = MINUTE;
const WAIT_PAUSE = SEC;

const WALLET_INFO_CACHE_TTL = 5 * SEC;

const MAX_BALANCE_WITH_CHECK_DIESEL = 100000000n; // 0.1 TON
const PENDING_DIESEL_TIMEOUT_SEC = 15 * 60; // 15 min

type WalletInfoCacheEntry = {
  info: ApiWalletInfo;
  fetchedAt: number;
};

const walletInfoCache = new Map<string, WalletInfoCacheEntry>();
const inFlightTransfers = new Set<string>();

function getWalletInfoCacheKey(network: ApiNetwork, address: string) {
  return `${network}:${address}`;
}

/** Blocks caching of wallet info during an active send to avoid using stale seqno */
function markTransferInFlight(network: ApiNetwork, address: string) {
  inFlightTransfers.add(getWalletInfoCacheKey(network, address));
}

function clearTransferInFlight(network: ApiNetwork, address: string) {
  inFlightTransfers.delete(getWalletInfoCacheKey(network, address));
}

function isTransferInFlight(network: ApiNetwork, address: string) {
  return inFlightTransfers.has(getWalletInfoCacheKey(network, address));
}

function readCachedWalletInfo(network: ApiNetwork, address: string) {
  const cacheKey = getWalletInfoCacheKey(network, address);
  const entry = walletInfoCache.get(cacheKey);
  if (!entry) return undefined;

  if (Date.now() - entry.fetchedAt > WALLET_INFO_CACHE_TTL) {
    walletInfoCache.delete(cacheKey);
    return undefined;
  }

  return entry.info;
}

function rememberWalletInfo(network: ApiNetwork, address: string, info: ApiWalletInfo) {
  if (isTransferInFlight(network, address)) {
    return;
  }

  walletInfoCache.set(getWalletInfoCacheKey(network, address), {
    info,
    fetchedAt: Date.now(),
  });
}

function consumeCachedWalletInfo(network: ApiNetwork, address: string, allowInFlight = false) {
  if (!allowInFlight && isTransferInFlight(network, address)) {
    return undefined;
  }

  const cacheKey = getWalletInfoCacheKey(network, address);
  const info = readCachedWalletInfo(network, address);
  if (info) {
    walletInfoCache.delete(cacheKey);
  }

  return info;
}

export async function checkTransactionDraft(
  options: CustomTransactionOptions<ApiCheckTransactionDraftOptions>,
): Promise<ApiCheckTransactionDraftResult> {
  const {
    accountId,
    amount = 0n,
    tokenAddress,
    payload: rawPayload,
    stateInit: stateInitString,
    forwardAmount,
    allowGasless,
  } = options;
  let { toAddress } = options;

  const { network } = parseAccountId(accountId);

  let result: ApiCheckTransactionDraftResult = {};

  try {
    result = await checkToAddress(network, toAddress);
    if ('error' in result) {
      return result;
    }

    toAddress = result.resolvedAddress!;

    const { isInitialized } = await getContractInfo(network, toAddress);

    let stateInit: Cell | undefined;

    if (stateInitString) {
      try {
        stateInit = Cell.fromBase64(stateInitString);
      } catch {
        return {
          ...result,
          error: ApiTransactionDraftError.InvalidStateInit,
        };
      }
    }

    if (result.isBounceable && !isInitialized && !stateInit) {
      result.isToAddressNew = !(await checkHasTransaction(network, toAddress));
      return {
        ...result,
        error: ApiTransactionDraftError.InactiveContract,
      };
    }

    result.resolvedAddress = toAddress;

    if (amount < 0n) {
      return {
        ...result,
        error: ApiTransactionDraftError.InvalidAmount,
      };
    }

    const account = await fetchStoredChainAccount(accountId, 'ton');
    const wallet = getTonWallet(account.byChain.ton);
    const { address, isInitialized: isWalletInitialized } = account.byChain.ton;
    const signer = getSigner(accountId, account, undefined, true);
    const walletInfo = await getWalletInfo(network, wallet);
    rememberWalletInfo(network, address, walletInfo);
    const { seqno, balance: toncoinBalance } = walletInfo;

    let toncoinAmount: bigint;
    let balance: bigint;
    let fee: bigint;
    let realFee: bigint;
    let payload: Cell | undefined;

    const payloadResult = await convertPayloadToCell(rawPayload, network, toAddress, signer);
    if ('error' in payloadResult) {
      return { ...result, error: payloadResult.error };
    }
    payload = payloadResult.cell;

    if (!tokenAddress) {
      balance = toncoinBalance;
      toncoinAmount = amount;
      fee = 0n;
      realFee = 0n;
    } else {
      const tokenTransfer = await buildTokenTransfer({
        network,
        tokenAddress,
        fromAddress: address,
        toAddress,
        amount,
        payload,
        forwardAmount,
        isLedger: account.type === 'ledger',
      });
      ({ amount: toncoinAmount, toAddress, payload } = tokenTransfer);
      const { realAmount: realToncoinAmount, isTokenWalletDeployed, mintlessTokenBalance } = tokenTransfer;

      // When the token is transferred, actually some TON is transferred, and the token sits inside the payload.
      // From the user perspective, this TON amount is a fee.
      fee = toncoinAmount;
      realFee = realToncoinAmount;

      const tokenWalletAddress = toAddress;
      balance = await calculateTokenBalanceWithMintless(
        network, tokenWalletAddress, isTokenWalletDeployed, mintlessTokenBalance,
      );
    }

    const isFullTonTransfer = !tokenAddress && toncoinBalance === amount;

    const signingResult = await signTransaction({
      account,
      messages: [{
        toAddress,
        amount: toncoinAmount,
        payload,
        stateInit,
        hints: {
          tokenAddress,
        },
      }],
      seqno,
      signer,
      doPayFeeFromAmount: isFullTonTransfer,
    });
    if ('error' in signingResult) {
      return {
        ...result,
        error: signingResult.error,
      };
    }

    // todo: Use `received` from the emulation to calculate the real fee. Check what happens when the receiver is the same wallet.
    const { networkFee } = applyFeeFactorToEmulationResult(
      await emulateTransactionWithFallback(network, wallet, signingResult.transaction, isWalletInitialized),
    );
    fee += networkFee;
    realFee += networkFee;
    result.fee = fee;
    result.realFee = realFee;
    result.diesel = DIESEL_NOT_AVAILABLE;

    let isEnoughBalance: boolean;

    if (!tokenAddress) {
      isEnoughBalance = toncoinBalance >= fee + (isFullTonTransfer ? 0n : amount);
    } else {
      const canTransferGasfully = toncoinBalance >= fee;

      if (allowGasless) {
        result.diesel = await getDiesel({
          accountId,
          tokenAddress,
          canTransferGasfully,
          toncoinBalance,
          tokenBalance: balance,
        });
      }

      if (isDieselAvailable(result.diesel)) {
        isEnoughBalance = amount + getDieselTokenAmount(result.diesel) <= balance;
      } else {
        isEnoughBalance = canTransferGasfully && amount <= balance;
      }
    }

    return isEnoughBalance ? result : {
      ...result,
      error: ApiTransactionDraftError.InsufficientBalance,
    };
  } catch (err: any) {
    return {
      ...handleServerError(err),
      ...result,
    };
  }
}

function estimateDiesel(
  address: string,
  tokenAddress: string,
  toncoinAmount: string,
  isW5?: boolean,
  isStars?: boolean,
) {
  return callBackendGet<{
    status: DieselStatus;
    // The amount is defined only when the status is "available" or "stars-fee": https://github.com/mytonwallet-org/mytonwallet-backend/blob/44c1bf43fb776286152db8901b45fe8341752e35/src/endpoints/diesel.ts#L163
    amount?: string;
    pendingCreatedAt?: string;
  }>('/diesel/estimate', {
    address, tokenAddress, toncoinAmount, isW5, isStars,
  });
}

export async function checkToAddress(network: ApiNetwork, toAddress: string) {
  const resolved = await resolveAddress(network, toAddress);
  if ('error' in resolved) return resolved;
  toAddress = resolved.address;

  const { isUserFriendly, isTestOnly, isBounceable } = parseAddress(toAddress);

  const result = {
    addressName: resolved.name,
    resolvedAddress: resolved.address,
    isMemoRequired: resolved.isMemoRequired,
    isScam: resolved.isScam,
    isBounceable,
  };

  const regex = /[+=/]/;
  const isUrlSafe = !regex.test(toAddress);

  if (!isUserFriendly || !isUrlSafe || (network === 'mainnet' && isTestOnly)) {
    return {
      ...result,
      error: ApiTransactionDraftError.InvalidAddressFormat,
    };
  }

  return result;
}

export async function submitGasfullTransfer(
  options: CustomTransactionOptions<ApiSubmitGasfullTransferOptions>,
): Promise<ApiSubmitGasfullTransferResult | { error: string }> {
  const {
    accountId,
    password,
    amount,
    stateInit: stateInitBase64,
    tokenAddress,
    payload: rawPayload,
    forwardAmount,
    fee,
    noFeeCheck,
  } = options;
  let { toAddress } = options;

  const { network } = parseAccountId(accountId);

  try {
    const account = await fetchStoredChainAccount(accountId, 'ton');
    const { address: fromAddress } = account.byChain.ton;
    const wallet = getTonWallet(account.byChain.ton);
    const signer = getSigner(accountId, account, password);

    const payloadResult = await convertPayloadToCell(rawPayload, network, toAddress, signer);
    if ('error' in payloadResult) return payloadResult;
    let payload = payloadResult.cell;
    const { encryptedComment } = payloadResult;

    let stateInit = stateInitBase64 ? Cell.fromBase64(stateInitBase64) : undefined;
    let toncoinAmount: bigint;

    if (!tokenAddress) {
      toncoinAmount = amount;
    } else {
      ({
        amount: toncoinAmount,
        toAddress,
        payload,
        stateInit,
      } = await buildTokenTransfer({
        network,
        tokenAddress,
        fromAddress,
        toAddress,
        amount,
        payload,
        forwardAmount,
        isLedger: account.type === 'ledger',
      }));
    }

    return await withoutTransferConcurrency(network, fromAddress, async (finalizeInBackground) => {
      markTransferInFlight(network, fromAddress);
      let clearInBackground = false;

      try {
        const cachedWalletInfo = consumeCachedWalletInfo(network, fromAddress, true);
        const walletInfo = cachedWalletInfo ?? await getWalletInfo(network, wallet);

        const { seqno, balance: toncoinBalance, isInitialized } = walletInfo;
        const isFullTonTransfer = !tokenAddress && toncoinBalance === amount;

        const signingResult = await signTransaction({
          account,
          messages: [{
            toAddress,
            amount: toncoinAmount,
            payload,
            stateInit,
            hints: {
              tokenAddress,
            },
          }],
          seqno,
          signer,
          doPayFeeFromAmount: isFullTonTransfer,
        });
        if ('error' in signingResult) return signingResult;
        const { transaction } = signingResult;

        if (!noFeeCheck) {
          if (fee !== undefined) {
            const isEnoughBalance = tokenAddress
              ? toncoinBalance >= fee
              : isFullTonTransfer
                ? toncoinBalance > fee
                : toncoinBalance >= toncoinAmount + fee;

            if (!isEnoughBalance) {
              return { error: ApiTransactionError.InsufficientBalance };
            }
          } else {
            const { networkFee } = await emulateTransactionWithFallback(network, wallet, transaction, isInitialized);

            const isEnoughBalance = isFullTonTransfer
              ? toncoinBalance > networkFee
              : toncoinBalance >= toncoinAmount + networkFee;

            if (!isEnoughBalance) {
              return { error: ApiTransactionError.InsufficientBalance };
            }
          }
        }

        const client = getTonClient(network);
        const { msgHash, boc, msgHashNormalized } = await sendExternal(
          client,
          wallet,
          transaction,
          undefined,
          isInitialized,
        );

        finalizeInBackground(async () => {
          try {
            await retrySendBoc(network, fromAddress, boc, seqno);
          } finally {
            clearTransferInFlight(network, fromAddress);
          }
        });
        clearInBackground = true;

        return {
          txId: msgHashNormalized,
          msgHashForCexSwap: msgHash,
          localActivityParams: {
            externalMsgHashNorm: msgHashNormalized,
            encryptedComment,
          },
        };
      } finally {
        if (!clearInBackground) {
          clearTransferInFlight(network, fromAddress);
        }
      }
    });
  } catch (err: any) {
    logDebugError('submitTransfer', err);

    return { error: resolveTransactionError(err) };
  }
}

export async function submitGaslessTransfer(
  options: CustomTransactionOptions<ApiSubmitGaslessTransferOptions>,
): Promise<ApiSubmitGaslessTransferResult | { error: string }> {
  try {
    const {
      toAddress,
      amount,
      accountId,
      password,
      tokenAddress,
      payload: rawPayload,
      forwardAmount,
      noFeeCheck,
      dieselAmount,
      isGaslessWithStars,
    } = options;

    const { network } = parseAccountId(accountId);

    const account = await fetchStoredChainAccount(accountId, 'ton');
    const { address: fromAddress, version } = account.byChain.ton;
    const signer = getSigner(accountId, account, password);

    const payloadResult = await convertPayloadToCell(rawPayload, network, toAddress, signer);
    if ('error' in payloadResult) return payloadResult;
    const { cell: payload, encryptedComment } = payloadResult;

    const messages: TonTransferParams[] = [
      await buildTokenTransfer({
        network,
        tokenAddress,
        fromAddress,
        toAddress,
        amount,
        payload,
        forwardAmount,
        isLedger: account.type === 'ledger',
      }),
    ];

    if (!isGaslessWithStars) {
      messages.push(
        await buildTokenTransfer({
          network,
          tokenAddress,
          fromAddress,
          toAddress: DIESEL_ADDRESS,
          amount: dieselAmount,
          shouldSkipMintless: true,
          payload: getOurFeePayload(),
          isLedger: account.type === 'ledger',
        }),
      );
    }

    const result = await submitMultiTransfer({
      accountId,
      password,
      messages,
      isGasless: true,
      noFeeCheck,
    });
    if ('error' in result) return result;

    return {
      txId: result.msgHashNormalized,
      msgHashForCexSwap: result.msgHash,
      localActivityParams: {
        externalMsgHashNorm: result.msgHashNormalized,
        encryptedComment,
        extra: {
          withW5Gasless: version === 'W5',
        },
      },
    };
  } catch (err) {
    logDebugError('submitTransferWithDiesel', err);

    return { error: resolveTransactionError(err) };
  }
}

async function convertPayloadToCell(
  payload: AnyTonTransferPayload | undefined,
  network: ApiNetwork,
  toAddress: string,
  signer: Signer,
): Promise<{ cell?: Cell; encryptedComment?: string } | { error: ApiAnyDisplayError }> {
  if (!payload || payload instanceof Cell) {
    return { cell: payload };
  }

  if (payload.type === 'comment') {
    if (payload.shouldEncrypt) {
      return makeEncryptedCommentPayload(payload.text, network, toAddress, signer);
    }

    // This is what @ton/core does under the hood when a string payload is passed to `internal()`
    return { cell: packBytesAsSnakeCell(commentToBytes(payload.text)) };
  }

  if (payload.type === 'base64') {
    return { cell: parseBase64(payload.data) };
  }

  if (payload.type === 'binary') {
    return payload.data.length ? { cell: packBytesAsSnakeCell(payload.data) } : {};
  }

  throw new TypeError(`Unexpected payload type ${(payload as AnyTonTransferPayload).type}`);
}

async function makeEncryptedCommentPayload(
  comment: string,
  network: ApiNetwork,
  toAddress: string,
  signer: Signer,
) {
  const toPublicKey = await getWalletPublicKey(network, toAddress);
  if (!toPublicKey) {
    return { error: ApiTransactionDraftError.WalletNotInitialized };
  }

  const result = await signer.encryptComment(comment, toPublicKey);
  if ('error' in result) {
    return result;
  }

  return {
    cell: packBytesAsSnakeForEncryptedData(result),
    encryptedComment: result.subarray(4).toString('base64'),
  };
}

export function resolveTransactionError(error: any): ApiAnyDisplayError | string {
  if (error instanceof ApiServerError) {
    if (isExpiredTransactionError(error.message)) {
      return ApiTransactionError.IncorrectDeviceTime;
    } else if (isSeqnoMismatchError(error.message)) {
      return ApiTransactionError.ConcurrentTransaction;
    } else if (error.statusCode === 400) {
      return error.message;
    } else if (error.displayError) {
      return error.displayError;
    }
  }
  return ApiTransactionError.UnsuccesfulTransfer;
}

export async function checkMultiTransactionDraft(
  accountId: string,
  messages: TonTransferParams[],
  isGasless?: boolean,
): Promise<ApiCheckMultiTransactionDraftResult> {
  let totalAmount: bigint = 0n;

  const { network } = parseAccountId(accountId);
  const account = await fetchStoredChainAccount(accountId, 'ton');

  try {
    for (const { toAddress, amount } of messages) {
      if (amount < 0n) {
        return { error: ApiTransactionDraftError.InvalidAmount };
      }

      const isMainnet = network === 'mainnet';
      const { isValid, isTestOnly } = parseAddress(toAddress);

      if (!isValid || (isMainnet && isTestOnly)) {
        return { error: ApiTransactionDraftError.InvalidToAddress };
      }

      totalAmount += amount;
    }

    // Check individual token balances
    const { hasInsufficientTokenBalance, parsedPayloads } = await isTokenBalanceInsufficient(
      network,
      account.byChain.ton.address,
      messages,
    );

    const wallet = getTonWallet(account.byChain.ton);
    const walletInfo = await getWalletInfo(network, wallet);
    rememberWalletInfo(network, account.byChain.ton.address, walletInfo);
    const { seqno, balance } = walletInfo;

    const signer = getSigner(accountId, account, undefined, true);
    const signingResult = await signTransaction({ account, messages, seqno, signer });
    if ('error' in signingResult) return signingResult;

    const emulation = applyFeeFactorToEmulationResult(
      await emulateTransactionWithFallback(
        network,
        wallet,
        signingResult.transaction,
        walletInfo.isInitialized,
      ),
    );
    const result = { emulation, parsedPayloads };

    // TODO Should `totalAmount` be `0` for `isGasless`?
    // Check for insufficient balance (both tokens and TON) and return error
    const hasInsufficientTonBalance = !isGasless && balance < totalAmount + result.emulation.networkFee;

    if (hasInsufficientTokenBalance || hasInsufficientTonBalance) {
      return { ...result, error: ApiTransactionDraftError.InsufficientBalance };
    }

    return result;
  } catch (err: any) {
    return handleServerError(err);
  }
}

async function isTokenBalanceInsufficient(
  network: ApiNetwork,
  walletAddress: string,
  messages: TonTransferParams[],
): Promise<{
    hasInsufficientTokenBalance: boolean;
    parsedPayloads: (ApiParsedPayload | undefined)[];
  }> {
  const payloadParsingResults = await Promise.all(
    messages.map(async ({ payload, toAddress }) => {
      if (!payload) return { tokenResult: undefined, parsedPayload: undefined };

      try {
        const parsedPayload = await parsePayloadSlice(network, toAddress, payload.beginParse());

        if (parsedPayload?.type === 'tokens:transfer') {
          return {
            tokenResult: {
              tokenAddress: parsedPayload.tokenAddress,
              amount: parsedPayload.amount,
            },
            parsedPayload,
          };
        }

        return { tokenResult: undefined, parsedPayload };
      } catch (e) {
        // If payload parsing fails, treat as regular TON transfer
        logDebugError('isTokenBalanceInsufficient', 'Error parsing payload', e);
      }

      return { tokenResult: undefined, parsedPayload: undefined };
    }),
  );

  // Accumulate token amounts by address
  const tokenAmountsByAddress: Record<string, bigint> = {};
  const parsedPayloads = payloadParsingResults.map((result) => result?.parsedPayload);
  let hasUnknownToken = false;

  for (const result of payloadParsingResults) {
    if (result?.tokenResult) {
      const { tokenAddress, amount } = result.tokenResult;

      if (!tokenAddress) {
        // Possible when the jetton wallet is not deployed, therefore the minter address is unknown and set to "".
        // This is handled in `parsePayloadSlice`. If the sender jetton wallet is not deployed, assuming the balance is 0.
        hasUnknownToken = true;
        continue;
      }

      if (!tokenAmountsByAddress[tokenAddress]) {
        tokenAmountsByAddress[tokenAddress] = 0n;
      }
      tokenAmountsByAddress[tokenAddress] += amount;
    }
  }

  if (hasUnknownToken) {
    return { hasInsufficientTokenBalance: true, parsedPayloads };
  }

  const tokenAddresses = Object.keys(tokenAmountsByAddress);
  if (tokenAddresses.length === 0) {
    return { hasInsufficientTokenBalance: false, parsedPayloads }; // No token transfers
  }

  const tokenBalances = await Promise.all(
    tokenAddresses.map((tokenAddress) =>
      tokenAddress !== STON_PTON_ADDRESS
        ? getTokenBalanceWithMintless(network, walletAddress, tokenAddress)
        : 0n,
    ),
  );

  // Check if any token has insufficient balance
  for (let i = 0; i < tokenAddresses.length; i++) {
    const tokenAddress = tokenAddresses[i];
    const requiredAmount = tokenAmountsByAddress[tokenAddress];
    const availableBalance = tokenBalances[i];

    if (tokenAddress === STON_PTON_ADDRESS) {
      continue; // PTON can be here from the built-in swaps
    }

    if (availableBalance < requiredAmount) {
      return { hasInsufficientTokenBalance: true, parsedPayloads };
    }
  }

  return { hasInsufficientTokenBalance: false, parsedPayloads };
}

export type GaslessType = 'diesel' | 'w5';

interface SubmitMultiTransferOptions {
  accountId: string;
  /** Required only for mnemonic accounts */
  password?: string;
  messages: TonTransferParams[];
  expireAt?: number;
  isGasless?: boolean;
  noFeeCheck?: boolean;
}

// todo: Support submitting multiple transactions (not only multiple messages). The signing already supports that. It will allow to:
//  1) send multiple NFTs with a single API call,
//  2) renew multiple domains in a single function call,
//  3) simplify the implementation of swapping with Ledger
export async function submitMultiTransfer({
  accountId, password, messages, expireAt, isGasless, noFeeCheck,
}: SubmitMultiTransferOptions): Promise<ApiSubmitMultiTransferResult> {
  const { network } = parseAccountId(accountId);

  const account = await fetchStoredChainAccount(accountId, 'ton');
  const { address: fromAddress, version } = account.byChain.ton;

  try {
    const wallet = getTonWallet(account.byChain.ton);

    let totalAmount = 0n;
    messages.forEach((message) => {
      totalAmount += BigInt(message.amount);
    });

    return await withoutTransferConcurrency(network, fromAddress, async (finalizeInBackground) => {
      markTransferInFlight(network, fromAddress);
      let clearInBackground = false;

      try {
        const cachedWalletInfo = consumeCachedWalletInfo(network, fromAddress, true);
        const walletInfo = cachedWalletInfo ?? await getWalletInfo(network, wallet);

        const { seqno, balance, isInitialized: walletIsInitialized } = walletInfo;

        const gaslessType = isGasless ? version === 'W5' ? 'w5' : 'diesel' : undefined;
        const withW5Gasless = gaslessType === 'w5';

        const signer = getSigner(accountId, account, password);
        const signingResult = await signTransaction({
          account,
          messages,
          expireAt: withW5Gasless
            ? Math.round(Date.now() / 1000) + PENDING_DIESEL_TIMEOUT_SEC
            : expireAt,
          seqno,
          signer,
          shouldBeInternal: withW5Gasless,
        });
        if ('error' in signingResult) return signingResult;
        const { transaction } = signingResult;

        if (!noFeeCheck && !isGasless) {
          const { networkFee } = await emulateTransactionWithFallback(
            network,
            wallet,
            transaction,
            walletIsInitialized,
          );
          if (balance < totalAmount + networkFee) {
            return { error: ApiTransactionError.InsufficientBalance };
          }
        }

        const client = getTonClient(network);
        const { msgHash, boc, paymentLink, msgHashNormalized } = await sendExternal(
          client,
          wallet,
          transaction,
          gaslessType,
          walletIsInitialized,
        );

        if (!isGasless) {
          finalizeInBackground(async () => {
            try {
              await retrySendBoc(network, fromAddress, boc, seqno);
            } finally {
              clearTransferInFlight(network, fromAddress);
            }
          });
          clearInBackground = true;
        } else {
          // TODO: Wait for gasless transfer
        }

        const clearedMessages = messages.map((message) => {
          if (typeof message.payload !== 'string' && typeof message.payload !== 'undefined') {
            return omit(message, ['payload']);
          }
          return message;
        });

        return {
          seqno,
          amount: totalAmount.toString(),
          messages: clearedMessages,
          boc,
          msgHash,
          msgHashNormalized,
          paymentLink,
          withW5Gasless,
        };
      } finally {
        if (!clearInBackground) {
          clearTransferInFlight(network, fromAddress);
        }
      }
    });
  } catch (err) {
    logDebugError('submitMultiTransfer', err);
    return { error: resolveTransactionError(err) };
  }
}

export async function signTransfers(
  accountId: string,
  messages: TonTransferParams[],
  password?: string,
  expireAt?: number,
  /** Used for specific transactions on vesting.ton.org */
  ledgerVestingAddress?: string,
  isTonConnect?: boolean,
): Promise<ApiSignedTransfer<DappProtocolType.TonConnect>[] | { error: ApiAnyDisplayError }> {
  const account = await fetchStoredChainAccount(accountId, 'ton');

  // If there is an outgoing transfer in progress, this expression waits for it to finish. This helps to avoid seqno
  // mismatches. This is not fully reliable, because the signed transactions are sent by a separate API method, but it
  // works in most cases.
  await withoutTransferConcurrency(parseAccountId(accountId).network, account.byChain.ton.address, () => {});

  const seqno = await getWalletSeqno(
    parseAccountId(accountId).network,
    ledgerVestingAddress ?? account.byChain.ton.address,
  );
  const signer = getSigner(
    accountId,
    account,
    password,
    false,
    ledgerVestingAddress ? LEDGER_VESTING_SUBWALLET_ID : undefined,
  );
  const signedTransactions = await signTransactions({
    account, expireAt, messages, seqno, signer, isTonConnect,
  });
  if ('error' in signedTransactions) return signedTransactions;

  return signedTransactions.map(({ seqno, transaction }) => ({
    chain: 'ton',
    payload: {
      seqno,
      base64: transaction.toBoc().toString('base64'),
    },
  }));
}

interface SignTransactionOptions {
  account: ApiAccountWithChain<'ton'>;
  doPayFeeFromAmount?: boolean;
  messages: TonTransferParams[];
  seqno: number;
  signer: Signer;
  /** Unix seconds */
  expireAt?: number;
  /** If true, will sign the transaction as an internal message instead of external. Not supported by Ledger. */
  shouldBeInternal?: boolean;
  isTonConnect?: boolean;
}

async function signTransaction(options: SignTransactionOptions) {
  const result = await signTransactions({ ...options, allowOnlyOneTransaction: true });
  if ('error' in result) return result;
  return result[0];
}

/**
 * A universal function for signing any number of transactions in any account type.
 *
 * If the account doesn't support signing all the given messages in a single transaction, will produce multiple signed
 * transactions. If you need exactly 1 signed transaction, use `allowOnlyOneTransaction` or `signTransaction` (the
 * function will throw an error in case of multiple transactions).
 *
 * The reason for signing multiple transactions (not messages) in a single function call is improving the UX. Each
 * transaction requires a manual user action to sign with Ledger. So, all the transactions should be checked before
 * actually signing any of them.
 */
async function signTransactions({
  account,
  messages,
  doPayFeeFromAmount,
  seqno,
  signer,
  expireAt = Math.round(Date.now() / 1000) + TRANSFER_TIMEOUT_SEC,
  shouldBeInternal,
  allowOnlyOneTransaction,
  isTonConnect,
}: SignTransactionOptions & { allowOnlyOneTransaction?: boolean }) {
  const messagesPerTransaction = getMaxMessagesInTransaction(account);
  const messagesByTransaction = split(messages, messagesPerTransaction);

  if (allowOnlyOneTransaction && messagesByTransaction.length !== 1) {
    throw new Error(
      messagesByTransaction.length === 0
        ? 'No messages to sign'
        : `Too many messages for 1 transaction (${messages.length} messages given)`,
    );
  }

  const transactionsToSign = messagesByTransaction.map((transactionMessages, index) => {
    if (!signer.isMock) {
      logDebug('Signing transaction', {
        seqno,
        messages: transactionMessages.map((msg) => pick(msg, ['toAddress', 'amount'])),
      });
    }

    return makePreparedTransactionToSign({
      messages: transactionMessages,
      seqno: seqno + index,
      doPayFeeFromAmount,
      expireAt,
      shouldBeInternal,
    });
  });

  // All the transactions are passed to a single `signer.signTransactions` call, because it checks the transactions
  // before signing. See the `signTransactions` description for more details.
  const signedTransactions = await signer.signTransactions(transactionsToSign, isTonConnect);
  if ('error' in signedTransactions) return signedTransactions;

  return signedTransactions.map((transaction, index) => ({
    seqno: transactionsToSign[index].seqno,
    transaction,
  }));
}

async function retrySendBoc(
  network: ApiNetwork,
  address: string,
  boc: string,
  seqno: number,
) {
  const tonClient = getTonClient(network);
  const waitUntil = Date.now() + WAIT_TRANSFER_TIMEOUT;

  while (Date.now() < waitUntil) {
    const [error, walletInfo] = await Promise.all([
      tonClient.sendFile(boc).catch((err) => String(err)),
      getWalletInfo(network, address).catch(() => undefined),
    ]);

    // Errors mean that `seqno` was changed or not enough of balance
    if (error?.match(/(exitcode=33|exitcode=133|inbound external message rejected by account)/)) {
      break;
    }

    // seqno here may change before exit code appears
    if (walletInfo && walletInfo.seqno > seqno) {
      break;
    }

    await pause(WAIT_PAUSE);
  }
}

async function emulateTransactionWithFallback(
  network: ApiNetwork,
  wallet: TonWallet,
  transaction: Cell,
  isInitialized?: boolean,
): Promise<ApiEmulationWithFallbackResult> {
  try {
    const emulation = await emulateTransaction(network, wallet, transaction, isInitialized);
    return { isFallback: false, ...emulation };
  } catch (err) {
    logDebugError('Failed to emulate a transaction', err);
  }

  // Falling back to the legacy fee estimation method just in case.
  // It doesn't support estimating more than 20 messages (inside the transaction) at once.
  // eslint-disable-next-line no-null/no-null
  const { code = null, data = null } = !isInitialized ? wallet.init : {};
  const { source_fees: fees } = await getTonClient(network).estimateExternalMessageFee(wallet.address, {
    body: transaction,
    initCode: code,
    initData: data,
    ignoreSignature: true,
  });
  const networkFee = BigInt(fees.in_fwd_fee + fees.storage_fee + fees.gas_fee + fees.fwd_fee);
  return { isFallback: true, networkFee };
}

export async function sendSignedTransactions(
  accountId: string,
  transactions: ApiSignedTransfer<DappProtocolType.TonConnect>[],
) {
  const { network } = parseAccountId(accountId);
  const storedWallet = await fetchStoredWallet(accountId, 'ton');
  const { address: fromAddress } = storedWallet;
  const client = getTonClient(network);
  const wallet = getTonWallet(storedWallet);
  const walletIsInitialized = storedWallet.isInitialized;

  const attempts = ATTEMPTS + transactions.length;
  let index = 0;
  let attempt = 0;

  const sentTransactions: { boc: string; msgHashNormalized: string }[] = [];

  return withoutTransferConcurrency(network, fromAddress, async (finalizeInBackground) => {
    markTransferInFlight(network, fromAddress);
    let clearInBackground = false;

    try {
      while (index < transactions.length && attempt < attempts) {
        const { payload: { base64, seqno } } = transactions[index];
        try {
          const { boc, msgHashNormalized } = await sendExternal(
            client,
            wallet,
            Cell.fromBase64(base64),
            undefined,
            walletIsInitialized,
          );
          sentTransactions.push({ boc, msgHashNormalized });

          const ensureSent = () => retrySendBoc(network, fromAddress, boc, seqno);
          if (index === transactions.length - 1) {
            finalizeInBackground(async () => {
              try {
                await ensureSent();
              } finally {
                clearTransferInFlight(network, fromAddress);
              }
            });
            clearInBackground = true;
          } else {
            await ensureSent();
          }

          index++;
        } catch (err) {
          if (err instanceof ApiServerError && isSeqnoMismatchError(err.message)) {
            return { error: ApiTransactionError.ConcurrentTransaction };
          }
          logDebugError('sendSignedMessages', err);
        }
        attempt++;
      }

      return sentTransactions;
    } finally {
      if (!clearInBackground) {
        clearTransferInFlight(network, fromAddress);
      }
    }
  });
}

export function fetchEstimateDiesel(
  accountId: string, tokenAddress: string,
): Promise<ApiFetchEstimateDieselResult> {
  return getDiesel({
    accountId,
    tokenAddress,
    // We pass `false` because `fetchEstimateDiesel` assumes that the transfer is gasless anyway
    canTransferGasfully: false,
  });
}

/**
 * Decides whether the transfer must be gasless and fetches the diesel estimate from the backend.
 */
async function getDiesel({
  accountId,
  tokenAddress,
  canTransferGasfully,
  toncoinBalance,
  tokenBalance,
}: {
  accountId: string;
  tokenAddress: string;
  canTransferGasfully: boolean;
  // The below fields allow to avoid network requests if you already have these data
  toncoinBalance?: bigint;
  tokenBalance?: bigint;
}): Promise<ApiFetchEstimateDieselResult> {
  const { network } = parseAccountId(accountId);
  if (network !== 'mainnet') return DIESEL_NOT_AVAILABLE;

  const storedTonWallet = await fetchStoredWallet(accountId, 'ton');
  const wallet = getTonWallet(storedTonWallet);

  const token = getTokenByAddress(tokenAddress)!;
  if (!token.isGaslessEnabled && !token.isStarsEnabled) return DIESEL_NOT_AVAILABLE;

  const { address, version } = storedTonWallet;
  toncoinBalance ??= await getWalletBalance(network, wallet);
  const fee = getDieselToncoinFee(token);
  const toncoinNeeded = fee.amount - toncoinBalance;

  if (toncoinBalance >= MAX_BALANCE_WITH_CHECK_DIESEL || toncoinNeeded <= 0n) return DIESEL_NOT_AVAILABLE;

  const rawDiesel = await estimateDiesel(
    address,
    tokenAddress,
    toDecimal(toncoinNeeded),
    version === 'W5',
    fee.isStars,
  );
  const diesel: ApiFetchEstimateDieselResult = {
    status: rawDiesel.status,
    amount: rawDiesel.amount === undefined
      ? undefined
      : fromDecimal(rawDiesel.amount, rawDiesel.status === 'stars-fee' ? 0 : token.decimals),
    nativeAmount: toncoinNeeded,
    remainingFee: toncoinBalance,
    realFee: fee.realFee,
  };

  const tokenAmount = getDieselTokenAmount(diesel);
  if (tokenAmount === 0n) {
    return diesel;
  }

  tokenBalance ??= await getTokenBalanceWithMintless(network, address, tokenAddress);
  const canPayDiesel = tokenBalance >= tokenAmount;
  const isAwaitingNotExpiredPrevious = Boolean(
    rawDiesel.pendingCreatedAt
    && Date.now() - new Date(rawDiesel.pendingCreatedAt).getTime() < PENDING_DIESEL_TIMEOUT_SEC * SEC,
  );

  // When both TON and diesel are insufficient, we want to show the TON fee
  const shouldBeGasless = (!canTransferGasfully && canPayDiesel) || isAwaitingNotExpiredPrevious;
  return shouldBeGasless ? diesel : DIESEL_NOT_AVAILABLE;
}

/**
 * Guesses the total TON fee (including the gas attached to the transaction) that will be spent on a diesel transfer.
 *
 * `amount` is what will be taken from the wallet;
 * `realFee` is approximately what will be actually spent (the rest will return in the excess);
 * `isStars` tells whether the fee is estimated considering that the diesel will be paid in stars.
 */
function getDieselToncoinFee(token: ApiToken) {
  const isStars = !token.isGaslessEnabled && token.isStarsEnabled;
  let { amount, realAmount: realFee } = getToncoinAmountForTransfer(token, false);

  // Multiplying by 2 because the diesel transfer has 2 transactions:
  // - for the transfer itself,
  // - for sending the diesel to the MTW wallet.
  if (!isStars) {
    amount *= 2n;
    realFee *= 2n;
  }

  amount += DEFAULT_FEE;
  realFee += DEFAULT_FEE;

  return { amount, realFee, isStars };
}

function applyFeeFactorToEmulationResult(estimation: ApiEmulationWithFallbackResult): ApiEmulationWithFallbackResult {
  estimation = {
    ...estimation,
    networkFee: bigintMultiplyToNumber(estimation.networkFee, FEE_FACTOR),
  };

  if ('traceOutputs' in estimation) {
    estimation.traceOutputs = estimation.traceOutputs.map((transaction) => ({
      ...transaction,
      networkFee: bigintMultiplyToNumber(transaction.networkFee, FEE_FACTOR),
    }));
  }

  return estimation;
}

function makePreparedTransactionToSign(
  options: Pick<SignTransactionOptions, 'messages' | 'doPayFeeFromAmount' | 'expireAt' | 'shouldBeInternal' | 'seqno'>,
): PreparedTransactionToSign {
  const { messages, seqno, doPayFeeFromAmount, expireAt, shouldBeInternal } = options;

  return {
    authType: shouldBeInternal ? 'internal' : undefined,
    seqno,
    messages: messages.map((message) => {
      const { amount, payload, toAddress, stateInit } = message;
      return internal({
        value: amount,
        to: toAddress,
        body: payload,
        bounce: parseAddress(toAddress).isBounceable,
        init: parseStateInitCell(stateInit),
      });
    }),
    sendMode: (doPayFeeFromAmount ? SendMode.CARRY_ALL_REMAINING_BALANCE : SendMode.PAY_GAS_SEPARATELY)
      // It's important to add IGNORE_ERRORS to every transaction. Otherwise, failed transactions may repeat and drain
      // the wallet balance: https://docs.ton.org/v3/documentation/smart-contracts/message-management/sending-messages#behavior-without-2-flag
      + SendMode.IGNORE_ERRORS,
    timeout: expireAt,
    hints: messages[0].hints, // Currently hints are used only by Ledger, which has only 1 message per transaction
  };
}
