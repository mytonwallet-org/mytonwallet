import type { ApiSwapActivity, ApiSwapHistoryItem } from '../../../types';
import type { ActiveCexSwapReconciliationState } from './types';

import { getIsBackendSwapId, parseTxId } from '../../../../util/activities';
import { storage } from '../../../storages';
import { normalizeIdentifier } from './matcher';
import { mutateReconcilerStorageItem } from './storageMutationQueue';

const STORAGE_KEY = 'activeCexSwapReconciliationState';
const MAX_STATES_PER_ACCOUNT = 100;
const FINAL_STATE_TTL_MS = 24 * 60 * 60 * 1000;
const ACTIVE_STATUSES = new Set(['pending', 'pendingTrusted']);

export function buildActiveCexSwapState(
  accountId: string,
  swap: ApiSwapHistoryItem | ApiSwapActivity,
): ActiveCexSwapReconciliationState | undefined {
  if (!swap.cex) return undefined;

  const backendSwapId = normalizeBackendSwapId(swap.id);
  const knownHashes = normalizeHashes([
    ...(swap.hashes ?? []),
    swap.msgHash,
    'externalMsgHashNorm' in swap ? swap.externalMsgHashNorm : undefined,
  ]);

  return {
    accountId,
    backendSwapId,
    cexTransactionId: swap.cex.transactionId,
    provider: swap.cexLabel,
    status: swap.isCanceled ? 'expired' : swap.status,
    knownHashes,
    submittedHashes: [],
    from: swap.from,
    to: swap.to,
    createdAt: swap.timestamp,
    updatedAt: Date.now(),
  };
}

export async function rememberActiveCexSwap(accountId: string, swap: ApiSwapHistoryItem | ApiSwapActivity) {
  const state = buildActiveCexSwapState(accountId, swap);
  if (!state) return;

  await mutateActiveCexSwapStates(accountId, (states) => upsertActiveCexSwapStates(states, [state]));
}

export async function rememberActiveCexSwaps(
  accountId: string,
  swaps: readonly (ApiSwapHistoryItem | ApiSwapActivity)[],
) {
  const states = swaps
    .map((swap) => buildActiveCexSwapState(accountId, swap))
    .filter((state): state is ActiveCexSwapReconciliationState => Boolean(state));
  if (!states.length) return;

  await mutateActiveCexSwapStates(accountId, (existing) => upsertActiveCexSwapStates(existing, states));
}

