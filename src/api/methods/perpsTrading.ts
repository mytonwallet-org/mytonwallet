import type { LangCode } from '../../global/types';
import type {
  ApiPerpsActivityPageRequest, ApiPerpsBuildWithdrawalRequest, ApiPerpsEstimatePositionRequest,
  ApiPerpsExecutePositionResult, ApiPerpsMarketAsset, ApiPerpsOpenPositionRequest,
  ApiPerpsPositionSide, ApiPerpsTradingAvailability,
  ApiPerpsWithdrawPermit, ApiPriceHistoryPeriod, OnApiUpdate,
} from '../types';
import type {
  ApiPerpsActivityHistory,
  ApiPerpsDraftRequest,
  ApiPerpsFundingRequirements,
  ApiPerpsLeverageEstimate,
  ApiPerpsMarketSnapshot,
  ApiPerpsOperation,
  ApiPerpsQuote,
  ApiPerpsSnapshot,
  ApiPerpsTradeIntent,
} from '../types/perpsTrading';

import { ARBITRUM_USDC_MAINNET } from '../../config';
import { Big } from '../../lib/big.js';
import { parseAccountId } from '../../util/account';
import { getChainConfig } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import withCacheAsync from '../../util/withCacheAsync';
import { chains } from '../chains';
import { assertHyperliquidWithdrawPermitIntegrity } from '../chains/evm/hyperliquidPayloadValidation';
import { fetchStoredChainAccount } from '../common/accounts';
import { getPerpsOrderError, PERPS_CCTP_FORWARD_FEE_USDC } from '../common/perps';
import { normalizePerpsActivityPage } from '../common/perpsActivities';
import { getPerpsAssetsFetchedAt } from '../common/perpsAssets';
import { buildPerpsMarketCatalogue } from '../common/perpsMarket';
import {
  applyPerpsLeverageChangeDeposit,
  getPerpsFundingRequirements,
  getPerpsMarketTradingAvailability,
  getPerpsOpenInterestUsd,
  getPerpsWireAssetIndex,
  normalizePerpsPosition,
  resolvePerpsDraft,
  resolvePerpsTradeIntent,
  validatePerpsOrderSize,
  validatePerpsReviewedBuild,
} from '../common/perpsPresentation';
import { getPerpsReceiptDetails, getPerpsResultingPositionSize } from '../common/perpsReceipt';
import { balanceRefreshRequests } from '../common/polling/balanceRefresh';
import {
  executePerpsClosePosition,
  executePerpsDepositMargin,
  executePerpsModifyPosition,
  executePerpsOpenFromBalance,
  executePerpsOpenPosition,
  executePerpsWithdrawMargin,
  perpsBuildWithdrawal,
  perpsEstimateModifyPosition,
  perpsEstimatePosition,
  perpsGetActivities,
  perpsGetAsset,
  perpsGetAssetChart,
  perpsGetAssets,
  perpsGetPositions,
  perpsWithdrawReleasedMargin,
} from './perps';

const quotes = new Map<string, ApiPerpsQuote>();
const balanceAccountIds = new Set<string>();
const operations = new Map<string, ApiPerpsOperation>();
const withdrawalReviews = new Map<string, {
  request: ApiPerpsBuildWithdrawalRequest; withdraw: ApiPerpsWithdrawPermit; expiresAt: number;
}>();
type FundingBalances = { availableUsdc: string; availableEth: string };
const fundingBalances = new Map<string, {
  value?: FundingBalances; pending?: Promise<FundingBalances>; expiresAt: number;
}>();
const getPreviewPositions = withCacheAsync(
  (address: string) => perpsGetPositions({ addressByChain: { hyperliquid: address } }),
  () => false,
);
let onUpdate: OnApiUpdate | undefined;

export function initPerpsTrading(update: OnApiUpdate) {
  onUpdate = update;
}

function publishOperation(operation: ApiPerpsOperation) {
  onUpdate?.({ type: 'perpsOperationUpdated', operation: { ...operation } });
}

function hasUnresolvedOperation(accountId: string, request?: Pick<ApiPerpsQuote, 'assetId' | 'kind'>): boolean {
  if (balanceAccountIds.has(accountId)) return true;
  return [...operations.values()].some((operation) => {
    if (operation.accountId !== accountId || operation.state === 'completed' || operation.state === 'failed'
      || (operation.state === 'unknown' && operation.acknowledgedAt !== undefined)) return false;
    return !(operation.state === 'partial' && operation.orderStatus === 'filled' && operation.orderId !== undefined
      && ['close', 'reduce'].includes(operation.kind) && operation.assetId !== request?.assetId
      && (request?.kind === 'close' || request?.kind === 'reduce'));
  });
}

