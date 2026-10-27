import type { SignedMfaRequest } from '../chains/ton/util/signer';
import type { ApiSwapActivity } from './activities';
import type {
  ApiEvmSwapCall,
  ApiEvmSwapTransactionRequest,
  ApiSwapBuildTransactionRequest,
  ApiSwapExecuteTransactionResult,
  ApiSwapHistoryItem,
  ApiSwapTransfer,
} from './backend';
import type { ApiChain, ApiNetwork, ApiToken } from './misc';

/** A validated Uranus buy needs one fresh quote before another build can be signed. */
export const URANUS_PRICE_DRIFT_ERROR = 'uranus-price-drift';
export const SWAP_ROUTERS_UNAVAILABLE_ERROR = 'Swap routers are unavailable';

export type ApiSwapDefaultsRequest = {
  tokenIn?: ApiToken;
  tokenOut?: ApiToken;
  /** Account chains in UI order, including the user's manual ordering. */
  accountChains: ApiChain[];
  network: ApiNetwork;
  balancesUsdBySlug: Record<string, number>;
};

export type ApiSwapDefaults = {
  tokenIn?: ApiToken;
  tokenOut?: ApiToken;
};

export type ApiBuildOnchainSwapTransferOptions = {
  accountId: string;
  request: ApiSwapBuildTransactionRequest;
  transfers?: ApiSwapTransfer[];
  transaction?: string;
  transactionRequest?: ApiEvmSwapTransactionRequest;
  swapId: string;
  authToken: string;
  enclaveToken: string;
};

export type ApiBuildOnchainSwapTransferResult = {
  id: string;
  transfers?: ApiSwapTransfer[];
  transaction?: string;
  transactionRequest?: ApiEvmSwapTransactionRequest;
  calls?: ApiEvmSwapCall[];
  chain: ApiChain;
  /**
   * EVM: the swap runs as one EIP-7702 batch because a Permit2 approve, a router permit,
   * or an Alchemy delegate is missing.
   */
  needsBatch?: boolean;
};

export type ApiSubmitOnchainSwapTransferOptions = {
  accountId: string;
  enclaveToken: string;
  transfers?: ApiSwapTransfer[];
  transaction?: string;
  transactionRequest?: ApiEvmSwapTransactionRequest;
  calls?: ApiEvmSwapCall[];
  /** EVM: from the estimate or the build. Same meaning as `ApiBuildOnchainSwapTransferResult.needsBatch`. */
  needsBatch?: boolean;
  historyItem: ApiSwapHistoryItem;
  isGasless?: boolean;
  authToken: string;
  localSwap: ApiSwapActivity;
  swapId: string;
  /** Sends the signed transaction to the backend's `/swap/execute` */
  executeSwap?: (signedTransaction: string) => Promise<ApiSwapExecuteTransactionResult>;
};

export type ApiSubmitOnchainSwapTransferResult =
  | { activityId: string; submittedHashes: string[] }
  | { mfaRequest: SignedMfaRequest }
  | { error: string };
