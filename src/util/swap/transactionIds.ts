import type { ApiChain, ApiSwapActivity } from '../../api/types';

import { parseTxId } from '../activities';
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

function getFallbackSwapTransactionId({ id, cex, hashes, from }: ApiSwapActivity): SwapTransactionId | undefined {
  const chain = getChainBySlug(from);
  if (!chain) return undefined;

  if (!cex) {
    return {
      hash: parseTxId(id).hash,
      chain,
    };
  }

  if (!hashes[0]) return undefined;

  return {
    hash: hashes[0],
    chain, // Legacy fallback: historically assumed to be the source transaction hash.
  };
}
