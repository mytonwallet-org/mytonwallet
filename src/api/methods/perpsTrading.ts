import type { LangCode } from '../../global/types';
import type {
  ApiPerpsActivityPageRequest, ApiPerpsBuildWithdrawalRequest, ApiPerpsEstimatePositionRequest,
  ApiPerpsExecutePositionResult, ApiPerpsGetPositionsResult, ApiPerpsLimits, ApiPerpsListedAsset, ApiPerpsMarketAsset,
  ApiPerpsOpenPositionRequest, ApiPerpsPositionSide, ApiPerpsTradeActivity, ApiPerpsWithdrawPermit,
  ApiPriceHistoryPeriod, OnApiUpdate,
} from '../types';
import type {
  ApiPerpsAccountPosition,
  ApiPerpsActivityHistory,
  ApiPerpsBalanceWithdrawalQuote,
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
import { logDebugError } from '../../util/logs';
import { pause } from '../../util/schedulers';
import withCacheAsync from '../../util/withCacheAsync';
import { chains } from '../chains';
import {
  assertHyperliquidExchangeBuildIntegrity,
  assertHyperliquidWithdrawPermitIntegrity,
} from '../chains/evm/hyperliquidPayloadValidation';
import {
  getPerpsOrderError,
  isPerpsVenueRejection,
  isPerpsWalletAddress,
  PERPS_BALANCE_WITHDRAWAL_ASSET_ID,
  PERPS_CCTP_DEPOSIT_CHAIN,
  PERPS_CCTP_FORWARD_FEE_USDC,
  PERPS_TRADE_LOOKUP_INTERVAL_MS,
  PERPS_TRADE_WINDOW_MS,
} from '../common/perps';
import { normalizePerpsActivityPage } from '../common/perpsActivities';
import { getPerpsAssetsFetchedAt } from '../common/perpsAssets';
import { buildPerpsMarketCatalogue } from '../common/perpsMarket';
import {
  applyPerpsLeverageChangeDeposit,
  applyPerpsLeverageChangeMargin,
  assertPerpsBalanceCovers,
  getPerpsBalanceFundingRequirements,
  getPerpsBalanceWithdrawalPreview,
  getPerpsFundingRequirements,
  getPerpsMarketTradingAvailability,
  getPerpsOpenInterestUsd,
  getPerpsReceiveEstimate,
  getPerpsWireAssetIndex,
  limitPerpsLeverageChangeDeposit,
  normalizePerpsPosition,
  readPerpsSpendableUsdc,
  resolvePerpsDraft,
  resolvePerpsTradeIntent,
  validatePerpsOrderSize,
  validatePerpsReviewedBuild,
} from '../common/perpsPresentation';
import { getPerpsReceiptDetails, getPerpsResultingPositionSize } from '../common/perpsReceipt';
import { balanceRefreshRequests } from '../common/polling/balanceRefresh';
import { getTokenBySlug } from '../common/tokens';
import { ApiServerError } from '../errors';
import {
  estimatePerpsDepositFundingGasUsdc,
  executePerpsClosePosition,
  executePerpsDepositMargin,
  executePerpsModifyPosition,
  executePerpsOpenFromBalance,
  executePerpsOpenPosition,
  executePerpsOpenPositionFromBalance,
  executePerpsWithdrawMargin,
  getPerpsWallet as wallet,
  perpsBuildBalanceWithdraw,
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
import {
  getPerpsAccountSnapshot,
  getPerpsPositionsState,
  initPerpsPositions,
  requestPerpsPositionsRefresh,
} from './perpsPositions';

/** The backend's largest page. The window an operation's trade falls in holds far fewer trades. */
const PERPS_TRADE_LOOKUP_PAGE_SIZE = 100;
/**
 * Trade times come from Hyperliquid's clock and an operation's window from the device's. A trade this close outside
 * the window still keeps the operation from being settled as not placed.
 */
const PERPS_TRADE_CLOCK_MARGIN_MS = 2 * 60_000;

/** An operation's trade, or `'notPlaced'` once its window has closed without one. */
type PerpsOperationTrade = ApiPerpsTradeActivity | 'notPlaced';

const quotes = new Map<string, ApiPerpsQuote>();
const balanceAccountIds = new Set<string>();
const operations = new Map<string, ApiPerpsOperation>();
const withdrawalReviews = new Map<string, {
  request: ApiPerpsBuildWithdrawalRequest; withdraw: ApiPerpsWithdrawPermit; expiresAt: number;
}>();
/** The latest balance withdrawal review of each account; preparing another one replaces it. */
const balanceWithdrawalReviews = new Map<string, { quote: ApiPerpsBalanceWithdrawalQuote; sourceDex: unknown }>();
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
  initPerpsPositions(update);
}

function publishOperation(operation: ApiPerpsOperation) {
  onUpdate?.({ type: 'perpsOperationUpdated', operation: { ...operation } });
}

/** A copy of the record an operation ID already belongs to. Another account's ID is refused. */
function readExistingOperation(accountId: string, operationId: string): ApiPerpsOperation | undefined {
  const operation = operations.get(operationId);
  if (operation && operation.accountId !== accountId) throw new Error('PerpsInvalidOperation');
  return operation && { ...operation };
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

/** The listed market for `assetId`, outside `unavailableDexs`. Throws unless it can be traded. */
function getTradablePerpsAsset<T extends ApiPerpsListedAsset>(
  assets: readonly T[] | undefined, assetId: string, unavailableDexs: readonly string[] = [],
): T {
  const asset = assets?.find((value) => value.id === assetId);
  if (!asset || unavailableDexs.includes(asset.dex)) throw new Error('PerpsMarketUnavailable');
  const availability = getPerpsMarketTradingAvailability(asset);
  if (!availability.isAvailable) throw new Error(availability.reason);
  return asset;
}

/** The account's open position in `asset`, if any. */
function findPerpsPosition(
  accountId: string, asset: ApiPerpsListedAsset, result: ApiPerpsGetPositionsResult,
): ApiPerpsAccountPosition | undefined {
  const raw = getPerpsPositionsState(result).assetPositions
    .find(({ position }) => position.coin === asset.name)?.position;
  return raw && !Big(raw.szi).eq(0) ? normalizePerpsPosition(accountId, asset, raw) : undefined;
}

/** Fetch the selected leverage only; clients debounce selection changes. A draft without an amount prices nothing. */
export async function perpsGetLeverageEstimate(
  accountId: string, draft: ApiPerpsDraftRequest,
): Promise<ApiPerpsLeverageEstimate> {
  if (!draft.leverageOnly && (!draft.amount || !Big(draft.amount).gt(0))) return { leverage: draft.leverage };
  if (!draft.editing && draft.fraction === undefined && !draft.reset && !draft.close) {
    const { address } = await wallet(accountId, true);
    const asset = getTradablePerpsAsset((await perpsGetAssets()).assetsByChain.hyperliquid, draft.assetId);
    const fromBalance = draft.funding === 'balance';
    // A deposit's credit after the bridge fee is the margin; an open paid from the balance posts the whole amount.
    const estimate = await perpsEstimatePosition({
      chain: asset.chain, address, asset: asset.id, side: draft.side,
      depositAmount: Big(draft.amount).plus(fromBalance ? 0 : PERPS_CCTP_FORWARD_FEE_USDC).round(6, Big.roundUp)
        .toFixed(),
      leverage: draft.leverage, isCross: false,
      ...(fromBalance ? { fundingSource: 'balance' as const } : undefined),
    });
    if ('error' in estimate) throw new Error(estimate.error);
    return { leverage: draft.leverage, liquidationPrice: positiveLiquidationPrice(estimate.liquidationPrice) };
  }
  const quote = await perpsPreviewOrder(accountId, draft);
  return { leverage: quote.leverage,
    liquidationPrice: quote.kind === 'unchanged' ? quote.liquidationPrice : quote.estimatedLiquidationPrice };
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
  const response = await perpsGetAssets(langCode, options);
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
    onboarding: response.onboarding,
  };
}

/** The account snapshot with the market catalogue it was resolved against; the two are read in parallel. */
export async function perpsGetSnapshot(
  accountId: string, langCode?: LangCode, options?: { forceAssets?: boolean },
): Promise<ApiPerpsSnapshot> {
  let market: ApiPerpsMarketSnapshot | undefined;
  const account = await getPerpsAccountSnapshot(accountId, async () => {
    market = await perpsGetMarketSnapshot(langCode, options?.forceAssets ? { force: true } : undefined);
    return market.assets;
  });
  return { ...market!, ...account };
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
  return { asset: enrichAsset(detail.asset), history: normalizePerpsActivityPage(detail, address) };
}

function estimateRequest(quote: ApiPerpsQuote): ApiPerpsEstimatePositionRequest {
  if (quote.openFromBalance) {
    const { chain, address, asset, side, amount, leverage, isCross } = quote.openFromBalance;
    return { chain, address, asset, side, depositAmount: amount, leverage, isCross, fundingSource: 'balance' };
  }
  if (quote.open) {
    const { chain, address, asset, side, depositAmount, leverage, isCross } = quote.open;
    return { chain, address, asset, side, depositAmount, leverage, isCross };
  }
  if (quote.modify) {
    const { chain, address, asset, depositAmount, leverage, reduceOnly, fundingSource } = quote.modify;
    return { chain, address, asset, depositAmount, leverage, reduceOnly, fundingSource };
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

type PerpsNativeFee = { eth: string; usd?: string };

type PerpsDepositGas = {
  requiredGasUsdc?: string;
  nativeFee?: PerpsNativeFee;
};

async function readPerpsDepositGasUsdc(
  accountId: string,
  address: string,
  paymentUsdc: string,
): Promise<string> {
  if (!Big(paymentUsdc).gt(0)) {
    return '0';
  }

  return estimatePerpsDepositFundingGasUsdc(accountId, address, paymentUsdc);
}

/** ETH and USD estimates of a deposit's network fee, or nothing while fee data is unavailable. */
async function estimatePerpsNetworkFee(accountId: string, address: string): Promise<PerpsNativeFee | undefined> {
  try {
    const { network } = parseAccountId(accountId);
    const { nativeToken } = getChainConfig(PERPS_CCTP_DEPOSIT_CHAIN);
    const eth = toDecimal(
      await chains[PERPS_CCTP_DEPOSIT_CHAIN].estimatePerpsDepositNetworkFee(network, address),
      nativeToken.decimals,
    );
    const priceUsd = getTokenBySlug(nativeToken.slug)?.priceUsd;
    return { eth, usd: priceUsd ? Big(eth).mul(priceUsd).round(6, Big.roundUp).toFixed() : undefined };
  } catch (err) {
    logDebugError('estimatePerpsNetworkFee', err);
    return undefined;
  }
}

/** Starts the network-fee estimate of a wallet open or increase, which always deposits, alongside its estimate. */
function startPerpsNetworkFee(quote: ApiPerpsQuote, address: string) {
  return quote.funding !== 'balance' && (quote.kind === 'open' || quote.kind === 'increase')
    ? estimatePerpsNetworkFee(quote.accountId, address) : undefined;
}

/**
 * ETH gas when the wallet covers the estimated userOp. Otherwise the paymaster cost in USDC.
 * `started` is an estimate already in flight; a settled `undefined` means that estimate failed.
 */
async function resolvePerpsDepositGas(
  accountId: string,
  address: string,
  availableEth: string,
  paymentUsdc: string,
  started?: Promise<PerpsNativeFee | undefined>,
): Promise<PerpsDepositGas> {
  if (!Big(paymentUsdc).gt(0)) return {};

  const nativeFee = await (started ?? estimatePerpsNetworkFee(accountId, address));
  if (nativeFee && Big(availableEth).gte(nativeFee.eth)) {
    return { nativeFee };
  }

  return { requiredGasUsdc: await readPerpsDepositGasUsdc(accountId, address, paymentUsdc) };
}

function applyPerpsDepositGas(quote: ApiPerpsQuote, gas: PerpsDepositGas) {
  if (gas.requiredGasUsdc !== undefined) {
    quote.estimatedNetworkFeeUsdc = gas.requiredGasUsdc;
    return;
  }
  if (!gas.nativeFee) return;

  quote.estimatedNetworkFeeEth = gas.nativeFee.eth;
  if (gas.nativeFee.usd !== undefined) quote.estimatedNetworkFeeUsd = gas.nativeFee.usd;
}

async function attachPerpsFundingRequirements(
  accountId: string,
  address: string,
  params: Parameters<typeof getPerpsFundingRequirements>[0],
  paymentUsdc: string,
): Promise<ApiPerpsFundingRequirements> {
  const gas = await resolvePerpsDepositGas(accountId, address, params.availableEth, paymentUsdc);

  return getPerpsFundingRequirements({ ...params, ...gas });
}

export async function perpsGetFundingRequirements(
  accountId: string, draft: ApiPerpsDraftRequest,
): Promise<ApiPerpsFundingRequirements> {
  const { address } = await wallet(accountId, true);
  if (draft.funding === 'balance') {
    const [response, positions] = await Promise.all([
      perpsGetAssets(), perpsGetPositions({ addressByChain: { hyperliquid: address } }),
    ]);
    const asset = getTradablePerpsAsset(response.assetsByChain.hyperliquid, draft.assetId);
    if (draft.editing && !findPerpsPosition(accountId, asset, positions)) throw new Error('PerpsPositionChanged');
    const spendableUsdc = readPerpsSpendableUsdc(getPerpsPositionsState(positions).spendableUsdcByDex, asset.dex);
    return buildFundingRequirements({ asset, draft, depositLimits: response.limitsByChain.hyperliquid, spendableUsdc });
  }
  const [response, balances] = await Promise.all([
    perpsGetAssets(), readFundingBalances(accountId, address, false),
  ]);
  const asset = getTradablePerpsAsset(response.assetsByChain.hyperliquid, draft.assetId);
  const position = draft.editing
    ? findPerpsPosition(accountId, asset, await perpsGetPositions({ addressByChain: { hyperliquid: address } }))
    : undefined;
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
  const paymentUsdc = getPerpsFundingRequirements({
    asset, draft, position, depositLimits, leverageDepositAmount,
    ...balances,
  }).requiredUsdc;

  return attachPerpsFundingRequirements(accountId, address, {
    asset, draft, position, depositLimits, leverageDepositAmount,
    ...balances,
  }, paymentUsdc);
}

/**
 * What a draft requires from its source: the book's `spendableUsdc` when given, otherwise the wallet's `balances`.
 */
function buildFundingRequirements({ spendableUsdc, balances, ...params }: {
  asset: ApiPerpsMarketAsset;
  draft: ApiPerpsDraftRequest;
  position?: ApiPerpsAccountPosition;
  depositLimits: ApiPerpsLimits;
  spendableUsdc?: string;
  balances?: FundingBalances;
  leverageDepositAmount?: string;
}): ApiPerpsFundingRequirements {
  if (spendableUsdc !== undefined) {
    return getPerpsBalanceFundingRequirements(params.asset, params.draft.leverage, spendableUsdc);
  }
  return getPerpsFundingRequirements({
    ...params,
    ...balances!,
  });
}

/**
 * Quotes a leverage change and returns what it needs before its review adds headroom. `availableUsdc` is what the
 * funding source holds. Without it (display previews), a deposit is not checked against it.
 */
async function estimatePerpsLeverageChange(
  quote: ApiPerpsQuote, asset: ApiPerpsMarketAsset, availableUsdc?: string,
): Promise<string> {
  const fromBalance = quote.funding === 'balance';
  const modifyEstimate = await perpsEstimateModifyPosition({
    chain: asset.chain, address: quote.modify!.address, asset: asset.id, leverage: quote.leverage,
    ...(fromBalance ? { fundingSource: 'balance' as const } : undefined),
  });
  if ('error' in modifyEstimate) throw new Error(modifyEstimate.error);
  const needed = fromBalance ? modifyEstimate.marginAmount : modifyEstimate.depositAmount;
  if (typeof needed !== 'string') throw new Error('PerpsIncompleteData');
  if (fromBalance) applyPerpsLeverageChangeMargin(quote, needed, availableUsdc);
  else applyPerpsLeverageChangeDeposit(quote, needed, availableUsdc);
  quote.estimatedFees = modifyEstimate.estimatedFees;
  return needed;
}

async function estimatePerpsOrder(quote: ApiPerpsQuote, asset: ApiPerpsMarketAsset): Promise<void> {
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
  if (quote.kind === 'open') quote.switchesToUnified = estimate.switchesToUnified;
  const size = Big(estimate.size);
  validatePerpsOrderSize(quote, asset, estimate.size);
  if (quote.kind === 'close') {
    quote.estimatedReceiveAmount = getPerpsReceiveEstimate(quote);
    return;
  }
  if (quote.kind === 'leverage') {
    if (!size.eq(quote.previousSize!)) throw new Error('PerpsPositionChanged');
  } else {
    quote.orderSize = size.toFixed();
    const previousSize = Big(quote.previousSize ?? 0);
    const totalSize = quote.kind === 'reduce' ? previousSize.minus(size) : previousSize.plus(size);
    if (totalSize.lte(0)) throw new Error('PerpsPositionChanged');
    quote.size = totalSize.toFixed();
    // The estimate prices the order where its build will; the catalogue mark can lag that price.
    const orderValue = Big(estimate.orderValue);
    const price = orderValue.gt(0) ? orderValue.div(size) : Big(quote.markPrice);
    quote.notional = quote.kind === 'open' ? estimate.orderValue : totalSize.mul(price).round(6).toFixed();
    applyPerpsMarginEstimate(quote, estimate.marginRequired);
    quote.estimatedReceiveAmount = getPerpsReceiveEstimate(quote);
  }
  quote.estimatedLiquidationPrice = positiveLiquidationPrice(estimate.liquidationPrice);
}

/**
 * An order that deposits posts `marginRequired` of the credited USDC as margin. The rest of the credit, less the
 * estimated trading fees, stays free on Hyperliquid. Unknown inputs leave the estimates unset, and an order paid from
 * the balance deposits nothing to leave free.
 */
function applyPerpsMarginEstimate(quote: ApiPerpsQuote, marginRequired: string) {
  if (quote.kind !== 'open' && quote.kind !== 'increase') return;
  const margin = Big(marginRequired);
  if (!margin.gt(0)) return;
  quote.estimatedCollateral = margin.plus(quote.previousCollateral ?? 0).toFixed();
  const trading = quote.estimatedFees?.trading;
  if (trading === undefined || quote.funding === 'balance') return;
  const remaining = Big(quote.paymentAmount).minus(quote.bridgeFee).minus(margin).minus(trading);
  if (remaining.gte(0)) quote.estimatedRemainingCollateral = remaining.round(6, Big.roundDown).toFixed();
}

/**
 * Prices a resolved quote and sets what it requires from its source. A quote paid from the balance must fit the book's
 * spendable USDC. Any other quote reads `readBalances`, limits a leverage deposit to what the wallet holds, and pays
 * the deposit gas in ETH when that balance covers it, otherwise in USDC.
 */
async function applyPerpsQuoteFunding(
  quote: ApiPerpsQuote,
  { address, availableUsdc, spendableUsdc, ...params }: {
    address: string;
    asset: ApiPerpsMarketAsset;
    draft: ApiPerpsDraftRequest;
    position?: ApiPerpsAccountPosition;
    depositLimits: ApiPerpsLimits;
    availableUsdc?: string;
    spendableUsdc?: string;
  },
  readBalances: () => MaybePromise<FundingBalances>,
) {
  const nativeFeeEstimate = startPerpsNetworkFee(quote, address);
  const leverageNeed = quote.kind === 'leverage'
    ? await estimatePerpsLeverageChange(quote, params.asset, availableUsdc ?? spendableUsdc)
    : undefined;
  await estimatePerpsOrder(quote, params.asset);
  if (spendableUsdc !== undefined) {
    assertPerpsBalanceCovers(quote, params.asset, spendableUsdc);
    quote.fundingRequirements = buildFundingRequirements({ ...params, spendableUsdc });
    return;
  }
  const balances = await readBalances();
  if (leverageNeed !== undefined && availableUsdc === undefined) {
    limitPerpsLeverageChangeDeposit(quote, leverageNeed, balances.availableUsdc);
  }
  const gas = await resolvePerpsDepositGas(
    quote.accountId, address, balances.availableEth, quote.paymentAmount, nativeFeeEstimate,
  );
  applyPerpsDepositGas(quote, gas);
  quote.fundingRequirements = getPerpsFundingRequirements({
    ...params,
    ...balances,
    ...gas,
    leverageDepositAmount: leverageNeed,
  });
}

/** Display estimate only. Review preparation refreshes funds and creates the executable quote. */
export async function perpsPreviewOrder(
  accountId: string, request: ApiPerpsDraftRequest | ApiPerpsTradeIntent,
): Promise<ApiPerpsQuote> {
  const { address } = await wallet(accountId, true);
  const response = await perpsGetAssets();
  const asset = getTradablePerpsAsset(response.assetsByChain.hyperliquid, request.assetId);
  const depositLimits = response.limitsByChain.hyperliquid;
  const isEditing = 'kind' in request ? request.kind !== 'open' : request.editing;
  const fromBalance = !('kind' in request) && request.funding === 'balance';
  // The positions read also carries the spendable USDC a balance draft is checked against.
  const positions = isEditing || fromBalance ? await getPreviewPositions(address) : undefined;
  const position = isEditing ? findPerpsPosition(accountId, asset, positions!) : undefined;
  const draft = resolvePerpsTradeIntent(request, position);
  const spendableUsdc = fromBalance
    ? readPerpsSpendableUsdc(getPerpsPositionsState(positions!).spendableUsdcByDex, asset.dex)
    : undefined;
  // A display preview checks the wallet balance only to size a wallet fraction; Review checks it in full.
  const walletFraction = !fromBalance && draft.fraction !== undefined && !draft.editing;
  const fractionBalances = walletFraction ? await readFundingBalances(accountId, address, false) : undefined;
  const availableUsdc = fractionBalances?.availableUsdc;
  const params = { address, asset, draft, position, depositLimits, availableUsdc, spendableUsdc };
  const quote = resolvePerpsDraft({ ...params, accountId, requestedKind: 'kind' in request ? request.kind : undefined,
    now: Date.now(), id: '' });
  await applyPerpsQuoteFunding(quote, params, () => fractionBalances ?? (Big(quote.paymentAmount).gt(0)
    ? readFundingBalances(accountId, address) : { availableUsdc: '0', availableEth: '0' }));
  return quote;
}

export async function perpsPrepareOrder(
  accountId: string,
  request: ApiPerpsDraftRequest | ApiPerpsTradeIntent,
): Promise<ApiPerpsQuote> {
  const { address } = await wallet(accountId, true);
  const snapshot = await perpsGetSnapshot(accountId, undefined, { forceAssets: true });
  const asset = getTradablePerpsAsset(snapshot.assets, request.assetId, snapshot.unavailableDexs);
  // A balance draft takes its margin from the book's spendable USDC and reads no wallet balance.
  const spendableUsdc = !('kind' in request) && request.funding === 'balance'
    ? readPerpsSpendableUsdc(snapshot.spendableUsdcByDex, asset.dex)
    : undefined;
  const balances = spendableUsdc === undefined ? await readFundingBalances(accountId, address, false) : undefined;
  const position = snapshot.positions.find((p) => p.assetId === request.assetId);
  const draft = resolvePerpsTradeIntent(request, position);
  const depositLimits = snapshot.limits;
  const availableUsdc = balances?.availableUsdc;
  const params = { address, asset, draft, position, depositLimits, availableUsdc, spendableUsdc };
  const quote = resolvePerpsDraft({ ...params, accountId, requestedKind: 'kind' in request ? request.kind : undefined,
    now: Date.now(), id: crypto.randomUUID() });
  await applyPerpsQuoteFunding(quote, params, () => balances!);
  if (quote.fundingRequirements!.needsUsdc) throw new Error('PerpsInsufficientUsdc');

  for (const [id, q] of quotes) if (q.expiresAt < Date.now()) quotes.delete(id);
  while (quotes.size >= 128) quotes.delete(quotes.keys().next().value!);

  quotes.set(quote.id, quote);
  return quote;
}

export async function perpsExecuteReviewedOrder(
  accountId: string,
  enclaveToken: string,
  quoteId: string,
  operationId: string,
): Promise<ApiPerpsOperation> {
  const existing = readExistingOperation(accountId, operationId);
  if (existing) return existing;
  const quote = quotes.get(quoteId);
  if (!quote || quote.accountId !== accountId || quote.expiresAt < Date.now()) {
    throw new Error('PerpsQuoteExpired');
  }
  if (quote.kind === 'unchanged') throw new Error('PerpsUnchanged');
  if (hasUnresolvedOperation(accountId, quote)) throw new Error('PerpsOperationPending');
  const { address } = await wallet(accountId, true);
  // Recheck after wallet resolution: another account may have claimed this operation ID.
  const concurrent = readExistingOperation(accountId, operationId);
  if (concurrent) return concurrent;
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
  const depositsFromWallet = quote.funding !== 'balance' && Big(quote.paymentAmount).gt(0);
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
    assertPerpsBalanceCovers(quote, asset, readPerpsSpendableUsdc(snapshot.spendableUsdcByDex, asset.dex));
    const hooks = {
      validateBuild: (build: Parameters<typeof validatePerpsReviewedBuild>[2]) => {
        validatePerpsReviewedBuild(quote, asset, build);
        // The switch changes the whole account, so this read has to agree that nothing it holds could be affected.
        if (build.setAbstraction && (
          snapshot.abstractionMode !== 'default' || snapshot.positions.length || snapshot.unavailableDexs.length
        )) {
          throw new Error('PerpsReviewChanged');
        }
        const orders = build.action?.orders;
        if (Array.isArray(orders) && typeof orders[0]?.s === 'string') operation.submittedOrderSize = orders[0].s;
      },
      onSubmitting: () => {
        started = true;
        operation.stage = depositsFromWallet ? 'deposit' : 'trade';
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
      onWithdrawalRejected: (reason: string) => {
        operation.error = `PerpsWithdrawalRejected: ${reason}`;
      },
    };
    if (quote.close) {
      const failure = await executePerpsClosePosition(accountId, enclaveToken, quote.close, hooks);
      if (failure) throw new Error(failure.error);
      // The close order filled. Proceeds the backend did not withdraw stay on the HyperCore balance, as for a reduce.
      operation.state = 'completed';
    } else {
      const result = quote.openFromBalance
        ? await executePerpsOpenPositionFromBalance(accountId, enclaveToken, quote.openFromBalance, hooks)
        : quote.open
          ? await executePerpsOpenPosition(accountId, enclaveToken, quote.open, hooks)
          : await executePerpsModifyPosition(accountId, enclaveToken, quote.modify!, hooks,
            quote.funding === 'balance' && quote.kind === 'leverage' ? quote.paymentAmount : undefined);
      if ('error' in result) {
        throw new Error(result.error === 'InsufficientBalance' && depositsFromWallet
          ? 'PerpsInsufficientUsdc' : result.error);
      }
      hooks.onTrade(result);
      if (result.status.startsWith('error:')) throw new Error(result.status);
      operation.state = result.status === 'filled' || (quote.kind === 'leverage' && result.status === 'ok')
        ? 'completed'
        : 'unknown';
    }
    if (!operation.error && isPerpsPartialFill(operation, operation.filledSize)) {
      operation.error = 'PerpsPartialFill';
    }
    operation.stage = 'finished';
  } catch (error) {
    const rejected = operation.orderStatus?.startsWith('error:') === true;
    operation.error = rejected ? getPerpsOrderError(operation.orderStatus!)
      : error instanceof Error ? error.message : String(error);
    const signatureRejected = isRejectedExchangeSignature(operation);
    // A rejected order that deposits nothing moved no funds. Deposits and uncertain withdrawals still need recovery.
    const state = !started || signatureRejected
      || (rejected && !depositsFromWallet && operation.stage !== 'withdrawal') ? 'failed' : 'unknown';
    if (signatureRejected) operation.error = `PerpsOrderRejected: ${operation.error}`;
    // The backend carries on with an order whose request a proxy ended, so its trade decides the outcome.
    const trade = state === 'unknown' && (quote.kind === 'open' || quote.kind === 'increase')
      && isPerpsRequestInTransit(error)
      ? await waitForPerpsOperationTrade(address, operation, quote.side)
      : undefined;
    if (trade === 'notPlaced') {
      settlePerpsOperationAsNotPlaced(operation);
    } else if (!trade || !completePerpsOperationWithTrade(operation, trade)) {
      operation.state = state;
      if (state === 'failed' && started) operation.stage = 'finished';
      logDebugError('perpsExecuteReviewedOrder', operation.kind, state, operation.error, operation.orderStatus);
    }
  } finally {
    publishOperation(operation);
    balanceRefreshRequests.runCallbacks(accountId, 'arbitrum');
    if (started) requestPerpsPositionsRefresh(accountId);
  }
  return { ...operation };
}

/**
 * Read-only recovery; absence of an order ID never authorizes an automatic retry. An unknown open or increase
 * completes once its trade appears in the account's activity, or fails once its window closed without one. Any other
 * uncertain outcome stays unresolved.
 */
export async function perpsReconcileOperation(
  accountId: string,
  saved: ApiPerpsOperation,
): Promise<ApiPerpsOperation> {
  if (saved.accountId !== accountId) throw new Error('PerpsInvalidOperation');
  const { address } = await wallet(accountId);
  const operation = operations.get(saved.id) ?? {
    ...saved,
    state: saved.state === 'running' ? ('unknown' as const) : saved.state,
  };
  if (operation.accountId !== accountId || operation.assetId !== saved.assetId || operation.kind !== saved.kind) {
    throw new Error('PerpsInvalidOperation');
  }
  if (operation.state === 'running') return { ...operation };
  operations.set(operation.id, operation);
  if (operation.state === 'unknown' && (operation.kind === 'open' || operation.kind === 'increase')) {
    const trade = await findPerpsOperationTrade(address, operation).catch((err: unknown) => {
      logDebugError('perpsReconcileOperation', err);
      return undefined;
    });
    // Another reconciliation can have settled the record, or the user acknowledged it, during the read.
    if (trade === 'notPlaced' && operation.state === 'unknown') {
      settlePerpsOperationAsNotPlaced(operation);
      requestPerpsPositionsRefresh(accountId);
    } else if (trade && trade !== 'notPlaced' && operation.state === 'unknown'
      && completePerpsOperationWithTrade(operation, trade)) {
      requestPerpsPositionsRefresh(accountId);
    }
  }
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
  // The original order may have changed the positions since they were last read.
  requestPerpsPositionsRefresh(accountId);
  return { ...operation };
}

/** A request that failed on its way, which the backend may still be carrying out. */
function isPerpsRequestInTransit(error: unknown): boolean {
  if (error instanceof ApiServerError) {
    return error.statusCode === undefined || [408, 502, 503, 504].includes(error.statusCode);
  }
  return error instanceof TypeError || (error instanceof Error && ['AbortError', 'TimeoutError'].includes(error.name));
}

/** Looks for the trade of an open or increase until it is found or its window has closed. */
async function waitForPerpsOperationTrade(
  address: string, operation: ApiPerpsOperation, side: ApiPerpsPositionSide,
): Promise<PerpsOperationTrade | undefined> {
  while (true) {
    const isLastRead = Date.now() > operation.createdAt + PERPS_TRADE_WINDOW_MS;
    const trade = await findPerpsOperationTrade(address, operation, side).catch((err: unknown) => {
      logDebugError('waitForPerpsOperationTrade', err);
      return undefined;
    });
    if (trade || isLastRead) return trade;
    await pause(PERPS_TRADE_LOOKUP_INTERVAL_MS);
  }
}

/**
 * The trade an open or increase placed: the one with its order ID when that is known, otherwise the earliest trade of
 * its kind in its market that `isPerpsTradeAvailableTo` allows. `'notPlaced'` when an operation without an order ID
 * has a closed window and no trade that could be its own, even allowing for clock differences. Undefined while unclear.
 */
async function findPerpsOperationTrade(
  address: string, operation: ApiPerpsOperation, side?: ApiPerpsPositionSide,
): Promise<PerpsOperationTrade | undefined> {
  const windowEnd = operation.createdAt + PERPS_TRADE_WINDOW_MS;
  const response = await perpsGetActivities({
    addressByChain: { hyperliquid: address },
    startTime: Math.max(0, operation.createdAt - PERPS_TRADE_CLOCK_MARGIN_MS),
    endTime: windowEnd + PERPS_TRADE_CLOCK_MARGIN_MS,
    limit: PERPS_TRADE_LOOKUP_PAGE_SIZE,
  });
  const snapshot = response.activitiesByChain.hyperliquid;
  if (!snapshot || snapshot.address?.toLowerCase() !== address.toLowerCase() || !Array.isArray(snapshot.activities)) {
    throw new Error('PerpsIncompleteData');
  }
  // A full page can leave out the trade
  if (snapshot.nextCursor) return undefined;
  const candidates = snapshot.activities.filter((trade) => trade.assetId === operation.assetId
    && trade.kind === operation.kind && (side === undefined || trade.side === side)
    && isPerpsTradeUnclaimed(operation, trade));
  const trade = candidates.filter((candidate) => isPerpsTradeAvailableTo(operation, candidate))
    .sort((a, b) => a.timestamp - b.timestamp)[0];
  if (trade) return trade;
  return operation.orderId === undefined && !candidates.length && Date.now() > windowEnd ? 'notPlaced' : undefined;
}

/**
 * Whether `trade` can be the one `operation` placed: made within its window and claimed by no other operation. Trading
 * stays locked from the operation's start until it settles or the user acknowledges it, so no other order of this app
 * can have made a trade in that window, even when the operation that did is not restored.
 */
function isPerpsTradeAvailableTo(operation: ApiPerpsOperation, trade: ApiPerpsTradeActivity): boolean {
  return isPerpsTradeUnclaimed(operation, trade)
    && trade.timestamp >= operation.createdAt && trade.timestamp <= getPerpsTradeWindowEnd(operation);
}

function isPerpsTradeUnclaimed(operation: ApiPerpsOperation, trade: ApiPerpsTradeActivity): boolean {
  return trade.orderId !== undefined
    && (operation.orderId === undefined || trade.orderId === operation.orderId)
    && ![...operations.values()].some((other) => other.id !== operation.id && other.orderId === trade.orderId);
}

/** The window ends `PERPS_TRADE_WINDOW_MS` after the start, or at an acknowledgement, after which other orders follow. */
function getPerpsTradeWindowEnd(operation: ApiPerpsOperation): number {
  const end = operation.createdAt + PERPS_TRADE_WINDOW_MS;
  return operation.acknowledgedAt === undefined ? end : Math.min(end, operation.acknowledgedAt);
}

/** The backend gives up on an order once its window has passed, so one with no trade by then was never placed. */
function settlePerpsOperationAsNotPlaced(operation: ApiPerpsOperation) {
  operation.state = 'failed';
  operation.stage = 'finished';
  operation.error = 'PerpsOrderNotPlaced';
}

/**
 * Completes an open or increase with its trade unless another operation claimed the trade or the user acknowledged
 * the operation before it was made, both of which can happen while the trade is read. Returns whether it completed.
 */
function completePerpsOperationWithTrade(operation: ApiPerpsOperation, trade: ApiPerpsTradeActivity): boolean {
  if (!isPerpsTradeAvailableTo(operation, trade)) return false;
  operation.orderId = trade.orderId;
  operation.orderStatus = 'filled';
  operation.filledSize = trade.size ?? operation.filledSize;
  operation.positionSize = (trade.kind === 'open' ? trade.size : trade.positionSizeAfter) ?? operation.positionSize;
  operation.state = 'completed';
  operation.stage = 'finished';
  operation.error = isPerpsPartialFill(operation, operation.filledSize) ? 'PerpsPartialFill' : undefined;
  return true;
}

function isPerpsPartialFill(operation: ApiPerpsOperation, filledSize?: string): boolean {
  return Boolean(filledSize && operation.submittedOrderSize && Big(filledSize).lt(operation.submittedOrderSize));
}

function hasRunningOperation(accountId: string): boolean {
  return balanceAccountIds.has(accountId) || [...operations.values()].some((operation) =>
    operation.accountId === accountId && operation.state === 'running');
}

/** Runs a balance action while blocking reviewed trading, until `heldUntil` of its result settles when given. */
async function withPerpsBalanceLock<T>(
  accountId: string,
  run: (address: string) => Promise<T>,
  heldUntil?: (result: T) => Promise<void> | undefined,
): Promise<T> {
  const { address } = await wallet(accountId, true);
  if (hasUnresolvedOperation(accountId)) throw new Error('PerpsOperationPending');
  balanceAccountIds.add(accountId);
  const release = () => {
    balanceAccountIds.delete(accountId);
  };
  let held: Promise<void> | undefined;
  try {
    const result = await run(address);
    held = heldUntil?.(result);
    return result;
  } finally {
    if (held) void held.then(release, release);
    else release();
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
  const result = await withPerpsBalanceLock(
    accountId,
    (address) => executePerpsDepositMargin(accountId, enclaveToken, { chain: 'hyperliquid', address, amount }),
    (deposit) => ('completion' in deposit ? deposit.completion : undefined),
  );
  return 'completion' in result ? { submitted: true } : result;
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

/**
 * A fresh review of withdrawing all that one withdrawal can send from the HyperCore balance to the account's wallet.
 * The quote is valid for 60 seconds.
 */
export async function perpsPrepareBalanceWithdrawal(accountId: string): Promise<ApiPerpsBalanceWithdrawalQuote> {
  const { address } = await wallet(accountId, true);
  if (hasUnresolvedOperation(accountId)) throw new Error('PerpsOperationPending');
  const preview = getPerpsBalanceWithdrawalPreview(
    getPerpsPositionsState(await perpsGetPositions({ addressByChain: { hyperliquid: address } })),
  );
  if (!preview) throw new Error('PerpsNothingToWithdraw');
  const build = await perpsBuildBalanceWithdraw({ chain: 'hyperliquid', address, amount: preview.amount }, address);
  assertHyperliquidExchangeBuildIntegrity(build, { expectedWalletRecipient: address });
  const quote: ApiPerpsBalanceWithdrawalQuote = {
    ...preview, id: crypto.randomUUID(), accountId, destination: address, expiresAt: Date.now() + 60_000,
  };
  balanceWithdrawalReviews.set(accountId, { quote, sourceDex: build.action.sourceDex });
  return quote;
}

/**
 * Sends the reviewed withdrawal once, building it again and requiring the reviewed amount and source. A failure before
 * submission or a venue rejection is `failed`. Any other result that does not confirm it is `unknown` and never retried.
 */
export async function perpsExecuteBalanceWithdrawal(
  accountId: string,
  enclaveToken: string,
  quoteId: string,
  operationId: string,
): Promise<ApiPerpsOperation> {
  const existing = readExistingOperation(accountId, operationId);
  if (existing) return existing;
  if (!readBalanceWithdrawalReview(accountId, quoteId)) throw new Error('PerpsQuoteExpired');
  return withPerpsBalanceLock(accountId, async (address) => {
    const concurrent = readExistingOperation(accountId, operationId);
    if (concurrent) return concurrent;
    const review = readBalanceWithdrawalReview(accountId, quoteId);
    if (!review || !isPerpsWalletAddress(review.quote.destination, address)) throw new Error('PerpsQuoteExpired');
    balanceWithdrawalReviews.delete(accountId);
    const operation: ApiPerpsOperation = {
      id: operationId,
      accountId,
      assetId: PERPS_BALANCE_WITHDRAWAL_ASSET_ID,
      kind: 'withdraw',
      state: 'running',
      stage: 'preparing',
      createdAt: Date.now(),
      withdrawalAmount: review.quote.amount,
      balanceWithdrawal: review.quote,
    };
    operations.set(operationId, operation);
    let started = false;
    try {
      const result = await executePerpsWithdrawMargin(
        accountId,
        enclaveToken,
        { chain: 'hyperliquid', address, amount: review.quote.amount },
        {
          validateBuild: (build) => {
            if (build.action?.sourceDex !== review.sourceDex) throw new Error('PerpsReviewChanged');
          },
          onSubmitting: () => {
            started = true;
            operation.stage = 'withdrawal';
            publishOperation(operation);
          },
        },
      );
      if ('error' in result) throw new Error(result.error);
      operation.orderStatus = result.status;
      if (result.status.startsWith('error')) {
        operation.state = 'failed';
        operation.error = `PerpsWithdrawalRejected: ${result.status}`;
      } else {
        operation.state = result.status === 'success' ? 'completed' : 'unknown';
      }
      operation.stage = 'finished';
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (started && isPerpsVenueRejection(error)) {
        operation.state = 'failed';
        operation.stage = 'finished';
        operation.error = `PerpsWithdrawalRejected: ${message}`;
      } else {
        operation.state = started ? 'unknown' : 'failed';
        // The build refuses an amount its source no longer covers.
        operation.error = !started && error instanceof ApiServerError && error.statusCode === 400
          ? 'PerpsReviewChanged' : message;
      }
    } finally {
      publishOperation(operation);
      balanceRefreshRequests.runCallbacks(accountId, 'arbitrum');
      if (started) requestPerpsPositionsRefresh(accountId);
    }
    return { ...operation };
  });
}

function readBalanceWithdrawalReview(accountId: string, quoteId: string) {
  const review = balanceWithdrawalReviews.get(accountId);
  return review?.quote.id === quoteId && review.quote.expiresAt >= Date.now() ? review : undefined;
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
  return validateWithdrawalReview(request, await perpsBuildWithdrawal(request));
}

function validateWithdrawalReview(
  request: ApiPerpsBuildWithdrawalRequest,
  result: Awaited<ReturnType<typeof perpsBuildWithdrawal>>,
): ApiPerpsWithdrawPermit {
  const { withdraw } = result;
  if (!withdraw) throw new Error('PerpsWithdrawalPending');
  if (!isPerpsWalletAddress(result.address, request.address)) throw new Error('PerpsInvalidOperation');
  assertHyperliquidWithdrawPermitIntegrity(withdraw, request.address);
  if (!Big(withdraw.amountUsdc).gt(PERPS_CCTP_FORWARD_FEE_USDC)
    || !Big(withdraw.amountUsdc).eq(String(withdraw.action.amount))
    || (request.amountUsdc !== undefined && Big(withdraw.amountUsdc).gt(request.amountUsdc))) {
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
  // Recovery withdraws at most what the order prepared or a reduce released. Only a close without either sweeps.
  const amountUsdc = operation.withdrawalAmount ?? operation.withdrawalRequestedAmount;
  const { address } = await wallet(accountId, true);
  const request: ApiPerpsBuildWithdrawalRequest = {
    chain: 'hyperliquid', address, asset: operation.assetId, amountUsdc,
  };
  // With nothing to withdraw the funds stay on the HyperCore balance, and the filled order holds no lock.
  const hasAmount = operation.kind !== 'reduce' || (amountUsdc && Big(amountUsdc).gt(PERPS_CCTP_FORWARD_FEE_USDC));
  const result = hasAmount ? await perpsBuildWithdrawal(request) : undefined;
  if (!result?.withdraw) {
    operation.state = 'completed';
    operation.stage = 'finished';
    publishOperation(operation);
    throw new Error('PerpsWithdrawalPending');
  }
  const withdraw = validateWithdrawalReview(request, result);
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
    operation.state = submitted && !isPerpsVenueRejection(error) ? 'unknown' : 'partial';
    operation.stage = 'withdrawal';
    operation.error = error instanceof Error ? error.message : String(error);
  }
  balanceRefreshRequests.runCallbacks(accountId, 'arbitrum');
  if (submitted) requestPerpsPositionsRefresh(accountId);
  publishOperation(operation);
  return { ...operation };
}
