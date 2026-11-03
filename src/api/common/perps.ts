import { Interface } from 'ethers';

import type {
  ApiEvmSwapTransactionRequest,
  ApiPerpsBuildBalanceWithdrawResult,
  ApiPerpsBuildClosePositionRequest,
  ApiPerpsBuildClosePositionResult,
  ApiPerpsBuildDepositResult,
  ApiPerpsBuildModifyPositionRequest,
  ApiPerpsBuildModifyPositionResult,
  ApiPerpsBuildPositionResult,
  ApiPerpsCctpDeposit,
  ApiPerpsChain,
  ApiPerpsExchangeBuild,
  ApiPerpsExchangeSignature,
  ApiPerpsExecuteClosePositionRequest,
  ApiPerpsExecutePositionRequest,
  ApiPerpsOpenPositionResult,
  ApiPerpsSignedExchangeAction,
  ApiPerpsWithdrawPermit,
} from '../types';

import { HYPERLIQUID_BRIDGE_CHAIN_ID } from '../chains/evm/hyperliquidPayloadValidation';

/** HL SDK + CCTP deposit assembly on perps position build routes (default fetch timeout is 10s). */
export const PERPS_BUILD_REQUEST_TIMEOUT_MS = 60_000;

/** Matches backend `HYPERLIQUID_DEPOSIT_WAIT_TIMEOUT_MS` plus HTTP margin. */
export const PERPS_EXECUTE_DEPOSIT_WAIT_TIMEOUT_MS = 200_000;

/** Phase-1 close/execute: backend polls until flat + withdrawable (see `HYPERLIQUID_CLOSE_SETTLE_EXECUTE_TIMEOUT_MS`). */
export const PERPS_CLOSE_EXECUTE_TIMEOUT_MS = 195_000;

/** Market IOC slippage shared with the backend's default order builder. */
export const PERPS_REVIEW_PRICE_TOLERANCE = '0.03';

export const PERPS_CCTP_FORWARD_FEE_USDC = 0.2;

/** CCTP bridge fee in Arbitrum USDC base units (6 decimals). */
export const PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS = 200_000n;

export function getPerpsOrderError(status: string): string {
  if (status === 'minTradeNtlRejected' || status.includes('minimum value of $10')) return 'PerpsOrderTooSmall';
  if (status === 'iocCancelRejected' || status.includes('could not immediately match')
    || status.includes('No liquidity available')) return 'PerpsOrderNotFilled';
  if (status === 'perpMarginRejected' || status.includes('Insufficient margin')) return 'PerpsInsufficientMargin';
  if (status === 'reduceOnlyRejected' || status.includes('Reduce only order')) return 'PerpsPositionChanged';
  return 'PerpsOrderRejected';
}

export const PERPS_CCTP_EXTENSION_ADDRESS = '0xA95d9c1F655341597C94393fDdc30cf3c08E4fcE';

export const PERPS_HYPERCORE_BRIDGE_RELAYER = '0x8dF10E315A7a9B1A613df4D7791411B89E47f45F';

export const PERPS_CCTP_DEPOSIT_CHAIN = 'arbitrum' as const;

const cctpExtensionInterface = new Interface([
  `function batchDepositForBurnWithAuth(
    (
      uint256 amount,
      uint256 authValidAfter,
      uint256 authValidBefore,
      bytes32 authNonce,
      uint8 v,
      bytes32 r,
      bytes32 s
    ) _receiveWithAuthorizationData,
    (
      uint256 amount,
      uint32 destinationDomain,
      bytes32 mintRecipient,
      bytes32 destinationCaller,
      uint256 maxFee,
      uint32 minFinalityThreshold,
      bytes hookData
    ) _depositForBurnData
  )`,
]);

type CctpPermitValues = {
  value: string | number;
  validAfter: string | number;
  validBefore: string | number;
  nonce: string;
};

export function getPerpsCctpCreditedAmountUsdc(grossDepositAmountUsdc: number | string): number {
  const amount = Number(grossDepositAmountUsdc);
  if (!Number.isFinite(amount)) {
    throw new Error('Invalid deposit amount');
  }
  return amount - PERPS_CCTP_FORWARD_FEE_USDC;
}

/**
 * Encode CctpExtension.batchDepositForBurnWithAuth after signTypedData(deposit.permitData).
 * Fills `deposit.swap.data` before the client EIP-7702-batches `[swap]`.
 */
export function buildPerpsCctpDepositTx(params: {
  from: string;
  deposit: ApiPerpsCctpDeposit;
  permitSignature: ApiPerpsExchangeSignature;
}): ApiEvmSwapTransactionRequest {
  const { deposit, from, permitSignature } = params;

  if (permitSignature.v !== 27 && permitSignature.v !== 28) {
    throw new Error('Permit signature v must be 27 or 28');
  }

  const permitValues = deposit.permitData.values as CctpPermitValues;
  const { burnCall } = deposit;

  return {
    from,
    to: PERPS_CCTP_EXTENSION_ADDRESS,
    value: '0',
    chainId: HYPERLIQUID_BRIDGE_CHAIN_ID,
    data: cctpExtensionInterface.encodeFunctionData('batchDepositForBurnWithAuth', [
      {
        amount: BigInt(String(permitValues.value)),
        authValidAfter: BigInt(String(permitValues.validAfter)),
        authValidBefore: BigInt(String(permitValues.validBefore)),
        authNonce: permitValues.nonce,
        v: permitSignature.v,
        r: permitSignature.r,
        s: permitSignature.s,
      },
      {
        amount: BigInt(burnCall.amount),
        destinationDomain: burnCall.destinationDomain,
        mintRecipient: burnCall.mintRecipient,
        destinationCaller: burnCall.destinationCaller,
        maxFee: BigInt(burnCall.maxFee),
        minFinalityThreshold: burnCall.minFinalityThreshold,
        hookData: burnCall.hookData,
      },
    ]),
  };
}

