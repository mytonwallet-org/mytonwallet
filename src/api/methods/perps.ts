import type { LangCode } from '../../global/types';
import type {
  ApiEvmSwapCall,
  ApiHistoryList,
  ApiPerpsAssetDetail,
  ApiPerpsBuildBalanceWithdrawRequest,
  ApiPerpsBuildBalanceWithdrawResult,
  ApiPerpsBuildClosePositionRequest,
  ApiPerpsBuildClosePositionResult,
  ApiPerpsBuildDepositRequest,
  ApiPerpsBuildDepositResult,
  ApiPerpsBuildModifyPositionRequest,
  ApiPerpsBuildModifyPositionResult,
  ApiPerpsBuildPositionRequest,
  ApiPerpsBuildPositionResult,
  ApiPerpsBuildWithdrawalRequest,
  ApiPerpsBuildWithdrawalResult,
  ApiPerpsCctpDeposit,
  ApiPerpsChain,
  ApiPerpsClosePositionResult,
  ApiPerpsEstimateModifyPositionRequest,
  ApiPerpsEstimateModifyPositionResult,
  ApiPerpsEstimatePositionRequest,
  ApiPerpsEstimatePositionResult,
  ApiPerpsExchangeActionPayload,
  ApiPerpsExchangeBuild,
  ApiPerpsExecuteClosePositionRequest,
  ApiPerpsExecuteClosePositionResult,
  ApiPerpsExecutePositionRequest,
  ApiPerpsExecutePositionResult,
  ApiPerpsGetActivitiesRequest,
  ApiPerpsGetActivitiesResult,
  ApiPerpsGetAssetChartRequest,
  ApiPerpsGetAssetRequest,
  ApiPerpsGetAssetsResult,
  ApiPerpsGetPositionsRequest,
  ApiPerpsGetPositionsResult,
  ApiPerpsModifyPositionResult,
  ApiPerpsOpenPositionRequest,
  ApiPerpsOpenPositionResult,
  ApiPerpsWithdrawPermit,
  OnApiUpdate,
} from '../types';
import { ApiCommonError, ApiTransactionError } from '../types';

import { Big } from '../../lib/big.js';
import { parseAccountId } from '../../util/account';
import { logDebugError } from '../../util/logs';
import { fetchPrivateKeyString } from '../chains/evm/auth';
import {
  buildPerpsCctpDepositTransferWithPrivateKey,
  signHyperliquidExchangeBuild,
  signHyperliquidExchangePayload,
  signHyperliquidWithdrawPermit,
  submitPerpsCctpDepositTransfer,
} from '../chains/evm/perps';
import { fetchEvmWallet } from '../chains/evm/util/account';
import { fetchStoredChainAccount } from '../common/accounts';
import { callBackendPost } from '../common/backend';
import {
  buildPerpsBalanceWithdrawExecuteRequest,
  buildPerpsCloseOrderExecuteRequest,
  buildPerpsCloseWithdrawExecuteRequest,
  buildPerpsDepositExecuteRequest,
  buildPerpsModifyExecuteRequest,
  buildPerpsModifyReduceExecuteRequest,
  buildPerpsOpenExecuteRequest,
  buildPerpsOpenFromBalanceExecuteRequest,
  PERPS_BUILD_REQUEST_TIMEOUT_MS,
  PERPS_CCTP_DEPOSIT_CHAIN,
  PERPS_CCTP_FORWARD_FEE_USDC,
  PERPS_CLOSE_EXECUTE_TIMEOUT_MS,
  PERPS_EXECUTE_DEPOSIT_WAIT_TIMEOUT_MS,
  PERPS_REVIEW_PRICE_TOLERANCE,
} from '../common/perps';
import { getPerpsAssets, refreshPerpsAssets } from '../common/perpsAssets';

let onUpdate: OnApiUpdate | undefined;

