import type { ApiChain, ApiSwapHistoryItem } from '../../../types';
import type { WalletOperationIntent } from './types';

import { getIsBackendSwapId, parseTxId } from '../../../../util/activities';
import { getChainBySlug } from '../../../../util/tokens';
import { storage } from '../../../storages';
import { mutateReconcilerStorageItem } from './storageMutationQueue';

const STORAGE_KEY = 'walletOperationIntents';
const MAX_INTENTS_PER_ACCOUNT = 100;
const MAX_INTENT_AGE_MS = 7 * 24 * 60 * 60 * 1000;

export function buildSwapOperationId(backendSwapId: string) {
  return `swap:${normalizeBackendSwapId(backendSwapId)}`;
}

export async function getWalletOperationIntents(accountId: string): Promise<WalletOperationIntent[]> {
  const byAccount = await storage.getItem(STORAGE_KEY);
  return pruneIntents(byAccount?.[accountId] ?? []);
}

export async function upsertWalletOperationIntent(intent: WalletOperationIntent) {
  await mutateWalletOperationIntents(intent.accountId, (intents) => {
    const existing = intents.find((item) => item.operationId === intent.operationId);
    const nextIntent = existing ? mergeWalletOperationIntents(existing, intent) : intent;
    return [
      nextIntent,
      ...intents.filter((item) => item.operationId !== intent.operationId),
    ];
  });
}

export async function rememberCexSwapOperationIntent(accountId: string, swap: ApiSwapHistoryItem) {
  await upsertWalletOperationIntent(buildCexSwapOperationIntent(accountId, swap));
}

export async function rememberDexSwapOperationIntent(
  accountId: string,
  swap: ApiSwapHistoryItem,
  options: {
    gasless?: boolean;
    expectedExternalMsgHashNorm?: string;
  } = {},
) {
  await upsertWalletOperationIntent(buildDexSwapOperationIntent(accountId, swap, options));
}

export function buildCexSwapOperationIntent(accountId: string, swap: ApiSwapHistoryItem): WalletOperationIntent {
  const backendSwapId = normalizeBackendSwapId(swap.id);

  return {
    operationId: buildSwapOperationId(backendSwapId),
    accountId,
    kind: 'swap',
    createdAt: swap.timestamp,
    status: swap.status,
    from: {
      slug: swap.from,
      amount: swap.fromAmount,
      chain: maybeGetChainBySlug(swap.from),
    },
    to: {
      slug: swap.to,
      amount: swap.toAmount,
      chain: maybeGetChainBySlug(swap.to),
    },
    swap: {
      type: 'cex',
      backendSwapId,
      cexTransactionId: swap.cex?.transactionId,
      submittedHashes: swap.hashes,
    },
  };
}

export function buildDexSwapOperationIntent(
  accountId: string,
  swap: ApiSwapHistoryItem,
  options: {
    gasless?: boolean;
    expectedExternalMsgHashNorm?: string;
  } = {},
): WalletOperationIntent {
  const backendSwapId = normalizeBackendSwapId(swap.id);

  return {
    operationId: buildSwapOperationId(backendSwapId),
    accountId,
    kind: 'swap',
    createdAt: swap.timestamp,
    status: swap.status,
    from: {
      slug: swap.from,
      amount: swap.fromAmount,
      chain: maybeGetChainBySlug(swap.from),
    },
    to: {
      slug: swap.to,
      amount: swap.toAmount,
      chain: maybeGetChainBySlug(swap.to),
    },
    swap: {
      type: 'dex',
      backendSwapId,
      expectedExternalMsgHashNorm: options.expectedExternalMsgHashNorm,
      submittedHashes: swap.hashes,
      gasless: options.gasless,
    },
  };
}

export async function rememberWalletOperationSubmittedHashes(
  accountId: string,
  operationId: string,
  submittedHashes: readonly string[],
) {
  const normalizedOperationId = normalizeSwapOperationId(operationId);
  const hashes = submittedHashes.filter(Boolean);
  if (!hashes.length) return;

  await mutateWalletOperationIntents(accountId, (intents) => {
    if (!intents.some((intent) => intent.operationId === normalizedOperationId)) {
      return [{
        operationId: normalizedOperationId,
        accountId,
        kind: 'swap',
        createdAt: Date.now(),
        status: 'pendingTrusted',
        swap: {
          type: 'cex',
          backendSwapId: normalizeBackendSwapId(operationId.replace(/^swap:/u, '')),
          submittedHashes: hashes,
        },
      }, ...intents];
    }

    return intents.map((intent) => {
      if (intent.operationId !== normalizedOperationId) return intent;
      if (!intent.swap) return intent;

      return {
        ...intent,
        swap: {
          ...intent.swap,
          submittedHashes: unique([...(intent.swap?.submittedHashes ?? []), ...hashes]),
        },
      } satisfies WalletOperationIntent;
    });
  });
}

async function mutateWalletOperationIntents(
  accountId: string,
  mutate: (intents: WalletOperationIntent[]) => WalletOperationIntent[],
) {
  await mutateReconcilerStorageItem<Record<string, WalletOperationIntent[]>>(STORAGE_KEY, (byAccount) => {
    const nextByAccount = { ...byAccount };
    nextByAccount[accountId] = pruneIntents(mutate(pruneIntents(nextByAccount[accountId] ?? [])));
    return nextByAccount;
  });
}

function mergeWalletOperationIntents(
  existing: WalletOperationIntent,
  incoming: WalletOperationIntent): WalletOperationIntent {
  const swap = existing.swap || incoming.swap
    ? {
      ...existing.swap,
      ...incoming.swap,
      submittedHashes: unique([
        ...(existing.swap?.submittedHashes ?? []),
        ...(incoming.swap?.submittedHashes ?? []),
      ]),
    } as WalletOperationIntent['swap']
    : undefined;

  return {
    ...existing,
    ...incoming,
    swap,
  };
}

function pruneIntents(intents: readonly WalletOperationIntent[]) {
  const cutoff = Date.now() - MAX_INTENT_AGE_MS;
  return [...intents]
    .filter((intent) => intent.createdAt >= cutoff || intent.status === 'pending' || intent.status === 'pendingTrusted')
    .sort((a, b) => b.createdAt - a.createdAt || a.operationId.localeCompare(b.operationId))
    .slice(0, MAX_INTENTS_PER_ACCOUNT);
}

function unique(values: readonly string[]) {
  return Array.from(new Set(values.filter(Boolean)));
}

function maybeGetChainBySlug(slug: string): ApiChain | undefined {
  try {
    return getChainBySlug(slug);
  } catch {
    return undefined;
  }
}

function normalizeSwapOperationId(operationId: string) {
  if (!operationId.startsWith('swap:')) return operationId;
  return buildSwapOperationId(operationId.replace(/^swap:/u, ''));
}

function normalizeBackendSwapId(id: string) {
  const parsed = parseTxId(id);
  return getIsBackendSwapId(id) || parsed.type === 'local' ? parsed.hash : id;
}
