/**
 * Generalized dApp Session Storage Types
 *
 * These types extend the existing ApiDapp storage structure to support
 * multiple protocols while maintaining backward compatibility.
 */

import type { ApiChain, ApiDappurlTrustStatusStatus, ApiNetwork } from '../types';
import type { ApiSseOptions } from '../types/storage';
import type { DappMetadata, DappSessionChain } from './types';
import { DappProtocolType } from './types';

// =============================================================================
// Storage Types
// =============================================================================

/**
 * Base dApp connection stored in persistence.
 * Extends existing ApiDapp structure with protocol type.
 */
export interface StoredDappConnection {
  /** Protocol type - defaults to 'tonConnect' for backward compatibility */
  protocolType?: DappProtocolType;

  // --- Common fields (from existing ApiDappMetadata) ---
  /** dApp URL (origin) */
  url: string;
  /** dApp display name */
  name: string;
  /** dApp icon URL */
  iconUrl: string;
  /** Manifest URL (TON Connect) */
  manifestUrl?: string;

  // --- Session fields ---
  /** When the connection was established (Unix timestamp ms) */
  connectedAt: number;
  /** Domain trust level (WalletConnect Verify, trusted bridge origin, etc.). */
  urlTrustStatus?: ApiDappurlTrustStatusStatus;

  // --- Protocol-specific data ---
  /** SSE options for TON Connect SSE connections */
  sse?: ApiSseOptions;
  /** WalletConnect session topic */
  wcTopic?: string;
  /** WalletConnect pairing topic */
  wcPairingTopic?: string;
  /** Connected chains for this session */
  chains?: StoredSessionChain[];
}

/**
 * Chain info stored in persistence.
 */
export interface StoredSessionChain {
  chain: ApiChain;
  address: string;
  network: ApiNetwork;
}

/**
 * Storage structure for all dApp connections.
 * Indexed by accountId -> url -> uniqueId -> connection
 *
 * This maintains backward compatibility with existing ApiDappsState structure.
 */
type AccountId = string;
type DappUrl = string;
type DappConnectionId = string;
export type StoredDappsState = Record<AccountId, StoredDappsByUrl>;
export type StoredDappsByUrl = Record<DappUrl, StoredDappsById>;
export type StoredDappsById = Record<DappConnectionId, StoredDappConnection>;

// =============================================================================
// Migration Helpers
// =============================================================================

/**
 * Check if a stored connection is using the legacy format (no protocolType).
 */
export function isLegacyConnection(connection: StoredDappConnection): boolean {
  return connection.protocolType === undefined;
}

const URL_TRUST_STATUSES: ReadonlySet<ApiDappurlTrustStatusStatus> = new Set([
  'verified',
  'unknown',
  'invalid',
  'dangerous',
]);

type StoredDappConnectionWithLegacy = StoredDappConnection & { isUrlEnsured?: boolean };

function normalizeStoredDappurlTrustStatus(connection: StoredDappConnectionWithLegacy): StoredDappConnection {
  const { isUrlEnsured: _legacy, ...rest } = connection;
  let urlTrustStatus = rest.urlTrustStatus;

  if (!urlTrustStatus || !URL_TRUST_STATUSES.has(urlTrustStatus)) {
    urlTrustStatus = _legacy === true ? 'verified' : 'unknown';
  }

  return { ...rest, urlTrustStatus };
}

/**
 * Migrate a legacy connection to the new format.
 * All legacy connections are assumed to be TON Connect.
 */
export function migrateLegacyConnection(connection: StoredDappConnection): StoredDappConnection {
  let next: StoredDappConnectionWithLegacy = { ...connection };

  if (isLegacyConnection(connection)) {
    next = { ...next, protocolType: DappProtocolType.TonConnect };
  }

  return normalizeStoredDappurlTrustStatus(next);
}

// =============================================================================
// Conversion Helpers
// =============================================================================

/**
 * Convert stored connection to DappMetadata.
 */
export function toMetadata(connection: StoredDappConnection): DappMetadata {
  return {
    url: connection.url,
    name: connection.name,
    iconUrl: connection.iconUrl,
    manifestUrl: connection.manifestUrl,
  };
}

/**
 * Convert stored session chains to runtime format.
 */
export function toSessionChains(stored: StoredSessionChain[] | undefined): DappSessionChain[] {
  if (!stored) return [];

  return stored.map((chain) => ({
    chain: chain.chain,
    address: chain.address,
    network: chain.network,
  }));
}

// =============================================================================
// Filter Helpers
// =============================================================================

/**
 * Filter connections by protocol type.
 */
export function filterByProtocol(
  connections: StoredDappConnection[],
  protocolType: DappProtocolType,
): StoredDappConnection[] {
  return connections.filter((conn) => {
    const type = conn.protocolType ?? DappProtocolType.TonConnect;
    return type === protocolType;
  });
}

/**
 * Get all connections for a specific account and protocol.
 */
export function getAccountConnectionsByProtocol(
  state: StoredDappsState | undefined,
  accountId: string,
  protocolType: DappProtocolType,
): StoredDappConnection[] {
  if (!state?.[accountId]) return [];

  const byUrl = state[accountId];
  const connections: StoredDappConnection[] = [];

  for (const byId of Object.values(byUrl)) {
    for (const connection of Object.values(byId)) {
      const type = connection.protocolType ?? DappProtocolType.TonConnect;
      if (type === protocolType) {
        connections.push(connection);
      }
    }
  }

  return connections;
}
