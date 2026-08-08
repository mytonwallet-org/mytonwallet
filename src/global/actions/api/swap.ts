import type {
  ApiChain,
  ApiCheckTransactionDraftResult,
  ApiSubmitGasfullTransferOptions,
  ApiSwapBuildTransactionRequest,
  ApiSwapCexEstimateResponse,
  ApiSwapDexEstimateResponse,
  ApiSwapEstimateRequest,
  ApiSwapEstimateVariant,
  ApiSwapHistoryItem,
  ApiTransferPayload,
} from '../../../api/types';
import type {
  AssetPairs,
  GlobalState,
} from '../../types';
import {
  SwapErrorType,
  SwapInputSource,
  SwapState,
  SwapType,
} from '../../types';

import { DEFAULT_SWAP_FIRST_TOKEN_SLUG, DEFAULT_SWAP_SECOND_TOKEN_SLUG, TONCOIN } from '../../../config';
import { Big } from '../../../lib/big.js';
import { parseTxId } from '../../../util/activities';
import { getDoesUsePinPad } from '../../../util/biometrics';
import { getChainConfig, getEvmChains, getIsSupportedChain } from '../../../util/chain';
import { fromDecimal, roundDecimal, toDecimal } from '../../../util/decimals';
import { canAffordSwapEstimateVariant, shouldSwapBeGasless } from '../../../util/fee/swapFee';
import generateUniqueId from '../../../util/generateUniqueId';
import { pick } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { pause, waitFor } from '../../../util/schedulers';
import { isSwapPairValid } from '../../../util/swap/isSwapPairValid';
import { findNativeToken, getChainBySlug, getIsNativeToken, getNativeToken } from '../../../util/tokens';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../..';
import { resolveSwapAssetId } from '../../helpers';
import { runActivityUpdateInOrder } from '../../helpers/activityUpdateQueue';
import {
  selectCexSwapRefreshContextActivities,
  selectPendingCexSwapActivities,
} from '../../helpers/cexSwapRefresh';
import { withEnclaveSessionRelease } from '../../helpers/enclave';
import {
  getSwapEstimateResetParams,
  isSwapEstimateInputEqual,
  isSwapFormFilled,
  shouldAvoidSwapEstimation,
} from '../../helpers/swap';
import {
  handleTransferResult,
  isErrorTransferResult,
  prepareTransfer,
  reportErrorTransferResult,
} from '../../helpers/transfer';
import {
  applyActivitiesPatch,
  clearCurrentSwap,
  clearIsPinAccepted,
  updateCurrentSwap,
} from '../../reducers';
import {
  selectAccount,
  selectAccountState,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountTokenBalance,
  selectCurrentSwapTokenIn,
  selectCurrentSwapTokenOut,
  selectCurrentToncoinBalance,
  selectSwapType,
} from '../../selectors';
import { switchAccount } from './auth';

const pairsCache: Record<string, { timestamp: number }> = {};

const CACHE_DURATION = 15 * 60 * 1000; // 15 minutes
const WAIT_FOR_CEX_DEPOSIT_ADDRESS = 5 * 1000;
const UNSUPPORTED_NEAR_INTENTS_MEMO_ERROR = 'Unsupported deposit memo for source chain';
const SERVER_ERRORS_MAP = {
  'Insufficient liquidity': SwapErrorType.NotEnoughLiquidity,
  'Tokens must be different': SwapErrorType.InvalidPair,
  'Asset not found': SwapErrorType.InvalidPair,
  'Pair not found': SwapErrorType.InvalidPair,
  'Too small amount': SwapErrorType.TooSmallAmount,
};

function buildSwapBuildRequest(global: GlobalState): ApiSwapBuildTransactionRequest {
  const {
    dexLabel,
    dexRouterLabel,
    amountIn,
    amountOut,
    amountOutMin,
    slippage,
    networkFee,
    swapFee,
    ourFee,
    dieselFee,
    realNetworkFee,
    routes,
  } = global.currentSwap;

  const tokenIn = selectCurrentSwapTokenIn(global)!;
  const tokenOut = selectCurrentSwapTokenOut(global)!;
  const from = resolveSwapAssetId(tokenIn);
  const to = resolveSwapAssetId(tokenOut);

  const currentAccountId = selectCurrentAccountId(global)!;
  const account = selectAccount(global, currentAccountId);
  const historyAddress = account?.byChain.ton?.address;
  if (!historyAddress) {
    throw new Error('TON history address is required to build swap transaction');
  }
  const nativeTokenIn = findNativeToken(getChainBySlug(tokenIn.slug));
  const nativeTokenInBalance = nativeTokenIn ? selectCurrentAccountTokenBalance(global, nativeTokenIn.slug) : undefined;
  const swapType = selectSwapType(global);
  return {
    from,
    to,
    fromAmount: amountIn!,
    toAmount: amountOut!,
    toMinAmount: amountOutMin!,
    slippage,
    fromAddress: account?.byChain[tokenIn.chain as ApiChain]?.address ?? historyAddress,
    historyAddress,
    shouldTryDiesel: shouldSwapBeGasless({ ...global.currentSwap, swapType, nativeTokenInBalance }),
    dexRouterLabel: dexRouterLabel || undefined,
    dexLabel,
    networkFee: realNetworkFee ?? networkFee,
    swapFee: swapFee!,
    ourFee: ourFee!,
    dieselFee,
    routes,
  };
}