function isRejectedExchangeSignature(operation: ApiPerpsOperation): boolean {
  return (operation.kind === 'close' || operation.kind === 'reduce')
    && operation.stage === 'trade'
    && operation.depositTxHash === undefined
    && operation.orderId === undefined && operation.orderStatus === undefined
    && operation.filledSize === undefined && operation.positionSize === undefined
    && operation.averagePrice === undefined
    && operation.withdrawalAmount === undefined
    && /^\[HL_EXCHANGE_ERROR\] (?:L1 error: )?User or API Wallet 0x[0-9a-fA-F]{40} does not exist\.$/u
      .test(operation.error ?? '');
}

async function wallet(accountId: string, forTrading = false) {
  const { network } = parseAccountId(accountId);
  if (network !== 'mainnet') throw new Error('PerpsUnsupportedAccount');
  const account = await fetchStoredChainAccount(accountId, 'arbitrum');
  const tradingAvailability: ApiPerpsTradingAvailability = account.type === 'view' || account.type === 'ledger'
    ? { isAvailable: false, reason: 'PerpsUnsupportedAccount' } : { isAvailable: true };
  if (forTrading && !tradingAvailability.isAvailable) throw new Error(tradingAvailability.reason);
  return { ...account.byChain.arbitrum, tradingAvailability };
}

/** Fetch the selected leverage only; clients debounce selection changes. */
export async function perpsGetLeverageEstimates(
  accountId: string, draft: ApiPerpsDraftRequest,
): Promise<ApiPerpsLeverageEstimate[]> {
  if (!draft.leverageOnly && (!draft.amount || !Big(draft.amount).gt(0))) return [];
  if (!draft.editing && draft.unit === 'currency' && draft.fraction === undefined
    && !draft.reset && !draft.convertFrom && !draft.close) {
    const { address } = await wallet(accountId, true);
    const catalogue = await perpsGetAssets();
    const asset = buildPerpsMarketCatalogue(catalogue).assets.find((value) => value.id === draft.assetId);
    if (!asset) throw new Error('PerpsMarketUnavailable');
    const availability = getPerpsMarketTradingAvailability(asset);
    if (!availability.isAvailable) throw new Error(availability.reason);
    const estimate = await perpsEstimatePosition({
      chain: asset.chain, address, asset: asset.id, side: draft.side,
      depositAmount: Big(draft.amount).plus(PERPS_CCTP_FORWARD_FEE_USDC).round(6, Big.roundUp).toFixed(),
      leverage: draft.leverage, isCross: false,
    });
    if ('error' in estimate) throw new Error(estimate.error);
    return [{ leverage: draft.leverage, liquidationPrice: positiveLiquidationPrice(estimate.liquidationPrice) }];
  }
  const quote = await perpsPreviewOrder(accountId, draft);
  return [{ leverage: quote.leverage,
    liquidationPrice: quote.kind === 'unchanged' ? quote.liquidationPrice : quote.estimatedLiquidationPrice }];
}

function positiveLiquidationPrice(price?: string): string | undefined {
  return price !== undefined && Big(price).gt(0) ? price : undefined;
}

export function perpsGetReceiptDetails(input: Parameters<typeof getPerpsReceiptDetails>[0]) {
  return getPerpsReceiptDetails(input);
}

function enrichAsset(asset: ApiPerpsMarketAsset): ApiPerpsMarketAsset {
  return { ...asset, tradingAvailability: getPerpsMarketTradingAvailability(asset), context: {
    ...asset.context,
    percentChange24h: Big(asset.context.prevDayPx).gt(0)
      ? Number(Big(asset.context.markPx).div(asset.context.prevDayPx).minus(1).mul(100)) : undefined,
    fundingPercent: asset.context.funding ? Big(asset.context.funding).mul(100).toFixed() : undefined,
    fundingIntervalHours: asset.context.funding !== undefined ? 1 : undefined,
    openInterestUsd: getPerpsOpenInterestUsd(asset),
  } };
}

export async function perpsGetMarketSnapshot(
  langCode?: LangCode, options?: { force?: boolean },
): Promise<ApiPerpsMarketSnapshot> {
  const response = await perpsGetAssets(undefined, langCode, options);
  const catalogue = buildPerpsMarketCatalogue(response);
  const assets = catalogue.assets.map(enrichAsset);
  return {
    assets,
    limits: response.limitsByChain.hyperliquid,
    marketSections: catalogue.sections.map((section) => ({
      ...section,
      assets: section.assets.map((asset) => assets.find((value) => value.id === asset.id)!),
    })),
    assetsFetchedAt: getPerpsAssetsFetchedAt(response, langCode),
  };
}

