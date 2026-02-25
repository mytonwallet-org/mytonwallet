/**
 * Unified dApp Protocol Abstraction Types
 *
 * This module defines interfaces for abstracting different dApp connection protocols
 * (TON Connect, WalletConnect) behind a common interface.
 */
import type {
  ConnectEventSuccess,
  ConnectRequest,
  DisconnectRpcResponseSuccess,
  SendTransactionRpcResponseSuccess,
  SignDataPayload,
  SignDataRpcResponseSuccess,
} from '@tonconnect/protocol';
import type { SessionTypes } from '@walletconnect/types';

import type { AppEnvironment } from '../environment';
import type { ApiEmulationResult } from '../types/emulation';
import type { ApiAnyDisplayError } from '../types/errors';
import type {
  ApiChain,
  ApiDappPermissions,
  ApiDappRequest,
  ApiDappTransfer,
  ApiNetwork,
  ApiSignedTransfer,
} from '../types/misc';
import type { OnApiUpdate } from '../types/updates';
import type { TonConnectTransactionPayload } from './adapters/tonConnect/types';
import type { WalletConnectSessionProposal, WalletConnectSignRequest } from './adapters/walletConnect/types';
import type { DappProtocolError } from './errors';
import type { StoredDappConnection } from './storage';

// =============================================================================
// Protocol Types
// =============================================================================

/**
 * Supported dApp connection protocols.
 * - 'TonConnect': TON Connect protocol for TON blockchain
 * - 'WalletConnect': WalletConnect v2 for EVM, Solana, and other chains
 */
export enum DappProtocolType {
  TonConnect = 'tonConnect',
  WalletConnect = 'walletConnect',
};

export const DAPP_PROTOCOL_TYPES = Object.values(DappProtocolType);

/**
 * Transport types for dApp connections.
 * Different protocols may use different subsets of these transports.
 */
export type DappTransportType =
  | 'extension' // Browser extension injection
  | 'inAppBrowser' // Mobile in-app browser
  | 'sse' // Server-sent events (TON Connect bridge)
  | 'relay'; // WalletConnect relay server

export type UnifiedSignDataPayload = SignDataPayload;

type ProtocolSpecificData<T extends string> = {
  session: T extends 'tonConnect' ? ConnectEventSuccess : SessionTypes.Namespaces;
  connect: T extends 'tonConnect' ? ConnectRequest : WalletConnectSessionProposal;
  transaction: T extends 'tonConnect' ? TonConnectTransactionPayload : WalletConnectSignRequest;
  sign: T extends 'tonConnect' ? SignDataPayload : WalletConnectSignRequest;
  methodResult: T extends 'tonConnect'
    ? SendTransactionRpcResponseSuccess | SignDataRpcResponseSuccess | DisconnectRpcResponseSuccess
    : {
      result: string;
      id: string;
    };
};

// =============================================================================
// Dapp Metadata & Session
// =============================================================================

/**
 * Basic dApp metadata, common across all protocols.
 */
export interface DappMetadata {
  /** dApp's URL (origin) */
  url: string;
  /** dApp's display name */
  name: string;
  /** dApp's icon URL */
  iconUrl: string;
  /** Optional description */
  description?: string;
  /** Manifest URL (for TON Connect) */
  manifestUrl?: string;
}

/**
 * Chain-specific session information within a dApp connection.
 */
export interface DappSessionChain {
  /** Which blockchain this session applies to */
  chain: ApiChain;
  /** Wallet address for this chain */
  address: string;
  /** Public key (if applicable) */
  publicKey?: string;
  /** Network (mainnet/testnet) */
  network: ApiNetwork;
}

/**
 * Unified dApp session representing an active connection.
 */
export interface DappSession<T extends string = any> {
  /** Unique session identifier */
  id: string;
  /** Which protocol established this session */
  protocolType: DappProtocolType;
  /** MyTonWallet account ID */
  accountId: string;
  /** dApp metadata */
  dapp: DappMetadata;
  /** Chain-specific session data */
  chains: DappSessionChain[];
  /** When the session was established (Unix timestamp ms) */
  connectedAt: number;
  /** When the session expires (Unix timestamp ms), if applicable */
  expiresAt?: number;
  protocolData: ProtocolSpecificData<T>['session'];
}

// =============================================================================
// Connection Requests
// =============================================================================

/**
 * Proof request for connection verification (e.g., TON Proof).
 */
export interface DappProofRequest {
  /** Type of proof requested */
  type: 'tonProof' | 'signature';
  /** Timestamp when proof was requested (Unix seconds) */
  timestamp: number;
  /** Domain making the request */
  domain: string;
  /** Payload to sign */
  payload: string;
}

/**
 * Permission types that can be requested during connection.
 */
export interface DappPermissions {
  /** Whether to share wallet address */
  address: boolean;
  /** Whether proof/signature is required */
  proof: boolean;
}

/**
 * Incoming connection request from a dApp.
 */