function buildSwapEstimates(estimate: ApiSwapDexEstimateResponse): ApiSwapEstimateVariant[] {
  const bestEstimate: ApiSwapEstimateVariant = {
    ...pick(estimate, [
      'fromAmount',
      'toAmount',
      'toMinAmount',
      'impact',
      'dexLabel',
      'networkFee',
      'realNetworkFee',
      'swapFee',
      'swapFeePercent',
      'ourFee',
      'dieselFee',
      'networkFee',
      'routes',
    ]),
  };

  return [
    bestEstimate,
    ...(estimate.other ?? []),
  ];
}

function processNativeMaxSwap(global: GlobalState) {
  const tokenIn = selectCurrentSwapTokenIn(global)!;
  let fromAmount = global.currentSwap.amountIn ?? '0';
  let isFromAmountMax = false;

  if (
    global.currentSwap.amountIn
    && selectSwapType(global) === SwapType.OnChain
    && global.currentSwap.inputSource === SwapInputSource.In
    && global.currentSwap.isMaxAmount
  ) {
    const tokenBalance = selectCurrentAccountTokenBalance(global, tokenIn.slug);
    fromAmount = toDecimal(tokenBalance, tokenIn.decimals);
    isFromAmountMax = true;
  }
  return { fromAmount, isFromAmountMax };
}

addActionHandler('startSwap', (global, actions, payload) => {
  const { state, amountIn, ...rest } = payload ?? {};

  const requiredState = state || SwapState.Initial;
  const normalizedAmountIn = amountIn?.replace('-', '');

  global = updateCurrentSwap(global, {
    ...rest,
    amountIn: normalizedAmountIn,
    state: requiredState,
    swapId: generateUniqueId(),
    inputSource: SwapInputSource.In,
  });

  if (requiredState === SwapState.Initial && isSwapFormFilled(global)) {
    global = updateCurrentSwap(global, { isEstimating: true }, true);
  }

  setGlobal(global);
});

addActionHandler('switchSwapAccount', async (global, actions, { accountId }) => {
  if (accountId === selectCurrentAccountId(global)) {
    return;
  }

  // `switchAccount` clears `currentSwap`, so snapshot the user-entered draft and re-apply it afterwards
  const {
    tokenInSlug,
    tokenOutSlug,
    amountIn,
    amountOut,
    inputSource,
    isMaxAmount,
    slippage,
  } = global.currentSwap;

  await switchAccount(global, accountId);

  global = getGlobal();
  setGlobal(updateCurrentSwap(global, {
    state: SwapState.Initial,
    swapId: generateUniqueId(),
    tokenInSlug,
    tokenOutSlug,
    amountIn,
    amountOut,
    inputSource,
    isMaxAmount,
    slippage,
  }));
});

addActionHandler('setDefaultSwapParams', (global, actions, payload) => {
  let { tokenInSlug: requiredTokenInSlug, tokenOutSlug: requiredTokenOutSlug } = payload ?? {};
  const { withResetAmount } = payload ?? {};

  requiredTokenInSlug = requiredTokenInSlug || DEFAULT_SWAP_FIRST_TOKEN_SLUG;
  requiredTokenOutSlug = requiredTokenOutSlug || DEFAULT_SWAP_SECOND_TOKEN_SLUG;
  if (
    global.currentSwap.tokenInSlug === requiredTokenInSlug
    && global.currentSwap.tokenOutSlug === requiredTokenOutSlug
    && !withResetAmount
  ) {
    return;
  }

  global = updateCurrentSwap(global, {
    tokenInSlug: requiredTokenInSlug,
    tokenOutSlug: requiredTokenOutSlug,
    inputSource: SwapInputSource.In,
    ...(withResetAmount ? { amountIn: undefined, amountOut: undefined } : undefined),
  });
  setGlobal(global);
});

addActionHandler('cancelSwap', (global, actions, { shouldReset } = {}) => {
  if (shouldReset) {
    const { tokenInSlug, tokenOutSlug } = global.currentSwap;

    global = clearCurrentSwap(global);
    global = updateCurrentSwap(global, {
      tokenInSlug,
      tokenOutSlug,
      amountIn: undefined,
      amountOut: undefined,
      inputSource: SwapInputSource.In,
    });

    setGlobal(global);
    return;
  }

  if (getDoesUsePinPad()) {
    global = clearIsPinAccepted(global);
  }
  global = updateCurrentSwap(global, {
    state: SwapState.None,
    swapId: undefined,
  });
  setGlobal(global);
});