export function initPerps(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

function isPerpsExecuteSuccess(result: ApiPerpsExecutePositionResult): boolean {
  return !result.status.startsWith('error');
}

export type PerpsExecutionHooks = {
  validateBuild?: (build: Partial<ApiPerpsExchangeBuild> & {
    deposit?: ApiPerpsCctpDeposit;
    updateLeverage?: ApiPerpsExchangeActionPayload;
    updateIsolatedMargin?: ApiPerpsExchangeActionPayload;
  }) => void;
  onSubmitting?: () => void;
  onDeposit?: (hash: string) => void;
  onTrade?: (result: ApiPerpsExecutePositionResult) => void;
  onWithdrawal?: (amount: string) => void;
};

function isPerpsCloseOrderSuccess(
  close?: ApiPerpsExecutePositionResult,
): close is ApiPerpsExecutePositionResult & { status: 'filled' } {
  return close?.status === 'filled';
}

function readPositiveUsdc(amount: number | string): Big | undefined {
  try {
    const value = Big(amount);
    return value.gt(0) ? value : undefined;
  } catch {
    return undefined;
  }
}

function perpsAmountsMatch(left: number | string, right: number | string): boolean {
  try {
    return Big(left).eq(right);
  } catch {
    return false;
  }
}

type PerpsWireOrder = {
  a?: unknown;
  b?: unknown;
  p?: unknown;
  s?: unknown;
  r?: unknown;
  t?: { limit?: { tif?: unknown } };
};

function assertPerpsOpenFromBalanceBuild(
  request: ApiPerpsOpenPositionRequest,
  build: ApiPerpsOpenPositionResult,
) {
  if ('deposit' in build || 'spotToPerp' in build) throw new Error('PerpsReviewChanged');
  const { action } = build;
  const orders = action.orders;
  const order = Array.isArray(orders) ? orders[0] as PerpsWireOrder : undefined;
  const leverage = build.updateLeverage.action;
  if (
    action.type !== 'order'
    || action.grouping !== 'na'
    || !Array.isArray(orders)
    || orders.length !== 1
    || !order
    || leverage.type !== 'updateLeverage'
    || leverage.leverage !== request.leverage
    || leverage.isCross !== request.isCross
    || leverage.asset !== order.a
    || order.b !== (request.side === 'long')
    || order.r !== false
    || order.t?.limit?.tif !== 'Ioc'
    || typeof order.p !== 'string'
    || typeof order.s !== 'string'
  ) {
    throw new Error('PerpsReviewChanged');
  }

  let size: Big;
  try {
    size = Big(order.s);
  } catch {
    throw new Error('PerpsReviewChanged');
  }
  if (!size.gt(0)) throw new Error('PerpsReviewChanged');
  const requested = readPositiveUsdc(request.amount);
  if (!requested) throw new Error('PerpsReviewChanged');
  const slippage = Big(request.slippage ?? Number(PERPS_REVIEW_PRICE_TOLERANCE));
  if (build.marketReferencePrice !== undefined) {
    let reference: Big;
    try {
      reference = Big(build.marketReferencePrice);
    } catch {
      throw new Error('PerpsReviewChanged');
    }
    if (!reference.gt(0)) throw new Error('PerpsReviewChanged');
    const referenceSize = requested.mul(request.leverage).div(reference);
    if (size.lt(referenceSize.div(Big(1).plus(slippage)))
      || size.gt(referenceSize.div(Big(1).minus(slippage)))) {
      throw new Error('PerpsReviewChanged');
    }
    return;
  }
  // A market IOC limit stays within slippage of the mid.
  let implied: Big;
  try {
    implied = size.mul(order.p).div(request.leverage);
  } catch {
    throw new Error('PerpsReviewChanged');
  }
  if (implied.minus(requested).abs().gt(requested.mul(slippage).plus(1))) throw new Error('PerpsReviewChanged');
}

async function signPerpsOpenExecutePayloads(
  accountId: string,
  privateKey: string,
  build: ApiPerpsBuildPositionResult,
) {
  const { network } = parseAccountId(accountId);

  const signOptions = {
    expectedSpotToPerpAmountUsdc: build.deposit.creditedAmountUsdc,
  };

  const [signature, approveBuilderFee, spotToPerp, updateLeverage] = await Promise.all([
    signHyperliquidExchangeBuild(network, privateKey, build, signOptions),
    build.approveBuilderFee
      ? signHyperliquidExchangePayload(network, privateKey, build.approveBuilderFee, signOptions)
      : undefined,
    build.spotToPerp
      ? signHyperliquidExchangePayload(network, privateKey, build.spotToPerp, signOptions)
      : undefined,
    signHyperliquidExchangePayload(network, privateKey, build.updateLeverage, signOptions),
  ]);

  return { signature, approveBuilderFee, spotToPerp, updateLeverage };
}

async function signPerpsModifyExecutePayloads(
  accountId: string,
  privateKey: string,
  build: ApiPerpsBuildModifyPositionResult,
) {
  const { network } = parseAccountId(accountId);

  const signOptions = build.deposit
    ? { expectedSpotToPerpAmountUsdc: build.deposit.creditedAmountUsdc }
    : undefined;

  if (build.updateLeverage && build.action === undefined) {
    const [updateLeverage, updateIsolatedMargin, spotToPerp, approveBuilderFee] = await Promise.all([
      signHyperliquidExchangePayload(network, privateKey, build.updateLeverage, signOptions),
      build.updateIsolatedMargin
        ? signHyperliquidExchangePayload(network, privateKey, build.updateIsolatedMargin, signOptions)
        : undefined,
      build.spotToPerp
        ? signHyperliquidExchangePayload(network, privateKey, build.spotToPerp, signOptions)
        : undefined,
      build.approveBuilderFee
        ? signHyperliquidExchangePayload(network, privateKey, build.approveBuilderFee, signOptions)
        : undefined,
    ]);

    return { updateLeverage, updateIsolatedMargin, spotToPerp, approveBuilderFee };
  }

  if (
    build.hash === undefined
    || build.nonce === undefined
    || build.action === undefined
    || build.typedData === undefined
  ) {
    throw new Error('Invalid modify build: missing order exchange fields');
  }

  const orderBuild = build as ApiPerpsBuildModifyPositionResult & {
    hash: string;
    nonce: number;
    action: Record<string, unknown>;
    typedData: NonNullable<ApiPerpsBuildModifyPositionResult['typedData']>;
  };

  const [signature, approveBuilderFee, spotToPerp] = await Promise.all([
    signHyperliquidExchangeBuild(network, privateKey, orderBuild, signOptions),
    build.approveBuilderFee
      ? signHyperliquidExchangePayload(network, privateKey, build.approveBuilderFee, signOptions)
      : undefined,
    build.spotToPerp
      ? signHyperliquidExchangePayload(network, privateKey, build.spotToPerp, signOptions)
      : undefined,
  ]);

  return { signature, approveBuilderFee, spotToPerp };
}

async function submitPerpsCloseWithdrawExecute(
  accountId: string,
  privateKey: string,
  chain: ApiPerpsChain,
  walletAddress: string,
  withdraw: ApiPerpsWithdrawPermit,
  onSubmitting?: NoneToVoidFunction,
): Promise<ApiPerpsExecuteClosePositionResult> {
  const { network } = parseAccountId(accountId);
  const signature = await signHyperliquidWithdrawPermit(
    network,
    privateKey,
    withdraw,
    walletAddress,
  );

  const request = buildPerpsCloseWithdrawExecuteRequest(chain, walletAddress, withdraw, signature);
  onSubmitting?.();
  return perpsExecuteClosePosition(request);
}

export function perpsGetPositions(request: ApiPerpsGetPositionsRequest): Promise<ApiPerpsGetPositionsResult> {
  return callBackendPost('/perps/positions', request);
}

export function perpsGetActivities(request: ApiPerpsGetActivitiesRequest): Promise<ApiPerpsGetActivitiesResult> {
  return callBackendPost('/perps/activities', request);
}

/**
 * Catalogue from the cache. `force` is the explicit refresh; polling replaces the cache on its own.
 * A language the cache was not stored for is fetched before it is returned.
 */
export function perpsGetAssets(
  signal?: AbortSignal,
  langCode?: LangCode,
  options?: { force?: boolean },
): Promise<ApiPerpsGetAssetsResult> {
  return options?.force ? refreshPerpsAssets(langCode, signal) : getPerpsAssets(langCode, signal);
}

export function perpsGetAsset(request: ApiPerpsGetAssetRequest): Promise<ApiPerpsAssetDetail> {
  return callBackendPost('/perps/asset', request);
}

/** Close series for one catalogue asset. Points are `[seconds, price]`, oldest first. */
export function perpsGetAssetChart(request: ApiPerpsGetAssetChartRequest): Promise<ApiHistoryList> {
  return callBackendPost('/perps/asset/chart', request);
}

type PerpsEstimatePositionErrorBody = { error: string } | { errors: { msg: string }[] };

export async function perpsEstimatePosition(
  request: ApiPerpsEstimatePositionRequest,
): Promise<ApiPerpsEstimatePositionResult | { error: string }> {
  const answer = await callBackendPost<ApiPerpsEstimatePositionResult | PerpsEstimatePositionErrorBody>(
    '/perps/position/estimate',
    request,
    { isAllowBadRequest: true },
  );

  if ('errors' in answer) {
    const message = answer.errors.map(({ msg }) => msg).filter(Boolean).join(', ');
    return { error: message || 'Estimate failed.' };
  }

  if ('error' in answer) {
    return { error: answer.error || 'Estimate failed.' };
  }

  return answer;
}

export async function perpsEstimateModifyPosition(
  request: ApiPerpsEstimateModifyPositionRequest,
): Promise<ApiPerpsEstimateModifyPositionResult | { error: string }> {
  const answer = await callBackendPost<ApiPerpsEstimateModifyPositionResult | PerpsEstimatePositionErrorBody>(
    '/perps/position/modify/estimate',
    request,
    { isAllowBadRequest: true },
  );

  if ('errors' in answer) {
    const message = answer.errors.map(({ msg }) => msg).filter(Boolean).join(', ');
    return { error: message || 'Estimate failed.' };
  }

  if ('error' in answer) {
    return { error: answer.error || 'Estimate failed.' };
  }

  return answer;
}

function perpsBuildPosition(request: ApiPerpsBuildPositionRequest): Promise<ApiPerpsBuildPositionResult> {
  return callBackendPost('/perps/position/build', {
    ...request, slippage: request.slippage ?? Number(PERPS_REVIEW_PRICE_TOLERANCE),
  }, {
    timeout: PERPS_BUILD_REQUEST_TIMEOUT_MS,
  });
}

/** Deposit from `/perps/position/modify/estimate`. A different confirmed amount is refused. */
async function resolveLeverageChangeDeposit(
  request: ApiPerpsBuildModifyPositionRequest,
  leverage: number,
): Promise<{ request: ApiPerpsBuildModifyPositionRequest } | { error: string }> {
  const estimate = await perpsEstimateModifyPosition({
    chain: request.chain,
    address: request.address,
    asset: request.asset,
    leverage,
  });

  if ('error' in estimate || typeof estimate.depositAmount !== 'string') {
    return { error: 'error' in estimate ? estimate.error : 'Estimate failed.' };
  }

  const confirmed = request.depositAmount;
  if (confirmed !== undefined && String(confirmed) !== '') {
    try {
      if (!Big(confirmed).eq(estimate.depositAmount)) return { error: 'PerpsQuoteExpired' };
    } catch {
      return { error: 'PerpsQuoteExpired' };
    }
  }

  return { request: { ...request, depositAmount: estimate.depositAmount } };
}

function perpsBuildModifyPosition(
  request: ApiPerpsBuildModifyPositionRequest,
): Promise<ApiPerpsBuildModifyPositionResult> {
  return callBackendPost('/perps/position/modify/build', {
    ...request, slippage: request.slippage ?? Number(PERPS_REVIEW_PRICE_TOLERANCE),
  }, {
    timeout: PERPS_BUILD_REQUEST_TIMEOUT_MS,
  });
}

export function perpsBuildWithdrawal(request: ApiPerpsBuildWithdrawalRequest): Promise<ApiPerpsBuildWithdrawalResult> {
  return callBackendPost('/perps/position/withdraw/build', request);
}

function perpsBuildClosePosition(
  request: ApiPerpsBuildClosePositionRequest,
): Promise<ApiPerpsBuildClosePositionResult> {
  return callBackendPost('/perps/position/close/build', {
    ...request, slippage: request.slippage ?? Number(PERPS_REVIEW_PRICE_TOLERANCE),
  }, {
    timeout: PERPS_BUILD_REQUEST_TIMEOUT_MS,
  });
}

function perpsBuildDeposit(request: ApiPerpsBuildDepositRequest): Promise<ApiPerpsBuildDepositResult> {
  return callBackendPost('/perps/deposit/build', request, {
    timeout: PERPS_BUILD_REQUEST_TIMEOUT_MS,
  });
}

function perpsBuildBalanceWithdraw(
  request: ApiPerpsBuildBalanceWithdrawRequest,
): Promise<ApiPerpsBuildBalanceWithdrawResult> {
  return callBackendPost('/perps/withdraw/build', request);
}

function perpsBuildOpenPosition(request: ApiPerpsOpenPositionRequest): Promise<ApiPerpsOpenPositionResult> {
  return callBackendPost('/perps/position/open', {
    ...request,
    slippage: request.slippage ?? Number(PERPS_REVIEW_PRICE_TOLERANCE),
  }, {
    timeout: PERPS_BUILD_REQUEST_TIMEOUT_MS,
  });
}

// May be called via void to reduce blocking UI - backend manages state on its own.
function perpsExecutePosition(request: ApiPerpsExecutePositionRequest): Promise<ApiPerpsExecutePositionResult> {
  const timeout = request.depositAmount !== undefined
    ? PERPS_EXECUTE_DEPOSIT_WAIT_TIMEOUT_MS
    : undefined;

  return callBackendPost('/perps/position/execute', request, { timeout });
}

function perpsExecuteClosePosition(
  request: ApiPerpsExecuteClosePositionRequest,
  options?: { timeout?: number },
): Promise<ApiPerpsExecuteClosePositionResult> {
  const isCloseOrderPhase = request.action?.type === 'order';
  const timeout = options?.timeout ?? (isCloseOrderPhase ? PERPS_CLOSE_EXECUTE_TIMEOUT_MS : undefined);

  return callBackendPost('/perps/position/close/execute', request, { timeout });
}

type PreparedPerpsOpen =
  | ({
    build: ApiPerpsBuildPositionResult;
    executeRequest: ApiPerpsExecutePositionRequest;
    privateKey: string;
    chain: typeof PERPS_CCTP_DEPOSIT_CHAIN;
    calls: ApiEvmSwapCall[];
  })
  | { error: string };

async function preparePerpsOpenPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<PreparedPerpsOpen> {
  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);

  if (address.toLowerCase() !== request.address.toLowerCase()) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const build = await perpsBuildPosition(request);
  if (build.address?.toLowerCase() !== address.toLowerCase()) throw new Error('PerpsReviewChanged');
  hooks.validateBuild?.(build);

  const account = await fetchStoredChainAccount(accountId, PERPS_CCTP_DEPOSIT_CHAIN);

  if (account.type === 'ledger' || account.type === 'view') {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const privateKey = await fetchPrivateKeyString(PERPS_CCTP_DEPOSIT_CHAIN, accountId, enclaveToken, account);

  if (!privateKey) {
    return { error: ApiCommonError.InvalidPassword };
  }

  const signed = await signPerpsOpenExecutePayloads(accountId, privateKey, build);
  const executeRequest = buildPerpsOpenExecuteRequest(request.chain, build, signed);

  const transfer = await buildPerpsCctpDepositTransferWithPrivateKey(accountId, build.deposit, privateKey);

  if ('error' in transfer) {
    return { error: transfer.error };
  }

  return {
    build,
    executeRequest,
    privateKey,
    chain: transfer.chain,
    calls: transfer.calls,
  };
}

type PendingPerpsExecution = {
  depositTxHash: string;
  execution: Promise<ApiPerpsExecutePositionResult>;
};

/** Internal reviewed-order path; do not expose callbacks through the API dispatch table. */
export async function executePerpsOpenPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<(ApiPerpsExecutePositionResult & { depositTxHash: string }) | { error: string }> {
  const result = await startPerpsOpenPosition(accountId, enclaveToken, request, hooks);
  if ('error' in result) return result;
  return { ...await result.execution, depositTxHash: result.depositTxHash };
}

/** Wait for the trade (and any withdrawal) before completing a reviewed operation. */
export async function executePerpsModifyPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildModifyPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<ApiPerpsModifyPositionResult> {
  const result = await startPerpsModifyPosition(accountId, enclaveToken, request, hooks);
  return 'execution' in result ? { ...await result.execution, depositTxHash: result.depositTxHash } : result;
}

/**
 * Atomic open: start `/perps/position/execute` (CCTP wait + HL order) before the on-chain
 * deposit lands so the backend baseline is taken early; submit CCTP while execute polls.
 */
async function startPerpsOpenPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<PendingPerpsExecution | { error: string }> {
  const prepared = await preparePerpsOpenPosition(accountId, enclaveToken, request, hooks);

  if ('error' in prepared) {
    return prepared;
  }

  const {
    build,
    executeRequest,
    privateKey,
    calls,
  } = prepared;

  hooks.onSubmitting?.();
  const executePromise = perpsExecutePosition(executeRequest);
  // Execution can reject while the deposit is still awaiting submission; it is awaited below.
  void executePromise.catch(() => undefined);

  const depositResult = await submitPerpsCctpDepositTransfer({
    accountId,
    enclaveToken,
    deposit: build.deposit,
    calls,
    privateKey,
  });

  if ('error' in depositResult) {
    void executePromise.catch(() => undefined);
    return depositResult;
  }

  const depositTxHash = depositResult.txHash;
  hooks.onDeposit?.(depositTxHash);

  void executePromise
    .then((result) => hooks.onTrade?.(result))
    .catch((err) => {
      logDebugError('perpsExecutePosition', err);
    });

  return { depositTxHash, execution: executePromise };
}

type PreparedPerpsModify =
  | ({
    flow: 'execute';
    build: ApiPerpsBuildModifyPositionResult;
    executeRequest: ApiPerpsExecutePositionRequest;
    privateKey: string;
    needsDeposit: boolean;
    chain: typeof PERPS_CCTP_DEPOSIT_CHAIN;
    calls?: ApiEvmSwapCall[];
  })
  | ({
    flow: 'reduce_close';
    build: ApiPerpsBuildModifyPositionResult;
    reduceExecuteRequest: ApiPerpsExecuteClosePositionRequest;
    privateKey: string;
    chain: typeof PERPS_CCTP_DEPOSIT_CHAIN;
  })
  | { error: string };

async function preparePerpsModifyPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildModifyPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<PreparedPerpsModify> {
  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);

  if (address.toLowerCase() !== request.address.toLowerCase()) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  let buildRequest = request;
  if (!request.reduceOnly && request.leverage !== undefined) {
    const resolved = await resolveLeverageChangeDeposit(request, request.leverage);
    if ('error' in resolved) return resolved;
    buildRequest = resolved.request;
  }

  const build = await perpsBuildModifyPosition(buildRequest);
  if (build.address?.toLowerCase() !== address.toLowerCase()) throw new Error('PerpsReviewChanged');
  hooks.validateBuild?.(build);
  const account = await fetchStoredChainAccount(accountId, PERPS_CCTP_DEPOSIT_CHAIN);

  if (account.type === 'ledger' || account.type === 'view') {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const privateKey = await fetchPrivateKeyString(PERPS_CCTP_DEPOSIT_CHAIN, accountId, enclaveToken, account);

  if (!privateKey) {
    return { error: ApiCommonError.InvalidPassword };
  }

  const signed = await signPerpsModifyExecutePayloads(accountId, privateKey, build);

  if (request.reduceOnly) {
    if (
      build.action === undefined
      || build.nonce === undefined
      || build.hash === undefined
      || build.typedData === undefined
      || signed.signature === undefined
    ) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    return {
      flow: 'reduce_close',
      build,
      reduceExecuteRequest: buildPerpsModifyReduceExecuteRequest(
        request.chain,
        build as ApiPerpsBuildModifyPositionResult & {
          hash: string;
          nonce: number;
          action: Record<string, unknown>;
          typedData: NonNullable<ApiPerpsBuildModifyPositionResult['typedData']>;
        },
        request,
        signed.signature,
      ),
      privateKey,
      chain: PERPS_CCTP_DEPOSIT_CHAIN,
    };
  }

  const executeRequest = buildPerpsModifyExecuteRequest(request.chain, build, signed);

  if (!build.deposit) {
    return {
      flow: 'execute',
      build,
      executeRequest,
      privateKey,
      needsDeposit: false,
      chain: PERPS_CCTP_DEPOSIT_CHAIN,
    };
  }

  const transfer = await buildPerpsCctpDepositTransferWithPrivateKey(accountId, build.deposit, privateKey);

  if ('error' in transfer) {
    return { error: transfer.error };
  }

  return {
    flow: 'execute',
    build,
    executeRequest,
    privateKey,
    needsDeposit: true,
    chain: transfer.chain,
    calls: transfer.calls,
  };
}

async function executePerpsModifyReduceClose(
  accountId: string,
  prepared: Extract<PreparedPerpsModify, { flow: 'reduce_close' }>,
  hooks: PerpsExecutionHooks,
): Promise<ApiPerpsModifyPositionResult> {
  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);

  hooks.onSubmitting?.();
  const closePhase = await perpsExecuteClosePosition(
    prepared.reduceExecuteRequest,
    { timeout: PERPS_CLOSE_EXECUTE_TIMEOUT_MS },
  );

  if (closePhase.close) hooks.onTrade?.(closePhase.close);
  if (!isPerpsCloseOrderSuccess(closePhase.close)) {
    return { error: closePhase.close?.status.startsWith('error:')
      ? closePhase.close.status : ApiTransactionError.UnsuccesfulTransfer };
  }
  if (closePhase.phase !== 'awaiting_withdraw_signature' || !closePhase.withdraw) {
    return { ...closePhase.close, withdrawalPhase: 'withdraw_unavailable' };
  }

  hooks.onWithdrawal?.(closePhase.withdraw.amountUsdc);
  const withdrawPhase = await submitPerpsCloseWithdrawExecute(
    accountId,
    prepared.privateKey,
    prepared.reduceExecuteRequest.chain,
    address,
    closePhase.withdraw,
  );

  if (withdrawPhase.phase !== 'completed' || !withdrawPhase.withdrawResult) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  return { ...closePhase.close, withdrawalPhase: 'completed' };
}

