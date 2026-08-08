import { getAddressDecoder } from '@solana/kit';

import type { ApiDerivation, ApiDerivationSpec, ApiSolanaWallet } from '../../types';

import { bytesToHex } from '../../common/utils';
import { SOLANA_DERIVATION_PATHS } from './constants';

/**
 * Target derivation spec for new Solana wallets.
 * Uses the Phantom path at index 0, which matches `pickBestWallet(isMigration: true)`
 * in auth.ts - so new-user import and chain-upgrade produce identical wallets.
 */
export const SOLANA_DERIVATION_SPEC: ApiDerivationSpec = {
  standard: 'bip39',
  curve: 'ed25519',
  path: SOLANA_DERIVATION_PATHS.phantom.replace('{index}', '0'),
};

/** Current target version for Solana derivation. Bump to trigger re-derivation of all stored wallets. */
export const SOLANA_DERIVATION_VERSION = 1;

/**
 * Computes a Solana address from a raw ed25519 public key.
 * Pure: no side effects, no secret material involved.
 */
export function getAddressFromPublicKey(publicKey: Uint8Array): string {
  return getAddressDecoder().decode(publicKey);
}

/**
 * Builds a public Solana wallet entry from a raw ed25519 public key and its derivation meta.
 * Pure: no side effects, no secret material involved.
 *
 * Used by both:
 * - the new-user import flow (after chain SDK derives publicKey from mnemonic), and
 * - the chain-upgrade executor (after the Enclave returns publicKey for a stored account),
 * so the two paths produce identical wallet entries.
 *
 * Stamps the wallet with the current `SOLANA_DERIVATION_VERSION` so it will not be re-targeted
 * by the chain-upgrade detector until the version is bumped.
 */
export function buildWalletFromPublicKey(
  publicKey: Uint8Array,
  derivation: ApiDerivation,
): ApiSolanaWallet {
  return {
    address: getAddressFromPublicKey(publicKey),
    publicKey: bytesToHex(publicKey),
    index: 0,
    derivation,
    derivationVersion: SOLANA_DERIVATION_VERSION,
  };
}
