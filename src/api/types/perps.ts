import type { ApiEvmSwapTransactionRequest, ApiPriceHistoryPeriod } from './backend';
import type { ApiMarketSection } from './market';
import type { ApiPerpsFees } from './perpsTrading';

export const API_PERPS_CHAINS = ['hyperliquid'] as const;

export type ApiPerpsChain = typeof API_PERPS_CHAINS[number];

/** Venue that lists and clears the perp (today equals `chain` for Hyperliquid). */
export const API_PERPS_PROVIDERS = ['hyperliquid'] as const;

export type ApiPerpsProvider = typeof API_PERPS_PROVIDERS[number];

/** Catalogue row id from `GET /perps/assets` (`hyperliquid:hl:BTC`, …). Used in all perps HTTP `asset` fields. */
export type ApiPerpsAssetId = string;

export type ApiPerpsPositionSide = 'long' | 'short';

/**
 * Where an open, increase or leverage change takes its margin from: a CCTP deposit from the wallet, or the book's
 * spendable HyperCore balance (`spendableUsdcByDex`).
 */
export type ApiPerpsFundingSource = 'wallet' | 'balance';

export type ApiPerpsExchangeSignature = {
  r: string;
  s: string;
  v: number;
};

export type ApiPerpsSignedExchangeAction = {
  action: Record<string, unknown>;
  nonce: number;
  signature: ApiPerpsExchangeSignature;
};

export type ApiPerpsExchangeTypedData = {
  domain: Record<string, unknown>;
  types: Record<string, Array<{ name: string; type: string }>>;
  primaryType: string;
  message: Record<string, unknown>;
};

export type ApiPerpsExchangeActionPayload = {
  hash: string;
  nonce: number;
  action: Record<string, unknown>;
  typedData: ApiPerpsExchangeTypedData;
};

export type ApiPerpsExchangeBuild = {
  /** Actual mid captured by the backend when constructing this market IOC order. */
  marketReferencePrice?: string;
  hash: string;
  nonce: number;
  action: Record<string, unknown>;
  typedData: ApiPerpsExchangeTypedData;
};

export type ApiPerpsPermitData = {
  domain: Record<string, unknown>;
  types: Record<string, unknown>;
  values: Record<string, unknown>;
};

export type ApiPerpsCctpBurnCall = {
  amount: string;
  destinationDomain: number;
  mintRecipient: string;
  destinationCaller: string;
  maxFee: string;
  minFinalityThreshold: number;
  hookData: string;
};

export type ApiPerpsCctpDeposit = {
  amountUsdc: string;
  feeUsdc: string;
  creditedAmountUsdc: string;
  burnCall: ApiPerpsCctpBurnCall;
  permitData: ApiPerpsPermitData;
  requiresPermitSignature: true;
  swap: ApiEvmSwapTransactionRequest;
};

export type ApiPerpsWithdrawPermit = {
  permitData: ApiPerpsPermitData;
  requiresPermitSignature: true;
  action: Record<string, unknown>;
  nonce: number;
  amountUsdc: string;
  forwardFeeUsdc?: string;
  destination: string;
};

export type ApiPerpsPosition = {
  coin: string;
  /** Venue-signed cumulative funding amounts, passed through unchanged; not normalized to positive income. */
  cumFunding?: { allTime: string; sinceChange: string; sinceOpen: string };
  entryPx: string | null;
  leverage: { type: string; value: number };
  liquidationPx: string | null;
  marginUsed: string;
  maxTradeSzs: [string, string];
  positionValue: string;
  returnOnEquity: string;
  szi: string;
  unrealizedPnl: string;
};

export type ApiPerpsSpotBalance = {
  coin: string;
  total?: string;
  hold?: string;
};

export type ApiPerpsSpotClearinghouseState = {
  balances?: ApiPerpsSpotBalance[];
};

