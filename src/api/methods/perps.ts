import type { LangCode } from '../../global/types';
import type { HyperliquidExchangeSignOptions } from '../chains/evm/hyperliquidPayloadValidation';
import type { PerpsSigner } from '../chains/evm/perps';
import type { EvmMetaTransaction } from '../chains/evm/smartAccount/types';
import type {
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
  ApiPerpsEstimateModifyPositionRequest,
  ApiPerpsEstimateModifyPositionResult,
  ApiPerpsEstimatePositionRequest,
  ApiPerpsEstimatePositionResult,
  ApiPerpsExchangeActionPayload,
  ApiPerpsExchangeBuild,
  ApiPerpsExchangeSignature,
  ApiPerpsExecuteClosePositionRequest,
  ApiPerpsExecuteClosePositionResult,
  ApiPerpsExecutePositionRequest,
  ApiPerpsExecutePositionResult,
  ApiPerpsFundingSource,
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
  ApiPerpsSignedExchangeAction,
  ApiPerpsTradingAvailability,
  ApiPerpsWithdrawPermit,
  OnApiUpdate,
} from '../types';
import { ApiCommonError, ApiTransactionError, EvmSmartAccountError } from '../types';

import { Big } from '../../lib/big.js';
import { parseAccountId } from '../../util/account';
import { omitUndefined } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { chains } from '../chains';
import {
  buildPerpsCctpDepositTransfer,
  estimatePerpsCctpDepositGasUsdc,
  signHyperliquidExchangeBuild,
  signHyperliquidExchangePayload,
  signHyperliquidWithdrawPermit,
  submitPerpsCctpDepositTransfer,
} from '../chains/evm/perps';
import { fetchStoredChainAccount } from '../common/accounts';
import { callBackendPost } from '../common/backend';
import {
  isPerpsVenueRejection,
  isPerpsWalletAddress,
  PERPS_BUILD_REQUEST_TIMEOUT_MS,
  PERPS_CCTP_DEPOSIT_CHAIN,
  PERPS_CCTP_FORWARD_FEE_USDC,
  PERPS_CLOSE_EXECUTE_TIMEOUT_MS,
  PERPS_EXECUTE_DEPOSIT_WAIT_TIMEOUT_MS,
  PERPS_GASLESS_GAS_FALLBACK_USDC,
  PERPS_REVIEW_PRICE_TOLERANCE,
} from '../common/perps';
import { getPerpsAssets, refreshPerpsAssets } from '../common/perpsAssets';
import { readPerpsMarketOrder, readPositiveDecimal } from '../common/perpsPresentation';

let onUpdate: OnApiUpdate | undefined;

