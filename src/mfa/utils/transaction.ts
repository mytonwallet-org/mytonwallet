import type { ApiTransaction } from '../types';

import { MFA_API_URL } from '../config';
import { fetchJson } from '../../util/fetch';

export async function fetchTransaction(hash: string) {
  const response = await fetchJson(`${MFA_API_URL}/transaction/${hash}`, undefined);
  return response as ApiTransaction;
}

export async function confirmTransaction(hash: string, txHash: string) {
  const response = await fetchJson(
    `${MFA_API_URL}/transaction/${hash}/confirm`,
    undefined,
    {
      method: 'POST',
      body: JSON.stringify({ txHash }),
      headers: { 'Content-Type': 'application/json' },
    },
  );

  return response as ApiTransaction;
}