export type ApiPerpsClearinghouseState = {
  address?: string;
  abstractionMode?: string;
  /** HyperCore spot USDC total (not in perps `marginSummary.accountValue`). */
  spotUsdcTotal?: string;
  spotUsdcAvailable?: string;
  /**
   * USDC an order in each book (`''` is the native book) can post as margin without a wallet deposit: free spot USDC
   * on unified and portfolio-margin accounts, the book's own `withdrawable` on standard accounts, `"0"` otherwise.
   */
  spendableUsdcByDex?: Record<string, string>;
  /** What Hyperliquid will charge on the account's first outbound transfer. `"0"` once paid. */
  firstTransferFeeUsdc?: string;
  spotClearinghouse?: ApiPerpsSpotClearinghouseState;
  assetPositions: Array<{ position: ApiPerpsPosition; type: string }>;
  crossMaintenanceMarginUsed: string;
  crossMarginSummary: {
    accountValue: string;
    totalMarginUsed: string;
    totalNtlPos: string;
    totalRawUsd: string;
  };
  marginSummary: {
    accountValue: string;
    totalMarginUsed: string;
    totalNtlPos: string;
    totalRawUsd: string;
  };
  time: number;
  withdrawable: string;
};

export type ApiPerpsGetPositionsRequest = {
  addressByChain: Partial<Record<ApiPerpsChain, string>>;
};

export type ApiPerpsGetPositionsResult = {
  positionsByChain: Partial<Record<ApiPerpsChain, ApiPerpsClearinghouseState>>;
};

export type ApiPerpsTradeActivity = ApiPerpsAssetActivity;

export type ApiPerpsActivityPageRequest = {
  startTime?: number;
  endTime?: number;
  cursor?: string;
  limit?: number;
};

export type ApiPerpsActivitiesSnapshot = {
  address: string;
  activities: ApiPerpsTradeActivity[];
  nextCursor?: string;
};

export type ApiPerpsGetActivitiesRequest = ApiPerpsActivityPageRequest & {
  addressByChain: Partial<Record<ApiPerpsChain, string>>;
};

export type ApiPerpsGetActivitiesResult = {
  activitiesByChain: Partial<Record<ApiPerpsChain, ApiPerpsActivitiesSnapshot>>;
};

export type ApiPerpsAssetContext = {
  percentChange24h?: number;
  fundingPercent?: string;
  fundingIntervalHours?: number;
  funding: string;
  openInterest: string;
  openInterestUsd?: string;
  prevDayPx: string;
  dayNtlVlm: string;
  premium: string;
  oraclePx: string;
  markPx: string;
  midPx: string | null;
  impactPxs: [string, string] | null;
  dayBaseVlm: string;
};

export type ApiPerpsListedAsset = {
  id: ApiPerpsAssetId;
  index: number;
  /** Canonical exchange action index resolved by the backend for this market. */
  wireAssetIndex?: number;
  /** Hyperliquid wire `coin` (display only — position/build routes use `id`). */
  name: string;
  chain: ApiPerpsChain;
  provider: ApiPerpsProvider;
  /** HIP-3 book id; empty string is the default Hyperliquid perps book. */
  dex: string;
  /** Display ticker (`xyz:TSLA` → `TSLA`). */
  symbol: string;
  /** Verified Hyperliquid icon URL, or null when the coin has no SVG. */
  image: string | null;
  /** Market accent derived from the asset icon, independent of price direction. */
  tintColor?: string;
  szDecimals: number;
  maxLeverage: number;
  marginTableId?: number;
  onlyIsolated?: boolean;
  isDelisted?: boolean;
  marginMode?: string;
  context: ApiPerpsAssetContext;
};

/** Enabled perps markets for one chain (sorted by dex, then universe index). */
export type ApiPerpsAssetsSnapshot = ApiPerpsListedAsset[];

export type ApiPerpsTradingAvailability = {
  isAvailable: boolean;
  reason?: 'PerpsTradingUnavailable' | 'PerpsUnsupportedAccount';
};

