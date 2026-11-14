import { getAddress } from 'ethers';

import type {
  ApiSwapBuildTransactionRequest,
  ApiSwapDexEstimateResponse,
  ApiSwapEstimateRequest,
  ApiTokenWithPrice,
} from '../types';

import { Big } from '../../lib/big.js';
import { getChainConfig } from '../../util/chain';
import { omit } from '../../util/iteratees';
import { getSwapItemSlug } from './swap';
import { getTokenBySlug } from './tokens';

type AssetSelection = Pick<ApiSwapEstimateRequest, 'from' | 'to'>;
type ExecutionQuote = {
  accountId: string;
  expiresAt: number;
  sourceToken: ApiTokenWithPrice;
  destinationToken: ApiTokenWithPrice;
  fromAddress?: string;
  toAddress?: string;
  slippage?: number;
  fromAmount: string;
  toMinAmount: string;
  ourFee: string;
  networkFee: string;
  nativeFeeBudget: string;
};

/** Backend-only details; applications keep the existing swap contract */
export type BackendSwapEstimate = ApiSwapDexEstimateResponse & {
  vtNativeFeeBudget?: string;
  ourFeeMode?: 'included';
};
type BackendSwapBuildRequest = ApiSwapBuildTransactionRequest & { vtNativeFeeBudget?: string };

const EXECUTION_QUOTES: ExecutionQuote[] = [];
const MAX_EXECUTION_QUOTES = 100;
const EXECUTION_QUOTE_TTL = 5 * 60 * 1000;

export function normalizeSwapAssetSelection<T extends AssetSelection>(request: T) {
  const source = getTokenBySlug(getSwapItemSlug(request.from));
  const destination = getTokenBySlug(getSwapItemSlug(request.to));
  if (!source || !destination || source.chain === destination.chain
    || getChainConfig(source.chain).chainStandard !== 'ethereum'
    || getChainConfig(destination.chain).chainStandard !== 'ethereum') {
    return request;
  }
  return { ...request, from: getSwapAssetId(source), to: getSwapAssetId(destination) };
}

export function rememberSwapExecutionQuote(
  accountId: string,
  request: ApiSwapEstimateRequest,
  estimate: BackendSwapEstimate,
): ApiSwapDexEstimateResponse {
  const { vtNativeFeeBudget, ...publicEstimate } = estimate;
  if (estimate.dexRouterLabel !== 'layerzero') return publicEstimate;
  const sourceToken = getTokenBySlug(getSwapItemSlug(request.from));
  const destinationToken = getTokenBySlug(getSwapItemSlug(request.to));
  if (!sourceToken || !destinationToken || !vtNativeFeeBudget
    || sourceToken.chain !== estimate.chain || sourceToken.chain === destinationToken.chain) {
    throw new Error('Ambiguous execution quote assets or missing budget');
  }
  EXECUTION_QUOTES.push({
    accountId,
    expiresAt: Date.now() + EXECUTION_QUOTE_TTL,
    sourceToken: { ...sourceToken },
    destinationToken: { ...destinationToken },
    fromAddress: request.fromAddress,
    toAddress: request.toAddress,
    slippage: request.slippage,
    fromAmount: estimate.fromAmount,
    toMinAmount: estimate.toMinAmount,
    ourFee: estimate.ourFee,
    networkFee: estimate.realNetworkFee ?? estimate.networkFee,
    nativeFeeBudget: vtNativeFeeBudget,
  });
  if (EXECUTION_QUOTES.length > MAX_EXECUTION_QUOTES) EXECUTION_QUOTES.shift();
  return omit(publicEstimate, ['ourFeeMode']);
}

export function prepareSwapBuildRequest(
  accountId: string,
  request: ApiSwapBuildTransactionRequest,
): BackendSwapBuildRequest {
  const normalized = normalizeSwapAssetSelection(request);
  if (request.dexRouterLabel !== 'layerzero') return normalized;
  const quote = getSwapExecutionQuote(accountId, request);
  return { ...normalized, vtNativeFeeBudget: quote.nativeFeeBudget };
}

export function getSwapExecutionQuote(accountId: string, request: ApiSwapBuildTransactionRequest) {
  const normalized = normalizeSwapAssetSelection(request);
  const matching = EXECUTION_QUOTES.filter((quote) => (
    quote.accountId === accountId && quote.expiresAt > Date.now()
    && request.dexRouterLabel === 'layerzero' && !request.cexLabel && request.swapMode !== 'exact_out'
    && normalized.from === getSwapAssetId(quote.sourceToken)
    && normalized.to === getSwapAssetId(quote.destinationToken)
    && request.fromAddress.toLowerCase() === quote.fromAddress?.toLowerCase()
    && request.toAddress?.toLowerCase() === quote.toAddress?.toLowerCase()
    && request.slippage === quote.slippage && request.fromAmount === quote.fromAmount
    && request.toMinAmount === quote.toMinAmount && request.ourFee === quote.ourFee
    && request.networkFee === quote.networkFee
  ));
  if (!matching.length) throw new Error('Confirmed execution quote changed or expired; a fresh estimate is required');
  // The old app echoes the displayed quote, not a new handle. Equal displayed quotes may never raise any saved ceiling.
  return matching.reduce((best, quote) => Big(quote.nativeFeeBudget).lt(best.nativeFeeBudget) ? quote : best);
}

export function getSwapAssetId(token: ApiTokenWithPrice) {
  return `${token.chain}:${token.tokenAddress ? getAddress(token.tokenAddress) : 'native'}`;
}