/** Maps `/perps/position/close/build` → phase-1 `/perps/position/close/execute` (`action.type === 'order'`). */
export function buildPerpsCloseOrderExecuteRequest(
  chain: ApiPerpsChain,
  build: ApiPerpsBuildClosePositionResult,
  request: ApiPerpsBuildClosePositionRequest,
  signature: ApiPerpsExchangeSignature,
): ApiPerpsExecuteClosePositionRequest {
  return {
    chain,
    address: build.address,
    asset: request.asset,
    action: build.action,
    nonce: build.nonce,
    signature,
    destination: request.address,
  };
}

/** Maps signed CCTP withdraw permit → phase-2 `/perps/position/close/execute` (`sendToEvmWithData`). */
export function buildPerpsCloseWithdrawExecuteRequest(
  chain: ApiPerpsChain,
  address: string,
  withdraw: ApiPerpsWithdrawPermit,
  signature: ApiPerpsExchangeSignature,
): ApiPerpsExecuteClosePositionRequest {
  return {
    chain,
    address,
    action: withdraw.action,
    nonce: withdraw.nonce,
    signature,
  };
}

export function buildPerpsOpenExecuteRequest(
  chain: ApiPerpsChain,
  build: ApiPerpsBuildPositionResult,
  signed: {
    signature: ApiPerpsExchangeSignature;
    approveBuilderFee?: ApiPerpsSignedExchangeAction;
    spotToPerp?: ApiPerpsSignedExchangeAction;
    updateLeverage?: ApiPerpsSignedExchangeAction;
  },
): ApiPerpsExecutePositionRequest {
  return {
    chain,
    address: build.address,
    action: build.action,
    nonce: build.nonce,
    signature: signed.signature,
    approveBuilderFee: signed.approveBuilderFee,
    spotToPerp: signed.spotToPerp,
    updateLeverage: signed.updateLeverage,
    depositAmount: build.deposit.amountUsdc,
  };
}

/** Maps `/perps/deposit/build` → `/perps/position/execute` with no order. */
export function buildPerpsDepositExecuteRequest(
  chain: ApiPerpsChain,
  build: ApiPerpsBuildDepositResult,
  signed: { spotToPerp?: ApiPerpsSignedExchangeAction },
): ApiPerpsExecutePositionRequest {
  return {
    chain,
    address: build.address,
    depositAmount: build.deposit.amountUsdc,
    spotToPerp: signed.spotToPerp,
  };
}

/** Maps `/perps/withdraw/build` → `/perps/position/execute` (`sendToEvmWithData` only). */
export function buildPerpsBalanceWithdrawExecuteRequest(
  chain: ApiPerpsChain,
  build: ApiPerpsBuildBalanceWithdrawResult,
  signature: ApiPerpsExchangeSignature,
): ApiPerpsExecutePositionRequest {
  return {
    chain,
    address: build.address,
    action: build.action,
    nonce: build.nonce,
    signature,
  };
}

/** Maps `/perps/position/open` → `/perps/position/execute` without `depositAmount`. */
export function buildPerpsOpenFromBalanceExecuteRequest(
  chain: ApiPerpsChain,
  build: ApiPerpsOpenPositionResult,
  signed: {
    signature: ApiPerpsExchangeSignature;
    approveBuilderFee?: ApiPerpsSignedExchangeAction;
    updateLeverage: ApiPerpsSignedExchangeAction;
  },
): ApiPerpsExecutePositionRequest {
  return {
    chain,
    address: build.address,
    action: build.action,
    nonce: build.nonce,
    signature: signed.signature,
    approveBuilderFee: signed.approveBuilderFee,
    updateLeverage: signed.updateLeverage,
  };
}

/** Maps `/perps/position/modify/build` → shared `/perps/position/execute`. */
export function buildPerpsModifyExecuteRequest(
  chain: ApiPerpsChain,
  build: ApiPerpsBuildModifyPositionResult,
  signed: {
    signature?: ApiPerpsExchangeSignature;
    approveBuilderFee?: ApiPerpsSignedExchangeAction;
    spotToPerp?: ApiPerpsSignedExchangeAction;
    updateLeverage?: ApiPerpsSignedExchangeAction;
    updateIsolatedMargin?: ApiPerpsSignedExchangeAction;
  },
): ApiPerpsExecutePositionRequest {
  const request: ApiPerpsExecutePositionRequest = {
    chain,
    address: build.address,
    approveBuilderFee: signed.approveBuilderFee,
    spotToPerp: signed.spotToPerp,
    updateLeverage: signed.updateLeverage,
    updateIsolatedMargin: signed.updateIsolatedMargin,
    depositAmount: build.deposit?.amountUsdc,
  };

  if (build.action !== undefined && build.nonce !== undefined && signed.signature !== undefined) {
    request.action = build.action;
    request.nonce = build.nonce;
    request.signature = signed.signature;
  }

  return request;
}

/** Reduce-only modify order → `/perps/position/close/execute` (same as close phase 1). */
export function buildPerpsModifyReduceExecuteRequest(
  chain: ApiPerpsChain,
  build: ApiPerpsBuildModifyPositionResult & ApiPerpsExchangeBuild,
  request: ApiPerpsBuildModifyPositionRequest,
  signature: ApiPerpsExchangeSignature,
): ApiPerpsExecuteClosePositionRequest {
  return {
    chain,
    address: build.address,
    asset: request.asset,
    action: build.action,
    nonce: build.nonce,
    signature,
    destination: request.address,
    skipPositionFlatWait: true,
    depositAmount: request.depositAmount,
  };
}
