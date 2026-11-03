import type {
  ApiPerpsBuildClosePositionRequest,
  ApiPerpsBuildModifyPositionRequest,
  ApiPerpsBuildPositionRequest,
  ApiPerpsLimits,
  ApiPerpsMarketAsset,
  ApiPerpsMarketSection,
  ApiPerpsPosition,
  ApiPerpsPositionSide,
  ApiPerpsTradeActivity,
  ApiPerpsTradingAvailability,
} from './perps';

export type ApiPerpsOperationKind = 'open' | 'increase' | 'reduce' | 'close' | 'leverage';

export type ApiPerpsFees = {
  exchange?: string;
  service?: string;
  trading: string;
  bridge?: string;
  total: string;
};

export type ApiPerpsLeverageEstimate = { leverage: number; liquidationPrice?: string };

export type ApiPerpsFundingRequirements = {
  requiredUsdc: string;
  requiredEth: string;
  /** Approximate display value of the gas reserve, not an execution fee quote. */
  requiredEthUsd: string;
  usdcBalance: string;
  /** Maximum opening collateral after the shared deposit bridge fee. */
  availableCollateral?: string;
  ethBalance: string;
  needsUsdc: boolean;
  needsEth: boolean;
};

export type ApiPerpsReceiptDetails = {
  fees?: ApiPerpsFees;
  /** Net USDC delivered after the withdrawal bridge fee. */
  receiveAmount?: string;
  /** USDC deposited by this operation that was not allocated to the position or spent on fees. */
  remainingCollateral?: string;
};

/** Normalized account position with collateral and P&L separate from position notional. */
export type ApiPerpsAccountPosition = {
  id: string;
  assetId: string;
  dex: string;
  side: ApiPerpsPositionSide;
  size: string;
  collateral: string;
  equity: string;
  isNearLiquidation?: boolean;
  returnOnEquity?: string;
  /** Raw Hyperliquid cumFunding.sinceOpen, with the venue's sign preserved (not positive-income normalized). */
  funding?: string;
  raw: ApiPerpsPosition;
};

export type ApiPerpsMarketSnapshot = {
  assets: ApiPerpsMarketAsset[];
  marketSections: ApiPerpsMarketSection[];
  limits: ApiPerpsLimits;
  /** Original catalogue fetch time; zero when freshness cannot be established. */
  assetsFetchedAt: number;
};

/** Account snapshot shared by web, iOS, and Android. Monetary values are decimal strings in USD. */
export type ApiPerpsSnapshot = ApiPerpsMarketSnapshot & {
  abstractionMode?: string;
  spotUsdcTotal?: string;
  spotUsdcAvailable?: string;
  withdrawable?: string;
  /** Account signing support, independent of balances and market availability. */
  tradingAvailability?: ApiPerpsTradingAvailability;
  positions: ApiPerpsAccountPosition[];
  totalEquity: string;
  totalPnl: string;
  totalReturnOnEquity?: string;
  timestamp: number;
  unavailableDexs: string[];
};

export type ApiPerpsDraftRequest = {
  assetId: string;
  side: ApiPerpsPositionSide;
  amount: string;
  unit: 'currency' | 'asset';
  leverage: number;
  editing?: boolean;
  /** Change leverage while preserving the current position size. */
  leverageOnly?: boolean;
  close?: boolean;
  fraction?: number;
  reset?: boolean;
  convertFrom?: 'currency' | 'asset';
};

/** Gross deposit or released-margin inputs, resolved against the latest account position by the SDK. */
export type ApiPerpsTradeIntent =
  | { kind: 'open'; assetId: string; side: ApiPerpsPositionSide; depositAmount: string; leverage: number }
  | { kind: 'increase' | 'reduce'; assetId: string; amount: string }
  | { kind: 'leverage'; assetId: string; leverage: number }
  | { kind: 'close'; assetId: string };

