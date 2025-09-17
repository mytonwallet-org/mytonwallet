import type { ApiWallet } from '../types';

import { PUSH_API_URL } from '../config';
import { fetchJson } from '../../util/fetch';
import generateUniqueId from '../../util/generateUniqueId';

export async function fetchConnectedAddress(token: string) {
  const reqId = generateUniqueId();
  // TODO Remove `reqId` when caching is fixed
  const result = await fetchJson(`${PUSH_API_URL}/users/connectedAddress?${reqId}`, undefined, {
    headers: {
      authorization: token,
    },
  });

  return result as ApiWallet;
}

export async function connectWallet(walletAddress: string, token: string) {
  const payload = {
    connectedAddress: walletAddress,
  };

  const result = await fetchJson(`${PUSH_API_URL}/users/connectedAddress`, undefined, {
    method: 'POST',
    body: JSON.stringify(payload),
    headers: {
      'Content-Type': 'application/json',
      authorization: token,
    },
  });

  return result as ApiWallet;
}