export async function perpsGetSnapshot(
  accountId: string, langCode?: LangCode, options?: { forceAssets?: boolean },
): Promise<ApiPerpsSnapshot> {
  const { address, tradingAvailability } = await wallet(accountId);
  const market = await perpsGetMarketSnapshot(langCode, options?.forceAssets ? { force: true } : undefined);
  const { assets } = market;
  const unavailableDexs: string[] = [];
  const positions: ApiPerpsSnapshot['positions'] = [];
  const result = await perpsGetPositions({ addressByChain: { hyperliquid: address } });
  const state = result.positionsByChain.hyperliquid;
  if (!state) throw new Error('PerpsIncompleteData');
  for (const { position } of state.assetPositions) {
    if (Big(position.szi).eq(0)) continue;
    const asset = assets.find((value) => value.name === position.coin);
    if (!asset) {
      unavailableDexs.push(position.coin.includes(':') ? position.coin.split(':')[0] : '');
      continue;
    }
    positions.push(normalizePerpsPosition(accountId, asset, position));
  }
  const unique = [...new Map(positions.map((p) => [p.id, p])).values()].sort((a, b) =>
    a.id.localeCompare(b.id),
  );
  const totalPnl = unique.reduce((sum, p) => sum.plus(p.raw.unrealizedPnl), Big(0));
  const totalCollateral = unique.reduce((sum, p) => sum.plus(p.collateral), Big(0));
  return {
    ...market,
    tradingAvailability,
    abstractionMode: state.abstractionMode,
    spotUsdcTotal: state.spotUsdcTotal,
    spotUsdcAvailable: state.spotUsdcAvailable,
    withdrawable: state.withdrawable,
    positions: unique,
    timestamp: Date.now(),
    unavailableDexs: [...new Set(unavailableDexs)],
    totalEquity: unique.reduce((sum, p) => sum.plus(p.equity), Big(0)).toFixed(),
    totalPnl: totalPnl.toFixed(),
    totalReturnOnEquity: totalCollateral.gt(0) ? totalPnl.div(totalCollateral).toFixed() : undefined,
  };
}

export async function perpsGetCandles(assetId: string, period: ApiPriceHistoryPeriod): Promise<number[][]> {
  if (!['1D', '7D', '1M', '3M', '1Y', 'ALL'].includes(period)) throw new Error('PerpsMarketUnavailable');
  const points = await perpsGetAssetChart({ chain: 'hyperliquid', asset: assetId, period });
  if (!Array.isArray(points) || points.some((point) => !Array.isArray(point) || point.length !== 2
    || !point.every(Number.isFinite) || point[0] <= 0 || point[1] <= 0)) throw new Error('PerpsIncompleteData');
  return points;
}

export async function perpsGetActivityHistory(
  accountId: string, page: ApiPerpsActivityPageRequest = {},
): Promise<ApiPerpsActivityHistory> {
  const { address } = await wallet(accountId);
  const response = await perpsGetActivities({ ...page, addressByChain: { hyperliquid: address } });
  const snapshot = response.activitiesByChain.hyperliquid;
  if (!snapshot) throw new Error('PerpsIncompleteData');
  return normalizePerpsActivityPage(snapshot, address);
}

export async function perpsGetAssetDetail(
  accountId: string, assetId: string, page: ApiPerpsActivityPageRequest = {},
) {
  const { address } = await wallet(accountId);
  const detail = await perpsGetAsset({ ...page, chain: 'hyperliquid', address, asset: assetId });
  if (detail.asset?.id !== assetId) throw new Error('PerpsIncompleteData');
  return { asset: enrichAsset(detail.asset), position: detail.position,
    history: normalizePerpsActivityPage(detail, address) };
}

function estimateRequest(quote: ApiPerpsQuote): ApiPerpsEstimatePositionRequest {
  if (quote.open) {
    const { chain, address, asset, side, depositAmount, leverage, isCross } = quote.open;
    return { chain, address, asset, side, depositAmount, leverage, isCross };
  }
  if (quote.modify) {
    const { chain, address, asset, depositAmount, leverage, reduceOnly } = quote.modify;
    return { chain, address, asset, depositAmount, leverage, reduceOnly };
  }
  const { chain, address, asset } = quote.close!;
  return { chain, address, asset, close: true };
}

async function readFundingBalances(accountId: string, address: string, allowCache = true): Promise<FundingBalances> {
  const key = `${accountId}/${address.toLowerCase()}`;
  const cached = fundingBalances.get(key);
  if (allowCache) {
    if (cached?.pending) return cached.pending;
    if (cached?.value && cached.expiresAt > Date.now()) return cached.value;
  }
  const entry: { value?: FundingBalances; pending?: Promise<FundingBalances>; expiresAt: number } = {
    expiresAt: Date.now() + 30_000,
  };
  const pending = chains.arbitrum.getWalletAssets('mainnet', address, () => {}).then((balances) => {
    const nativeToken = getChainConfig('arbitrum').nativeToken;
    const value = {
      availableUsdc: toDecimal(balances[ARBITRUM_USDC_MAINNET.slug] ?? 0n, ARBITRUM_USDC_MAINNET.decimals),
      availableEth: toDecimal(balances[nativeToken.slug] ?? 0n, nativeToken.decimals),
    };
    entry.value = value;
    entry.pending = undefined;
    return value;
  }, (error: unknown) => {
    if (fundingBalances.get(key) === entry) fundingBalances.delete(key);
    throw error;
  });
  entry.pending = pending;
  fundingBalances.set(key, entry);
  while (fundingBalances.size > 64) fundingBalances.delete(fundingBalances.keys().next().value!);
  return pending;
}

