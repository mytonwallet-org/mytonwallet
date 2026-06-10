import type { ApiInstallRequest } from '../types';

import { MFA_API_URL } from '../config';
import { fetchJson } from '../../util/fetch';

export const fetchInstallRequest = async (reqId: string) => {
  const response = await fetchJson(`${MFA_API_URL}/installRequest/${reqId}`);
  return response as ApiInstallRequest;
};

export const confirmInstallRequest = async (
  reqId: string,
  initData: string,
) => {
  const response = await fetchJson(
    `${MFA_API_URL}/installRequest/${reqId}`,
    undefined,
    {
      method: 'POST',
      body: JSON.stringify({ initData }),
      headers: { 'Content-Type': 'application/json' },
    },
  );

  return response as ApiInstallRequest;
};