export type ApiPerpsMarketAsset = ApiPerpsListedAsset & {
  /** SDK trading support. Absent cached values do not establish availability. */
  tradingAvailability?: ApiPerpsTradingAvailability;
  displayName?: string;
  description?: string;
  label?: string;
  keywords?: string[];
  /** 1M close series, oldest first. Present on mover cards in `GET /perps/assets`. */
  sparkline?: number[];
};

export type ApiPerpsMarketSection = ApiMarketSection<ApiPerpsMarketAsset>;

/** Venue floors from `GET /perps/assets`. */
export type ApiPerpsLimits = {
  /** Gross CCTP deposit to open. The credit after the 0.2 fee meets `minPositionMarginUsdc`. */
  minOpenDepositUsdc: string;
  /**
   * An increase must be strictly greater than this (the CCTP fee).
   * The position minimum applies to the margin left after the change, not to this deposit.
   */
  minIncreaseDepositUsdc: string;
  /**
   * Margin an open position must still hold after a change. A partial reduce may not
   * leave less. Closing the position is the close flow.
   */
  minPositionMarginUsdc: string;
};

export type ApiPerpsOnboardingStory = {
  id: string;
  url: string;
  /** First frame of `url`, shown until the video has a frame of its own. */
  preview: string;
  /** Seconds. */
  duration: number;
  bytes: number;
};

export type ApiPerpsOnboarding = {
  stories: ApiPerpsOnboardingStory[];
};

export type ApiPerpsGetAssetsResult = {
  assetsByChain: Partial<Record<ApiPerpsChain, ApiPerpsAssetsSnapshot>>;
  /** An empty list means no market sections are shown. */
  sections: ApiPerpsMarketSection[];
  limitsByChain: Record<ApiPerpsChain, ApiPerpsLimits>;
  /** Absent from backends and cached catalogues that predate the onboarding stories. */
  onboarding?: ApiPerpsOnboarding;
};

/** Open perp on one catalogue asset. Omitted from `POST /perps/asset` when the leg is flat. */
export type ApiPerpsOpenPosition = {
  side: ApiPerpsPositionSide;
  size: string;
  leverage?: number;
  isCross: boolean;
  entryPrice?: string;
  markPrice?: string;
  liquidationPrice?: string;
  positionValue?: string;
  unrealizedPnl?: string;
  marginUsed?: string;
  returnOnEquity?: string;
};

export type ApiPerpsAssetActivityKind = 'open' | 'increase' | 'reduce' | 'close' | 'liquidation';

export type ApiPerpsAssetWithdrawalStatus = 'pending' | 'completed' | 'unavailable';

export type ApiPerpsAssetActivity = {
  id: string;
  orderId?: number;
  fillIds?: number[];
  assetId?: ApiPerpsAssetId;
  dex: string;
  kind: ApiPerpsAssetActivityKind;
  side: ApiPerpsPositionSide;
  timestamp: number;
  leverage?: number;
  isCross?: boolean;
  collateralBefore?: string;
  collateralAfter?: string;
  /** Absolute position size before an increase or reduce. */
  positionSizeBefore?: string;
  /** Absolute position size after an increase or reduce. */
  positionSizeAfter?: string;
  /**
   * USDC added to the position on an increase, or withdrawn on a reduce.
   * Absent when no bridge ledger row sits on the matching side of the fill.
   */
  transferredAmount?: string;
  deposit?: {
    grossAmount: string;
    bridgeFee: string;
    creditedAmount: string;
    txHash?: string;
  };
  withdrawal?: {
    amount: string;
    bridgeFee: string;
    receivedAmount: string;
    txHash?: string;
    status: ApiPerpsAssetWithdrawalStatus;
  };
  entryPrice?: string;
  exitPrice?: string;
  size?: string;
  notional?: string;
  realizedPnl?: string;
  fees?: {
    trading?: string;
    builder?: string;
    bridge?: string;
  };
  positionOpenedAt?: number;
};

