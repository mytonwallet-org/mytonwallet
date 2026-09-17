import type { ApiBalanceBySlug, ApiNetwork } from '../types';

import { parseAccountId } from '../../util/account';

/**
 * Tracks which tokens the polled wallets hold, so that the backend is asked for the details of those tokens only. The
 * token cache is a poor substitute: it accumulates every token ever seen on the device and is cleared on sign-out
 * alone.
 *
 * The set only grows while an account is polled. Balances reach it both as full snapshots and as single-token socket
 * deltas, and the two are indistinguishable at this point, so replacing a wallet's set with an incoming map would let
 * a delta drop the tokens it says nothing about. The cost is that a token spent during the session keeps its slot
 * until the next launch.
 *
 * Zero balances are ignored: providers report the token accounts of everything a wallet ever touched (TON asks for
 * jetton wallets with `exclude_zero_balance: false`, Solana with `showZeroBalance: true`), and those carry no holding.
 */

const slugsByAccount = new Map<string, Set<string>>();

/** Returns `true` when the balances contain a held slug that no polled wallet reported before. */
export function recordHeldTokens(accountId: string, balances: ApiBalanceBySlug) {
  let hasNewSlugs = false;
  let accountSlugs = slugsByAccount.get(accountId);

  for (const [slug, balance] of Object.entries(balances)) {
    if (balance <= 0n || accountSlugs?.has(slug)) continue;

    if (!accountSlugs) {
      accountSlugs = new Set();
      slugsByAccount.set(accountId, accountSlugs);
    }

    // Every wallet holding the token gets its own record, otherwise removing one of them would drop the token from the
    // union while the others still hold it. The payload, in contrast, changes only when no wallet held the token before.
    hasNewSlugs ||= !isHeld(slug);
    accountSlugs.add(slug);
  }

  return hasNewSlugs;
}

export function getHeldSlugs() {
  const result = new Set<string>();

  for (const accountSlugs of slugsByAccount.values()) {
    for (const slug of accountSlugs) {
      result.add(slug);
    }
  }

  return result;
}

export function forgetHeldTokens(accountId: string) {
  slugsByAccount.delete(accountId);
}

export function forgetNetworkHeldTokens(network: ApiNetwork) {
  forgetByNetwork((accountNetwork) => accountNetwork === network);
}

/** Only one network is polled at a time, so the rest hold nothing worth asking the backend about */
export function forgetOtherNetworksHeldTokens(network: ApiNetwork) {
  forgetByNetwork((accountNetwork) => accountNetwork !== network);
}

export function forgetAllHeldTokens() {
  slugsByAccount.clear();
}

function forgetByNetwork(shouldForget: (network: ApiNetwork) => boolean) {
  for (const accountId of slugsByAccount.keys()) {
    if (shouldForget(parseAccountId(accountId).network)) {
      slugsByAccount.delete(accountId);
    }
  }
}

function isHeld(slug: string) {
  for (const accountSlugs of slugsByAccount.values()) {
    if (accountSlugs.has(slug)) return true;
  }

  return false;
}
