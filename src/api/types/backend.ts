import type { DieselStatus } from '../../global/types';
import type { StakingPoolConfig } from '../chains/ton/contracts/JettonStaking/StakingPool';
import type { ApiTonWalletVersion } from '../chains/ton/types';
import type { ApiCountryCode, ApiLoyaltyType, ApiMtwCardType, ApiTokenWithPrice } from './misc';

export type ApiTokenDetails = Pick<ApiTokenWithPrice, 'slug' | 'type' | 'priceUsd' | 'percentChange24h'>;

export type ApiSwapDexLabel = 'dedust' | 'ston';

export type ApiSwapEstimateRequest = {
  from: string;
  to: string;
  slippage: number;
  fromAmount?: string;
  toAmount?: string;
  fromAddress: string;
  shouldTryDiesel?: boolean;
  swapVersion?: 1 | 2;
  toncoinBalance?: string;
  walletVersion?: ApiTonWalletVersion;
  isFromAmountMax?: boolean;
};

export type ApiSwapMinter = 'native' | `jetton:${string}`; // jetton:<raw_address>

export type ApiSwapProtocol = ([
  'dedust',
  'stonfi_v1',
  'stonfi_v2',
  'tonco',
  'memeslab',
  'tonfun',
])[number];

export type ApiSwapRoute = {
  pool_address: string;
  is_stable: boolean;
  in_minter: ApiSwapMinter;
  out_minter: ApiSwapMinter;
  in_amount: string;
  out_amount: string;
  network_fee: string;
  protocol_slug: ApiSwapProtocol;
};

export type ApiSwapEstimateVariant = {
  fromAmount: string;
  toAmount: string;
  toMinAmount: string;
  impact: number;
  dexLabel: ApiSwapDexLabel;
  other?: ApiSwapEstimateVariant[];
  routes?: ApiSwapRoute[][];
  // Fees
  networkFee: string;
  realNetworkFee: string;
  swapFee: string;
  swapFeePercent: number;
  ourFee: string;
  dieselFee?: string;
};

export type ApiSwapEstimateResponse = ApiSwapEstimateRequest & {
  toAmount: string;
  fromAmount: string;
  toMinAmount: string;
  impact: number;
  dexLabel: ApiSwapDexLabel;
  dieselStatus: DieselStatus;
  other?: ApiSwapEstimateVariant[]; // Only in V2
  routes?: ApiSwapRoute[][]; // Only in V3
  // Fees
  networkFee: string;
  realNetworkFee: string;
  swapFee: string;
  swapFeePercent: number;
  ourFee: string;
  ourFeePercent: number;
  dieselFee?: string;
};

export type ApiSwapBuildRequest = Pick<ApiSwapEstimateResponse,
  'from'
  | 'to'
  | 'fromAddress'
  | 'dexLabel'
  | 'fromAmount'
  | 'toAmount'
  | 'toMinAmount'
  | 'slippage'
  | 'shouldTryDiesel'
  | 'swapVersion'
  | 'networkFee'
  | 'swapFee'
  | 'ourFee'
  | 'dieselFee'
  | 'routes'
> & {
  walletVersion?: ApiTonWalletVersion;
};

export type ApiSwapTransfer = {
  toAddress: string;
  amount: string;
  payload: string;
};

export type ApiSwapBuildResponse = {
  id: string;
  transfers: ApiSwapTransfer[];
};

// Swap assets and history
export type ApiSwapAsset = {
  name: string;
  symbol: string;
  chain: string;
  slug: string;
  decimals: number;
  isPopular: boolean;
  priceUsd: number;
  image?: string;
  tokenAddress?: string;
  keywords?: string[];
  color?: string;
  /** A small dim label to show in the UI right after the token name */
  label?: string;
};

export type ApiSwapPairAsset = {
  symbol: string;
  slug: string;
  contract?: string;
  isReverseProhibited?: boolean;
};

export type ApiSwapHistoryItem = BaseApiSwapHistoryItem & {
  id: string;
  timestamp: number;
  lt?: number;
  ourFee?: string;
  /**
   * Swap confirmation status
   * Both 'pendingTrusted' and 'pending' mean the swap is awaiting confirmation by the blockchain.
   * - 'pendingTrusted' — awaiting confirmation and trusted (initiated by our app).
   * - 'pending' — awaiting confirmation from an external/unauthenticated source.
   * - 'confirmed' — included in a shardblock but not yet finalized in the masterchain.
   *
   * There are two backends: ToncenterApi and our backend.
   * Swaps returned by ToncenterApi have the status 'pending'.
   * Swaps returned by our backend also have the status 'pending', but they are meant to be 'pendingTrusted'.
   * When an activity reaches the `GlobalState`, it already has the correct status set.
   *
   * TODO: Replace the status 'pending' with 'pendingTrusted' on our backend once all clients are updated.
   */
  status: 'pending' | 'pendingTrusted' | 'confirmed' | 'completed' | 'failed' | 'expired';
  hashes: string[];
  isCanceled?: boolean;
  cex?: {
    /** The address to send the "from" token to */
    payinAddress: string;
    /** The address where the "to" token will be sent to */
    payoutAddress: string;
    /** The memo to use with the "from" token sending transaction */
    payinExtraId?: string;
    status: ApiSwapCexTransactionStatus;
    transactionId: string;
  };
};