export interface DappConnectionRequest<T extends string = any> {
  /** Which protocol is requesting connection */
  // accept enum or its serialization for places, where real enum cannot be imported
  protocolType: T | `${T}`;
  /** Transport used for this request */
  transport: DappTransportType;
  /** Requested chains and their capabilities */
  requestedChains: {
    chain: ApiChain;
    network: ApiNetwork;
  }[];
  /** Requested permissions */
  permissions: ApiDappPermissions;
  protocolData: ProtocolSpecificData<T>['connect'];
}

export interface DappDisconnectRequest {
  requestId: string;
}

/**
 * User's response to a connection request.
 */
export interface DappConnectionApproval {
  /** Which account to connect */
  accountId: string;
  /** Proof signature, if proof was requested */
  proofSignature?: string;
  /** Approved chains (may be subset of requested) */
  approvedChains: ApiChain[];
}

/**
 * Result of a connection attempt.
 */
export type DappConnectionResult<T extends string = any> =
  | { success: true; session: DappSession<T> }
  | { success: false; error: DappProtocolError };

// =============================================================================
// Method Requests (Transactions, Signing)
// =============================================================================

/**
 * Transaction signing request from a dApp.
 */
export interface DappTransactionRequest<T extends string = any> {
  /** Unique request ID */
  id: string;
  /** Target chain for the transaction */
  chain: ApiChain;
  /** Original protocol-specific params */
  payload: ProtocolSpecificData<T>['transaction'];
}

/**
 * Arbitrary data signing request from a dApp.
 */
export interface DappSignDataRequest<T extends string = any> {
  /** Unique request ID */
  id: string;
  /** Target chain */
  chain: ApiChain;
  /** Data to sign (protocol-specific format) */
  payload: ProtocolSpecificData<T>['sign'];
}

/**
 * Union type for all dApp method requests.
 */
export type DappMethodRequest =
  | { type: 'transaction'; request: DappTransactionRequest }
  | { type: 'signData'; request: DappSignDataRequest };

/**
 * Result of a method request.
 */
export type DappMethodResult<T extends string = any> =
  | {
    success: true;
    result: ProtocolSpecificData<T>['methodResult'];
  }
  | { success: false; error: DappProtocolError };

// =============================================================================
// Protocol Adapter Interface
// =============================================================================

/**
 * Configuration for initializing a protocol adapter.
 */
export interface DappProtocolConfig {
  /** Update callback for emitting UI updates */
  onUpdate: OnApiUpdate;
  /** Whether running as browser extension */
  isExtension?: boolean;
  env: AppEnvironment;
  /**
   * Per-chain dApp capabilities injected from the chains registry.
   * Adapters use this to avoid importing chain SDKs directly.
   */
  chainDappSupports?: Partial<Record<ApiChain,
    Pick<ChainDappSupport, 'parseTransactionForPreview' | 'sendSignedTransaction'>>
  >;
}

/**
 * Interface that all protocol adapters must implement.
 * This provides a unified API for different dApp connection protocols.
 */
export interface DappProtocolAdapter<T extends `${DappProtocolType}` = any> {
  /** Which protocol this adapter handles */
  readonly protocolType: T;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /**
   * Initialize the adapter.
   * Called once when the adapter is registered.
   */
  init(config: DappProtocolConfig): Promise<void>;

  /**
   * Clean up resources and close connections.
   * Called when the adapter is being destroyed.
   */
  destroy(): Promise<void>;

  // ---------------------------------------------------------------------------
  // Connection Handling
  // ---------------------------------------------------------------------------

  /**
   * Handle an incoming connection request.
   * Should validate the request and emit UI updates for user approval.
   *
   * @param request - The connection request
   * @param requestId - Unique ID for tracking this request
   * @returns Promise that resolves when connection is approved/rejected
   */
  connect(
    request: ApiDappRequest,
    message: DappConnectionRequest<T>,
    requestId: number
  ): Promise<DappConnectionResult<T>>;

  /**
   * Restore an existing session (reconnect).
   *
   * @param sessionId - Session to restore
   * @param requestId - Unique ID for tracking this request
   */
  reconnect(
    request: ApiDappRequest,
    requestId: number,
  ): Promise<DappConnectionResult<T>>;

  /**
   * Disconnect a session.
   *
   * @param sessionId - Session to disconnect
   * @param notifyDapp - Whether to notify the dApp of disconnection
   */
  disconnect(
    request: ApiDappRequest,
    message: DappDisconnectRequest
  ): Promise<DappMethodResult<T>>;

  // ---------------------------------------------------------------------------
  // Request Handling
  // ---------------------------------------------------------------------------

  /**
   * Handle a transaction request from a dApp.
   *
   * @param request - The transaction request
   * @returns Promise that resolves with the transaction result (e.g., tx hash)
   */
  sendTransaction(
    request: ApiDappRequest,
    message: DappTransactionRequest<T>,
  ): Promise<DappMethodResult<T>>;