addActionHandler('submitSwap', withEnclaveSessionRelease(async (global, actions, { enclaveToken }) => {
  if (!prepareTransfer(
    0 as never, // Swap isn't available for hardware accounts yet, so this argument value doesn't matter
    updateCurrentSwap,
  )) {
    return;
  }

  const swapBuildRequest = buildSwapBuildRequest(global);
  const buildResult = await callApi(
    'swapBuildTransfer', selectCurrentAccountId(global)!, enclaveToken, swapBuildRequest,
  );

  if (!handleTransferResult(buildResult, updateCurrentSwap)) {
    logDebugError('submitSwap:build', buildResult);
    return;
  }

  // `handleTransferResult` reset the loading state, but `swapSubmit` still runs before the slide changes -
  // keep it on so the confirm button doesn't flash the Back button
  setGlobal(updateCurrentSwap(getGlobal(), { isLoading: true }));

  const swapHistoryItem: ApiSwapHistoryItem = {
    id: buildResult.id,
    timestamp: Date.now(),
    status: 'pendingTrusted',
    from: swapBuildRequest.from,
    fromAddress: swapBuildRequest.fromAddress,
    fromAmount: swapBuildRequest.fromAmount,
    to: swapBuildRequest.to,
    toAmount: swapBuildRequest.toAmount!,
    networkFee: global.currentSwap.realNetworkFee ?? global.currentSwap.networkFee!,
    swapFee: global.currentSwap.swapFee!,
    ourFee: global.currentSwap.ourFee,
    hashes: [],
    transactionIds: {},
  };

  const result = await callApi(
    'swapSubmit',
    buildResult.chain,
    selectCurrentAccountId(global)!,
    enclaveToken,
    buildResult.transfers,
    swapHistoryItem,
    swapBuildRequest.shouldTryDiesel,
    buildResult.transaction,
  );

  if (isErrorTransferResult(result)) {
    logDebugError('submitSwap:result', result);

    reportErrorTransferResult(result, updateCurrentSwap);

    return;
  }

  setGlobal(updateCurrentSwap(getGlobal(), {
    isLoading: undefined,
    state: result.mfaRequestHash ? SwapState.ConfirmMfa : SwapState.Complete,
    activityId: result.activityId,
    swapId: result.swapId,
    mfaRequestHash: result.mfaRequestHash,
  }));
}));

addActionHandler('submitSwapCex', withEnclaveSessionRelease(async (global, actions, { enclaveToken }) => {
  if (!prepareTransfer(
    0 as never, // Swap isn't available for hardware accounts yet, so this argument value doesn't matter
    updateCurrentSwap,
  )) {
    return;
  }

  global = getGlobal();

  const currentAccountId = selectCurrentAccountId(global)!;
  const account = selectCurrentAccount(global);
  const tokenIn = global.swapTokenInfo.bySlug[global.currentSwap.tokenInSlug!];
  const tokenOut = global.swapTokenInfo.bySlug[global.currentSwap.tokenOutSlug!];
  const isFromWallet = !!account?.byChain[tokenIn.chain as ApiChain];
  const isToWallet = !!account?.byChain[tokenOut.chain as ApiChain];
  const tonAddress = account?.byChain.ton?.address ?? '';
  let toAddress: string;

  if (isToWallet) {
    toAddress = account.byChain[tokenOut.chain as ApiChain]!.address;
  } else {
    if (!global.currentSwap.toAddress) {
      // Should be set by the `SwapBlockchain` screen
      throw new Error('toAddress is not set');
    }
    toAddress = global.currentSwap.toAddress;
  }

  const sourceAddress = getIsSupportedChain(tokenIn.chain)
    ? account?.byChain[tokenIn.chain]?.address
    : undefined;
  const cexLabel = global.currentSwap.currentCexLabel;

  if (!sourceAddress && cexLabel === 'near-intents') {
    setGlobal(updateCurrentSwap(global, { errorType: SwapErrorType.InvalidPair }));
    return;
  }

  const swapBuildRequest = buildSwapBuildRequest(global);
  const swapTransactionRequest: ApiSwapBuildTransactionRequest = {
    ...swapBuildRequest,
    fromAddress: cexLabel === 'near-intents' ? sourceAddress! : tonAddress,
    historyAddress: tonAddress,
    cexLabel,
    toAddress,
  };

  const swapItem = await callApi('swapCexCreateTransaction', currentAccountId, enclaveToken, swapTransactionRequest);

  const swapItemError = (swapItem as { error?: unknown } | undefined)?.error;
  if (isErrorTransferResult(swapItem) && swapItemError === UNSUPPORTED_NEAR_INTENTS_MEMO_ERROR) {
    showUnsupportedNearIntentsMemoError();
    return;
  }

  if (!handleTransferResult(swapItem, updateCurrentSwap)) {
    return;
  }

  const memo = swapItem.swap.cex!.payinExtraId;

  if (shouldBlockUnsupportedNearIntentsMemo(swapItem.swap.cexLabel, tokenIn.chain, memo)) {
    logDebugError('submitSwapCex: unsupported Near Intents deposit memo', {
      cexLabel: swapItem.swap.cexLabel,
      chain: tokenIn.chain,
    });

    showUnsupportedNearIntentsMemoError();
    return;
  }

  const canAutoSubmit = isFromWallet && canAutoSubmitCexDeposit(tokenIn.chain, memo);
  const isManualDepositRequired = isFromWallet && !canAutoSubmit;

  global = getGlobal();
  global = updateCurrentSwap(global, {
    state: canAutoSubmit ? SwapState.Complete : SwapState.WaitTokens,
    activityId: swapItem.activity.id,
    payinAddress: swapItem.swap.cex!.payinAddress,
    payoutAddress: swapItem.swap.cex!.payoutAddress,
    payinExtraId: memo,
    isManualDepositRequired,
  });
  setGlobal(global);

  if (canAutoSubmit) {
    const payload = memo ? { type: 'comment', text: memo } satisfies ApiTransferPayload : undefined;
    const transferOptions: ApiSubmitGasfullTransferOptions = {
      enclaveToken,
      accountId: currentAccountId,
      fee: fromDecimal(swapItem.swap.networkFee, tokenIn.decimals),
      amount: fromDecimal(swapItem.swap.fromAmount, tokenIn.decimals),
      toAddress: swapItem.swap.cex!.payinAddress,
      tokenAddress: tokenIn.tokenAddress,
      payload,
    };

    await pause(WAIT_FOR_CEX_DEPOSIT_ADDRESS);

    const transferResult = await callApi('swapCexSubmit', tokenIn.chain as ApiChain, transferOptions, swapItem.swap.id);

    if (isErrorTransferResult(transferResult)) {
      reportErrorTransferResult(transferResult, updateCurrentSwap);
      return;
    }

    if ('mfaRequestHash' in transferResult && transferResult.mfaRequestHash) {
      global = getGlobal();
      global = updateCurrentSwap(global, {
        state: SwapState.ConfirmMfa,
        swapId: 'swapId' in transferResult ? transferResult.swapId : swapItem.swap.id,
        mfaRequestHash: transferResult.mfaRequestHash,
      });
      setGlobal(global);
    }
  }
}));