export type BaseApiSwapHistoryItem = {
  from: string;
  fromAmount: string;
  fromAddress: string;
  to: string;
  toAmount: string;
  /** The real fee in the chain's native token */
  networkFee: string;
  swapFee: string;
};

// Cross-chain centralized swap
type ApiSwapCexTransactionStatus = 'new' | 'waiting' | 'confirming' | 'exchanging' | 'sending' | 'finished'
  | 'failed' | 'refunded' | 'hold' | 'overdue' | 'expired';

export type ApiSwapCexEstimateRequest = {
  from: string;
  fromAmount: string;
  to: string;
};

export type ApiSwapCexEstimateResponse = {
  from: string;
  fromAmount: string;
  to: string;
  toAmount: string;
  swapFee: string;
  // additional
  fromMin: string;
  fromMax: string;
};

export type ApiSwapCexCreateTransactionRequest = {
  from: string;
  fromAmount: string;
  /** Always TON address */
  fromAddress: string;
  to: string;
  /** Any chain address */
  toAddress: string;
  payoutExtraId?: string;
  /** From the estimate request */
  swapFee: string;
  /** Measured in the "from" chain's native token */
  networkFee?: string;
};

export type ApiSwapCexCreateTransactionResponse = {
  request: ApiSwapCexCreateTransactionRequest;
  swap: ApiSwapHistoryItem;
};

// Staking
export type ApiStakingJettonPool = {
  pool: string;
  poolConfig: StakingPoolConfig;
  token: string;
  periods: {
    period: number;
    unstakeCommission: number;
    token: string;
  }[];
};

/** Note: all the timestamps are in Unix seconds */
export type ApiStakingCommonResponse = {
  liquid: {
    currentRate: number;
    nextRoundRate: number;
    collection?: string;
    apy: number;
    /** The string is a floating point number */
    available: string;
    loyaltyApy: Record<ApiLoyaltyType, number>;
  };
  round: {
    start: number;
    end: number;
    unlock: number;
  };
  prevRound: {
    start: number;
    end: number;
    unlock: number;
  };
  jettonPools: Omit<ApiStakingJettonPool, 'poolConfig'>[];
  ethena: {
    apy: number;
    apyVerified: number;
    rate: number;
    isDisabled?: boolean;
  };
};

/** Note: all timestamps are in Unix milliseconds */
export type ApiStakingCommonData = Override<ApiStakingCommonResponse, {
  liquid: Override<ApiStakingCommonResponse['liquid'], {
    available: bigint;
  }>;
  jettonPools: ApiStakingJettonPool[];
}>;

export type ApiSite = {
  url: string;
  name: string;
  icon: string;
  manifestUrl: string;
  description: string;
  canBeRestricted: boolean;
  isExternal: boolean;
  isFeatured?: boolean;
  isVerified?: boolean;
  categoryId?: number;

  extendedIcon?: string;
  badgeText?: string;
  withBorder?: boolean;
  borderColor?: [string, string?];
};

export type ApiSiteCategory = {
  id: number;
  name: string;
};

// Prices
export type ApiPriceHistoryPeriod = '1D' | '7D' | '1M' | '3M' | '1Y' | 'ALL';

// Vesting
export type ApiVestingPartStatus = 'frozen' | 'ready' | 'unfrozen' | 'missed';

export type ApiVestingInfo = {
  id: number;
  title: string;
  startsAt: Date;
  initialAmount: number;
  parts: {
    id: number;
    time: string;
    timeEnd: string;
    amount: number;
    status: ApiVestingPartStatus;
  }[];
};

export type ApiCardInfo = {
  all: number;
  notMinted: number;
  price: number;
};

export type ApiCardsInfo = Record<ApiMtwCardType, ApiCardInfo>;

export type ApiAccountConfig = {
  cardsInfo?: ApiCardsInfo;
  activePromotion?: ApiPromotion;
};

export type ApiSwapVersion = 2 | 3;

export type ApiPromotion = {
  id: string;
  kind: 'cardOverlay';
  cardOverlay: {
    mascotIcon?: {
      url: string;
      top: number;
      right: number;
      height: number;
      width: number;
      rotation: number;
    };
    onClickAction: 'openPromotionModal' | 'openMintCardModal';
  };
  modal?: {
    backgroundImageUrl: string;
    backgroundFallback: string;
    heroImageUrl?: string;
    title: string;
    titleColor?: string;
    description: string;
    descriptionColor?: string;
    availabilityIndicator?: string;
    actionButton?: {
      title: string;
      url: string;
    };
  };
};

export type ApiBackendConfig = {
  isLimited: boolean;
  isCopyStorageEnabled?: boolean;
  supportAccountsCount?: number;
  now: number;
  country: ApiCountryCode;
  isUpdateRequired: boolean;
  isVestingEnabled?: boolean;
  isWebSocketEnabled?: boolean;
  swapVersion?: ApiSwapVersion;
  seasonalTheme?: 'newYear' | 'valentine';
};