/**
 * Modify: one password, then build → sign → `/perps/position/execute`.
 * A leverage change re-reads `/perps/position/modify/estimate` and builds with that deposit.
 * Increase size and a positive leverage deposit start execute before the CCTP transfer, same as open.
 * A leverage increase estimates `"0"` and signs `updateLeverage` only.
 * Reduce-only uses `/perps/position/close/execute`.
 */
async function startPerpsModifyPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildModifyPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<ApiPerpsModifyPositionResult | PendingPerpsExecution> {
  const prepared = await preparePerpsModifyPosition(accountId, enclaveToken, request, hooks);

  if ('error' in prepared) {
    return prepared;
  }

  if (prepared.flow === 'reduce_close') {
    return executePerpsModifyReduceClose(accountId, prepared, hooks);
  }

  const {
    executeRequest,
    privateKey,
    needsDeposit,
    build,
    calls,
  } = prepared;

  if (!needsDeposit || !build.deposit) {
    hooks.onSubmitting?.();
    return perpsExecutePosition(executeRequest);
  }

  hooks.onSubmitting?.();
  const executePromise = perpsExecutePosition(executeRequest);
  // Execution can reject while the deposit is still awaiting submission; it is awaited below.
  void executePromise.catch(() => undefined);

  const depositResult = await submitPerpsCctpDepositTransfer({
    accountId,
    enclaveToken,
    deposit: build.deposit,
    calls,
    privateKey,
  });

  if ('error' in depositResult) {
    void executePromise.catch(() => undefined);
    return depositResult;
  }

  const depositTxHash = depositResult.txHash;
  hooks.onDeposit?.(depositTxHash);

  void executePromise
    .then((result) => hooks.onTrade?.(result))
    .catch((err) => {
      logDebugError('perpsExecutePosition', err);
    });

  return { depositTxHash, execution: executePromise };
}