function showUnsupportedNearIntentsMemoError() {
  const global = clearIsPinAccepted(getGlobal());
  setGlobal(updateCurrentSwap(global, {
    state: SwapState.Initial,
    isLoading: undefined,
    errorType: SwapErrorType.UnexpectedError,
    payinAddress: undefined,
    payoutAddress: undefined,
    payinExtraId: undefined,
    isManualDepositRequired: undefined,
  }));
}

function canAutoSubmitCexDeposit(chain: string, memo?: string) {
  return !memo || canAutoSubmitCexMemo(chain);
}

export function shouldBlockUnsupportedNearIntentsMemo(
  cexLabel: string | undefined,
  chain: string,
  memo?: string,
) {
  return cexLabel === 'near-intents' && Boolean(memo) && !canAutoSubmitCexMemo(chain);
}

function canAutoSubmitCexMemo(chain: string) {
  return chain === 'ton' || chain === 'solana';
}

addActionHandler('updateSwapMfaRequestStatus', async (global) => {
  const { mfaRequestHash, swapId } = global.currentSwap;
  if (!mfaRequestHash || !swapId) return;

  const result = await callApi('fetchMfaRequest', mfaRequestHash);
  if (!result?.isConfirmed) return;

  const accountId = selectCurrentAccountId(getGlobal());
  if (!accountId) return;

  try {
    await callApi('confirmSwapMfaRequest', accountId, swapId, result.txHash);
  } catch (err) {
    logDebugError('updateSwapMfaRequestStatus:confirmSwapMfaRequest', err);
  }

  global = getGlobal();
  global = updateCurrentSwap(global, {
    state: SwapState.Complete,
    mfaRequestHash: undefined,
  });
  setGlobal(global);
});

addActionHandler('switchSwapTokens', (global) => {
  const {
    tokenInSlug, tokenOutSlug, amountIn, amountOut,
  } = global.currentSwap;

  global = updateCurrentSwap(global, {
    isMaxAmount: false,
    amountIn: amountOut,
    amountOut: amountIn,
    tokenInSlug: tokenOutSlug,
    tokenOutSlug: tokenInSlug,
    inputSource: SwapInputSource.In,
    maxAmountFromBackend: undefined,
  });
  setGlobal(global);
});

addActionHandler('setSwapTokenIn', (global, actions, { tokenSlug: newTokenInSlug }) => {
  const {
    amountIn,
    amountOut,
    tokenInSlug,
    tokenOutSlug,
  } = global.currentSwap;
  const newTokenIn = global.swapTokenInfo.bySlug[newTokenInSlug];
  const adjustedAmountIn = amountIn ? roundDecimal(amountIn, newTokenIn.decimals) : amountIn;

  // Don't set the same token in both inputs
  const newTokenOutSlug = newTokenInSlug === tokenOutSlug ? tokenInSlug : tokenOutSlug;
  const newTokenOut = newTokenOutSlug ? global.swapTokenInfo.bySlug[newTokenOutSlug] : undefined;
  const adjustedAmountOut = amountOut && newTokenOut ? roundDecimal(amountOut, newTokenOut.decimals) : amountOut;

  global = updateCurrentSwap(global, {
    amountIn: adjustedAmountIn === '0' ? undefined : adjustedAmountIn,
    amountOut: adjustedAmountOut === '0' ? undefined : adjustedAmountOut,
    tokenInSlug: newTokenInSlug,
    tokenOutSlug: newTokenOutSlug,
    maxAmountFromBackend: undefined,
  });
  setGlobal(global);
});