export async function rememberActiveCexSwapSubmittedHashes(
  accountId: string,
  backendSwapId: string,
  submittedHashes: readonly string[],
) {
  const normalizedBackendSwapId = normalizeBackendSwapIdForInput(backendSwapId);
  const hashes = normalizeHashes(submittedHashes);
  if (!hashes.length) return;

  await mutateActiveCexSwapStates(accountId, (states) => {
    const existing = states.find((state) => state.backendSwapId === normalizedBackendSwapId);
    const nextState: ActiveCexSwapReconciliationState = existing
      ? {
        ...existing,
        submittedHashes: normalizeHashes([...existing.submittedHashes, ...hashes]),
        updatedAt: Date.now(),
      }
      : {
        accountId,
        backendSwapId: normalizedBackendSwapId,
        status: 'pendingTrusted',
        knownHashes: [],
        submittedHashes: hashes,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

    return upsertActiveCexSwapStates(states, [nextState]);
  });
}

export async function expireActiveCexSwaps(accountId: string, backendSwapIds: readonly string[]) {
  const normalizedBackendSwapIds = new Set(backendSwapIds.map(normalizeBackendSwapIdForInput));
  if (!normalizedBackendSwapIds.size) return;

  await mutateActiveCexSwapStates(accountId, (states) => states.map((state) => (
    normalizedBackendSwapIds.has(state.backendSwapId)
      ? { ...state, status: 'expired', updatedAt: Date.now() }
      : state
  )));
}

export async function getActiveCexSwapStates(accountId: string): Promise<ActiveCexSwapReconciliationState[]> {
  const byAccount = await storage.getItem(STORAGE_KEY);
  return pruneStates(byAccount?.[accountId] ?? []).filter(isActiveCexSwapState);
}

async function mutateActiveCexSwapStates(
  accountId: string,
  mutate: (states: ActiveCexSwapReconciliationState[]) => ActiveCexSwapReconciliationState[],
) {
  await mutateReconcilerStorageItem<Record<string, ActiveCexSwapReconciliationState[]>>(STORAGE_KEY, (byAccount) => {
    const nextByAccount = { ...byAccount };
    nextByAccount[accountId] = pruneStates(mutate(pruneStates(nextByAccount[accountId] ?? [])));
    return nextByAccount;
  });
}

function upsertActiveCexSwapStates(
  states: readonly ActiveCexSwapReconciliationState[],
  incomingStates: readonly ActiveCexSwapReconciliationState[],
) {
  const byBackendId = new Map(states.map((state) => [state.backendSwapId, state]));

  for (const incoming of incomingStates) {
    const existing = byBackendId.get(incoming.backendSwapId);
    byBackendId.set(incoming.backendSwapId, existing ? mergeActiveCexSwapState(existing, incoming) : incoming);
  }

  return Array.from(byBackendId.values());
}

function mergeActiveCexSwapState(
  existing: ActiveCexSwapReconciliationState,
  incoming: ActiveCexSwapReconciliationState,
): ActiveCexSwapReconciliationState {
  const status = getMostProgressedStatus(existing.status, incoming.status);
  return {
    ...existing,
    ...incoming,
    cexTransactionId: incoming.cexTransactionId ?? existing.cexTransactionId,
    provider: incoming.provider ?? existing.provider,
    knownHashes: normalizeHashes([...existing.knownHashes, ...incoming.knownHashes]),
    submittedHashes: normalizeHashes([...existing.submittedHashes, ...incoming.submittedHashes]),
    status,
    createdAt: Math.min(existing.createdAt, incoming.createdAt),
    updatedAt: Math.max(existing.updatedAt, incoming.updatedAt),
  };
}

function getMostProgressedStatus(
  existing: ActiveCexSwapReconciliationState['status'],
  incoming: ActiveCexSwapReconciliationState['status'],
): ActiveCexSwapReconciliationState['status'] {
  const rank: Record<ActiveCexSwapReconciliationState['status'], number> = {
    local: 0,
    pending: 1,
    pendingTrusted: 2,
    confirmed: 3,
    completed: 4,
    failed: 4,
    expired: 4,
  };
  return rank[incoming] > rank[existing] ? incoming : existing;
}

function pruneStates(states: readonly ActiveCexSwapReconciliationState[]) {
  const finalStateCutoff = Date.now() - FINAL_STATE_TTL_MS;
  return [...states]
    .filter((state) => isActiveCexSwapState(state) || state.updatedAt >= finalStateCutoff)
    .sort((a, b) => b.updatedAt - a.updatedAt || a.backendSwapId.localeCompare(b.backendSwapId))
    .slice(0, MAX_STATES_PER_ACCOUNT);
}

function isActiveCexSwapState(state: ActiveCexSwapReconciliationState) {
  return ACTIVE_STATUSES.has(state.status);
}

function normalizeHashes(hashes: readonly (string | undefined)[]) {
  return Array.from(new Set(hashes.map(normalizeIdentifier).filter((hash): hash is string => Boolean(hash))));
}

function normalizeBackendSwapId(id: string) {
  const parsed = parseTxId(id);
  return getIsBackendSwapId(id) || parsed.type === 'local' ? parsed.hash : id;
}

function normalizeBackendSwapIdForInput(id: string) {
  return normalizeBackendSwapId(id.replace(/^swap:/u, ''));
}
