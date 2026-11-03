import type { SignedMfaRequest } from '../chains/ton/util/signer';
import type { ApiAccountAny, ApiChain, ApiMfa, ApiTonWallet, OnApiUpdate } from '../types';

import { parseAccountId } from '../../util/account';
import { logDebugError } from '../../util/logs';
import chains from '../chains';
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

/**
 * The MFA implementation. MFA lives on the TON wallet: the extension address, the stored `mfa` field and
 * the account updates below are all TON-shaped.
 */
function resolveMfa() {
  const mfa = chains.ton?.mfa;
  if (!mfa) {
    throw new Error('MFA is not supported in this build');
  }

  return mfa;
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
  enclaveToken?: string,
) {
  const result = await resolveMfa().installMfaExtension(accountId, user.id, enclaveToken);
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

  if (enclaveToken) {
    try {
      const walletAddress = await fetchStoredAddress(accountId, 'ton');
      const authToken = await getBackendAuthToken(accountId, enclaveToken);
      await upsertTelegramAccount({ walletAddress, user, authToken });
    } catch (err) {
      logDebugError('upsertTelegramAccount', err);
    }
  }

  return result.mfaContractAddress;
}

export async function publishRemoveMfaRequest(accountId: string, enclaveToken?: string) {
  const walletAddress = await fetchStoredAddress(accountId, 'ton');
  const result = await resolveMfa().createRemoveMfaExtensionPayload(accountId, enclaveToken);
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

export async function refreshMfaState(accountId: string, enclaveToken?: string): Promise<{
  changed: boolean;
  mfa?: ApiTonWallet['mfa'];
}> {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const { network } = parseAccountId(accountId);
  const { address: walletAddress, mfa: currentMfa } = account.byChain.ton;

  const mfaAddress = await resolveMfa().resolveExtensionAddress(network, walletAddress);
  let nextMfa: ApiTonWallet['mfa'] | undefined = mfaAddress ? {
    address: mfaAddress,
    user: currentMfa?.user,
  } : undefined;

  if (nextMfa) {
    try {
      const authToken = enclaveToken
        ? await getBackendAuthToken(accountId, enclaveToken)
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

  const changed = !isSameMfa(currentMfa, nextMfa);

  if (changed) {
    await updateStoredWallet(accountId, 'ton', { mfa: nextMfa });
  }

  return { changed, mfa: nextMfa };
}

/**
 * Reports the MFA state when it changes the storage or differs from `reportedMfa`, the state this caller reported
 * before. The UI may lack MFA that the storage already has, so a comparison with the storage alone would never report
 * it, while other flows write the storage without this caller knowing.
 */
export async function refreshMfaStateAndNotify(accountId: string, reportedMfa?: ApiMfa | false) {
  const { changed, mfa } = await refreshMfaState(accountId);
  if (changed || reportedMfa === undefined || !isSameMfa(reportedMfa || undefined, mfa)) {
    onUpdate({
      type: 'updateAccount',
      accountId,
      chain: 'ton',
      mfa: mfa ?? false,
    });
  }

  return mfa ?? false;
}

function isSameMfa(first?: ApiMfa, second?: ApiMfa) {
  return first?.address === second?.address
    && first?.user?.id === second?.user?.id
    && first?.user?.name === second?.user?.name
    && first?.user?.username === second?.user?.username
    && first?.user?.avatarUrl === second?.user?.avatarUrl;
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