addActionHandler('setSwapTokenOut', (global, actions, { tokenSlug: newTokenOutSlug }) => {
  const {
    amountIn,
    amountOut,
    tokenInSlug,
    tokenOutSlug,
  } = global.currentSwap;
  const newTokenOut = global.swapTokenInfo.bySlug[newTokenOutSlug];
  const adjustedAmountOut = amountOut ? roundDecimal(amountOut, newTokenOut.decimals) : amountOut;

  // Don't set the same token in both inputs
  const newTokenInSlug = newTokenOutSlug === tokenInSlug ? tokenOutSlug : tokenInSlug;
  const newTokenIn = newTokenInSlug ? global.swapTokenInfo.bySlug[newTokenInSlug] : undefined;
  const adjustedAmountIn = amountIn && newTokenIn ? roundDecimal(amountIn, newTokenIn.decimals) : amountIn;

  global = updateCurrentSwap(global, {
    amountOut: adjustedAmountOut === '0' ? undefined : adjustedAmountOut,
    amountIn: adjustedAmountIn === '0' ? undefined : adjustedAmountIn,
    tokenOutSlug: newTokenOutSlug,
    tokenInSlug: newTokenInSlug,
    maxAmountFromBackend: undefined,
  });
  setGlobal(global);
});

addActionHandler('setSwapAmountIn', (global, actions, { amount, isMaxAmount = false }) => {
  global = updateCurrentSwap(global, {
    amountIn: amount,
    isMaxAmount,
    inputSource: SwapInputSource.In,
  });
  setGlobal(global);
});

addActionHandler('setSwapAmountOut', (global, actions, { amount }) => {
  global = updateCurrentSwap(global, {
    amountOut: amount,
    isMaxAmount: false,
    inputSource: SwapInputSource.Out,
  });
  setGlobal(global);
});

addActionHandler('setSlippage', (global, actions, { slippage }) => {
  return updateCurrentSwap(global, { slippage });
});

addActionHandler('estimateSwap', async () => {
  await estimateSwapConcurrently(async (global, shouldStop) => {
    const { tokenInSlug, tokenOutSlug } = global.currentSwap;
    const accountChains = selectCurrentAccount(global)?.byChain ?? {};

    if (tokenInSlug) {
      // The swap pairs are loaded not only for the below `isSwapPairValid` call, but also for `TokenSelector` to
      // highlight the allowed swap pairs. The `loadSwapPairs` can be not awaited when the pair is well-known to be
      // valid, but we don't do it, because: 1) to keep the code simpler and more reliable, 2) `loadSwapPairs` has no
      // own concurrent execution protection, it relies on the `estimateSwap` concurrent execution protection.
      await loadSwapPairs(tokenInSlug);

      if (shouldStop()) return;
      global = getGlobal();
    }

    if (tokenInSlug && tokenOutSlug) {
      if (!isSwapPairValid(
        tokenInSlug,
        tokenOutSlug,
        global.swapPairs?.bySlug,
        global.swapVersion,
        accountChains,
      )) {
        return {
          ...getSwapEstimateResetParams(global),
          errorType: SwapErrorType.InvalidPair,
        };
      }
    }

    if (!isSwapFormFilled(global)) {
      return getSwapEstimateResetParams(global);
    }

    return estimateSwap(global, shouldStop);
  });
});

