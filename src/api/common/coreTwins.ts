import type { StorageKey } from '../storages/types';
import type { ApiAccountAny, ApiNetwork, OnApiUpdate } from '../types';

import { IS_CORE_WALLET, IS_FEATURE_LIMITED } from '../../config';
import { parseAccountId } from '../../util/account';
import { omit } from '../../util/iteratees';
import { storage } from '../storages';

// Older Core-identity builds silently mirrored every wallet onto the opposite network: importing a wallet created an
// invisible twin (same key, same contract) on testnet for a mainnet wallet and vice versa. Once the combo build
// (Core identity, features unlocked) exposes the network switcher and per-account logout, those hidden twins make
// `signOut` adopt a twin instead of resetting and let a "log out" leave the same secret behind.
//
// This is a boot-time idempotent purge, NOT a state migration: the twin population is defined by the build flavor,
// not the state version, so gating it on a stateVersion bump would let a trimmed build consume the bump and leave the
// twins (and the logout bug) unfixable once the same storage later serves the combo build. The `coreTwinsPurged`
// marker decouples it from stateVersion — a trimmed->combo flip still purges on the first combo boot.
//
// Crash-safety: dapps are cleaned BEFORE accounts, so a partial run leaves the twins still detectable in `accounts`
// and the next boot recomputes the same ids and re-cleans both. The purge always keeps the MAINNET member of a twin
// pair — mainnet holds the real funds, and a testnet-parked user upgrading to combo must not see their mainnet
// record vanish. The `removeAccounts` handler re-selects the active account onto a survivor if the removed twin
// was current, so no `currentAccountId` read is needed here.

/**
 * Full {chain -> publicKey} map of an account that owns a mnemonic (the only accounts older builds ever
 * auto-mirrored), or `undefined` when the account is not mnemonic-based or holds no public keys.
 */
function getMnemonicChainPublicKeys(account: ApiAccountAny): Record<string, string> | undefined {
  if (account.type !== 'ton' && account.type !== 'bip39') return undefined;
  const keys: Record<string, string> = {};
  for (const [chain, wallet] of Object.entries(account.byChain ?? {})) {
    if (wallet?.publicKey) keys[chain] = wallet.publicKey;
  }
  return Object.keys(keys).length ? keys : undefined;
}

/**
 * Ids of accounts on the non-kept network whose whole {chain -> publicKey} set is held by a single
 * kept-network account. Funds-safe by construction: every returned id has ALL of its keys retained in that
 * surviving kept-network sibling, so any deliberate wallet without a same-key kept-network mirror and any
 * multi-chain wallet only partially mirrored are never returned.
 */
export function findRemovableTwinIds(
  accounts: Record<string, ApiAccountAny>,
  keptNetwork: ApiNetwork,
): string[] {
  const keptNetworkKeyMaps: Record<string, string>[] = [];
  for (const [accountId, account] of Object.entries(accounts)) {
    if (parseAccountId(accountId).network !== keptNetwork) continue;
    const chainKeys = getMnemonicChainPublicKeys(account);
    if (chainKeys) keptNetworkKeyMaps.push(chainKeys);
  }

  const removableIds: string[] = [];
  for (const [accountId, account] of Object.entries(accounts)) {
    if (parseAccountId(accountId).network === keptNetwork) continue;
    const chainKeys = getMnemonicChainPublicKeys(account);
    const isFullyCovered = chainKeys && keptNetworkKeyMaps.some((siblingKeys) => (
      Object.entries(chainKeys).every(([chain, publicKey]) => siblingKeys[chain] === publicKey)
    ));
    if (isFullyCovered) {
      removableIds.push(accountId);
    }
  }

  return removableIds;
}

export async function purgeCoreTwins(onUpdate: OnApiUpdate) {
  // Only the full-featured combo build purges twins. The trimmed core build keeps them on purpose (it mirrors every
  // wallet across networks and relies on wipe-both logout) and must not touch the marker, so the eventual combo boot
  // over the same storage still runs the purge. Non-Core builds never created twins.
  if (!(IS_CORE_WALLET && !IS_FEATURE_LIMITED)) return;

  if (await storage.getItem('coreTwinsPurged' as StorageKey)) return;

  const accounts = await storage.getItem('accounts') as Record<string, ApiAccountAny> | undefined;
  const removableIds = accounts ? findRemovableTwinIds(accounts, 'mainnet') : [];

  if (removableIds.length) {
    const dapps = await storage.getItem('dapps') as Record<string, unknown> | undefined;
    if (dapps) {
      await storage.setItem('dapps', omit(dapps, removableIds));
    }
    await storage.setItem('accounts', omit(accounts!, removableIds));
    onUpdate({ type: 'removeAccounts', accountIds: removableIds });
  }

  // Set the marker only after a full successful pass (a no-twins storage also marks itself done).
  await storage.setItem('coreTwinsPurged' as StorageKey, true);
}