/**
 * Close: `/perps/position/close/build` -> sign order -> `/perps/position/close/execute` (order) ->
 * server polls settle -> sign `withdraw.permitData` -> `/perps/position/close/execute` (sendToEvmWithData).
 */
export async function executePerpsClosePosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildClosePositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<ApiPerpsClosePositionResult> {
  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);

  if (address.toLowerCase() !== request.address.toLowerCase()) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const account = await fetchStoredChainAccount(accountId, PERPS_CCTP_DEPOSIT_CHAIN);

  if (account.type === 'ledger' || account.type === 'view') {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const privateKey = await fetchPrivateKeyString(PERPS_CCTP_DEPOSIT_CHAIN, accountId, enclaveToken, account);

  if (!privateKey) {
    return { error: ApiCommonError.InvalidPassword };
  }

  const build = await perpsBuildClosePosition(request);
  if (build.address?.toLowerCase() !== address.toLowerCase()) throw new Error('PerpsReviewChanged');
  hooks.validateBuild?.(build);

  if (!build.action || build.action.type !== 'order' || !Array.isArray(build.action.orders)
    || typeof build.action.grouping !== 'string' || build.nonce === undefined || !build.hash || !build.typedData) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
  const closeBuild = build;

  const { network } = parseAccountId(accountId);
  const closeSignature = await signHyperliquidExchangeBuild(network, privateKey, closeBuild);
  hooks.onSubmitting?.();
  const closePhase = await perpsExecuteClosePosition(
    buildPerpsCloseOrderExecuteRequest(request.chain, closeBuild, request, closeSignature),
    { timeout: PERPS_CLOSE_EXECUTE_TIMEOUT_MS },
  );

  if (closePhase.close) hooks.onTrade?.(closePhase.close);
  if (!isPerpsCloseOrderSuccess(closePhase.close)) {
    return { error: closePhase.close?.status.startsWith('error:')
      ? closePhase.close.status : ApiTransactionError.UnsuccesfulTransfer };
  }
  if (closePhase.phase !== 'awaiting_withdraw_signature' || !closePhase.withdraw) {
    return { phase: 'withdraw_unavailable', close: closePhase.close };
  }

  hooks.onWithdrawal?.(closePhase.withdraw.amountUsdc);
  const withdrawPhase = await submitPerpsCloseWithdrawExecute(
    accountId,
    privateKey,
    request.chain,
    address,
    closePhase.withdraw,
  );

  if (withdrawPhase.phase !== 'completed' || !withdrawPhase.withdrawResult) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  return {
    phase: 'completed',
    close: closePhase.close,
    withdrawResult: withdrawPhase.withdrawResult,
  };
}