export type ApiPerpsGetAssetRequest = {
  address: string;
  /** Catalogue row id from `GET /perps/assets`. */
  asset: ApiPerpsAssetId;
  chain: ApiPerpsChain;
  startTime?: number;
  endTime?: number;
  cursor?: string;
  limit?: number;
};

/** One catalogue asset, the caller's open leg on it, and that asset's activity. */
export type ApiPerpsAssetDetail = {
  address: string;
  asset: ApiPerpsMarketAsset;
  position?: ApiPerpsOpenPosition;
  activities: ApiPerpsAssetActivity[];
  nextCursor?: string;
};

export type ApiPerpsGetAssetChartRequest = {
  asset: ApiPerpsAssetId;
  chain: ApiPerpsChain;
  period: ApiPriceHistoryPeriod;
};

/**
 * Quote for the order ticket, before `/perps/position/build` or `/perps/position/modify/build`.
 * An open or increase sends `depositAmount`: the credit after the 0.2 fee is the margin, or the whole amount with
 * `fundingSource: 'balance'`, and the order notional is that margin times leverage. A reduce sends `depositAmount`
 * as the margin to release, which sizes its order; what the order frees is withdrawn to Arbitrum.
 */
export type ApiPerpsEstimatePositionRequest = {
  /** Quote the exact open size without partial-reduction minimums. */
  close?: boolean;
  chain: ApiPerpsChain;
  address: string;
  /** Catalogue row id from `GET /perps/assets`. */
  asset: ApiPerpsAssetId;
  /** Required for a new position. An open position uses its own side when omitted. */
  side?: ApiPerpsPositionSide;
  /**
   * Gross USDC about to be bridged, which must exceed the CCTP fee, the margin taken from the balance, or the
   * margin a reduce releases.
   */
  depositAmount?: number | string;
  reduceOnly?: boolean;
  leverage?: number;
  /** Required for a new position. An open position keeps its margin mode when omitted. */
  isCross?: boolean;
  /** `balance`: an open or increase posts the whole `depositAmount` from the balance. Not used with a reduce or close. */
  fundingSource?: ApiPerpsFundingSource;
};

/**
 * Quote for `POST /perps/position/modify/estimate`, before a leverage change is signed.
 * `depositAmount` is the gross USDC to bridge. The credit after the 0.2 fee is added
 * to the isolated position as margin. `"0"` when the new leverage needs no extra margin.
 */
export type ApiPerpsEstimateModifyPositionRequest = {
  chain: ApiPerpsChain;
  address: string;
  /** Catalogue row id from `GET /perps/assets`. */
  asset: ApiPerpsAssetId;
  leverage: number;
  /** `balance`: the extra margin comes from the book's spendable balance and `marginAmount` reports it. */
  fundingSource?: ApiPerpsFundingSource;
};

export type ApiPerpsEstimateModifyPositionResult = {
  /** Estimated USDC execution/bridge fees; excludes unquoted Arbitrum ETH gas. */
  estimatedFees?: ApiPerpsFees;
  /**
   * Gross CCTP deposit. The credit after the fee is the margin added to the position.
   * `"0"` when increasing leverage needs no top-up, and always with `fundingSource: 'balance'`.
   */
  depositAmount: string;
  /** Only with `fundingSource: 'balance'`: the margin the new leverage takes from the balance, `"0"` when none. */
  marginAmount?: string;
};

/** Hyperliquid order-ticket figures for the position this order would produce. */
export type ApiPerpsEstimatePositionResult = {
  /** Estimated USDC execution/bridge fees; absent if rates are unavailable. Excludes Arbitrum ETH gas. */
  estimatedFees?: ApiPerpsFees;
  /** Notional of this order at the reference price. `0` when only leverage changes. */
  orderValue: string;
  /**
   * Initial margin this order posts (`orderValue / leverage`).
   * `0` for a reduce. For a leverage-only change, the position's new initial margin.
   */
  marginRequired: string;
  /** Rounded order size, or the open size when only leverage changes. */
  size: string;
  /** Resulting position. Omitted when the order flattens it or the price cannot be resolved. */
  liquidationPrice?: string;
  /** The build of this order will carry `setAbstraction`, which the review has to show. */
  switchesToUnified?: boolean;
};