  /**
   * Handle a data signing request from a dApp.
   *
   * @param request - The sign data request
   * @returns Promise that resolves with the signature
   */
  signData(
    request: ApiDappRequest,
    message: DappSignDataRequest<T>,
  ): Promise<DappMethodResult<T>>;

  // ---------------------------------------------------------------------------
  // Transport-specific Methods
  // ---------------------------------------------------------------------------

  /**
   * Handle a deep link for this protocol.
   * Only applicable for protocols that use deep links (SSE, WalletConnect).
   *
   * @param url - The deep link URL
   * @returns Return strategy or undefined
   */
  handleDeepLink(
    url: string,
    isFromInAppBrowser?: boolean,
    requestId?: string
  ): Promise<string | undefined>;

  /**
   * Resetup existing remote connection for this protocol on app start or on state change.
   * Only applicable for protocols that use remote connections (SSE, WebSocket).
   */
  resetupRemoteConnection?(): Promise<void>;

  /**
   * Let remote dApp know that local connection is revoked.
   * Only applicable for protocols that use deep links (SSE, WalletConnect).
   *
   * @param accountId - MTW accountId
   * @param url - The deep link URL
   */
  closeRemoteConnection(accountId: string, dapp: StoredDappConnection): Promise<void>;

  /**
   * Check if a deep link URL belongs to this protocol.
   */
  canHandleDeepLink(url: string): boolean;
}

// =============================================================================
// Chain dApp Support Extension
// =============================================================================

/**
 * Chain-specific session info for protocol handshakes.
 */
export interface ChainDappSessionInfo {
  /** Wallet address */
  address: string;
  /** Public key (hex-encoded) */
  publicKey?: string;
  /** Any chain-specific additional info */
  extra?: Record<string, unknown>;
}

export interface DappSignDataResult<T extends DappProtocolType = any> {
  chain: T extends 'tonConnect' ? 'ton' : ApiChain;
  result: Omit<SignDataRpcResponseSuccess['result'], 'payload'>
    & {
      payload: UnifiedSignDataPayload;
    };
}

/**
 * dApp support interface to be added to ChainSdk.
 * This allows chains to provide protocol-agnostic dApp functionality.
 */
export interface ChainDappSupport<T extends ApiChain = any> {
  /** Which protocols this chain supports */
  supportedProtocols: DappProtocolType[];

  /**
   * Sign a connection proof (e.g., TON Proof, Solana message).
   */
  signConnectionProof?(
    accountId: string,
    proof: DappProofRequest,
    password?: string,
  ): Promise<{ signature: string } | { error: ApiAnyDisplayError }>;

  signDappTransfers(
    accountId: string,
    transactions: ApiDappTransfer[],
    options: {
      password?: string;
      validUntil?: number;
      vestingAddress?: string;
      isLegacyOutput?: boolean;
    },
  ): Promise<ApiSignedTransfer<
    T extends 'ton'
      ? DappProtocolType.TonConnect
      : DappProtocolType.WalletConnect
  >[] | { error: ApiAnyDisplayError }
  >;

  signDappData(
    accountId: string,
    url: string,
    payload: UnifiedSignDataPayload,
    password?: string
  ): Promise<DappSignDataResult | { error: ApiAnyDisplayError }>;

  // Used by Solana only now
  parseTransactionForPreview?(
    rawTx: string,
    address: string,
    network: ApiNetwork,
  ): Promise<{ transfers: ApiDappTransfer[]; emulation: ApiEmulationResult | undefined }>;

  // Used by Solana only now
  sendSignedTransaction?(
    transaction: string,
    network: ApiNetwork,
  ): Promise<string>;
}

// =============================================================================
// Protocol Manager Types
// =============================================================================

/**
 * Registry entry for a protocol adapter.
 */
export interface DappProtocolRegistration {
  adapter: DappProtocolAdapter;
  initialized: boolean;
}

/**
 * Interface for the protocol manager that coordinates all adapters.
 */
export interface AbstractDappProtocolManager {
  /**
   * Register a protocol adapter.
   */
  registerAdapter(adapter: DappProtocolAdapter): void;

  /**
   * Initialize all registered adapters.
   */
  init(config: DappProtocolConfig): Promise<void>;

  /**
   * Get adapter for a specific protocol.
   */
  getAdapter(type: DappProtocolType): DappProtocolAdapter | undefined;

  /**
   * Handle a deep link, routing to appropriate adapter.
   */
  handleDeepLink(
    url: string,
    isFromInAppBrowser?: boolean,
    requestId?: string
  ): Promise<string | undefined>;

  /**
   * Find appropriate adapter for specific dApp then resetup remote connection.
   */
  resetupRemoteConnection(url?: string): Promise<void>;

  /**
   * Find appropriate adapter for specific dApp then close remote connection.
   */
  closeRemoteConnection(accountId: string, dapp: StoredDappConnection): Promise<void>;

  /**
   * Destroy all adapters and clean up.
   */
  destroy(): Promise<void>;
}