async function unlockPerpsTradingKey(
  accountId: string,
  enclaveToken: string,
): Promise<{ privateKey: string } | { error: string }> {
  const account = await fetchStoredChainAccount(accountId, PERPS_CCTP_DEPOSIT_CHAIN);
  if (account.type === 'ledger' || account.type === 'view') {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
  const privateKey = await fetchPrivateKeyString(PERPS_CCTP_DEPOSIT_CHAIN, accountId, enclaveToken, account);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };
  return { privateKey };
}

/**
 * Credit the HyperCore balance from the wallet. No position.
 * `/perps/deposit/build` → sign → start `/perps/position/execute`, then submit the Arbitrum burn
 * without awaiting it. `completion` settles after the burn and the execute wait.
 */
export async function executePerpsDepositMargin(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildDepositRequest,
): Promise<{ error: string } | { submitted: true; completion: Promise<void> }> {
  const amount = readPositiveUsdc(request.amount);
  if (!amount || !amount.gt(PERPS_CCTP_FORWARD_FEE_USDC)) return { error: 'PerpsAmountTooSmall' };

  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);
  if (address.toLowerCase() !== request.address.toLowerCase()) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const build = await perpsBuildDeposit(request);
  if (!build.deposit
    || build.address?.toLowerCase() !== address.toLowerCase()
    || !perpsAmountsMatch(build.deposit.amountUsdc, request.amount)) {
    throw new Error('PerpsReviewChanged');
  }

  const unlocked = await unlockPerpsTradingKey(accountId, enclaveToken);
  if ('error' in unlocked) return unlocked;
  const { privateKey } = unlocked;
  const { network } = parseAccountId(accountId);
  const spotToPerp = build.spotToPerp
    ? await signHyperliquidExchangePayload(network, privateKey, build.spotToPerp, {
      expectedSpotToPerpAmountUsdc: build.deposit.creditedAmountUsdc,
    })
    : undefined;
  const transfer = await buildPerpsCctpDepositTransferWithPrivateKey(accountId, build.deposit, privateKey);
  if ('error' in transfer) return transfer;

  const executeRequest = buildPerpsDepositExecuteRequest(request.chain, build, { spotToPerp });
  const executePromise = perpsExecutePosition(executeRequest);
  // Execute can reject while the burn is still being sent.
  void executePromise.catch(() => undefined);

  const completion = (async () => {
    let depositTxHash: string | undefined;
    try {
      const depositResult = await submitPerpsCctpDepositTransfer({
        accountId,
        enclaveToken,
        deposit: build.deposit,
        calls: transfer.calls,
        privateKey,
      });
      if ('error' in depositResult) {
        void executePromise.catch(() => undefined);
        onUpdate?.({
          type: 'perpsExecuteFailed',
          accountId,
          flow: 'deposit',
          ...(depositTxHash !== undefined ? { depositTxHash } : undefined),
          error: depositResult.error,
        });
        return;
      }

      depositTxHash = depositResult.txHash;
      onUpdate?.({
        type: 'perpsDepositSubmitted',
        accountId,
        flow: 'deposit',
        depositTxHash,
      });

      const result = await executePromise;

      if (!isPerpsExecuteSuccess(result)) {
        onUpdate?.({
          type: 'perpsExecuteFailed',
          accountId,
          flow: 'deposit',
          depositTxHash,
          error: result.status,
        });
        return;
      }

      onUpdate?.({
        type: 'perpsExecuteComplete',
        accountId,
        flow: 'deposit',
        depositTxHash,
        result,
      });
    } catch (err) {
      logDebugError('perpsDepositMargin', err);

      onUpdate?.({
        type: 'perpsExecuteFailed',
        accountId,
        flow: 'deposit',
        ...(depositTxHash !== undefined ? { depositTxHash } : undefined),
        error: err instanceof Error ? err.message : String(err),
      });
    }
  })();

  void completion.catch((err) => {
    logDebugError('perpsDepositMargin', err);
  });

  return { submitted: true, completion };
}

