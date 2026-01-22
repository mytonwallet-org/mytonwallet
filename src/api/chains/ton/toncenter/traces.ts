import type { ApiNetwork } from '../../../types';
import type { AddressBook, MetadataMap, Trace } from './types';

import { callToncenterV3 } from './other';

export type TracesResponse = {
  traces: Trace[];
  address_book: AddressBook;
  metadata: MetadataMap;
};

type FetchTraceResult = {
  trace?: Trace;
  addressBook: AddressBook;
  metadata: MetadataMap;
};

export async function fetchTrace(options: {
  network: ApiNetwork;
  msgHashNormalized: string;
  isActionPending?: boolean;
}): Promise<FetchTraceResult> {
  const { network, msgHashNormalized, isActionPending } = options;

  const response = await callToncenterV3<TracesResponse>(
    network,
    isActionPending ? '/pendingTraces' : '/traces',
    {
      [isActionPending ? 'ext_msg_hash' : 'msg_hash']: msgHashNormalized,
      include_actions: true,
    },
  );

  return {
    trace: response.traces[0],
    addressBook: response.address_book,
    metadata: response.metadata,
  };
}

/**
 * Fetches trace by ID, trying both `trace_id` and `msg_hash` parameters.
 * This is useful when the ID type is unknown (e.g., from a deeplink).
 */
export async function fetchTraceByIdOrHash(options: {
  network: ApiNetwork;
  txId: string;
}): Promise<FetchTraceResult> {
  const { network, txId } = options;

  // Try `trace_id` first as it's more likely for user-provided transaction IDs
  const responseByTraceId = await callToncenterV3<TracesResponse>(
    network,
    '/traces',
    {
      trace_id: txId,
      include_actions: true,
    },
  );

  if (responseByTraceId.traces.length > 0) {
    return {
      trace: responseByTraceId.traces[0],
      addressBook: responseByTraceId.address_book,
      metadata: responseByTraceId.metadata,
    };
  }

  // Fall back to `msg_hash` if `trace_id` didn't find anything
  const responseByMsgHash = await callToncenterV3<TracesResponse>(
    network,
    '/traces',
    {
      msg_hash: txId,
      include_actions: true,
    },
  );

  return {
    trace: responseByMsgHash.traces[0],
    addressBook: responseByMsgHash.address_book,
    metadata: responseByMsgHash.metadata,
  };
}

export async function fetchTraceByTxHash(options: {
  network: ApiNetwork;
  txHash: string;
}): Promise<FetchTraceResult> {
  const { network, txHash } = options;

  const response = await callToncenterV3<TracesResponse>(
    network,
    '/traces',
    {
      tx_hash: txHash,
      include_actions: true,
    },
  );

  return {
    trace: response.traces[0],
    addressBook: response.address_book,
    metadata: response.metadata,
  };
}
