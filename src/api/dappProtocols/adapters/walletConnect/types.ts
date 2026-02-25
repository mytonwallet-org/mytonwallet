/**
 * WalletConnect Adapter Types
 *
 * Types specific to the WalletConnect v2 protocol adapter.
 */

import type { ProposalTypes } from '@walletconnect/types';

import type { ApiChain, ApiNetwork } from '../../../types';

// =============================================================================
// CAIP (Chain Agnostic Improvement Proposal) Types
// =============================================================================

/**
 * CAIP-2 chain ID format (e.g., "eip155:1" for Ethereum mainnet).
 */
export type CaipChainId = string;

/**
 * CAIP-10 account ID format (e.g., "eip155:1:0x...").
 */
export type CaipAccountId = string;

/**
 * WalletConnect namespace definition.
 * Defines capabilities for a chain or chain family.
 */
export interface WalletConnectNamespace {
  /** CAIP-2 chain IDs (e.g., ["eip155:1", "eip155:137"]) */
  chains?: CaipChainId[];
  /** RPC methods the dApp wants to call */
  methods: string[];
  /** Events the dApp wants to receive */
  events: string[];
  /** CAIP-10 accounts (filled after connection approval) */
  accounts?: CaipAccountId[];
}

/**
 * Namespace proposal from dApp during session_proposal.
 */
export interface WalletConnectNamespaces {
  /** EVM chains (Ethereum, Polygon, etc.) */
  eip155?: WalletConnectNamespace;
  /** Solana */
  solana?: WalletConnectNamespace;
  /** Cosmos */
  cosmos?: WalletConnectNamespace;
  /** Other namespaces */
  [key: string]: WalletConnectNamespace | undefined;
}

// =============================================================================
// WalletConnect Protocol Data
// =============================================================================

/**
 * WalletConnect session proposal event data.
 */
export interface WalletConnectSessionProposal {
  id: number;
  params: ProposalTypes.Struct;
}

export interface WalletConnectSignRequest {
  topic?: string; // Omitted in injected request
  isSignOnly?: boolean;
  isFullTxRequested?: boolean;
  url?: string;
  address?: string;
  data: string;
}

// =============================================================================
// Method Types
// =============================================================================

/**
 * EVM transaction parameters (eth_sendTransaction).
 */
export interface EvmTransactionParams {
  from: string;
  to: string;
  value?: string;
  data?: string;
  gas?: string;
  gasPrice?: string;
  maxFeePerGas?: string;
  maxPriorityFeePerGas?: string;
  nonce?: string;
}

/**
 * Personal sign parameters (personal_sign).
 */
export interface PersonalSignParams {
  /** Message to sign (hex-encoded) */
  message: string;
  /** Address of the signer */
  address: string;
}

/**
 * Typed data sign parameters (eth_signTypedData_v4).
 */
export interface SignTypedDataParams {
  /** Address of the signer */
  address: string;
  /** Typed data (JSON string or object) */
  data: string | Record<string, unknown>;
}

// =============================================================================
// Namespace Mapping
// =============================================================================

export const SOLANA_CHAIN_IDS: Record<string, { chain: ApiChain; network: ApiNetwork }> = {
  'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp': { chain: 'solana', network: 'mainnet' },
  'solana:4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZ': { chain: 'solana', network: 'testnet' },
};

export const CHAIN_IDS_BY_CHAIN: Record<string, Record<string, { chain: ApiChain; network: ApiNetwork }>> = {
  solana: SOLANA_CHAIN_IDS,
};

export const CHAIN_IDS = {
  ...SOLANA_CHAIN_IDS,
};

/**
 * Extract session chains from WalletConnect namespaces.
 */
export function namespacesToSessionChains(
  namespaces: WalletConnectNamespaces,
) {
  const chains: {
    chain: ApiChain;
    network: ApiNetwork;
  }[] = [];

  for (const [ns, config] of Object.entries(namespaces)) {
    const chainVariants = CHAIN_IDS_BY_CHAIN[ns];
    for (const chain of config?.chains || []) {
      chains.push({
        chain: ns as ApiChain,
        network: chainVariants[chain]?.network || 'mainnet',
      });
    }
  }

  return chains;
}