export async function perpsGetFundingRequirements(
  accountId: string, draft: ApiPerpsDraftRequest,
): Promise<ApiPerpsFundingRequirements> {
  const { address } = await wallet(accountId, true);
  const [response, balances] = await Promise.all([
    perpsGetAssets(), readFundingBalances(accountId, address, false),
  ]);
  const asset = buildPerpsMarketCatalogue(response).assets.find((value) => value.id === draft.assetId);
  if (!asset) throw new Error('PerpsMarketUnavailable');
  const availability = getPerpsMarketTradingAvailability(asset);
  if (!availability.isAvailable) throw new Error(availability.reason);
  let position: ApiPerpsSnapshot['positions'][number] | undefined;
  if (draft.editing) {
    const positions = (await perpsGetPositions({ addressByChain: { hyperliquid: address } }))
      .positionsByChain.hyperliquid;
    if (!positions) throw new Error('PerpsIncompleteData');
    const raw = positions.assetPositions.find(({ position }) => position.coin === asset.name)?.position;
    if (raw && !Big(raw.szi).eq(0)) position = normalizePerpsPosition(accountId, asset, raw);
  }
  const depositLimits = response.limitsByChain.hyperliquid;
  let leverageDepositAmount: string | undefined;
  if (position && draft.editing && draft.leverage !== position.raw.leverage.value
    && (draft.leverageOnly || Big(draft.amount || '0').eq(position.collateral))) {
    const estimate = await perpsEstimateModifyPosition({
      chain: asset.chain, address, asset: asset.id, leverage: draft.leverage,
    });
    if ('error' in estimate) throw new Error(estimate.error);
    leverageDepositAmount = estimate.depositAmount;
  }
  return getPerpsFundingRequirements({
    asset, draft, position, depositLimits, leverageDepositAmount,
    ...balances,
  });
}

async function estimatePerpsOrder(
  quote: ApiPerpsQuote, asset: ApiPerpsMarketAsset, availableUsdc: string,
): Promise<void> {
  if (quote.kind === 'leverage') {
    const modifyEstimate = await perpsEstimateModifyPosition({
      chain: asset.chain, address: quote.modify!.address, asset: asset.id, leverage: quote.leverage,
    });
    if ('error' in modifyEstimate) throw new Error(modifyEstimate.error);
    if (typeof modifyEstimate.depositAmount !== 'string') throw new Error('PerpsIncompleteData');
    applyPerpsLeverageChangeDeposit(quote, modifyEstimate.depositAmount, availableUsdc);
    quote.estimatedFees = modifyEstimate.estimatedFees;
  }
  if (quote.kind === 'unchanged') return;
  const request = quote.kind === 'leverage'
    ? { ...estimateRequest(quote), depositAmount: undefined } : estimateRequest(quote);
  const estimate = await perpsEstimatePosition(request).catch((error: unknown) => {
    if (quote.kind === 'close') return undefined;
    throw error;
  });
  // A full-close estimate is informational: an unavailable estimate does not prevent exiting a position.
  if (!estimate) return;
  if ('error' in estimate) {
    if (quote.kind === 'close') return;
    throw new Error(estimate.error);
  }
  if (quote.kind !== 'leverage') quote.estimatedFees = estimate.estimatedFees;
  const size = Big(estimate.size);
  validatePerpsOrderSize(quote, asset, estimate.size);
  if (quote.kind === 'close') return;
  if (quote.kind === 'leverage') {
    if (!size.eq(quote.previousSize!)) throw new Error('PerpsPositionChanged');
  } else {
    quote.orderSize = size.toFixed();
    const previousSize = Big(quote.previousSize ?? 0);
    const totalSize = quote.kind === 'reduce' ? previousSize.minus(size) : previousSize.plus(size);
    if (totalSize.lte(0)) throw new Error('PerpsPositionChanged');
    quote.size = totalSize.toFixed();
    quote.notional = quote.kind === 'open'
      ? estimate.orderValue : totalSize.mul(quote.markPrice).toFixed();
  }
  quote.estimatedLiquidationPrice = positiveLiquidationPrice(estimate.liquidationPrice);
}

