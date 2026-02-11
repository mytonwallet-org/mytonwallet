import type { ApiSwapDexLabel, ApiSwapHistoryItem } from './backend';
import type { ApiNetwork, ApiNftMarketplace, ApiTransaction } from './misc';

type BaseActivity = {
  id: string;
  shouldHide?: boolean;
  /** Trace external message hash normalized. Not unique but doesn't change in pending activities. Only for TON. */
  externalMsgHashNorm?: string;
  /** Whether the activity data should be re-loaded to get the necessary data before showing in the activity list */
  shouldReload?: boolean;
  /**
   * Whether more details should be loaded by calling the `fetchTonActivityDetails` action when the activity modal is
   * open. Undefined means "no".
   */
  shouldLoadDetails?: boolean;
  extra?: {
    withW5Gasless?: boolean; // Only for TON
    dex?: ApiSwapDexLabel; // Only for TON liquidity deposit and withdrawal
    marketplace?: ApiNftMarketplace;
    /** Request identifier from the underlying message where available (TON only) */
    queryId?: string;
    /** Marks hidden transfers that include the MyTonWallet swap fee */
    isOurSwapFee?: boolean;
    /** Aggregated swap marker used to merge internal aggregator routes */
    mtwAggregator?: {
      traceId: string;
      swapIds: string[];
      from: string;
      to: string;
    };
    // TODO Move other extra fields here (externalMsgHash, ...)
  };
};

export type ApiTransactionActivity = BaseActivity & ApiTransaction & {
  kind: 'transaction';
};

export type ApiSwapActivity = BaseActivity & ApiSwapHistoryItem & {
  kind: 'swap';
};

export type ApiActivity = ApiTransactionActivity | ApiSwapActivity;

export type ApiFetchActivitySliceOptions = {
  accountId: string;
  tokenSlug?: string;
  /** If neither of the timestamps is set, the method must load the latest activities */
  toTimestamp?: number;
  fromTimestamp?: number;
  limit?: number;
};

export type ApiDecryptCommentOptions = {
  accountId: string;
  activity: ApiTransactionActivity & Required<Pick<ApiTransactionActivity, 'encryptedComment'>>;
  password?: string;
};

export type ApiFetchTransactionByIdOptions = {
  network: ApiNetwork;
  walletAddress: string;
  txId: string;
} | {
  network: ApiNetwork;
  walletAddress: string;
  txHash: string;
};