/**
 * Send USDC from the HyperCore balance to the account wallet. No position.
 * `/perps/withdraw/build` → sign `sendToEvmWithData` → `/perps/position/execute`.
 */
export async function executePerpsWithdrawMargin(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildBalanceWithdrawRequest,
): Promise<ApiPerpsExecutePositionResult | { error: string }> {
  const amount = readPositiveUsdc(request.amount);
  if (!amount || !amount.gt(PERPS_CCTP_FORWARD_FEE_USDC)) return { error: 'PerpsAmountTooSmall' };

  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);
  if (address.toLowerCase() !== request.address.toLowerCase()) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const build = await perpsBuildBalanceWithdraw(request);
  const recipient = build.action.destinationRecipient;
  if (
    build.address?.toLowerCase() !== address.toLowerCase()
    || build.action.type !== 'sendToEvmWithData'
    || typeof build.action.amount !== 'string'
    || !perpsAmountsMatch(build.action.amount, request.amount)
    || typeof recipient !== 'string'
    || recipient.toLowerCase() !== address.toLowerCase()
  ) {
    throw new Error('PerpsReviewChanged');
  }

  const unlocked = await unlockPerpsTradingKey(accountId, enclaveToken);
  if ('error' in unlocked) return unlocked;
  const { network } = parseAccountId(accountId);
  const signature = await signHyperliquidExchangeBuild(network, unlocked.privateKey, build, {
    expectedWalletRecipient: address,
  });
  return perpsExecutePosition(buildPerpsBalanceWithdrawExecuteRequest(request.chain, build, signature));
}

