import { Interface, isAddress } from 'ethers';

import type { ApiEvmSwapTransactionRequest, EVMChain } from '../../types';
import type { EvmSwapTransactionPayload, EvmSwapTransactionRequest, UniswapPermitData } from './swap';

import { Big } from '../../../lib/big.js';
import { fromDecimal } from '../../../util/decimals';
import { findNativeToken } from '../../../util/tokens';
import { getTokenByAddress } from '../../common/tokens';
import {
  LIFI_CONTRACTS,
  UNISWAP_PERMIT2_ADDRESS,
  UNISWAP_UNIVERSAL_ROUTER_ADDRESSES,
} from './constants';

/** What the user agreed to sell, the only source of the amounts and tokens a swap may authorize. */
export type EvmSwapIntent = {
  chainId: number;
  owner: string;
  /** Absent when the native coin is sold */
  sellToken?: string;
  /** Absent when the native coin is bought */
  buyToken?: string;
  maxSellAmount: bigint;
  maxNativeFee: bigint;
};

export type EvmSwapOrder = {
  from: string;
  to: string;
  fromAmount: string;
  networkFee?: string;
  swapMode?: 'exact_in' | 'exact_out';
  slippage?: number;
};

/** Lifetime of every Permit2 allowance and signature a swap grants; the swap spends it right away. */
export const SWAP_PERMIT2_LIFETIME_SECONDS = 30 * 60;

const MAX_UINT256 = (1n << 256n) - 1n;

const erc20ApproveInterface = new Interface(['function approve(address spender, uint256 amount) returns (bool)']);
const wrappedNativeInterface = new Interface([
  'function deposit() payable',
  'function withdraw(uint256 amount)',
]);

const PERMIT_SINGLE_TYPES = {
  PermitSingle: [
    { name: 'details', type: 'PermitDetails' },
    { name: 'spender', type: 'address' },
    { name: 'sigDeadline', type: 'uint256' },
  ],
  PermitDetails: [
    { name: 'token', type: 'address' },
    { name: 'amount', type: 'uint160' },
    { name: 'expiration', type: 'uint48' },
    { name: 'nonce', type: 'uint48' },
  ],
};

export class EvmSwapBindingError extends Error {
  constructor(reason: string) {
    super(`Unbound swap payload: ${reason}`);
  }
}

function refuse(reason: string): never {
  throw new EvmSwapBindingError(reason);
}

function isSameAddress(a: string | undefined, b: string | undefined) {
  return !!a && !!b && a.toLowerCase() === b.toLowerCase();
}

function toUnits(amount: string, decimals: number, multiplierPercent = 100) {
  const units = Big(amount).mul(Big(10).pow(decimals)).mul(multiplierPercent).div(100);

  return BigInt(units.round(0, Big.roundUp).toString());
}

export function buildEvmSwapIntent(
  chain: EVMChain,
  chainId: number | undefined,
  owner: string,
  order: EvmSwapOrder,
): EvmSwapIntent {
  const nativeToken = findNativeToken(chain);
  if (!nativeToken || chainId === undefined) refuse('Unknown chain');

  const sellToken = isAddress(order.from) ? order.from : undefined;
  if (!sellToken && order.from !== nativeToken.slug) refuse('Sold coin is not native to the swap chain');

  const sellDecimals = sellToken ? getTokenByAddress(sellToken, chain)?.decimals : nativeToken.decimals;
  if (sellDecimals === undefined) refuse('Unknown sell token');

  const slippagePercent = order.swapMode === 'exact_out' ? order.slippage ?? 0 : 0;

  return {
    chainId,
    owner,
    sellToken,
    buyToken: isAddress(order.to) ? order.to : undefined,
    maxSellAmount: toUnits(order.fromAmount, sellDecimals, 100 + slippagePercent),
    maxNativeFee: order.networkFee ? fromDecimal(order.networkFee, nativeToken.decimals) : 0n,
  };
}

function toBigInt(value: string | undefined) {
  try {
    return BigInt(value || '0');
  } catch {
    return refuse('Malformed amount');
  }
}

function assertNativeValue(value: string | undefined, max: bigint) {
  if (toBigInt(value) > max) refuse('Native value exceeds the swap amount');
}