export type ApiPerpsBuildPositionRequest = {
  chain: ApiPerpsChain;
  address: string;
  asset: ApiPerpsAssetId;
  side: ApiPerpsPositionSide;
  /**
   * Gross USDC burned on Arbitrum via CCTP. The floor is `limitsByChain.minOpenDepositUsdc`.
   * The credit after the 0.2 fee is the margin; the order notional is that margin times `leverage`.
   */
  depositAmount: number | string;
  slippage?: number;
  leverage: number;
  isCross: boolean;
};

export type ApiPerpsBuildPositionResult = ApiPerpsExchangeBuild & {
  address: string;
  deposit: ApiPerpsCctpDeposit;
  approveBuilderFee?: ApiPerpsExchangeActionPayload;
  /**
   * Sign when present: CCTP often credits HyperCore spot; execute relays `usdClassTransfer`
   * before the perps order when the bridge credit is detected on spot.
   */
  spotToPerp?: ApiPerpsExchangeActionPayload;
  /**
   * Present when the order switches the account to Unified first: it never chose a mode and holds nothing the switch
   * could affect. Signed for this account only, and only when the reviewed quote has `switchesToUnified`. Execute
   * submits it once the deposit lands; `spotToPerp` still moves a deposit credited on spot if the switch is refused.
   */
  setAbstraction?: ApiPerpsExchangeActionPayload;
  /** Sign and submit before the open order (pairs with `leverage` / `isCross` on build). */
  updateLeverage: ApiPerpsExchangeActionPayload;
};

/**
 * USDC from the wallet onto the HyperCore balance. No position.
 * Sign `deposit` and broadcast the Arbitrum burn. When `spotToPerp` is present,
 * sign it and submit it through `/perps/position/execute` with this gross amount.
 */
export type ApiPerpsBuildDepositRequest = {
  chain: ApiPerpsChain;
  address: string;
  /** Gross USDC. Must exceed the 0.2 CCTP fee. The credit lands on HyperCore. */
  amount: number | string;
};

export type ApiPerpsBuildDepositResult = {
  address: string;
  deposit: ApiPerpsCctpDeposit;
  spotToPerp?: ApiPerpsExchangeActionPayload;
};

/**
 * USDC from the HyperCore balance back to the account wallet. No position.
 * Sign `typedData` and submit `action`, `nonce` and the signature through
 * `/perps/position/execute`.
 */
export type ApiPerpsBuildBalanceWithdrawRequest = {
  chain: ApiPerpsChain;
  address: string;
  /** Gross USDC to send. Must exceed the 0.2 CCTP fee and leave the gas reserve. */
  amount: number | string;
};

export type ApiPerpsBuildBalanceWithdrawResult = ApiPerpsExchangeActionPayload & {
  address: string;
};

/**
 * Open from USDC already on the perps balance. `/perps/position/build` is the open
 * that arrives together with a wallet deposit. This one has no `deposit` and no `spotToPerp`.
 */
export type ApiPerpsOpenPositionRequest = {
  chain: ApiPerpsChain;
  address: string;
  asset: ApiPerpsAssetId;
  side: ApiPerpsPositionSide;
  /** USDC margin taken from the free perps balance. Notional is this times `leverage`. */
  amount: number | string;
  slippage?: number;
  leverage: number;
  isCross: boolean;
};

export type ApiPerpsOpenPositionResult = ApiPerpsExchangeBuild & {
  address: string;
  approveBuilderFee?: ApiPerpsExchangeActionPayload;
  updateLeverage: ApiPerpsExchangeActionPayload;
};

