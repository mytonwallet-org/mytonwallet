import type {
  ApiPerpsBuildClosePositionRequest,
  ApiPerpsBuildModifyPositionRequest,
  ApiPerpsBuildPositionRequest,
  ApiPerpsFundingSource,
  ApiPerpsLimits,
  ApiPerpsMarketAsset,
  ApiPerpsMarketSection,
  ApiPerpsOnboarding,
  ApiPerpsOpenPositionRequest,
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
  /** Hyperliquid's fee on the account's first outbound transfer, when a withdrawal the order makes pays it. */
  firstTransfer?: string;
  total: string;
};

export type ApiPerpsLeverageEstimate = { leverage: number; liquidationPrice?: string };

/** A balance draft needs no wallet funds: its required amounts are `"0"` and no wallet balance is read. */
export type ApiPerpsFundingRequirements = {
  requiredUsdc: string;
  /** The CCTP bridge fee that `requiredUsdc` includes. `"0"` when nothing is bridged. */
  requiredBridgeFeeUsdc: string;
  /** Paymaster cost in USDC when the deposit is gasless. `"0"` when the wallet pays gas in ETH. */
  requiredGasUsdc: string;
  /** Deposit gas in ETH when the wallet pays it. `"0"` when the deposit is gasless or deposits nothing. */
  requiredEth: string;
  /** USD value of `requiredEth`. */
  requiredEthUsd: string;
  /** Arbitrum wallet USDC, or the book's spendable HyperCore USDC for a balance draft. */
  usdcBalance: string;
  /**
   * Maximum opening collateral: wallet USDC after the shared deposit bridge fee, or for a balance draft the book's
   * spendable USDC after trading-fee headroom at the draft's leverage.
   */
  availableCollateral?: string;
  /** Arbitrum wallet ETH; `"0"` for a balance draft. */
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
  /** Net funding since the position opened: positive was received, negative was paid. */
  funding?: string;
  raw: ApiPerpsPosition;
};

export type ApiPerpsMarketSnapshot = {
  assets: ApiPerpsMarketAsset[];
  marketSections: ApiPerpsMarketSection[];
  limits: ApiPerpsLimits;
  /** Original catalogue fetch time; zero when freshness cannot be established. */
  assetsFetchedAt: number;
  onboarding?: ApiPerpsOnboarding;
};

/**
 * What one withdrawal can send from the HyperCore balance to the wallet. The backend debits a single source, native
 * `withdrawable` or free spot USDC, and keeps its gas reserve and any first transfer fee there.
 */
export type ApiPerpsBalanceWithdrawalPreview = {
  /** The larger source. Money in the other one takes a second withdrawal. */
  balance: string;
  /** Gross USDC sent: `balance` less the gas reserve and `firstTransferFee`. */
  amount: string;
  /** CCTP forwarding fee taken from `amount`. */
  bridgeFee: string;
  /** Hyperliquid's fee on the account's first outbound transfer, debited on top of `amount`. Absent once it is paid. */
  firstTransferFee?: string;
  /** Net USDC delivered: `amount` less `bridgeFee`. */
  receiveAmount: string;
};

export type ApiPerpsBalanceWithdrawalQuote = ApiPerpsBalanceWithdrawalPreview & {
  id: string;
  accountId: string;
  /** The account's Arbitrum wallet, which receives the USDC. */
  destination: string;
  expiresAt: number;
};

/** The account's positions, totals and Hyperliquid balances. Monetary values are decimal strings in USD. */
export type ApiPerpsAccountSnapshot = {
  abstractionMode?: string;
  /** USDC each book (`''` is the native book) can post as margin from the HyperCore balance; missing means none. */
  spendableUsdcByDex?: Record<string, string>;
  /** Absent unless the balance exceeds the minimum a withdrawal is offered for. */
  balanceWithdrawal?: ApiPerpsBalanceWithdrawalPreview;
  /** Account signing support, independent of balances and market availability. */
  tradingAvailability?: ApiPerpsTradingAvailability;
  positions: ApiPerpsAccountPosition[];
  totalEquity: string;
  totalPnl: string;
  totalReturnOnEquity?: string;
  timestamp: number;
  unavailableDexs: string[];
};

/** Account snapshot shared by web, iOS, and Android, together with the market catalogue it was resolved against. */
export type ApiPerpsSnapshot = ApiPerpsMarketSnapshot & ApiPerpsAccountSnapshot;