async function estimateSwap(global: GlobalState, shouldStop: () => boolean): Promise<SwapEstimateResult> {
  const tokenIn = global.swapTokenInfo.bySlug[global.currentSwap.tokenInSlug!];
  const tokenOut = global.swapTokenInfo.bySlug[global.currentSwap.tokenOutSlug!];

  const swapType = selectSwapType(global);
  const isOnChain = swapType === SwapType.OnChain;

  const from = resolveSwapAssetId(tokenIn);
  const to = resolveSwapAssetId(tokenOut);

  let estimateRequest: ApiSwapEstimateRequest;
  let shouldTryDiesel: boolean | undefined;
  let isFromAmountMax: boolean | undefined;
  let toncoinBalance: bigint | undefined;

  if (isOnChain) {
    const nativeTokenIn = getNativeToken(getChainBySlug(tokenIn.slug));
    const { fromAmount, isFromAmountMax: isMax } = processNativeMaxSwap(global);

    isFromAmountMax = isMax;

    const toAmount = global.currentSwap.amountOut ?? '0';
    const estimateAmount = global.currentSwap.inputSource === SwapInputSource.In ? { fromAmount } : { toAmount };

    if (tokenIn.chain === 'ton') {
      toncoinBalance = selectCurrentToncoinBalance(global);

      shouldTryDiesel = toncoinBalance < fromDecimal(global.currentSwap.networkFee ?? '0', nativeTokenIn.decimals);
    }

    estimateRequest = {
      ...estimateAmount,
      from,
      to,
      slippage: global.currentSwap.slippage,
      fromAddress: selectCurrentAccount(global)!.byChain[tokenIn.chain as ApiChain]!.address,
      shouldTryDiesel,
      isFromAmountMax,
      toncoinBalance: toncoinBalance !== undefined
        ? toDecimal(toncoinBalance ?? 0n, TONCOIN.decimals)
        : undefined,
    };
  } else {
    const account = selectCurrentAccount(global);
    const fromAddress = getIsSupportedChain(tokenIn.chain)
      ? account?.byChain[tokenIn.chain]?.address
      : undefined;
    const toAddress = getIsSupportedChain(tokenOut.chain)
      ? account?.byChain[tokenOut.chain]?.address ?? global.currentSwap.toAddress
      : global.currentSwap.toAddress;
    const shouldForceChangelly = swapType === SwapType.CrosschainToWallet && !fromAddress;

    estimateRequest = {
      fromAmount: global.currentSwap.amountIn ?? '0',
      from,
      to,
      fromAddress,
      toAddress,
      cexLabel: shouldForceChangelly ? 'changelly' : global.currentSwap.currentCexLabel,
    };
  }

  const estimate = await callApi('swapEstimate', selectCurrentAccountId(global)!, estimateRequest);

  if (shouldStop()) return undefined;

  global = getGlobal();

  if (!estimate || 'error' in estimate || 'errors' in estimate) {
    if (estimate && 'error' in estimate && estimate.error.includes('requests limit')) {
      return 'rateLimited';
    }

    const errorText = estimate === undefined
      ? undefined
      : 'error' in estimate
        ? estimate.error
        : 'errors' in estimate
          ? (estimate.errors as { msg: string }[]).map(({ msg }) => msg).join(', ')
          : undefined;

    const errorType = SERVER_ERRORS_MAP[errorText as keyof typeof SERVER_ERRORS_MAP]
      ?? SwapErrorType.UnexpectedError;

    logDebugError('estimateSwap', errorText, estimate);

    return {
      ...getSwapEstimateResetParams(global),
      // Keep the fee that enabled diesel; otherwise the next poll falls back to gasfull and oscillates.
      ...(shouldTryDiesel ? { networkFee: global.currentSwap.networkFee } : undefined),
      errorType,
    };
  }

  if (estimate.route === 'dex') {
    if (!isOnChain) {
      logDebugError('estimateSwap', 'Unexpected DEX estimate response', estimate);

      return {
        ...getSwapEstimateResetParams(global),
        errorType: SwapErrorType.UnexpectedError,
      };
    }

    const dexEstimate = estimate;
    const errorType = dexEstimate.toAmount === '0' && shouldTryDiesel
      ? SwapErrorType.NotEnoughForFee
      : undefined;

    const estimates = buildSwapEstimates(dexEstimate);
    const currentEstimate = chooseSwapEstimate(global, estimates, dexEstimate.dexLabel);

    return {
      ...getSwapEstimateResetParams(global),
      ...(global.currentSwap.inputSource === SwapInputSource.In
        ? { amountOut: currentEstimate.toAmount }
        : { amountIn: currentEstimate.fromAmount }
      ),
      ...(isFromAmountMax ? {
        amountIn: currentEstimate.fromAmount,
        maxAmountFromBackend: currentEstimate.fromAmount,
      } : undefined),
      amountOutMin: currentEstimate.toMinAmount,
      priceImpact: currentEstimate.impact,
      dexRouterLabel: dexEstimate.dexRouterLabel || undefined,
      errorType,
      dieselStatus: dexEstimate.dieselStatus,
      dexLabel: currentEstimate.dexLabel,
      routes: currentEstimate.routes,
      networkFee: currentEstimate.networkFee,
      realNetworkFee: currentEstimate.realNetworkFee,
      swapFee: currentEstimate.swapFee,
      swapFeePercent: currentEstimate.swapFeePercent,
      ourFee: currentEstimate.ourFee,
      ourFeePercent: dexEstimate.ourFeePercent,
      dieselFee: currentEstimate.dieselFee,
    };
  }

  if (estimate.route === 'cex') {
    if (isOnChain) {
      return {
        ...getSwapEstimateResetParams(global),
        errorType: SwapErrorType.UnexpectedError,
      };
    }

    const cexEstimate: ApiSwapCexEstimateResponse = estimate;
    const fromAmount = global.currentSwap.amountIn ?? '0';

    let networkFee: string | undefined;
    let realNetworkFee: string | undefined;
    let amountIn = cexEstimate.fromAmount;

    if (swapType !== SwapType.CrosschainToWallet) {
      if (!getIsSupportedChain(tokenIn.chain)) {
        throw new Error(`Unexpected chain ${tokenIn.chain}`);
      }

      const tokenInBalance = selectCurrentAccountTokenBalance(global, tokenIn.slug);
      const isEvmMaxNativeSwap = global.currentSwap.isMaxAmount
        && getIsNativeToken(tokenIn.slug)
        && getEvmChains().includes(tokenIn.chain);

      const txDraft = await callApi('checkTransactionDraft', tokenIn.chain, {
        accountId: selectCurrentAccountId(global)!,
        toAddress: getChainConfig(tokenIn.chain).feeCheckAddress,
        tokenAddress: tokenIn.tokenAddress,
        ...(isEvmMaxNativeSwap && tokenInBalance !== undefined ? { amount: tokenInBalance } : {}),
      });

      if (txDraft) {
        ({ networkFee, realNetworkFee } = convertTransferFeesToSwapFees(txDraft, tokenIn.chain));
      }

      // Auto-adjust amountIn for crosschain swaps when fee becomes known
      if (global.currentSwap.isMaxAmount && networkFee && getIsNativeToken(tokenIn.slug)) {
        const tokenBalance = selectCurrentAccountTokenBalance(global, tokenIn.slug);
        const amountInBigint = tokenBalance - fromDecimal(networkFee, tokenIn.decimals);

        amountIn = toDecimal(amountInBigint, tokenIn.decimals);
      }
    }

    return {
      ...getSwapEstimateResetParams(global),
      amountOut: cexEstimate.toAmount === '0' ? undefined : cexEstimate.toAmount,
      amountIn,
      limits: {
        fromMin: cexEstimate.fromMin,
        fromMax: cexEstimate.fromMax,
      },
      currentCexLabel: cexEstimate.cexLabel,
      currentCexProviderName: cexEstimate.providerName,
      currentCexTermsOfUseUrl: cexEstimate.termsOfUseUrl,
      currentCexPrivacyPolicyUrl: cexEstimate.privacyPolicyUrl,
      currentCexAmlKycPolicyUrl: cexEstimate.amlKycPolicyUrl,
      swapFee: cexEstimate.swapFee,
      networkFee,
      realNetworkFee,
      ourFee: cexEstimate.ourFee ?? '0',
      ourFeePercent: cexEstimate.ourFeePercent ?? 0,
      dieselStatus: 'not-available',
      amountOutMin: cexEstimate.toAmount,
      errorType: Big(fromAmount).lt(cexEstimate.fromMin)
        ? SwapErrorType.ChangellyMinSwap
        : Big(fromAmount).gt(cexEstimate.fromMax)
          ? SwapErrorType.ChangellyMaxSwap
          : undefined,
    };
  }

  logDebugError('estimateSwap', 'Unexpected estimate response route', estimate);

  return {
    ...getSwapEstimateResetParams(global),
    errorType: SwapErrorType.UnexpectedError,
  };
}