export type ApiPerpsBuildModifyPositionRequest = {
  chain: ApiPerpsChain;
  address: string;
  asset: ApiPerpsAssetId;
  /**
   * Gross USDC. On an increase, a CCTP deposit strictly above `limitsByChain.minIncreaseDepositUsdc`:
   * the credit after the 0.2 fee is added margin, and the order is that margin times the position leverage.
   * The position must still hold `limitsByChain.minPositionMarginUsdc`.
   * On a reduce, the margin to release and the gross USDC withdrawn to Arbitrum (must exceed the
   * 0.2 fee). With `leverage`, the gross from `/perps/position/modify/estimate`: a positive amount
   * is bridged and added to the isolated position before `updateLeverage`. `"0"` needs no top-up.
   */
  depositAmount?: number | string;
  /** The USDC reviewed for a leverage change with `fundingSource: 'balance'`, added to an isolated position. */
  marginAmount?: string;
  reduceOnly?: boolean;
  slippage?: number;
  /** New leverage. Keeps the position's cross/isolated mode. Pair with the estimate `depositAmount`. */
  leverage?: number;
  /**
   * `balance`: nothing is bridged. An increase takes `depositAmount` from the book's spendable balance in full as
   * margin; a leverage change sends no `depositAmount`, and an isolated position's top-up is `updateIsolatedMargin`.
   * Not used with `reduceOnly`.
   */
  fundingSource?: ApiPerpsFundingSource;
};

export type ApiPerpsBuildModifyPositionResult = {
  address: string;
  deposit?: ApiPerpsCctpDeposit;
  approveBuilderFee?: ApiPerpsExchangeActionPayload;
  spotToPerp?: ApiPerpsExchangeActionPayload;
  /** Present when `leverage` is set on build. */
  updateLeverage?: ApiPerpsExchangeActionPayload;
  /**
   * Adds margin to the isolated position: the CCTP credit of a leverage decrease funded from the wallet, or the
   * top-up a balance-funded one takes from the balance. Sign and pass to execute with `updateLeverage`.
   */
  updateIsolatedMargin?: ApiPerpsExchangeActionPayload;
} & Partial<ApiPerpsExchangeBuild>;

export type ApiPerpsBuildClosePositionRequest = {
  chain: ApiPerpsChain;
  address: string;
  asset: ApiPerpsAssetId;
  slippage?: number;
};

export type ApiPerpsBuildWithdrawalRequest = {
  chain: ApiPerpsChain;
  address: string;
  asset: ApiPerpsAssetId;
  /** Original gross reduction amount. Omit only for recovery of a full close. */
  amountUsdc?: string;
};

export type ApiPerpsBuildWithdrawalResult = {
  address: string;
  withdraw?: ApiPerpsWithdrawPermit;
};

/** Signed HL wire action from close/build — `{ type: 'order', orders, grouping }`. */
export type ApiPerpsCloseOrderAction = {
  type: 'order';
  orders: unknown[];
  grouping: string;
};

export type ApiPerpsCloseWithdrawAction = {
  type: 'sendToEvmWithData';
};

export type ApiPerpsBuildClosePositionResult = ApiPerpsExchangeBuild & {
  address: string;
  action: ApiPerpsCloseOrderAction & Record<string, unknown>;
  /** Sign and send with `close/execute` while the account has not approved the builder fee. */
  approveBuilderFee?: ApiPerpsExchangeActionPayload;
};