export type ApiPerpsDraftRequest = {
  assetId: string;
  side: ApiPerpsPositionSide;
  amount: string;
  leverage: number;
  editing?: boolean;
  /** Change leverage while preserving the current position size. */
  leverageOnly?: boolean;
  close?: boolean;
  fraction?: number;
  reset?: boolean;
  /** Margin source of an open, increase or leverage change; absent means the wallet. Reductions ignore it. */
  funding?: ApiPerpsFundingSource;
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
  collateral: string;
  previousCollateral?: string;
  /** Margin of the resulting position: the previous margin plus the backend estimate's `marginRequired`. */
  estimatedCollateral?: string;
  /**
   * Deposited USDC left free on Hyperliquid after the order's margin and estimated trading fees. Set only when the
   * margin and the fees are both estimated and the result is not negative, and never on a balance-funded quote.
   */
  estimatedRemainingCollateral?: string;
  /** USDC a reduce or close should deliver to the wallet after trading and bridge fees. */
  estimatedReceiveAmount?: string;
  estimatedFees?: ApiPerpsFees;
  /** Arbitrum gas of the deposit userOp, in ETH. Set when the wallet pays that gas. */
  estimatedNetworkFeeEth?: string;
  /** USD value of `estimatedNetworkFeeEth`; absent while the ETH price is unknown. */
  estimatedNetworkFeeUsd?: string;
  /** Paymaster cost of the deposit, in USDC. Set when the wallet pays gas in USDC. */
  estimatedNetworkFeeUsdc?: string;
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
  /** Gross wallet deposit, or the margin a balance-funded quote takes from the HyperCore balance. */
  paymentAmount: string;
  /** Released margin cannot be quoted until the reduce/close has settled. */
  receiveStatus?: 'pending' | 'available';
  /**
   * CCTP forwarding fee of the quote's bridge leg: a deposit, or the withdrawal of a reduce or close. `"0"` on a
   * balance-funded quote.
   */
  bridgeFee: string;
  /** Set on an open, increase or leverage change paid from the HyperCore balance, which deposits nothing. */
  funding?: 'balance';
  /** The order also switches the whole Hyperliquid account to Unified. A build must agree, and the review shows it. */
  switchesToUnified?: boolean;
  expiresAt: number;
  createdAt: number;
  open?: ApiPerpsBuildPositionRequest;
  /** A balance-funded open, built through `/perps/position/open`. */
  openFromBalance?: ApiPerpsOpenPositionRequest;
  modify?: ApiPerpsBuildModifyPositionRequest;
  close?: ApiPerpsBuildClosePositionRequest;
};

export type ApiPerpsOperation = {
  id: string;
  accountId: string;
  /** `PERPS_BALANCE_WITHDRAWAL_ASSET_ID` for a `withdraw`, which involves no market. */
  assetId: string;
  kind: ApiPerpsOperationKind | 'withdraw';
  state: 'running' | 'completed' | 'partial' | 'unknown' | 'failed';
  stage: 'preparing' | 'deposit' | 'trade' | 'withdrawal' | 'finished';
  createdAt: number;
  depositTxHash?: string;
  /** Explicit user acknowledgement releases the trading lock without resolving or replaying this operation. */
  acknowledgedAt?: number;
  orderId?: number;
  /** Size of the order sent to Hyperliquid. A trade found by reconciliation is a partial fill when it is smaller. */
  submittedOrderSize?: string;
  /** Venue response retained for rejection diagnostics and read-only reconciliation. */
  orderStatus?: string;
  filledSize?: string;
  positionSize?: string;
  averagePrice?: string;
  withdrawalAmount?: string;
  /** Exact gross released by a reduction; retained for withdrawal-only recovery. */
  withdrawalRequestedAmount?: string;
  /** The figures the user reviewed for a `withdraw`. */
  balanceWithdrawal?: ApiPerpsBalanceWithdrawalQuote;
  error?: string;
};

export type ApiPerpsFill = {
  /** Backend event ID of the grouped trade. */
  activityId: string;
  assetId?: string;
  leverage?: number;
  collateralBefore?: string;
  collateralAfter?: string;
  deposit?: ApiPerpsTradeActivity['deposit'];
  withdrawal?: ApiPerpsTradeActivity['withdrawal'];
  bridgeFee?: string;
  receiptFees?: ApiPerpsFees;
  coin: string;
  oid?: number;
  time: number;
  px?: string;
  sz?: string;
  closedPnl?: string;
  fee?: string;
  feeToken: string;
  eventKind: 'opened' | 'increased' | 'reduced' | 'closed' | 'liquidated';
  positionSide: 'long' | 'short';
  netPnl?: string;
  /** Executed quantity × fill price; this is trade notional, not collateral. */
  notional?: string;
  previousSize?: string;
  positionSize?: string;
  /** Before/after sizes valued at this execution's price, not historical margin. */
  previousNotional?: string;
  positionNotional?: string;
  entryPrice?: string;
  positionOpenedAt?: number;
};

export type ApiPerpsActivityHistory = {
  fills: ApiPerpsFill[];
  nextCursor?: string;
  /** True when the page has any trade, rendered or not, or older pages. */
  hasActivity: boolean;
};
