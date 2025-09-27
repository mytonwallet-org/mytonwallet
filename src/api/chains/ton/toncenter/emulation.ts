import type { ApiNetwork } from '../../../types';
import type { AccountState, AddressBook, AnyAction, MetadataMap, TraceDetail, Transaction } from './types';

import { fetchWithRetry } from '../../../../util/fetch';
import { NETWORK_CONFIG } from '../constants';
import { getToncenterHeaders } from './other';

export type EmulationResponse = {
  mc_block_seqno: number;
  trace: TraceDetail;
  actions: AnyAction[];
  transactions: Record<string, Transaction>;
  account_states: Record<string, AccountState>;
  rand_seed: string;
  metadata: MetadataMap;
  address_book: AddressBook;
};

export async function fetchEmulateTrace(network: ApiNetwork, boc: string): Promise<EmulationResponse> {
  const baseUrl = NETWORK_CONFIG[network].toncenterUrl;

  const response = await fetchWithRetry(`${baseUrl}/api/emulate/v1/emulateTrace`, {
    method: 'POST',
    headers: {
      ...getToncenterHeaders(network),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      boc,
      ignore_chksig: true,
      include_code_data: false,
      with_actions: true,
      include_address_book: true,
      include_metadata: true,
    }),
  });

  return response.json();
}
