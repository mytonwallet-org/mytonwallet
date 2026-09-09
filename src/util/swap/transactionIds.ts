import type { ApiChain, ApiSwapActivity } from '../../api/types';

import { getIsBackendSwapId, getIsTxIdLocal, parseTxId } from '../activities';
import { getChainBySlug } from '../tokens';

type SwapTransactionId = {
  hash: string;
  chain: ApiChain;
};

export type SwapTransactionIdRow = SwapTransactionId & {
  label: 'Transaction ID' | 'Outgoing Transaction ID' | 'Incoming Transaction ID';
};

export function getSwapTransactionIdRows(activity: ApiSwapActivity): SwapTransactionIdRow[] {
  const { outgoing, incoming } = activity.transactionIds;

  if (outgoing?.hash && incoming?.hash && outgoing.hash !== incoming.hash) {
    return [
      { ...outgoing, label: 'Outgoing Transaction ID' },
      { ...incoming, label: 'Incoming Transaction ID' },
    ];
  }

  const singleTransactionId = outgoing ?? incoming;
  if (singleTransactionId?.hash) {
    return [{ ...singleTransactionId, label: 'Transaction ID' }];
  }

  const fallback = getFallbackSwapTransactionId(activity);
  return fallback ? [{ ...fallback, label: 'Transaction ID' }] : [];
}

function getFallbackSwapTransactionId(activity: ApiSwapActivity): SwapTransactionId | undefined {
  const { id, cex, hashes, externalMsgHashNorm, from } = activity;
  const chain = getChainBySlug(from);
  if (!chain) return undefined;

  if (!cex) {
    // The transaction of a DEX swap is the trace the wallet signed. The id of a summary row (`<id>::backend-swap`,
    // `<id>::local`) names the backend record, not a transaction, so such a row without a hash has nothing to show
    const isSummaryRow = getIsBackendSwapId(id) || getIsTxIdLocal(id);
    const hash = externalMsgHashNorm ?? hashes[0] ?? (isSummaryRow ? undefined : parseTxId(id).hash);
    return hash ? { hash, chain } : undefined;
  }

  if (!hashes[0]) return undefined;

  return {
    hash: hashes[0],
    chain, // Legacy fallback: historically assumed to be the source transaction hash.
  };
}
