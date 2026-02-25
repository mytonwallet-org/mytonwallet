/**
 * TON Connect Adapter Types
 *
 * Types specific to the TON Connect protocol adapter.
 */

import type { DappProofRequest } from '../../types';

// =============================================================================
// TON Connect Specific Types
// =============================================================================

/**
 * TON Connect proof format.
 */
export interface TonConnectProof {
  timestamp: number;
  domain: string;
  payload: string;
}

export enum CHAIN {
  MAINNET = '-239',
  TESTNET = '-3',
}

export interface ApiDappRequestConfirmation {
  accountId: string;
  /** Base64. Shall miss when no proof is required. Can be multiple if walletConnect multichain connect is used */
  proofSignatures?: string[];
}

/**
 * TON Connect transaction payload message.
 */
export interface TonConnectTransactionMessage {
  address: string;
  amount: string;
  payload?: string;
  stateInit?: string;
}

/**
 * TON Connect transaction payload.
 */
export interface TonConnectTransactionPayload {
  valid_until?: number;
  network?: CHAIN;
  from?: string;
  messages: TonConnectTransactionMessage[];
}

// =============================================================================
// Conversion Functions
// =============================================================================

// TODO: mb use this in WC signedConnection implementation?
/**
 * Convert TON Connect proof to generic DappProofRequest.
 */
export function toProofRequest(proof: TonConnectProof): DappProofRequest {
  return {
    type: 'tonProof',
    timestamp: proof.timestamp,
    domain: proof.domain,
    payload: proof.payload,
  };
}

/**
 * Convert generic DappProofRequest to TON Connect proof format.
 */
export function fromProofRequest(request: DappProofRequest): TonConnectProof {
  return {
    timestamp: request.timestamp,
    domain: request.domain,
    payload: request.payload,
  };
}