addActionHandler('setSwapScreen', (global, actions, { state }) => {
  if (state === SwapState.Initial) {
    global = updateCurrentSwap(global, { swapId: generateUniqueId() });
  }
  global = updateCurrentSwap(global, { state });
  setGlobal(global);
});

addActionHandler('clearSwapError', (global) => {
  global = updateCurrentSwap(global, { error: undefined });
  setGlobal(global);
});

async function loadSwapPairs(tokenInSlug: string) {
  await waitFor(() => {
    const { swapTokenInfo: { isLoaded, bySlug } } = getGlobal();
    return !!(isLoaded || bySlug[tokenInSlug]);
  }, 500, 100);
  let global = getGlobal();

  const tokenIn = global.swapTokenInfo.bySlug[tokenInSlug];
  if (!tokenIn) {
    return;
  }

  const assetId = resolveSwapAssetId(tokenIn);

  const cache = pairsCache[tokenInSlug];
  const isCacheValid = cache && (Date.now() - cache.timestamp <= CACHE_DURATION);
  if (isCacheValid) {
    return;
  }

  const pairs = await callApi('swapGetPairs', assetId);
  global = getGlobal();

  const bySlug: AssetPairs = {};

  if (pairs) {
    for (const pair of pairs) {
      bySlug[pair.slug] = {
        ...(pair.isReverseProhibited && {
          isReverseProhibited: pair.isReverseProhibited,
        }),
      };
    }

    pairsCache[tokenInSlug] = { timestamp: Date.now() };
  }

  setGlobal({
    ...global,
    swapPairs: {
      bySlug: {
        ...global.swapPairs?.bySlug,
        [tokenInSlug]: bySlug,
      },
    },
  });
}

addActionHandler('setSwapCexAddress', (global, actions, { toAddress }) => {
  global = updateCurrentSwap(global, { toAddress });
  setGlobal(global);
});