export function initPerps(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

/** Pimlico paymaster reserve for a gasless CCTP deposit of the given gross USDC amount. */
export async function estimatePerpsDepositFundingGasUsdc(
  accountId: string,
  address: string,
  paymentUsdc: string,
): Promise<string> {
  if (!readPositiveDecimal(paymentUsdc)) {
    return '0';
  }

  try {
    const build = await perpsBuildDeposit({
      chain: 'hyperliquid',
      address,
      amount: paymentUsdc,
    });

    if (!build.deposit || build.address?.toLowerCase() !== address.toLowerCase()) {
      return PERPS_GASLESS_GAS_FALLBACK_USDC;
    }

    const estimate = await estimatePerpsCctpDepositGasUsdc(accountId, address, build.deposit);

    if ('error' in estimate) {
      if (estimate.error === EvmSmartAccountError.UserOperationMismatch) {
        throw new Error(estimate.error);
      }

      return PERPS_GASLESS_GAS_FALLBACK_USDC;
    }

    return estimate.gasUsdc;
  } catch (err) {
    if (err instanceof Error && err.message as EvmSmartAccountError === EvmSmartAccountError.UserOperationMismatch) {
      throw err;
    }

    return PERPS_GASLESS_GAS_FALLBACK_USDC;
  }
}

function isPerpsExecuteSuccess(result: ApiPerpsExecutePositionResult): boolean {
  return !result.status.startsWith('error');
}

export type PerpsExecutionHooks = {
  validateBuild?: (build: Partial<ApiPerpsExchangeBuild> & {
    deposit?: ApiPerpsCctpDeposit;
    spotToPerp?: ApiPerpsExchangeActionPayload;
    setAbstraction?: ApiPerpsExchangeActionPayload;
    updateLeverage?: ApiPerpsExchangeActionPayload;
    updateIsolatedMargin?: ApiPerpsExchangeActionPayload;
  }) => void;
  onSubmitting?: () => void;
  onDeposit?: (hash: string) => void;
  onTrade?: (result: ApiPerpsExecutePositionResult) => void;
  onWithdrawal?: (amount: string) => void;
  /** The venue refused the withdrawal of a filled order. Its proceeds stay on the HyperCore balance. */
  onWithdrawalRejected?: (reason: string) => void;
};

function isPerpsCloseOrderSuccess(
  close?: ApiPerpsExecutePositionResult,
): close is ApiPerpsExecutePositionResult & { status: 'filled' } {
  return close?.status === 'filled';
}

function perpsAmountsMatch(left: number | string, right: number | string): boolean {
  try {
    return Big(left).eq(right);
  } catch {
    return false;
  }
}

type PerpsWallet = {
  address: string;
  /** Account signing support, independent of balances and market availability. */
  tradingAvailability: ApiPerpsTradingAvailability;
  /** Reads the signing key with the user's enclave token. */
  unlock: (enclaveToken: string) => Promise<PerpsSigner | { error: string }>;
};

/** The account's Arbitrum wallet, which signs for Hyperliquid, and whether it may trade. */
export async function getPerpsWallet(accountId: string, forTrading = false): Promise<PerpsWallet> {
  const { network } = parseAccountId(accountId);
  if (network !== 'mainnet') throw new Error('PerpsUnsupportedAccount');
  const account = await fetchStoredChainAccount(accountId, PERPS_CCTP_DEPOSIT_CHAIN);
  const tradingAvailability: ApiPerpsTradingAvailability = account.type === 'view' || account.type === 'ledger'
    ? { isAvailable: false, reason: 'PerpsUnsupportedAccount' } : { isAvailable: true };
  if (forTrading && !tradingAvailability.isAvailable) throw new Error(tradingAvailability.reason);
  const { address } = account.byChain[PERPS_CCTP_DEPOSIT_CHAIN];

  return {
    address,
    tradingAvailability,
    unlock: async (enclaveToken) => {
      const privateKey = await chains[PERPS_CCTP_DEPOSIT_CHAIN].fetchPrivateKeyString(accountId, enclaveToken);
      return privateKey ? { network, address, privateKey } : { error: ApiCommonError.InvalidPassword };
    },
  };
}

/**
 * The wallet of one trading flow, resolved before any build request. View-only and Ledger accounts cannot sign, and a
 * request for another wallet is refused.
 */
async function resolvePerpsWallet(
  accountId: string,
  requestAddress?: string,
): Promise<PerpsWallet | { error: string }> {
  const wallet = await getPerpsWallet(accountId);

  return !wallet.tradingAvailability.isAvailable
    || (requestAddress !== undefined && !isPerpsWalletAddress(requestAddress, wallet.address))
    ? { error: ApiTransactionError.UnsuccesfulTransfer }
    : wallet;
}

function assertPerpsBuildWallet(build: { address?: string }, walletAddress: string) {
  if (!isPerpsWalletAddress(build.address, walletAddress)) throw new Error('PerpsReviewChanged');
}

type PerpsSidePayload = 'approveBuilderFee' | 'spotToPerp' | 'setAbstraction'
  | 'updateLeverage' | 'updateIsolatedMargin';

/** Validation goes by the action's own type, so a payload in another's slot would pass it and skip what reviews that slot. */
const PERPS_SIDE_PAYLOAD_ACTION_TYPES: Record<PerpsSidePayload, string> = {
  approveBuilderFee: 'approveBuilderFee',
  spotToPerp: 'usdClassTransfer',
  setAbstraction: 'userSetAbstraction',
  updateLeverage: 'updateLeverage',
  updateIsolatedMargin: 'updateIsolatedMargin',
};

type PerpsSignedBuild = Partial<Record<PerpsSidePayload, ApiPerpsSignedExchangeAction>> & {
  /** Signature of the build's own action. */
  signature?: ApiPerpsExchangeSignature;
};

/**
 * Signs the build's own action when `action` is set, and the listed side payloads: `true` requires the payload,
 * `false` signs it when the build carries it. Every payload must carry its slot's action type, and is validated
 * before it is signed.
 */
async function signPerpsBuild(
  signer: PerpsSigner,
  build: Partial<ApiPerpsExchangeBuild> & Partial<Record<PerpsSidePayload, ApiPerpsExchangeActionPayload>>,
  { action, payloads, options }: {
    action: boolean;
    payloads: Partial<Record<PerpsSidePayload, boolean>>;
    options?: HyperliquidExchangeSignOptions;
  },
): Promise<PerpsSignedBuild> {
  const names = Object.keys(payloads) as PerpsSidePayload[];
  if (
    (action && (build.action === undefined || build.nonce === undefined
      || build.hash === undefined || build.typedData === undefined))
    || names.some((name) => payloads[name] && !build[name])
  ) {
    throw new Error('Invalid build: missing exchange fields');
  }
  if (
    (action && build.action?.type !== 'order')
    || names.some((name) => build[name] && build[name].action.type !== PERPS_SIDE_PAYLOAD_ACTION_TYPES[name])
  ) {
    throw new Error('Invalid build: exchange action of the wrong type');
  }

  const [signature, signedPayloads] = await Promise.all([
    action ? signHyperliquidExchangeBuild(signer, build as ApiPerpsExchangeBuild, options) : undefined,
    Promise.all(names.map((name) => {
      const payload = build[name];
      return payload ? signHyperliquidExchangePayload(signer, payload, options) : Promise.resolve(undefined);
    })),
  ]);
  const signed: PerpsSignedBuild = { signature };
  names.forEach((name, index) => {
    signed[name] = signedPayloads[index];
  });
  return signed;
}

/**
 * `/perps/position/execute` body: the build's signed action, its signed side payloads, its bridged deposit and the
 * funding source of an order paid from the balance.
 */
function buildPerpsExecuteRequest(
  chain: ApiPerpsChain,
  build: { address: string; action?: Record<string, unknown>; nonce?: number; deposit?: ApiPerpsCctpDeposit },
  { signature, ...payloads }: PerpsSignedBuild,
  fundingSource?: ApiPerpsFundingSource,
): ApiPerpsExecutePositionRequest {
  return omitUndefined({
    chain,
    address: build.address,
    ...(signature && { action: build.action, nonce: build.nonce, signature }),
    ...payloads,
    depositAmount: build.deposit?.amountUsdc,
    fundingSource,
  });
}

/**
 * `/perps/position/open` market order for the requested side and leverage, with the leverage change of the same asset
 * and nothing bridged. Returns the order's size and limit price.
 */
function assertPerpsOpenFromBalanceBuild(
  request: ApiPerpsOpenPositionRequest,
  build: ApiPerpsOpenPositionResult,
) {
  if ('deposit' in build || 'spotToPerp' in build || 'setAbstraction' in build) throw new Error('PerpsReviewChanged');
  const { order, size, price } = readPerpsMarketOrder(build.action, request.side === 'long', false);
  const leverage = build.updateLeverage.action;
  if (
    build.action.type !== 'order'
    || build.action.grouping !== 'na'
    || leverage.type !== 'updateLeverage'
    || leverage.leverage !== request.leverage
    || leverage.isCross !== request.isCross
    || leverage.asset !== order.a
  ) {
    throw new Error('PerpsReviewChanged');
  }
  return { size, price };
}

/**
 * The order size of an unreviewed open from the balance must match the requested margin. Without the backend's
 * captured mid, the order's own limit price bounds the margin it implies.
 */
function assertPerpsOpenFromBalanceMargin(
  request: ApiPerpsOpenPositionRequest,
  build: ApiPerpsOpenPositionResult,
  { size, price }: { size: Big; price: Big },
) {
  const requested = readPositiveDecimal(String(request.amount));
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
  const implied = size.mul(price).div(request.leverage);
  if (implied.minus(requested).abs().gt(requested.mul(slippage).plus(1))) throw new Error('PerpsReviewChanged');
}

export function perpsGetPositions(request: ApiPerpsGetPositionsRequest): Promise<ApiPerpsGetPositionsResult> {
  return callBackendPost('/perps/positions', request);
}

export function perpsGetActivities(request: ApiPerpsGetActivitiesRequest): Promise<ApiPerpsGetActivitiesResult> {
  return callBackendPost('/perps/activities', request);
}

/**
 * Catalogue from the cache. `force` is the explicit refresh; polling in the iOS app also replaces the cache.
 * A language the cache was not stored for is fetched before it is returned.
 */
export function perpsGetAssets(langCode?: LangCode, options?: { force?: boolean }): Promise<ApiPerpsGetAssetsResult> {
  return options?.force ? refreshPerpsAssets(langCode) : getPerpsAssets(langCode);
}

export function perpsGetAsset(request: ApiPerpsGetAssetRequest): Promise<ApiPerpsAssetDetail> {
  return callBackendPost('/perps/asset', request);
}

/** Close series for one catalogue asset. Points are `[seconds, price]`, oldest first. */
export function perpsGetAssetChart(request: ApiPerpsGetAssetChartRequest): Promise<ApiHistoryList> {
  return callBackendPost('/perps/asset/chart', request);
}

/** An estimate, or the backend's refusal: a validation `errors` list or a single `error`. */
async function callPerpsEstimate<T extends object>(path: string, request: object): Promise<T | { error: string }> {
  const answer = await callBackendPost<T | { error: string } | { errors: { msg: string }[] }>(
    path,
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

export function perpsEstimatePosition(
  request: ApiPerpsEstimatePositionRequest,
): Promise<ApiPerpsEstimatePositionResult | { error: string }> {
  return callPerpsEstimate('/perps/position/estimate', request);
}

export function perpsEstimateModifyPosition(
  request: ApiPerpsEstimateModifyPositionRequest,
): Promise<ApiPerpsEstimateModifyPositionResult | { error: string }> {
  return callPerpsEstimate('/perps/position/modify/estimate', request);
}

function perpsBuildPosition(request: ApiPerpsBuildPositionRequest): Promise<ApiPerpsBuildPositionResult> {
  return callBackendPost('/perps/position/build', {
    ...request, slippage: request.slippage ?? Number(PERPS_REVIEW_PRICE_TOLERANCE),
  }, {
    timeout: PERPS_BUILD_REQUEST_TIMEOUT_MS,
  });
}

/**
 * Re-reads `/perps/position/modify/estimate` before a leverage change is built. What the change needs moves with the
 * price, so it pays the reviewed amount as long as that covers the need: a wallet-funded change as `depositAmount`,
 * a balance-funded one as `marginAmount`.
 */
async function resolveLeverageChange(
  request: ApiPerpsBuildModifyPositionRequest,
  leverage: number,
  reviewedMarginAmount?: string,
): Promise<{ request: ApiPerpsBuildModifyPositionRequest } | { error: string }> {
  const fromBalance = request.fundingSource === 'balance';
  const estimate = await perpsEstimateModifyPosition({
    chain: request.chain,
    address: request.address,
    asset: request.asset,
    leverage,
    ...(fromBalance ? { fundingSource: 'balance' as const } : undefined),
  });

  if ('error' in estimate || typeof estimate.depositAmount !== 'string') {
    return { error: 'error' in estimate ? estimate.error : 'Estimate failed.' };
  }

  if (fromBalance) {
    const isCovered = estimate.marginAmount !== undefined && reviewedMarginAmount !== undefined
      && isPerpsLeverageChangeCovered(reviewedMarginAmount, estimate.marginAmount);
    return isCovered
      ? { request: { ...request, depositAmount: undefined, marginAmount: reviewedMarginAmount } }
      : { error: 'PerpsQuoteExpired' };
  }

  const confirmed = request.depositAmount;
  if (confirmed === undefined || String(confirmed) === '') {
    return { request: { ...request, depositAmount: estimate.depositAmount } };
  }
  return isPerpsLeverageChangeCovered(confirmed, estimate.depositAmount) ? { request } : { error: 'PerpsQuoteExpired' };
}

/** A change that stopped needing margin builds without a top-up, which is not what was reviewed. */
function isPerpsLeverageChangeCovered(reviewed: number | string, needed: string): boolean {
  try {
    return Big(needed).eq(0) ? Big(reviewed).eq(0) : Big(reviewed).gte(needed);
  } catch {
    return false;
  }
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

/** `/perps/withdraw/build`, refused unless it withdraws the requested amount for the account's wallet. */
export async function perpsBuildBalanceWithdraw(
  request: ApiPerpsBuildBalanceWithdrawRequest,
  walletAddress: string,
): Promise<ApiPerpsBuildBalanceWithdrawResult> {
  const build = await callBackendPost<ApiPerpsBuildBalanceWithdrawResult>('/perps/withdraw/build', request);
  assertPerpsBuildWallet(build, walletAddress);
  // Signing accepts any supported action and checks the recipient; this flow only signs its withdrawal.
  if (build.action.type !== 'sendToEvmWithData' || typeof build.action.amount !== 'string'
    || !perpsAmountsMatch(build.action.amount, request.amount)) {
    throw new Error('PerpsReviewChanged');
  }
  return build;
}

function perpsBuildOpenPosition(request: ApiPerpsOpenPositionRequest): Promise<ApiPerpsOpenPositionResult> {
  return callBackendPost('/perps/position/open', {
    ...request,
    slippage: request.slippage ?? Number(PERPS_REVIEW_PRICE_TOLERANCE),
  }, {
    timeout: PERPS_BUILD_REQUEST_TIMEOUT_MS,
  });
}

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

/**
 * Starts `/perps/position/execute` (CCTP wait + Hyperliquid actions) before the deposit is broadcast, so the backend
 * takes its balance baseline before the funds land, then submits the CCTP burn and waits for the execution.
 */
async function executeWithPerpsDeposit(
  signer: PerpsSigner,
  executeRequest: ApiPerpsExecutePositionRequest,
  calls: EvmMetaTransaction[],
  hooks: Pick<PerpsExecutionHooks, 'onSubmitting' | 'onDeposit' | 'onTrade'>,
): Promise<(ApiPerpsExecutePositionResult & { depositTxHash: string }) | { error: string }> {
  hooks.onSubmitting?.();
  const execution = perpsExecutePosition(executeRequest);
  // Execution can reject while the deposit is still awaiting submission; it is awaited below.
  void execution.catch(() => undefined);

  const deposited = await submitPerpsCctpDepositTransfer(signer, calls);
  if ('error' in deposited) return deposited;
  hooks.onDeposit?.(deposited.txHash);

  const result = await execution.catch((err: unknown) => {
    logDebugError('perpsExecutePosition', err);
    throw err;
  });
  hooks.onTrade?.(result);
  return { ...result, depositTxHash: deposited.txHash };
}

/** Signs a withdrawal of released margin to the signer's wallet and submits it on `/perps/position/close/execute`. */
async function submitPerpsWithdrawal(
  signer: PerpsSigner,
  chain: ApiPerpsChain,
  withdraw: ApiPerpsWithdrawPermit,
  onSubmitting?: NoneToVoidFunction,
): Promise<ApiPerpsExecuteClosePositionResult> {
  const signature = await signHyperliquidWithdrawPermit(signer, withdraw);
  onSubmitting?.();
  return perpsExecuteClosePosition({
    chain,
    address: signer.address,
    action: withdraw.action,
    nonce: withdraw.nonce,
    signature,
  });
}

/**
 * Submits a signed close or reduce order on `/perps/position/close/execute`, then signs and submits the withdrawal
 * of the released margin when the backend offers one.
 */
async function executePerpsCloseOrder(
  signer: PerpsSigner,
  request: ApiPerpsExecuteClosePositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<{ close: ApiPerpsExecutePositionResult } | { error: string }> {
  hooks.onSubmitting?.();
  const closePhase = await perpsExecuteClosePosition(request, { timeout: PERPS_CLOSE_EXECUTE_TIMEOUT_MS });

  if (closePhase.close) hooks.onTrade?.(closePhase.close);
  if (!isPerpsCloseOrderSuccess(closePhase.close)) {
    return { error: closePhase.close?.status.startsWith('error:')
      ? closePhase.close.status : ApiTransactionError.UnsuccesfulTransfer };
  }
  if (closePhase.phase !== 'awaiting_withdraw_signature' || !closePhase.withdraw) {
    return { close: closePhase.close };
  }

  hooks.onWithdrawal?.(closePhase.withdraw.amountUsdc);
  let withdrawPhase: ApiPerpsExecuteClosePositionResult;
  try {
    withdrawPhase = await submitPerpsWithdrawal(signer, request.chain, closePhase.withdraw);
  } catch (err) {
    if (!isPerpsVenueRejection(err)) throw err;
    hooks.onWithdrawalRejected?.((err as Error).message);
    return { close: closePhase.close };
  }

  if (withdrawPhase.withdrawResult?.status.startsWith('error')) {
    hooks.onWithdrawalRejected?.(withdrawPhase.withdrawResult.status);
  } else if (withdrawPhase.phase !== 'completed' || !withdrawPhase.withdrawResult) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  return { close: closePhase.close };
}

/** Internal reviewed-order path; do not expose callbacks through the API dispatch table. */
export async function executePerpsOpenPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<(ApiPerpsExecutePositionResult & { depositTxHash: string }) | { error: string }> {
  const wallet = await resolvePerpsWallet(accountId, request.address);
  if ('error' in wallet) return wallet;

  const build = await perpsBuildPosition(request);
  assertPerpsBuildWallet(build, wallet.address);
  hooks.validateBuild?.(build);

  const signer = await wallet.unlock(enclaveToken);
  if ('error' in signer) return signer;

  const signed = await signPerpsBuild(signer, build, {
    action: true,
    payloads: { approveBuilderFee: false, spotToPerp: false, setAbstraction: false, updateLeverage: true },
    options: { expectedSpotToPerpAmountUsdc: build.deposit.creditedAmountUsdc, expectedAccount: signer.address },
  });
  const transfer = await buildPerpsCctpDepositTransfer(signer, build.deposit);
  if ('error' in transfer) return transfer;

  return executeWithPerpsDeposit(signer, buildPerpsExecuteRequest(request.chain, build, signed), transfer.calls, hooks);
}

/**
 * Modify: build → sign → `/perps/position/execute`, waiting for the trade (and any withdrawal).
 * A leverage change re-reads `/perps/position/modify/estimate` and builds with that deposit.
 * Increase size and a positive leverage deposit start execute before the CCTP transfer, same as open.
 * A leverage increase estimates `"0"` and signs `updateLeverage` only.
 * With `fundingSource: 'balance'` nothing is bridged: an increase signs its order, and a leverage change signs
 * `updateLeverage` with any `updateIsolatedMargin`, after the estimate confirms `reviewedMarginAmount`.
 * Reduce-only uses `/perps/position/close/execute`.
 */
export async function executePerpsModifyPosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildModifyPositionRequest,
  hooks: PerpsExecutionHooks,
  reviewedMarginAmount?: string,
): Promise<ApiPerpsModifyPositionResult> {
  const wallet = await resolvePerpsWallet(accountId, request.address);
  if ('error' in wallet) return wallet;

  let buildRequest = request;
  if (!request.reduceOnly && request.leverage !== undefined) {
    const resolved = await resolveLeverageChange(request, request.leverage, reviewedMarginAmount);
    if ('error' in resolved) return resolved;
    buildRequest = resolved.request;
  }

  const build = await perpsBuildModifyPosition(buildRequest);
  assertPerpsBuildWallet(build, wallet.address);
  const { fundingSource } = request;
  // A change paid from the balance never signs or submits a bridge transfer, whatever the build carries.
  if (fundingSource === 'balance' && (build.deposit || build.spotToPerp)) throw new Error('PerpsReviewChanged');
  hooks.validateBuild?.(build);

  const signer = await wallet.unlock(enclaveToken);
  if ('error' in signer) return signer;

  const isLeverageChange = Boolean(build.updateLeverage) && build.action === undefined;
  const signed = await signPerpsBuild(signer, build, {
    action: !isLeverageChange,
    payloads: isLeverageChange
      ? { updateLeverage: true, updateIsolatedMargin: false, spotToPerp: false, approveBuilderFee: false }
      : { approveBuilderFee: false, spotToPerp: false },
    options: build.deposit ? { expectedSpotToPerpAmountUsdc: build.deposit.creditedAmountUsdc } : undefined,
  });

  if (request.reduceOnly) {
    if (build.action === undefined || build.nonce === undefined || !signed.signature) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const result = await executePerpsCloseOrder(signer, {
      chain: request.chain,
      address: build.address,
      asset: request.asset,
      action: build.action,
      nonce: build.nonce,
      signature: signed.signature,
      destination: request.address,
      skipPositionFlatWait: true,
      approveBuilderFee: signed.approveBuilderFee,
    }, hooks);
    if ('error' in result) return result;
    return result.close;
  }

  const executeRequest = buildPerpsExecuteRequest(request.chain, build, signed, fundingSource);
  if (!build.deposit) {
    hooks.onSubmitting?.();
    return perpsExecutePosition(executeRequest);
  }

  const transfer = await buildPerpsCctpDepositTransfer(signer, build.deposit);
  if ('error' in transfer) return transfer;

  return executeWithPerpsDeposit(signer, executeRequest, transfer.calls, hooks);
}

/**
 * Close: `/perps/position/close/build` -> sign order -> `/perps/position/close/execute` (order) ->
 * server polls settle -> sign `withdraw.permitData` -> `/perps/position/close/execute` (sendToEvmWithData).
 * Returns the failure of a close that did not go through; progress reaches the caller through `hooks`.
 */
export async function executePerpsClosePosition(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsBuildClosePositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<{ error: string } | undefined> {
  const wallet = await resolvePerpsWallet(accountId, request.address);
  if ('error' in wallet) return wallet;
  const signer = await wallet.unlock(enclaveToken);
  if ('error' in signer) return signer;

  const build = await perpsBuildClosePosition(request);
  assertPerpsBuildWallet(build, signer.address);
  hooks.validateBuild?.(build);

  if (!build.action || build.action.type !== 'order' || !Array.isArray(build.action.orders)
    || typeof build.action.grouping !== 'string' || build.nonce === undefined || !build.hash || !build.typedData) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const signed = await signPerpsBuild(signer, build, { action: true, payloads: { approveBuilderFee: false } });
  const result = await executePerpsCloseOrder(signer, {
    chain: request.chain,
    address: build.address,
    asset: request.asset,
    action: build.action,
    nonce: build.nonce,
    signature: signed.signature!,
    destination: request.address,
    approveBuilderFee: signed.approveBuilderFee,
  }, hooks);

  return 'error' in result ? result : undefined;
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
  const amount = readPositiveDecimal(String(request.amount));
  if (!amount || !amount.gt(PERPS_CCTP_FORWARD_FEE_USDC)) return { error: 'PerpsAmountTooSmall' };

  const wallet = await resolvePerpsWallet(accountId, request.address);
  if ('error' in wallet) return wallet;

  const build = await perpsBuildDeposit(request);
  assertPerpsBuildWallet(build, wallet.address);
  if (!build.deposit || !perpsAmountsMatch(build.deposit.amountUsdc, request.amount)) {
    throw new Error('PerpsReviewChanged');
  }

  const signer = await wallet.unlock(enclaveToken);
  if ('error' in signer) return signer;
  const signed = await signPerpsBuild(signer, build, {
    action: false,
    payloads: { spotToPerp: false },
    options: { expectedSpotToPerpAmountUsdc: build.deposit.creditedAmountUsdc },
  });
  const transfer = await buildPerpsCctpDepositTransfer(signer, build.deposit);
  if ('error' in transfer) return transfer;

  const executeRequest = buildPerpsExecuteRequest(request.chain, build, signed);
  const completion = (async () => {
    let depositTxHash: string | undefined;
    const fail = (error: string) => onUpdate?.({
      type: 'perpsExecuteFailed',
      accountId,
      flow: 'deposit',
      ...(depositTxHash !== undefined ? { depositTxHash } : undefined),
      error,
    });

    try {
      const outcome = await executeWithPerpsDeposit(signer, executeRequest, transfer.calls, {
        onDeposit: (hash) => {
          depositTxHash = hash;
          onUpdate?.({ type: 'perpsDepositSubmitted', accountId, flow: 'deposit', depositTxHash: hash });
        },
      });
      if ('error' in outcome) {
        fail(outcome.error);
        return;
      }

      const { depositTxHash: hash, ...result } = outcome;
      if (!isPerpsExecuteSuccess(result)) {
        fail(result.status);
        return;
      }

      onUpdate?.({ type: 'perpsExecuteComplete', accountId, flow: 'deposit', depositTxHash: hash, result });
    } catch (err) {
      logDebugError('perpsDepositMargin', err);
      fail(err instanceof Error ? err.message : String(err));
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
  hooks: Pick<PerpsExecutionHooks, 'validateBuild' | 'onSubmitting'> = {},
): Promise<ApiPerpsExecutePositionResult | { error: string }> {
  const amount = readPositiveDecimal(String(request.amount));
  if (!amount || !amount.gt(PERPS_CCTP_FORWARD_FEE_USDC)) return { error: 'PerpsAmountTooSmall' };

  const wallet = await resolvePerpsWallet(accountId, request.address);
  if ('error' in wallet) return wallet;

  const build = await perpsBuildBalanceWithdraw(request, wallet.address);
  hooks.validateBuild?.(build);

  const signer = await wallet.unlock(enclaveToken);
  if ('error' in signer) return signer;
  const signature = await signHyperliquidExchangeBuild(signer, build, { expectedWalletRecipient: signer.address });
  hooks.onSubmitting?.();
  return perpsExecutePosition(buildPerpsExecuteRequest(request.chain, build, { signature }));
}

/**
 * Open a position from the free perps balance without a review. No wallet deposit.
 * `/perps/position/open` → sign leverage and the order → `/perps/position/execute`.
 */
export async function executePerpsOpenFromBalance(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsOpenPositionRequest,
): Promise<ApiPerpsExecutePositionResult | { error: string }> {
  if (!readPositiveDecimal(String(request.amount)) || !Number.isInteger(request.leverage) || request.leverage < 1) {
    return { error: 'PerpsInvalidAmount' };
  }

  const wallet = await resolvePerpsWallet(accountId, request.address);
  if ('error' in wallet) return wallet;

  const executeRequest = await signPerpsOpenFromBalance(wallet, enclaveToken, request);
  if ('error' in executeRequest) return executeRequest;
  return perpsExecutePosition(executeRequest);
}

/**
 * Internal reviewed-order path of an open paid from the HyperCore balance: `/perps/position/open` → sign leverage and
 * the order → `/perps/position/execute` with `fundingSource: 'balance'`. Nothing is bridged.
 */
export async function executePerpsOpenPositionFromBalance(
  accountId: string,
  enclaveToken: string,
  request: ApiPerpsOpenPositionRequest,
  hooks: PerpsExecutionHooks,
): Promise<ApiPerpsExecutePositionResult | { error: string }> {
  const wallet = await resolvePerpsWallet(accountId, request.address);
  if ('error' in wallet) return wallet;

  const executeRequest = await signPerpsOpenFromBalance(wallet, enclaveToken, request, hooks.validateBuild);
  if ('error' in executeRequest) return executeRequest;
  hooks.onSubmitting?.();
  return perpsExecutePosition({ ...executeRequest, fundingSource: 'balance' });
}

/**
 * Builds `/perps/position/open`, checks the build and signs its leverage change and order. A reviewed open checks the
 * order size against its review, which allows the market's lot rounding; otherwise it must match the margin.
 */
async function signPerpsOpenFromBalance(
  wallet: PerpsWallet,
  enclaveToken: string,
  request: ApiPerpsOpenPositionRequest,
  validateBuild?: PerpsExecutionHooks['validateBuild'],
): Promise<ApiPerpsExecutePositionRequest | { error: string }> {
  const build = await perpsBuildOpenPosition(request);
  assertPerpsBuildWallet(build, wallet.address);
  const order = assertPerpsOpenFromBalanceBuild(request, build);
  if (validateBuild) validateBuild(build);
  else assertPerpsOpenFromBalanceMargin(request, build, order);

  const signer = await wallet.unlock(enclaveToken);
  if ('error' in signer) return signer;
  const signed = await signPerpsBuild(signer, build, {
    action: true,
    payloads: { approveBuilderFee: false, updateLeverage: true },
  });
  return buildPerpsExecuteRequest(request.chain, build, signed);
}

/** Withdraw released collateral without placing another close order. */
export async function perpsWithdrawReleasedMargin(
  accountId: string,
  enclaveToken: string,
  withdraw: ApiPerpsWithdrawPermit,
  onSubmitting?: NoneToVoidFunction,
): Promise<ApiPerpsExecuteClosePositionResult> {
  const wallet = await resolvePerpsWallet(accountId);
  if ('error' in wallet) throw new Error('PerpsUnsupportedAccount');
  const signer = await wallet.unlock(enclaveToken);
  if ('error' in signer) throw new Error(signer.error);
  return submitPerpsWithdrawal(signer, 'hyperliquid', withdraw, onSubmitting);
}