function assertChainId(tx: { chainId?: number }, intent: EvmSwapIntent) {
  if (tx.chainId !== undefined && Number(tx.chainId) !== intent.chainId) refuse('Transaction targets another chain');
}

function decodeErc20Approve(data: string) {
  try {
    const [spender, amount] = erc20ApproveInterface.decodeFunctionData('approve', data);
    return { spender: spender as string, amount: amount as bigint };
  } catch {
    return refuse('Approval is not an ERC-20 approve');
  }
}

/** Rebuilds the approval on the sold token for a spender the client already trusts. */
function bindApproval(
  approval: EvmSwapTransactionRequest,
  intent: EvmSwapIntent,
  spender: string,
  amount: bigint,
): EvmSwapTransactionRequest {
  if (!intent.sellToken || !isSameAddress(approval.to, intent.sellToken)) refuse('Approval is not on the sold token');
  if (!isSameAddress(decodeErc20Approve(approval.data).spender, spender)) refuse('Approval spender is not trusted');
  assertChainId(approval, intent);

  return {
    from: intent.owner,
    to: intent.sellToken,
    data: erc20ApproveInterface.encodeFunctionData('approve', [spender, amount]),
    value: '0',
    chainId: intent.chainId,
    gasLimit: approval.gasLimit,
  };
}

function bindSwapCall(swap: EvmSwapTransactionRequest, intent: EvmSwapIntent, maxNativeValue: bigint) {
  assertChainId(swap, intent);
  assertNativeValue(swap.value, maxNativeValue);

  return { ...swap, from: intent.owner };
}

function buildPermitSingle(intent: EvmSwapIntent, spender: string, nonce: string, now: number): UniswapPermitData {
  const deadline = String(now + SWAP_PERMIT2_LIFETIME_SECONDS);

  return {
    domain: { name: 'Permit2', chainId: intent.chainId, verifyingContract: UNISWAP_PERMIT2_ADDRESS },
    types: PERMIT_SINGLE_TYPES,
    values: {
      details: { token: intent.sellToken!, amount: String(intent.maxSellAmount), expiration: deadline, nonce },
      spender,
      sigDeadline: deadline,
    },
  };
}

function bindUniswapClassic(chain: EVMChain, payload: EvmSwapTransactionPayload, intent: EvmSwapIntent, now: number) {
  const { swap, approval, permitData } = payload;
  if (!swap || !UNISWAP_UNIVERSAL_ROUTER_ADDRESSES[chain]?.includes(swap.to.toLowerCase())) {
    refuse('Swap target is not a Universal Router');
  }

  const bound: EvmSwapTransactionPayload = {
    provider: payload.provider,
    routing: payload.routing,
    requiresPermitSignature: payload.requiresPermitSignature,
    swap: bindSwapCall(swap, intent, intent.sellToken ? 0n : intent.maxSellAmount),
  };

  if (approval) {
    bound.approval = bindApproval(approval, intent, UNISWAP_PERMIT2_ADDRESS, MAX_UINT256);
  }

  if (permitData) {
    if (!isSameAddress(permitData.values?.details?.token, intent.sellToken)) refuse('Permit is not for the sold token');
    bound.permitData = buildPermitSingle(intent, swap.to, String(toBigInt(permitData.values.details.nonce)), now);
  } else if (approval && intent.sellToken) {
    bound.permit2Allowance = {
      token: intent.sellToken,
      spender: swap.to,
      amount: String(intent.maxSellAmount),
      expiration: String(now + SWAP_PERMIT2_LIFETIME_SECONDS),
    };
  }

  return bound;
}

function bindWrappedNativeSwap(payload: EvmSwapTransactionPayload, intent: EvmSwapIntent) {
  const { swap, routing } = payload;
  if (!swap || payload.approval || payload.permitData) refuse('Wrap carries extra calls');

  const isWrap = routing === 'WRAP';
  const wrappedToken = isWrap ? intent.buyToken : intent.sellToken;
  if (isWrap === !!intent.sellToken || !isSameAddress(swap.to, wrappedToken)) {
    refuse('Wrap target is not the swapped token');
  }

  let parsed;
  try {
    parsed = wrappedNativeInterface.parseTransaction({ data: swap.data, value: toBigInt(swap.value) });
  } catch {
    parsed = undefined;
  }

  if (isWrap ? parsed?.name !== 'deposit' : parsed?.name !== 'withdraw' || parsed.args[0] > intent.maxSellAmount) {
    refuse('Wrap call does not match the swap');
  }

  return {
    provider: payload.provider,
    routing,
    requiresPermitSignature: false,
    swap: bindSwapCall(swap, intent, isWrap ? intent.maxSellAmount : 0n),
  };
}

