/**
 * Backend DEX duplicate suppression for one narrow case: the backend can return a TON DEX swap row for the same
 * blockchain swap that the SDK has already represented as a TON trace aggregate. Without suppression the UI can show
 * both the backend DEX row and the SDK aggregate. This is not a generic DEX identity layer: suppression is allowed
 * only when the rows share explicit identity (hash, trace/source id, operation id, or backend swap id), never by
 * pair/amount/timestamp similarity.
 */
import type { ApiSwapActivity } from '../../../types';
import type { WalletOperationIntent } from './types';

import { getIsBackendSwapId, getIsTxIdLocal, parseTxId } from '../../../../util/activities';
import { getActivityMatchKeys, normalizeIdentifier } from './matcher';

type IdentityKeyKind = 'backend-swap' | 'operation' | 'chain';

type IdentityKey = `${IdentityKeyKind}:${string}`;

/**
 * Returns the backend TON DEX swaps that one aggregate already represents, by explicit shared identity only.
 *
 * This intentionally does not consider pair, amount, or timestamp similarity. Those fields are presentation data and
 * are not a deterministic relation: two same-sized swaps can happen close together. Duplicate suppression must fail
 * closed unless the backend row exposes a hash/id that is represented by the aggregate metadata or raw trace ids.
 */
export function getBackendDexSwapIdsRepresentedByTonAggregates(
  aggregates: readonly ApiSwapActivity[],
  backendSwaps: readonly ApiSwapActivity[],
  intents: readonly WalletOperationIntent[],
) {
  const keysByAggregate = aggregates.map((aggregate) => getTonAggregateIdentityKeys(aggregate, intents));
  const matchedAggregatesBySwap = backendSwaps.map((backendSwap) => {
    const swapKeys = getBackendDexSwapIdentityKeys(backendSwap, intents);
    return keysByAggregate
      .map((aggregateKeys, index) => (hasSharedKey(aggregateKeys, swapKeys) ? index : -1))
      .filter((index) => index >= 0);
  });
  const swapCountByAggregate = new Array<number>(aggregates.length).fill(0);

  for (const matchedAggregates of matchedAggregatesBySwap) {
    for (const index of matchedAggregates) swapCountByAggregate[index] += 1;
  }

  const representedSwapIds = new Set<string>();

  backendSwaps.forEach((backendSwap, index) => {
    const matchedAggregates = matchedAggregatesBySwap[index];
    // Both directions have to be unambiguous. One aggregate answering to several rows is as unresolved as one row
    // answering to several aggregates: dropping the rows in that state would leave one line where two trades happened.
    if (matchedAggregates.length !== 1) return;
    if (swapCountByAggregate[matchedAggregates[0]] !== 1) return;
    representedSwapIds.add(backendSwap.id);
  });

  return representedSwapIds;
}

function hasSharedKey(keys: ReadonlySet<IdentityKey>, otherKeys: ReadonlySet<IdentityKey>) {
  if (!keys.size || !otherKeys.size) return false;

  for (const key of otherKeys) {
    if (keys.has(key)) return true;
  }

  return false;
}

function getTonAggregateIdentityKeys(
  activity: ApiSwapActivity,
  intents: readonly WalletOperationIntent[],
) {
  const keys = new Set<IdentityKey>();
  const reconciliation = activity.extra?.reconciliation;

  addChainKey(keys, activity.externalMsgHashNorm);
  for (const hash of activity.hashes ?? []) addChainKey(keys, hash);
  addChainKey(keys, activity.extra?.mtwAggregator?.traceId);
  addOperationKey(keys, reconciliation?.operationId);
  addIntentOperationKeys(keys, activity, intents);
  addActivityIdKeys(keys, activity.id);

  for (const sourceActionId of reconciliation?.sourceActionIds ?? []) {
    addActivityIdKeys(keys, sourceActionId);
  }

  for (const hiddenSourceActionId of reconciliation?.hiddenSourceActionIds ?? []) {
    addActivityIdKeys(keys, hiddenSourceActionId);
  }

  return keys;
}

function getBackendDexSwapIdentityKeys(
  activity: ApiSwapActivity,
  intents: readonly WalletOperationIntent[],
) {
  const keys = new Set<IdentityKey>();
  const reconciliation = activity.extra?.reconciliation;

  addChainKey(keys, activity.externalMsgHashNorm);
  for (const hash of activity.hashes ?? []) addChainKey(keys, hash);
  addOperationKey(keys, reconciliation?.operationId);
  addIntentOperationKeys(keys, activity, intents);

  if (getIsBackendSwapId(activity.id)) {
    addBackendSwapKey(keys, parseTxId(activity.id).hash);
  } else {
    addActivityIdKeys(keys, activity.id);
  }

  for (const sourceActionId of reconciliation?.sourceActionIds ?? []) {
    if (getIsBackendSwapId(sourceActionId)) addBackendSwapKey(keys, parseTxId(sourceActionId).hash);
  }

  return keys;
}

/**
 * An intent names the operation a signed message belongs to, so two rows the same intent claims are the same trade.
 * This is the identity of last resort and the only one a venue-settled trade has: its row carries no chain hash until
 * the deposit trace is read, which for such a trade happens late or not at all.
 */
function addIntentOperationKeys(
  keys: Set<IdentityKey>,
  activity: ApiSwapActivity,
  intents: readonly WalletOperationIntent[],
) {
  if (!intents.length) return;

  for (const key of getActivityMatchKeys(activity, intents)) {
    if (key.type === 'operationId') addOperationKey(keys, key.value);
  }
}

function addActivityIdKeys(keys: Set<IdentityKey>, activityId: string | undefined) {
  if (!activityId || getIsTxIdLocal(activityId)) return;

  if (getIsBackendSwapId(activityId)) {
    addBackendSwapKey(keys, parseTxId(activityId).hash);
    return;
  }

  addChainKey(keys, parseTxId(activityId).hash);
}

function addBackendSwapKey(keys: Set<IdentityKey>, value: string | undefined) {
  addKey(keys, 'backend-swap', value);
}

function addOperationKey(keys: Set<IdentityKey>, value: string | undefined) {
  addKey(keys, 'operation', value);
}

function addChainKey(keys: Set<IdentityKey>, value: string | undefined) {
  addKey(keys, 'chain', value);
}

function addKey(keys: Set<IdentityKey>, kind: IdentityKeyKind, value: string | undefined) {
  const normalizedValue = normalizeIdentifier(value);
  if (normalizedValue) keys.add(`${kind}:${normalizedValue}`);
}