export type ApiPerpsExecutePositionRequest = {
  chain: ApiPerpsChain;
  address: string;
  /** Omitted when execute submits `updateLeverage` without an order. */
  action?: Record<string, unknown>;
  nonce?: number;
  signature?: ApiPerpsExchangeSignature;
  approveBuilderFee?: ApiPerpsSignedExchangeAction;
  /**
   * Gross Arb CCTP amount from `build.deposit.amountUsdc`. Required for atomic open, for
   * increase-size modify, for a leverage decrease whose estimate is positive, and for a
   * balance deposit. Execute snapshots withdrawable, waits until CCTP credits HyperCore,
   * then submits HL actions. Omit when opening from the perps balance, when the leverage
   * estimate is `"0"`, for reduce-only, and for a HyperCore balance withdrawal.
   */
  depositAmount?: number | string;
  /** Signed `spotToPerp` from build — required on execute when CCTP credits spot USDC. */
  spotToPerp?: ApiPerpsSignedExchangeAction;
  /** Signed `setAbstraction` from build — submitted once the deposit lands, before anything else. */
  setAbstraction?: ApiPerpsSignedExchangeAction;
  /** Signed `updateLeverage` from build — submit before the open order when leverage was set on build. */
  updateLeverage?: ApiPerpsSignedExchangeAction;
  /**
   * Signed isolated-margin top-up from a leverage-decrease build. Execute submits it after
   * the CCTP credit is in perps margin and before `updateLeverage`.
   */
  updateIsolatedMargin?: ApiPerpsSignedExchangeAction;
  /**
   * `balance`: the build took its margin from the HyperCore balance. Execute refuses `depositAmount` and
   * `spotToPerp`, and accepts `updateIsolatedMargin` only with the `updateLeverage` of the same asset and no order.
   */
  fundingSource?: ApiPerpsFundingSource;
};

export type ApiPerpsCctpCreditSurface = 'perps_withdrawable' | 'spot_usdc';

export type ApiPerpsExecuteDepositWait = {
  status: 'credited';
  grossDepositAmountUsdc: string;
  creditedAmountUsdc: string;
  baselineWithdrawableUsdc: string;
  creditSurface?: ApiPerpsCctpCreditSurface;
  waitedMs: number;
};

export type ApiPerpsExecutePositionResult = {
  address: string;
  oid?: number;
  status: string;
  filledSize?: string;
  avgPrice?: string;
  approveBuilderFee?: Record<string, unknown>;
  updateLeverage?: Record<string, unknown>;
  updateIsolatedMargin?: Record<string, unknown>;
  /** Present when execute waited for CCTP before submitting Hyperliquid actions. */
  depositWait?: ApiPerpsExecuteDepositWait;
  rawResponse: Record<string, unknown>;
};

export type ApiPerpsExecuteClosePositionRequest = {
  chain: ApiPerpsChain;
  address: string;
  /** Required for phase 1 (`action.type === 'order'` from close/build). Omit for CCTP withdraw. */
  asset?: ApiPerpsAssetId;
  action: Record<string, unknown>;
  nonce: number;
  signature: ApiPerpsExchangeSignature;
  /** Arb recipient for CCTP after close; defaults to `address` on the backend. */
  destination?: string;
  /** Partial reduce from modify/build — skip flat wait before optional CCTP withdraw. */
  skipPositionFlatWait?: boolean;
  approveBuilderFee?: ApiPerpsSignedExchangeAction;
};

export type ApiPerpsExecuteClosePhase = 'awaiting_withdraw_signature' | 'completed' | 'withdraw_unavailable';

export type ApiPerpsExecuteCloseSettleWait = {
  status: 'position_flat';
  asset: ApiPerpsAssetId;
  waitedMs: number;
};

export type ApiPerpsExecuteClosePositionResult = {
  address: string;
  phase: ApiPerpsExecuteClosePhase;
  close?: ApiPerpsExecutePositionResult;
  /** CCTP withdraw payload after phase-1 settle — sign `permitData`, then phase-2 execute. */
  withdraw?: ApiPerpsWithdrawPermit;
  closeSettleWait?: ApiPerpsExecuteCloseSettleWait;
  withdrawResult?: ApiPerpsExecutePositionResult;
};

export type ApiPerpsModifyPositionResult =
  | (ApiPerpsExecutePositionResult & { depositTxHash?: string })
  | { error: string };