function bindUniswapPayload(chain: EVMChain, payload: EvmSwapTransactionPayload, intent: EvmSwapIntent, now: number) {
  if (!payload.swap) refuse('Swap call is missing');

  switch (payload.routing) {
    case 'CLASSIC':
      return bindUniswapClassic(chain, payload, intent, now);
    case 'WRAP':
    case 'UNWRAP':
      return bindWrappedNativeSwap(payload, intent);
    default:
      return refuse(`Unsupported Uniswap routing: ${payload.routing}`);
  }
}

function bindLifiPayload(chain: EVMChain, payload: EvmSwapTransactionPayload, intent: EvmSwapIntent) {
  const { approval, lifiPermit2 } = payload;
  if (!lifiPermit2) refuse('LI.FI payload carries no Permit2 transfer');

  const contracts = LIFI_CONTRACTS[chain];
  const { permit2, permit2Proxy, token, amount, transactionRequest, witness } = lifiPermit2;

  if (!contracts || !isSameAddress(permit2Proxy, contracts.permit2Proxy)) {
    refuse('LI.FI Permit2 proxy is not trusted');
  }
  if (witness && !isSameAddress(witness.diamondAddress, contracts.diamond)) {
    refuse('LI.FI witness names another Diamond');
  }
  if (!isSameAddress(permit2, UNISWAP_PERMIT2_ADDRESS)) refuse('LI.FI Permit2 contract is not trusted');
  if (!intent.sellToken || !isSameAddress(token, intent.sellToken)) refuse('LI.FI permit is not for the sold token');
  if (toBigInt(amount) > intent.maxSellAmount) refuse('LI.FI permit exceeds the swap amount');

  return {
    provider: 'lifi' as const,
    approval: approval && bindApproval(approval, intent, UNISWAP_PERMIT2_ADDRESS, MAX_UINT256),
    lifiPermit2: {
      token: intent.sellToken,
      amount: String(toBigInt(amount)),
      permit2: UNISWAP_PERMIT2_ADDRESS,
      permit2Proxy: contracts.permit2Proxy,
      deadlineSeconds: SWAP_PERMIT2_LIFETIME_SECONDS,
      witness: witness && { diamondAddress: contracts.diamond },
      transactionRequest: bindSwapCall(transactionRequest, intent, intent.maxNativeFee),
    },
  };
}

/**
 * Returns a payload whose targets, spenders, tokens, amounts and lifetimes are pinned by the client or checked
 * against what the user agreed to sell. Only the route calldata stays the backend's.
 */
export function bindEvmSwapPayload(
  chain: EVMChain,
  payload: EvmSwapTransactionPayload,
  intent: EvmSwapIntent,
  now = Math.floor(Date.now() / 1000),
): EvmSwapTransactionPayload {
  return payload.provider === 'lifi'
    ? bindLifiPayload(chain, payload, intent)
    : bindUniswapPayload(chain, payload, intent, now);
}

export function bindEvmSwapTransactionRequest(
  chain: EVMChain,
  request: ApiEvmSwapTransactionRequest,
  intent: EvmSwapIntent,
): ApiEvmSwapTransactionRequest {
  const diamond = LIFI_CONTRACTS[chain]?.diamond;
  if (!diamond || !isSameAddress(request.to, diamond)) refuse('Swap target is not the LI.FI Diamond');
  if (Number(request.chainId) !== intent.chainId) refuse('Transaction targets another chain');
  if (intent.sellToken) refuse('A LI.FI token sale must go through a Permit2 transfer');
  assertNativeValue(request.value, intent.maxSellAmount + intent.maxNativeFee);

  // Gas prices come from the wallet's own fee data; only the refundable gas limit is taken from the backend.
  return {
    from: intent.owner,
    to: request.to,
    chainId: intent.chainId,
    data: request.data,
    value: request.value,
    gasLimit: request.gasLimit,
  };
}