/** Display estimate only. Review preparation refreshes funds and creates the executable quote. */
export async function perpsPreviewOrder(
  accountId: string, request: ApiPerpsDraftRequest | ApiPerpsTradeIntent,
): Promise<ApiPerpsQuote> {
  const { address } = await wallet(accountId, true);
  const response = await perpsGetAssets();
  const asset = buildPerpsMarketCatalogue(response).assets.find((value) => value.id === request.assetId);
  if (!asset) throw new Error('PerpsMarketUnavailable');
  const depositLimits = response.limitsByChain.hyperliquid;
  let position: ApiPerpsSnapshot['positions'][number] | undefined;
  if ('kind' in request ? request.kind !== 'open' : request.editing) {
    const state = (await getPreviewPositions(address)).positionsByChain.hyperliquid;
    if (!state) throw new Error('PerpsIncompleteData');
    const raw = state.assetPositions.find(({ position }) => position.coin === asset.name)?.position;
    if (raw && !Big(raw.szi).eq(0)) position = normalizePerpsPosition(accountId, asset, raw);
  }
  const draft = resolvePerpsTradeIntent(request, position);
  const walletFraction = draft.fraction !== undefined && !draft.editing;
  const fractionBalances = walletFraction ? await readFundingBalances(accountId, address, false) : undefined;
  const availableUsdc = fractionBalances?.availableUsdc ?? '1e30';
  const quote = resolvePerpsDraft({ accountId, address, asset, draft, position, depositLimits,
    requestedKind: 'kind' in request ? request.kind : undefined,
    availableUsdc, now: Date.now(), id: '' });
  await estimatePerpsOrder(quote, asset, availableUsdc);
  const balances = fractionBalances ?? (Big(quote.paymentAmount).gt(0)
    ? await readFundingBalances(accountId, address) : { availableUsdc: '0', availableEth: '0' });
  quote.fundingRequirements = getPerpsFundingRequirements({
    asset, draft, position, depositLimits, ...balances,
    leverageDepositAmount: quote.kind === 'leverage' ? quote.paymentAmount : undefined,
  });
  return quote;
}

export async function perpsPrepareOrder(
  accountId: string,
  request: ApiPerpsDraftRequest | ApiPerpsTradeIntent,
): Promise<ApiPerpsQuote> {
  const { address } = await wallet(accountId, true);
  const snapshot = await perpsGetSnapshot(accountId, undefined, { forceAssets: true });
  const asset = snapshot.assets.find((a) => a.id === request.assetId);

  if (!asset || snapshot.unavailableDexs.includes(asset.dex)) throw new Error('PerpsMarketUnavailable');
  const availability = getPerpsMarketTradingAvailability(asset);
  if (!availability.isAvailable) throw new Error(availability.reason);
  const balances = await readFundingBalances(accountId, address, false);
  const position = snapshot.positions.find((p) => p.assetId === request.assetId);
  const draft = resolvePerpsTradeIntent(request, position);
  const { availableUsdc } = balances;
  const depositLimits = snapshot.limits;
  const quote = resolvePerpsDraft({ accountId, address, asset, draft, position, depositLimits, availableUsdc,
    requestedKind: 'kind' in request ? request.kind : undefined,
    now: Date.now(), id: crypto.randomUUID() });
  await estimatePerpsOrder(quote, asset, availableUsdc);
  const fundingRequirements = getPerpsFundingRequirements({
    asset, draft, position, depositLimits, availableUsdc,
    availableEth: balances.availableEth,
    leverageDepositAmount: quote.kind === 'leverage' ? quote.paymentAmount : undefined,
  });

  if (fundingRequirements.needsEth) throw new Error('PerpsInsufficientGas');
  quote.fundingRequirements = fundingRequirements;
  for (const [id, q] of quotes) if (q.expiresAt < Date.now()) quotes.delete(id);
  while (quotes.size >= 128) quotes.delete(quotes.keys().next().value!);

  quotes.set(quote.id, quote);
  return quote;
}

export function perpsGetOperation(accountId: string, id: string): ApiPerpsOperation | undefined {
  const operation = operations.get(id);
  return operation?.accountId === accountId ? { ...operation } : undefined;
}

