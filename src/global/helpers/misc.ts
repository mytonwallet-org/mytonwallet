import type { AccountState, GlobalState } from '../types';

import { getChainFromAddress } from '../../util/isValidAddress';
import { getChainBySlug, getNativeToken } from '../../util/tokens';
import { getActions } from '../index';
import { selectCurrentAccount } from '../selectors';

/**
 * Parses the transfer parameters from the given QR content, assuming it's a plain address.
 * Returns `undefined` if this is not a valid address or the account doesn't have the corresponding wallet.
 */
export function parsePlainAddressQr(global: GlobalState, qrData: string) {
  const availableChains = selectCurrentAccount(global)?.byChain ?? {};
  const newChain = getChainFromAddress(qrData, availableChains, true);
  if (!newChain) {
    return undefined;
  }

  const currentTokenSlug = global.currentTransfer.tokenSlug;
  const currentChain = getChainBySlug(currentTokenSlug);
  const newTokenSlug = newChain !== currentChain ? getNativeToken(newChain).slug : currentTokenSlug;

  return {
    toAddress: qrData,
    tokenSlug: newTokenSlug,
  };
}

export function closeAllOverlays() {
  getActions().closeAnyModal();
  getActions().closeMediaViewer();
  return Promise.resolve();
}

/** replaceMap: keys - old (removed) activity ids, value - new (added) activity ids */
export function replaceActivityId(oldId: string | undefined, replaceMap: Record<string, string>) {
  const newId = oldId && replaceMap[oldId];
  return newId || oldId;
}

/**
 * An activity can be replaced by another row with a new id, for example a local swap is replaced by the row from
 * the chain. An id remembered before that replacement points to a row that no longer exists. This function walks
 * the chain of replacements and returns the id of the row that is present in `byId` now.
 */
export function resolveReplacedActivityId(activities: AccountState['activities'], id: string) {
  const { byId = {}, activityIdReplacements = {} } = activities ?? {};
  const visitedIds = new Set<string>();
  let resolvedId = id;

  while (!byId[resolvedId] && activityIdReplacements[resolvedId] && !visitedIds.has(resolvedId)) {
    visitedIds.add(resolvedId);
    resolvedId = activityIdReplacements[resolvedId];
  }

  return resolvedId;
}
