/**
 * dApp Protocol Adapters
 *
 * This module exports all available protocol adapters.
 */

export { getTonConnectAdapter, createTonConnectAdapter } from './tonConnect';
export { getWalletConnectAdapter, createWalletConnectAdapter } from './walletConnect';

// Re-export adapter-specific types
export type { TonConnectProof } from './tonConnect/types';
export type { WalletConnectNamespaces } from './walletConnect/types';