export async function perpsExecuteReviewedOrder(
  accountId: string,
  enclaveToken: string,
  quoteId: string,
  operationId: string,
): Promise<ApiPerpsOperation> {
  const existing = operations.get(operationId);
  if (existing) {
    if (existing.accountId !== accountId) throw new Error('PerpsInvalidOperation');
    return { ...existing };
  }
  const quote = quotes.get(quoteId);
  if (!quote || quote.accountId !== accountId || quote.expiresAt < Date.now()) {
    throw new Error('PerpsQuoteExpired');
  }
  if (quote.kind === 'unchanged') throw new Error('PerpsUnchanged');
  if (hasUnresolvedOperation(accountId, quote)) throw new Error('PerpsOperationPending');
  await wallet(accountId, true);
  // Recheck after wallet resolution: another account may have claimed this operation ID.
  const concurrent = operations.get(operationId);
  if (concurrent) {
    if (concurrent.accountId !== accountId) throw new Error('PerpsInvalidOperation');
    return { ...concurrent };
  }
  // Another confirmation can have started while resolving the wallet.
  if (hasUnresolvedOperation(accountId, quote) || !quotes.has(quoteId)) throw new Error('PerpsOperationPending');
  const operation: ApiPerpsOperation = {
    id: operationId,
    accountId,
    assetId: quote.assetId,
    kind: quote.kind,
    state: 'running',
    stage: 'preparing',
    createdAt: Date.now(),
    withdrawalRequestedAmount: quote.kind === 'reduce' && quote.modify?.depositAmount !== undefined
      ? String(quote.modify.depositAmount) : undefined,
  };
  operations.set(operationId, operation);
  quotes.delete(quoteId);
  let started = false;
  try {
    const snapshot = await perpsGetSnapshot(accountId, undefined, { forceAssets: true });
    const asset = snapshot.assets.find((a) => a.id === quote.assetId);
    const position = snapshot.positions.find((p) => p.assetId === quote.assetId);
    if (
      !asset
      || snapshot.unavailableDexs.includes(asset.dex)
      || quote.expiresAt < Date.now()
      || (quote.kind === 'open'
        ? !!position
        : !position || Big(position.raw.szi).abs().toFixed() !== quote.previousSize)
      || (position && (position.side !== quote.side
        || (position.raw.leverage.type === 'cross') !== quote.isCross
        || position.raw.leverage.value !== quote.previousLeverage))
    ) {
      throw new Error('PerpsQuoteExpired');
    }
    const availability = getPerpsMarketTradingAvailability(asset);
    if (!availability.isAvailable) throw new Error(availability.reason);
    if (quote.wireAssetIndex !== getPerpsWireAssetIndex(asset)) throw new Error('PerpsReviewChanged');
    let submittedOrderSize: string | undefined;
    const hooks = {
      validateBuild: (build: Parameters<typeof validatePerpsReviewedBuild>[2]) => {
        validatePerpsReviewedBuild(quote, asset, build);
        const orders = build.action?.orders;
        if (Array.isArray(orders) && typeof orders[0]?.s === 'string') submittedOrderSize = orders[0].s;
      },
      onSubmitting: () => {
        started = true;
        operation.stage = Big(quote.paymentAmount).gt(0) ? 'deposit' : 'trade';
        publishOperation(operation);
      },
      onDeposit: (hash: string) => {
        balanceRefreshRequests.runCallbacks(accountId, 'arbitrum');
        operation.depositTxHash = hash;
        operation.stage = 'trade';
        publishOperation(operation);
      },
      onTrade: (result: { oid?: number; status?: string; filledSize?: string; avgPrice?: string }) => {
        operation.orderId = result.oid ?? operation.orderId;
        operation.orderStatus = result.status ?? operation.orderStatus;
        operation.filledSize = result.filledSize ?? operation.filledSize;
        if (operation.filledSize && result.status === 'filled') {
          operation.positionSize = getPerpsResultingPositionSize(quote, operation.filledSize);
        }
        operation.averagePrice = result.avgPrice ?? operation.averagePrice;
        publishOperation(operation);
      },
      onWithdrawal: (amount: string) => {
        operation.stage = 'withdrawal';
        operation.withdrawalAmount = amount;
        publishOperation(operation);
      },
    };
    if (quote.close) {
      const result = await executePerpsClosePosition(accountId, enclaveToken, quote.close, hooks);
      if ('error' in result) throw new Error(result.error);
      operation.state = result.phase === 'completed' ? 'completed' : 'partial';
    } else {
      const result = quote.open
        ? await executePerpsOpenPosition(accountId, enclaveToken, quote.open, hooks)
        : await executePerpsModifyPosition(accountId, enclaveToken, quote.modify!, hooks);
      if ('error' in result) {
        throw new Error(result.error === 'InsufficientBalance' && Big(quote.paymentAmount).gt(0)
          ? 'PerpsInsufficientGas' : result.error);
      }
      hooks.onTrade(result);
      if (result.status.startsWith('error:')) throw new Error(result.status);
      operation.state
        = 'withdrawalPhase' in result && result.withdrawalPhase === 'withdraw_unavailable'
          ? 'partial'
          : result.status === 'filled' || (quote.kind === 'leverage' && result.status === 'ok')
            ? 'completed'
            : 'unknown';
    }
    if (operation.filledSize && submittedOrderSize && Big(operation.filledSize).lt(submittedOrderSize)) {
      operation.error = 'PerpsPartialFill';
    }
    operation.stage = 'finished';
  } catch (error) {
    const rejected = operation.orderStatus?.startsWith('error:') === true;
    operation.error = rejected ? getPerpsOrderError(operation.orderStatus!)
      : error instanceof Error ? error.message : String(error);
    const signatureRejected = isRejectedExchangeSignature(operation);
    // A rejected order that pays nothing moved no funds. Deposits and uncertain withdrawals still need recovery.
    operation.state = !started || signatureRejected
      || (rejected && !Big(quote.paymentAmount).gt(0)
        && operation.stage !== 'withdrawal') ? 'failed' : 'unknown';
    if (signatureRejected) operation.error = `PerpsOrderRejected: ${operation.error}`;
    if (operation.state === 'failed' && started) operation.stage = 'finished';
  } finally {
    publishOperation(operation);
    balanceRefreshRequests.runCallbacks(accountId, 'arbitrum');
  }
  return { ...operation };
}