async function signPerpsOpenFromBalancePayloads(
  accountId: string,
  privateKey: string,
  build: ApiPerpsOpenPositionResult,
) {
  const { network } = parseAccountId(accountId);
  const [signature, approveBuilderFee, updateLeverage] = await Promise.all([
    signHyperliquidExchangeBuild(network, privateKey, build),
    build.approveBuilderFee
      ? signHyperliquidExchangePayload(network, privateKey, build.approveBuilderFee)
      : undefined,
    signHyperliquidExchangePayload(network, privateKey, build.updateLeverage),
  ]);
  return { signature, approveBuilderFee, updateLeverage };
}

/**
 * Open a position from the free perps balance. No wallet deposit.
 * `/perps/position/open` → sign leverage and the order → `/perps/position/execute`.
 */
export async function executePerpsOpenFromBalance(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsOpenPositionRequest,
): Promise<ApiPerpsExecutePositionResult | { error: string }> {
  if (!readPositiveUsdc(request.amount) || !Number.isInteger(request.leverage) || request.leverage < 1) {
    return { error: 'PerpsInvalidAmount' };
  }

  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);
  if (address.toLowerCase() !== request.address.toLowerCase()) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const build = await perpsBuildOpenPosition(request);
  if (build.address?.toLowerCase() !== address.toLowerCase()) throw new Error('PerpsReviewChanged');
  assertPerpsOpenFromBalanceBuild(request, build);

  const unlocked = await unlockPerpsTradingKey(accountId, enclaveToken);
  if ('error' in unlocked) return unlocked;
  const signed = await signPerpsOpenFromBalancePayloads(accountId, unlocked.privateKey, build);
  return perpsExecutePosition(buildPerpsOpenFromBalanceExecuteRequest(request.chain, build, signed));
}

/** Withdraw released collateral without placing another close order. */
export async function perpsWithdrawReleasedMargin(
  accountId: string,
  enclaveToken: string,
  withdraw: ApiPerpsWithdrawPermit,
  onSubmitting?: NoneToVoidFunction,
): Promise<ApiPerpsExecuteClosePositionResult> {
  const { address } = await fetchEvmWallet(accountId, PERPS_CCTP_DEPOSIT_CHAIN);
  const account = await fetchStoredChainAccount(accountId, PERPS_CCTP_DEPOSIT_CHAIN);
  if (account.type === 'ledger' || account.type === 'view') throw new Error('PerpsUnsupportedAccount');
  const privateKey = await fetchPrivateKeyString(PERPS_CCTP_DEPOSIT_CHAIN, accountId, enclaveToken, account);
  if (!privateKey) throw new Error(ApiCommonError.InvalidPassword);
  return submitPerpsCloseWithdrawExecute(accountId, privateKey, 'hyperliquid', address, withdraw, onSubmitting);
}