export type ApiPerpsQuote = {
  id: string;
  accountId: string;
  assetId: string;
  /** Canonical exchange index pinned from the catalogue used for this review. */
  wireAssetIndex?: number;
  kind: ApiPerpsOperationKind | 'unchanged';
  side: ApiPerpsPositionSide;
  leverage: number;
  previousLeverage?: number;
  isCross: boolean;
  inputAmount: string;
  currentInputAmount?: string;
  collateral: string;
  previousCollateral?: string;
  estimatedCollateral?: string;
  estimatedFees?: ApiPerpsFees;
  fundingRequirements?: ApiPerpsFundingRequirements;
  previousFunding?: string;
  equity?: string;
  /** Current unrealized P&L, before execution/withdrawal fees; never the position equity. */
  profitLoss?: string;
  returnOnEquity?: string;
  size: string;
  previousSize?: string;
  orderSize?: string;
  notional: string;
  previousNotional?: string;
  markPrice: string;
  entryPrice?: string;
  /** Current position's liquidation price, not the reviewed target position's price. */
  liquidationPrice?: string;
  /** Backend estimate of the liquidation price after the reviewed order. */
  estimatedLiquidationPrice?: string;
  paymentAmount: string;
  /** Released margin cannot be quoted until the reduce/close has settled. */
  receiveStatus?: 'pending' | 'available';
  bridgeFee: string;
  expiresAt: number;
  createdAt: number;
  open?: ApiPerpsBuildPositionRequest;
  modify?: ApiPerpsBuildModifyPositionRequest;
  close?: ApiPerpsBuildClosePositionRequest;
};

export type ApiPerpsOperation = {
  id: string;
  accountId: string;
  assetId: string;
  kind: ApiPerpsOperationKind;
  state: 'running' | 'completed' | 'partial' | 'unknown' | 'failed';
  stage: 'preparing' | 'deposit' | 'trade' | 'withdrawal' | 'finished';
  createdAt: number;
  depositTxHash?: string;
  /** Explicit user acknowledgement releases the trading lock without resolving or replaying this operation. */
  acknowledgedAt?: number;
  orderId?: number;
  /** Venue response retained for rejection diagnostics and read-only reconciliation. */
  orderStatus?: string;
  filledSize?: string;
  positionSize?: string;
  averagePrice?: string;
  withdrawalAmount?: string;
  /** Exact gross released by a reduction; retained for withdrawal-only recovery. */
  withdrawalRequestedAmount?: string;
  error?: string;
};

export type ApiPerpsFill = {
  activityId?: string;
  assetId?: string;
  leverage?: number;
  collateralBefore?: string;
  collateralAfter?: string;
  /** USDC added on an increase or withdrawn on a reduce. Absent without a matching bridge row. */
  transferredAmount?: string;
  deposit?: ApiPerpsTradeActivity['deposit'];
  withdrawal?: ApiPerpsTradeActivity['withdrawal'];
  bridgeFee?: string;
  receiptFees?: ApiPerpsFees;
  coin: string;
  tid?: number;
  oid?: number;
  time: number;
  px?: string;
  sz?: string;
  side?: string;
  dir?: string;
  startPosition?: string;
  closedPnl?: string;
  fee?: string;
  feeToken: string;
  /** Included in `fee`, never added to it a second time. */
  builderFee?: string;
  /** Omitted for an aggregate spanning different execution hashes. */
  hash?: string;
  eventKind?: 'opened' | 'increased' | 'reduced' | 'closed' | 'liquidated';
  positionSide?: 'long' | 'short';
  netPnl?: string;
  /** Executed quantity × fill price; this is trade notional, not collateral. */
  notional?: string;
  previousSize?: string;
  positionSize?: string;
  /** Before/after sizes valued at this execution's price, not historical margin. */
  previousNotional?: string;
  positionNotional?: string;
  endPosition?: string;
  /** Weighted entry observed in a continuous fill history; absent for truncated histories. */
  entryPrice?: string;
  /** Only populated when the fetched fills contain a continuous position history from its open. */
  positionOpenedAt?: number;
  fillIds?: number[];
  liquidation?: { liquidatedUser?: string; markPx: string; method: string };
};

export type ApiPerpsRawFill = ApiPerpsFill & Required<Pick<ApiPerpsFill,
  'tid' | 'oid' | 'px' | 'sz' | 'side' | 'dir' | 'startPosition' | 'closedPnl' | 'fee'>>;

export type ApiPerpsCashFlow = {
  id: string;
  kind: 'funding' | 'deposit' | 'withdrawal' | 'transfer';
  direction: 'incoming' | 'outgoing' | 'internal';
  time: number;
  /** Unsigned token quantity; direction describes its effect on the user's perpetuals balance. */
  amount: string;
  token: string;
  coin?: string;
  assetId?: string;
  positionSide?: 'long' | 'short';
  fundingRate?: string;
  positionSize?: string;
  sourceDex?: string;
  destinationDex?: string;
  sourceAddress?: string;
  destinationAddress?: string;
  fees: { amount: string; token: string }[];
  hash?: string;
};

export type ApiPerpsActivityHistory = {
  fills: ApiPerpsFill[];
  cashFlows: ApiPerpsCashFlow[];
  nextCursor?: string;
  hasActivity?: boolean;
};