/** Read-only recovery; absence of an order ID never authorizes an automatic retry. */
export async function perpsReconcileOperation(
  accountId: string,
  saved: ApiPerpsOperation,
): Promise<ApiPerpsOperation> {
  if (saved.accountId !== accountId) throw new Error('PerpsInvalidOperation');
  await wallet(accountId);
  const operation = operations.get(saved.id) ?? {
    ...saved,
    state: saved.state === 'running' ? ('unknown' as const) : saved.state,
  };
  if (operation.accountId !== accountId || operation.assetId !== saved.assetId || operation.kind !== saved.kind) {
    throw new Error('PerpsInvalidOperation');
  }
  if (operation.state === 'running') return { ...operation };
  operations.set(operation.id, operation);
  // Restore the lock, but leave uncertain outcomes unresolved until backend reconciliation exists.
  return { ...operation };
}

/** Call only after the user acknowledges that the original order may still complete. Never retries it. */
export async function perpsAcknowledgeOperation(
  accountId: string,
  saved: ApiPerpsOperation,
): Promise<ApiPerpsOperation> {
  if (saved.accountId !== accountId || saved.state !== 'unknown') throw new Error('PerpsInvalidOperation');
  await wallet(accountId, true);
  // Read after the await, so a stale saved record cannot unlock an execution still running in this SDK.
  const operation = operations.get(saved.id) ?? { ...saved };
  if (operation.accountId !== accountId) throw new Error('PerpsInvalidOperation');
  if (operation.state === 'running' || operation.state === 'partial') throw new Error('PerpsOperationPending');
  if (operation.state === 'unknown') operation.acknowledgedAt ??= Date.now();
  operations.set(operation.id, operation);
  return { ...operation };
}

function hasRunningOperation(accountId: string): boolean {
  return balanceAccountIds.has(accountId) || [...operations.values()].some((operation) =>
    operation.accountId === accountId && operation.state === 'running');
}

async function withPerpsBalanceLock<T>(
  accountId: string,
  run: (address: string) => Promise<T>,
): Promise<T> {
  const { address } = await wallet(accountId, true);
  if (hasUnresolvedOperation(accountId)) throw new Error('PerpsOperationPending');
  balanceAccountIds.add(accountId);
  try {
    return await run(address);
  } finally {
    balanceAccountIds.delete(accountId);
  }
}

/**
 * Move USDC from the wallet onto the perps balance. Does not open or change a position.
 * Resolves once the burn is handed to the background, so the caller is not blocked on that transaction.
 * The account stays locked until the burn and `/perps/position/execute` settle.
 */
export async function perpsDepositMargin(
  accountId: string,
  enclaveToken: string,
  amount: string,
): Promise<{ submitted: true } | { error: string }> {
  const { address } = await wallet(accountId, true);
  if (hasUnresolvedOperation(accountId)) throw new Error('PerpsOperationPending');
  balanceAccountIds.add(accountId);
  let handedOff = false;
  try {
    const result = await executePerpsDepositMargin(
      accountId, enclaveToken, { chain: 'hyperliquid', address, amount },
    );
    if ('completion' in result) {
      handedOff = true;
      void result.completion.finally(() => {
        balanceAccountIds.delete(accountId);
      });
      return { submitted: true };
    }
    return result;
  } finally {
    if (!handedOff) balanceAccountIds.delete(accountId);
  }
}

/** Send USDC from the perps balance back to the account wallet. Does not change a position. */
export function perpsWithdrawMargin(
  accountId: string,
  enclaveToken: string,
  amount: string,
): Promise<ApiPerpsExecutePositionResult | { error: string }> {
  return withPerpsBalanceLock(accountId, (address) => executePerpsWithdrawMargin(
    accountId, enclaveToken, { chain: 'hyperliquid', address, amount },
  ));
}

