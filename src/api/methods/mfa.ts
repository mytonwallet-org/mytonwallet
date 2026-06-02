import { Address } from '@ton/core';

import type { SignedMfaRequest } from '../chains/ton/util/signer';
import type { ApiAccountAny, ApiChain, ApiMfa, ApiTonWallet, OnApiUpdate } from '../types';

import { parseAccountId } from '../../util/account';
import { logDebugError } from '../../util/logs';
import { resolveMfaExtensionAddress } from '../chains/ton/contracts/util';
import { createRemoveMfaExtensionPayload, installMfaExtension } from '../chains/ton/mfa';
import {
  fetchStoredAccount,
  fetchStoredAddress,
  fetchStoredChainAccount,
  setAccountValue,
  updateStoredWallet,
} from '../common/accounts';
import {
  createInstallMfaRequest,
  createMfaRequest,
  getInstallMfaRequest,
  getMfaRequest,
  getTelegramAccount,
  upsertTelegramAccount,
} from '../common/mfa';
import { getBackendAuthToken, getStoredBackendAuthToken } from './other';

let onUpdate: OnApiUpdate;
type MfaConfirmationHandler = (txHash: string) => void;
const mfaConfirmationHandlers = new Map<string, MfaConfirmationHandler[]>();

export function initMfa(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function fetchMfaRequest(hash: string) {
  const request = await getMfaRequest({ hash });
  if (request.isConfirmed && request.txHash) {
    const handlers = mfaConfirmationHandlers.get(hash);
    if (handlers) {
      mfaConfirmationHandlers.delete(hash);
      for (const handler of handlers) {
        try {
          handler(request.txHash);
        } catch (err) {
          logDebugError('mfaConfirmationHandler', err);
        }
      }
    }
  }
  return request;
}

export function registerMfaConfirmationHandler(hash: string, handler: MfaConfirmationHandler) {
  const handlers = mfaConfirmationHandlers.get(hash) ?? [];
  handlers.push(handler);
  mfaConfirmationHandlers.set(hash, handlers);
}

export async function fetchInstallMfaRequest(reqId: string) {
  return getInstallMfaRequest({ reqId });
}

export async function publishInstallMfaRequest(accountId: string) {
  const walletAddress = await fetchStoredAddress(accountId, 'ton');
  const reqId = await createInstallMfaRequest({ walletAddress });

  return reqId;
}

export async function publishSignedMfaRequest(
  accountId: string,
  chain: ApiChain,
  mfaRequest: SignedMfaRequest,
) {
  const walletAddress = await fetchStoredAddress(accountId, chain);
  const { payload, signature } = mfaRequest;

  const { reqId } = await createMfaRequest({
    walletAddress,
    payload: payload.toBoc(),
    signature,
  });

  return { mfaRequestHash: reqId };
}

export async function installMfaFromRequest(
  accountId: string,
  user: { id: string; name: string; username?: string; avatarUrl?: string },
  password?: string,
) {
  const result = await installMfaExtension(accountId, user.id, password);
  if ('error' in result) return result;

  const mfa = {
    address: result.mfaContractAddress,
    user,
  };
  await setAccountExtensionAddress(accountId, mfa);

  onUpdate({
    type: 'updateAccount',
    accountId,
    chain: 'ton',
    mfa,
  });

  if (password) {
    try {
      const walletAddress = await fetchStoredAddress(accountId, 'ton');
      const authToken = await getBackendAuthToken(accountId, password);
      await upsertTelegramAccount({ walletAddress, user, authToken });
    } catch (err) {
      logDebugError('upsertTelegramAccount', err);
    }
  }

  return result.mfaContractAddress;
}

export async function publishRemoveMfaRequest(accountId: string, password?: string) {
  const walletAddress = await fetchStoredAddress(accountId, 'ton');
  const result = await createRemoveMfaExtensionPayload(accountId, password);
  if ('error' in result) return result;

  return await createMfaRequest({
    walletAddress,
    payload: result.payload.toBoc(),
    signature: result.signature,
  });
}

export async function confirmMfaRemovalRequest(accountId: string) {
  await setAccountExtensionAddress(accountId, undefined);

  onUpdate({
    type: 'updateAccount',
    accountId,
    chain: 'ton',
    mfa: false,
  });
}

export async function refreshMfaState(accountId: string, password?: string): Promise<{
  changed: boolean;
  mfa?: ApiTonWallet['mfa'];
}> {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const { network } = parseAccountId(accountId);
  const { address: walletAddress, mfa: currentMfa } = account.byChain.ton;

  const mfaAddress = await resolveMfaExtensionAddress(network, Address.parse(walletAddress));
  let nextMfa: ApiTonWallet['mfa'] | undefined = mfaAddress ? {
    address: mfaAddress,
    user: currentMfa?.user,
  } : undefined;

  if (nextMfa) {
    try {
      const authToken = password
        ? await getBackendAuthToken(accountId, password)
        : await getStoredBackendAuthToken(accountId);

      if (authToken) {
        const telegramAccount = await getTelegramAccount({ walletAddress, authToken });
        if (telegramAccount) {
          const { id, name, username, avatarUrl } = telegramAccount.user;
          nextMfa = {
            ...nextMfa,
            user: { id, name, username, avatarUrl },
          };
        }
      }
    } catch (err) {
      logDebugError('refreshMfaState:getTelegramAccount', err);
    }
  }

  const changed = currentMfa?.address !== nextMfa?.address
    || currentMfa?.user?.id !== nextMfa?.user?.id
    || currentMfa?.user?.name !== nextMfa?.user?.name
    || currentMfa?.user?.username !== nextMfa?.user?.username
    || currentMfa?.user?.avatarUrl !== nextMfa?.user?.avatarUrl;

  if (changed) {
    await updateStoredWallet(accountId, 'ton', { mfa: nextMfa });
  }

  return { changed, mfa: nextMfa };
}

export async function refreshMfaStateAndNotify(accountId: string, password?: string) {
  const result = await refreshMfaState(accountId, password);
  if (result.changed) {
    onUpdate({
      type: 'updateAccount',
      accountId,
      chain: 'ton',
      mfa: result.mfa ?? false,
    });
  }

  return result;
}

async function setAccountExtensionAddress(
  accountId: string,
  mfa?: ApiMfa,
) {
  const account = await fetchStoredAccount<ApiAccountAny>(accountId);
  if (!account.byChain.ton) return;

  await setAccountValue(
    accountId,
    'accounts',
    {
      ...account,
      byChain: {
        ...account.byChain,
        ton: { ...account.byChain.ton, mfa },
      },
    },
  );
}
