import { Interface } from 'ethers';

import type { ApiEvmSwapTransactionRequest, ApiPerpsCctpDeposit, ApiPerpsExchangeSignature } from '../types';

/** Arbitrum One: the chain of the USDC bridge and of Hyperliquid's user-signed actions. */
export const HYPERLIQUID_BRIDGE_CHAIN_ID = 42161;

/** Fee in bps / 10, so 88 = 0.088% */
export const HYPERLIQUID_BUILDER_ORDER_FEE = 88;

/** HL SDK + CCTP deposit assembly on perps position build routes (default fetch timeout is 10s). */
export const PERPS_BUILD_REQUEST_TIMEOUT_MS = 60_000;

/** Matches backend `HYPERLIQUID_DEPOSIT_WAIT_TIMEOUT_MS` plus HTTP margin. */
export const PERPS_EXECUTE_DEPOSIT_WAIT_TIMEOUT_MS = 200_000;

export const PERPS_TRADE_LOOKUP_INTERVAL_MS = 5_000;

/**
 * How long after an operation starts its trade can happen: the snapshot read and build, then the backend's wait of up
 * to 180 s for the deposit, then the order. The backend never places the order after its wait.
 */
export const PERPS_TRADE_WINDOW_MS = 5 * 60_000;

/** Phase-1 close/execute: backend polls until flat + withdrawable (see `HYPERLIQUID_CLOSE_SETTLE_EXECUTE_TIMEOUT_MS`). */
export const PERPS_CLOSE_EXECUTE_TIMEOUT_MS = 195_000;

/** Market IOC slippage shared with the backend's default order builder. */
export const PERPS_REVIEW_PRICE_TOLERANCE = '0.03';

/** Share of the position's value a leverage decrease reviews above the margin it needs when previewed. */
export const PERPS_LEVERAGE_MARGIN_HEADROOM = '0.005';

export const PERPS_CCTP_FORWARD_FEE_USDC = 0.2;

/** Matches backend `HYPERLIQUID_CCTP_WITHDRAW_GAS_RESERVE_USDC`, which a balance withdrawal leaves on its source. */
export const PERPS_CCTP_WITHDRAW_GAS_RESERVE_USDC = 0.03;

/** The backend submits a signed action once, so the venue's refusal of it means no funds moved. */
export function isPerpsVenueRejection(error: unknown): boolean {
  return error instanceof Error && error.message.startsWith('[HL_EXCHANGE_ERROR]');
}

/** Operation `assetId` of a balance withdrawal. Catalogue asset IDs always start with `hyperliquid:`. */
export const PERPS_BALANCE_WITHDRAWAL_ASSET_ID = 'USDC';

/** CCTP bridge fee in Arbitrum USDC base units (6 decimals). */
export const PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS = 200_000n;

/** Conservative USDC reserve when a Pimlico gas quote is unavailable during funding checks. */
export const PERPS_GASLESS_GAS_FALLBACK_USDC = '0.5';

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

/** Whether an address from a request or a backend build is the account's own wallet. */
export function isPerpsWalletAddress(address: unknown, walletAddress: string): boolean {
  return typeof address === 'string' && address.toLowerCase() === walletAddress.toLowerCase();
}

/** Hyperliquid wire coin of a catalogue asset ID: `hyperliquid:hl:BTC` → `BTC`, `hyperliquid:xyz:TSLA` → `xyz:TSLA`. */
export function getPerpsCoinFromAssetId(assetId: string): string {
  return assetId.replace(/^hyperliquid:(hl:)?/, '');
}