/** Open a position using USDC already on the perps balance. Does not bridge a deposit. */
export function perpsOpenFromBalance(
  accountId: string,
  enclaveToken: string,
  order: {
    assetId: string;
    side: ApiPerpsPositionSide;
    amount: string;
    leverage: number;
    isCross: boolean;
  },
): Promise<ApiPerpsExecutePositionResult | { error: string }> {
  return withPerpsBalanceLock(accountId, (address) => {
    const request: ApiPerpsOpenPositionRequest = {
      chain: 'hyperliquid',
      address,
      asset: order.assetId,
      side: order.side,
      amount: order.amount,
      leverage: order.leverage,
      isCross: order.isCross,
    };
    return executePerpsOpenFromBalance(accountId, enclaveToken, request);
  });
}

async function buildWithdrawalReview(
  request: ApiPerpsBuildWithdrawalRequest,
): Promise<ApiPerpsWithdrawPermit> {
  const result = await perpsBuildWithdrawal(request);
  const { withdraw } = result;
  if (!withdraw) throw new Error('PerpsWithdrawalPending');
  if (typeof result.address !== 'string' || result.address.toLowerCase() !== request.address.toLowerCase()) {
    throw new Error('PerpsInvalidOperation');
  }
  assertHyperliquidWithdrawPermitIntegrity(withdraw, request.address);
  if (!Big(withdraw.amountUsdc).gt(PERPS_CCTP_FORWARD_FEE_USDC)
    || !Big(withdraw.amountUsdc).eq(String(withdraw.action.amount))
    || (request.amountUsdc !== undefined && !Big(withdraw.amountUsdc).eq(request.amountUsdc))) {
    throw new Error('PerpsReviewChanged');
  }
  return withdraw;
}

export async function perpsPrepareWithdrawal(accountId: string, operationId: string): Promise<string> {
  const operation = operations.get(operationId);
  if (operation?.accountId !== accountId || operation.state !== 'partial'
    || !['close', 'reduce'].includes(operation.kind)) throw new Error('PerpsInvalidOperation');
  if (hasRunningOperation(accountId)) throw new Error('PerpsOperationPending');
  withdrawalReviews.delete(operationId);
  const amountUsdc = operation.kind === 'reduce' ? operation.withdrawalRequestedAmount : undefined;
  if (operation.kind === 'reduce' && (!amountUsdc || !Big(amountUsdc).gt(PERPS_CCTP_FORWARD_FEE_USDC))) {
    throw new Error('PerpsWithdrawalPending');
  }
  const { address } = await wallet(accountId, true);
  const request: ApiPerpsBuildWithdrawalRequest = {
    chain: 'hyperliquid', address, asset: operation.assetId, amountUsdc,
  };
  const withdraw = await buildWithdrawalReview(request);
  if (operation.state !== 'partial' || operations.get(operationId) !== operation || hasRunningOperation(accountId)) {
    throw new Error('PerpsOperationPending');
  }
  withdrawalReviews.set(operationId, { request, withdraw, expiresAt: Date.now() + 60_000 });
  return withdraw.amountUsdc;
}

export async function perpsRetryWithdrawal(
  accountId: string,
  enclaveToken: string,
  operationId: string,
): Promise<ApiPerpsOperation> {
  const operation = operations.get(operationId);
  const review = withdrawalReviews.get(operationId);
  if (
    operation?.accountId !== accountId
    || operation.state !== 'partial'
    || !review
    || review.expiresAt < Date.now()
  ) {
    throw new Error('PerpsQuoteExpired');
  }
  if (hasRunningOperation(accountId)) throw new Error('PerpsOperationPending');
  withdrawalReviews.delete(operationId);
  operation.state = 'running';
  operation.stage = 'preparing';
  operation.withdrawalAmount = review.withdraw.amountUsdc;
  operation.error = undefined;
  publishOperation(operation);
  let submitted = false;
  try {
    const withdraw = await buildWithdrawalReview(review.request);
    const forwardingFee = withdraw.forwardFeeUsdc ?? PERPS_CCTP_FORWARD_FEE_USDC;
    const reviewedForwardingFee = review.withdraw.forwardFeeUsdc ?? PERPS_CCTP_FORWARD_FEE_USDC;
    if (!Big(withdraw.amountUsdc).eq(review.withdraw.amountUsdc)
      || !Big(forwardingFee).eq(reviewedForwardingFee)
      || withdraw.action.sourceDex !== review.withdraw.action.sourceDex) {
      throw new Error('PerpsReviewChanged');
    }
    const result = await perpsWithdrawReleasedMargin(accountId, enclaveToken, withdraw, () => {
      submitted = true;
      operation.stage = 'withdrawal';
      publishOperation(operation);
    });
    operation.state = result.phase === 'completed' && result.withdrawResult ? 'completed' : 'unknown';
    operation.stage = 'finished';
  } catch (error) {
    operation.state = submitted ? 'unknown' : 'partial';
    operation.stage = 'withdrawal';
    operation.error = error instanceof Error ? error.message : String(error);
  }
  balanceRefreshRequests.runCallbacks(accountId, 'arbitrum');
  publishOperation(operation);
  return { ...operation };
}
