/**
 * WalletConnect Adapter Types
 *
 * Types specific to the WalletConnect v2 protocol adapter.
 */

import type { PaymentOption } from '@walletconnect/pay';
import type { AuthTypes, ProposalTypes, Verify } from '@walletconnect/types';

import type { ApiBaseCurrency, ApiChain, ApiNetwork } from '../../../types';

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
 * WalletConnect session proposal event data (includes Verify API context when present).
 */
export interface WalletConnectSessionProposal {
  id: number;
  params: ProposalTypes.Struct;
  /** Present for relay sessions (WalletKit); omitted for extension/in-app synthetic proposals. */
  verifyContext?: Verify.Context;
  /** One-click auth: approve/reject via session_authenticate APIs */
  isSessionAuthenticate?: boolean;
  /** Populated auth payload for SIWE signing (one-click auth only) */
  authenticatePayload?: AuthTypes.PayloadParams;
}

export interface WalletConnectSignRequest {
  topic?: string; // Omitted in injected request
  isSignOnly?: boolean;
  isFullTxRequested?: boolean;
  url?: string;
  address?: string;
  /** Raw message / hex payload (personal_sign, eth_sign); omit when `eip712` is set */
  data?: string | string[] | EvmTransactionParams;
  /** EIP-712 typed data (eth_signTypedData_v4); takes precedence over `data` for signing */
  eip712?: WalletConnectEip712Params;
  isEthSign?: boolean;
  isSessionAuthenticate?: boolean;
}

// =============================================================================
// Method Types
// =============================================================================

/**
 * EVM transaction parameters (eth_sendTransaction / eth_signTransaction).
 * JSON-RPC passes them as a one-element array: `[EvmTransactionParams]`.
 */
export interface EvmTransactionParams {
  chainId?: string;
  data?: string;
  from: string;
  /** Alias for `gasLimit` used by some providers */
  gas?: string;
  gasLimit?: string;
  gasPrice?: string;
  maxFeePerGas?: string;
  maxPriorityFeePerGas?: string;
  nonce?: string;
  /** Omitted for contract creation */
  to?: string;
  value?: string;
}

/**
 * Personal sign parameters (personal_sign).
 */
export type PersonalSignParams = [
  message: string,
  address: string,
];

export type EthSignParams = [
  address: string,
  data: string,
];

/**
 * EIP-712 structured data for WalletConnect `eth_signTypedData` / `eth_signTypedData_v4`.
 */

export type EvmEip712SignDataPayload = {
  type: 'eip712';
  domain: Record<string, unknown>;
  types: Record<string, Array<{ name: string; type: string }>>;
  primaryType: string;
  message: Record<string, unknown>;
};

export type WalletConnectEip712Params = Omit<EvmEip712SignDataPayload, 'type'>;

/**
 * Typed data sign parameters (eth_signTypedData_v4).
 */
export type EthSignTypedDataParams = [
  address: string,
  data: unknown,
];

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

export type ChainId = { chain: ApiChain; network: ApiNetwork };
export type ChainIdByChain = Record<string, ChainId>;

export const SOLANA_CHAIN_IDS: ChainIdByChain = {
  'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp': { chain: 'solana', network: 'mainnet' },
  'solana:4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZ': { chain: 'solana', network: 'testnet' },
};

export const EVM_CHAIN_IDS: ChainIdByChain = {
  'eip155:1': { chain: 'ethereum', network: 'mainnet' },
  'eip155:5': { chain: 'ethereum', network: 'testnet' },
  'eip155:8453': { chain: 'base', network: 'mainnet' },
  'eip155:84532': { chain: 'base', network: 'testnet' },
  'eip155:137': { chain: 'polygon', network: 'mainnet' },
  'eip155:80002': { chain: 'polygon', network: 'testnet' },
  'eip155:42161': { chain: 'arbitrum', network: 'mainnet' },
  'eip155:421614': { chain: 'arbitrum', network: 'testnet' },
  'eip155:56': { chain: 'bnb', network: 'mainnet' },
  'eip155:97': { chain: 'bnb', network: 'testnet' },
  'eip155:43114': { chain: 'avalanche', network: 'mainnet' },
  'eip155:43113': { chain: 'avalanche', network: 'testnet' },
  'eip155:143': { chain: 'monad', network: 'mainnet' },
  'eip155:10143': { chain: 'monad', network: 'testnet' },
  'eip155:999': { chain: 'hyperliquid', network: 'mainnet' },
  'eip155:998': { chain: 'hyperliquid', network: 'testnet' },
};

export const CHAIN_IDS_BY_CHAIN: Record<string, ChainIdByChain> = {
  solana: SOLANA_CHAIN_IDS,
  eip155: EVM_CHAIN_IDS,
};

export const CHAIN_IDS: ChainIdByChain = {
  ...SOLANA_CHAIN_IDS,
  ...EVM_CHAIN_IDS,
};

export type WalletCapabilities = { atomic: { status: 'unsupported' } };

// =============================================================================
// WalletConnect Pay
// =============================================================================

export type WcPayMerchant = {
  name: string;
  iconUrl?: string;
};

export type WcPayAmountDisplay = {
  assetSymbol: string;
  assetName: string;
  decimals: number;
  iconUrl?: string;
  networkName?: string;
};

export type WcPayFiatCurrency = Extract<ApiBaseCurrency, 'USD' | 'EUR'>;

export type WcPayRawAmount = {
  unit?: string;
  value: string;
  display: {
    assetSymbol: string;
    assetName?: string;
    decimals: number;
  };
};

export type WcPayFiatAmount = {
  value: string;
  decimals: number;
  slug: WcPayFiatCurrency;
};

export type WcPayPaymentAmount = {
  value: string;
  display: WcPayAmountDisplay;
  fiatAmount?: WcPayFiatAmount;
};

export type WcPayPaymentInfo = {
  expiresAt: number;
  amount?: WcPayPaymentAmount;
};

export type WcPayPaymentOption = {
  id: string;
  account: string;
  amountValue: string;
  slug?: string;
  display: WcPayAmountDisplay;
  fiatAmount?: WcPayFiatAmount;
  etaS?: number;
  expiresAt?: number;
  kycUrl?: string;
};

export type WcPayContext = {
  accountId: string;
  paymentId: string;
  merchant: WcPayMerchant;
  paymentInfo?: WcPayPaymentInfo;
  paymentOption?: WcPayPaymentOption;
  promiseId?: string;
  paymentLink?: string;
  paymentOptions?: PaymentOption[];
};