addActionHandler('updatePendingSwaps', async (global, actions, payload) => {
  const accountId = selectCurrentAccountId(global);
  if (!accountId) return;

  await runActivityUpdateInOrder(accountId, async () => {
    global = getGlobal();
    if (selectCurrentAccountId(global) !== accountId) return;

    const { activities } = selectAccountState(global, accountId) ?? {};
    if (!activities) return;

    const pendingCexSwaps = selectPendingCexSwapActivities(global, accountId);
    const items = pendingCexSwaps.map((activity) => ({ id: parseTxId(activity.id).hash, chain: 'ton' as const }));
    if (!items.length) return;

    const result = await callApi(
      'fetchSwaps',
      accountId,
      items,
      selectCexSwapRefreshContextActivities(activities, pendingCexSwaps, payload?.contextActivities),
      { forceProviderRefresh: payload?.forceProviderRefresh },
    );
    const patch = result?.patch;
    if (!patch || (!patch.upsert.length && !patch.removeIds.length)) return;

    global = getGlobal();
    if (selectCurrentAccountId(global) !== accountId) return;

    // The SDK patch is authoritative for both stored rows and their explicit visibility.
    global = applyActivitiesPatch(global, accountId, patch);

    setGlobal(global);
  });
});

function convertTransferFeesToSwapFees(
  txDraft: Pick<ApiCheckTransactionDraftResult, 'explainedFee'>,
  chain: ApiChain,
) {
  const nativeToken = getNativeToken(chain);
  let networkFee: string | undefined;
  let realNetworkFee: string | undefined;

  const fullFee = txDraft?.explainedFee?.fullFee?.nativeSum;
  const realFee = txDraft?.explainedFee?.realFee?.nativeSum;

  if (fullFee !== undefined) {
    networkFee = toDecimal(fullFee, nativeToken.decimals);
  }
  if (realFee !== undefined) {
    realNetworkFee = toDecimal(realFee, nativeToken.decimals);
  }

  return { networkFee, realNetworkFee };
}

export type SwapEstimateResult = Partial<GlobalState['currentSwap']> | 'rateLimited' | undefined;

let isEstimatingSwap = false;

/**
 * A boilerplate of swap estimation, ensuring consistent behavior in concurrent usage scenarios.
 * This function is expected to be called periodically, and you may call it as often as you like.
 *
 * You may call the `shouldStop` function to check whether it makes sense to continue estimating (because the result
 * is likely to be ignored). If `shouldStop` returns true, `estimate` may return any value (it will be ignored).
 */
export async function estimateSwapConcurrently(
  estimate: (
    global: GlobalState,
    shouldStop: () => boolean,
  ) => SwapEstimateResult | Promise<SwapEstimateResult>,
) {
  const initialGlobal = getGlobal();

  if (shouldAvoidSwapEstimation(initialGlobal)) return;

  // There should be only 1 swap estimation at a time. A timer in SwapInitial will trigger another estimation attempt.
  if (isEstimatingSwap) {
    return;
  }

  try {
    isEstimatingSwap = true;

    const isEstimateInputIntact = isSwapEstimateInputEqual.bind(undefined, initialGlobal);

    const swapUpdate = await estimate(initialGlobal, () => {
      const currentGlobal = getGlobal();
      return shouldAvoidSwapEstimation(currentGlobal) || !isEstimateInputIntact(currentGlobal);
    });

    const finalGlobal = getGlobal();

    // If the dependencies were changed during the estimation, the estimation result should be ignored and the loading
    // indicator should stay (in order to avoid showing the outdated fee). A timer in SwapInitial will trigger another
    // estimation attempt to get the up-to-date fee.
    if (!isEstimateInputIntact(finalGlobal)) {
      return;
    }

    // If the swap estimation request has been rate-limited, we should keep showing the loading indicator
    if (swapUpdate === 'rateLimited') {
      return;
    }

    setGlobal(updateCurrentSwap(finalGlobal, {
      isEstimating: false,
      ...(shouldAvoidSwapEstimation(finalGlobal) ? undefined : swapUpdate),
    }));
  } finally {
    isEstimatingSwap = false;
  }
}

function chooseSwapEstimate(
  global: GlobalState,
  newEstimates: ApiSwapEstimateVariant[],
  proposedBestDexLabel: ApiSwapDexEstimateResponse['dexLabel'],
) {
  if (newEstimates.length === 0) {
    throw new Error('Unexpected empty `newEstimates` array');
  }

  const { tokenInSlug } = global.currentSwap;

  const tokenIn = tokenInSlug ? global.swapTokenInfo.bySlug[tokenInSlug] : undefined;
  const tokenInBalance = tokenInSlug ? selectCurrentAccountTokenBalance(global, tokenInSlug) : undefined;
  const nativeTokenIn = tokenInSlug ? findNativeToken(getChainBySlug(tokenInSlug)) : undefined;
  const nativeTokenInBalance = nativeTokenIn && selectCurrentAccountTokenBalance(global, nativeTokenIn.slug);
  let availableEstimates = newEstimates.filter((variant) => canAffordSwapEstimateVariant({
    variant,
    tokenIn,
    tokenInBalance,
    nativeTokenInBalance,
  }));

  if (availableEstimates.length === 0) {
    availableEstimates = newEstimates;
  }

  return availableEstimates.find(({ dexLabel }) => dexLabel === proposedBestDexLabel)
    ?? availableEstimates[0];
}
