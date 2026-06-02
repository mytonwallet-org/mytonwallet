import type { ApiMfaUser } from '../types';

import { MFA_API_BASE_URL } from '../../config';
import { ApiServerError } from '../errors';

type MfaRequestCreated = {
  reqId: string;
};

type InstallRequestCreated = {
  reqId: string;
};

type MfaRequest = {
  payload: string;
  signature: string;
  isConfirmed: boolean;
  txHash: string;
};

type InstallMfaRequest = {
  address: string;
  user?: ApiMfaUser;
};

type TelegramAccount = {
  user: ApiMfaUser;
};

export async function createMfaRequest(
  opts: { walletAddress: string; payload: Buffer; signature: Buffer },
): Promise<MfaRequestCreated> {
  const response = await fetch(`${MFA_API_BASE_URL}/transaction`, {
    method: 'POST',
    body: JSON.stringify({
      ...opts,
      payload: opts.payload.toString('base64'),
      signature: opts.signature.toString('base64'),
    }),
    headers: {
      'Content-Type': 'application/json',
    },
  });

  return response.json();
}

export async function createInstallMfaRequest(opts: { walletAddress: string }): Promise<InstallRequestCreated> {
  const response = await fetch(`${MFA_API_BASE_URL}/installRequest`, {
    method: 'POST',
    body: JSON.stringify({ ...opts }),
    headers: {
      'Content-Type': 'application/json',
    },
  });

  return response.json();
}

export async function getMfaRequest(opts: { hash: string }): Promise<MfaRequest> {
  const response = await fetch(`${MFA_API_BASE_URL}/transaction/${opts.hash}`);

  return await response.json();
};

export async function getInstallMfaRequest({ reqId }: { reqId: string }): Promise<InstallMfaRequest> {
  const response = await fetch(`${MFA_API_BASE_URL}/installRequest/${reqId}`);

  return await response.json();
};

export async function getTelegramAccount(opts: {
  walletAddress: string;
  authToken: string;
}): Promise<TelegramAccount | undefined> {
  const url = new URL(`${MFA_API_BASE_URL}/telegramAccount`);
  url.searchParams.set('walletAddress', opts.walletAddress);

  const response = await fetch(url, {
    headers: {
      'X-Auth-Token': opts.authToken,
    },
  });

  const result = await response.json().catch(() => undefined);
  if (response.status === 404) return undefined;
  if (!response.ok) {
    throw new ApiServerError(result?.error ?? `HTTP Error ${response.status}`, response.status);
  }

  return isTelegramAccount(result) ? result : undefined;
}

function isTelegramAccount(value: unknown): value is TelegramAccount {
  if (!value || typeof value !== 'object') return false;

  const { user } = value as { user?: Partial<ApiMfaUser> };

  return Boolean(user && typeof user.id === 'string' && typeof user.name === 'string');
}

export async function upsertTelegramAccount(opts: {
  walletAddress: string;
  user: TelegramAccount['user'];
  authToken: string;
}): Promise<void> {
  await fetch(`${MFA_API_BASE_URL}/telegramAccount`, {
    method: 'PUT',
    body: JSON.stringify({
      walletAddress: opts.walletAddress,
      user: opts.user,
    }),
    headers: {
      'Content-Type': 'application/json',
      'X-Auth-Token': opts.authToken,
    },
  });
}
