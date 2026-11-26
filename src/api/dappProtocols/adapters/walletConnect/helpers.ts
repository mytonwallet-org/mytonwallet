import type { Verify } from '@walletconnect/types';

import type { ApiChain, ApiDappRequest, ApiDappurlTrustStatusStatus, ApiNetwork } from '../../../types';
import type { DappProtocolError } from '../../errors';
import type { StoredSessionChain } from '../../storage';
import type { WalletConnectEip712Params } from './types';

import { parseAccountId } from '../../../../util/account';
import { getSignedTypedData, getSignedTypedDataDomain } from '../../../chains/evm/typedDataMessage';
import { getCurrentAccountId, getCurrentAccountIdOrFail } from '../../../common/accounts';
import { ApiUserRejectsError } from '../../../errors';
import { findLastConnectedAccount, getDappsState } from '../../../methods/dapps';

export function safeHost(url: string | undefined): string {
  if (!url) return '<no-url>';
  try {
    return new URL(url).hostname;
  } catch {
    return '<invalid-url>';
  }
}

/**
 * WalletConnect / EIP-1474 pass `eth_signTypedData*` params as `[address, typedData]`
 * where `typedData` is a JSON string or object `{ domain, types, primaryType, message }`.
 */
export function parseWalletConnectTypedData(raw: unknown): WalletConnectEip712Params | undefined {
  let value: unknown = raw;
  if (typeof raw === 'string') {
    try {
      value = JSON.parse(raw) as unknown;
    } catch {
      return undefined;
    }
  }

  const parsed = value as Record<string, unknown>;
  const { domain, types, message, primaryType } = parsed;

  if (!domain || typeof domain !== 'object') {
    return undefined;
  }

  if (!types || typeof types !== 'object' || Array.isArray(types)) {
    return undefined;
  }

  if (!message || typeof message !== 'object' || Array.isArray(message)) {
    return undefined;
  }

  if (typeof primaryType !== 'string') {
    return undefined;
  }

  return {
    domain,
    types,
    primaryType,
    message,
  } as WalletConnectEip712Params;
}

// The typed data as it gets signed, or `undefined` when a confirmation would show another struct or message, or
// could not read the domain
export function getSignedWalletConnectTypedData(typedData: WalletConnectEip712Params) {
  const domain = getSignedTypedDataDomain(typedData.domain);
  const signedTypedData = domain && getSignedTypedData(typedData.types, typedData.primaryType, typedData.message);

  return signedTypedData && { ...typedData, ...signedTypedData, domain };
}

export async function getCurrentAccountOrFail() {
  const accountId = await getCurrentAccountId();
  if (!accountId) {
    throw new Error('No currentAccountFound');
  }
  return accountId;
}

export async function getDappByTopic(topic: string, mode: 'default' | 'pairing') {
  const dapps = await getDappsState();

  if (!dapps) {
    return;
  }

  for (const byAccId of Object.entries(dapps)) {
    for (const byUrl of Object.values(byAccId[1])) {
      for (const byDappId of Object.values(byUrl)) {
        if (mode === 'pairing'
          ? byDappId.wcPairingTopic === topic
          : byDappId.wcTopic === topic
        ) {
          return { dapp: byDappId, accountId: byAccId[0] };
        }
      }
    }
  }
}

export async function ensureRequestParams(
  request: ApiDappRequest,
): Promise<ApiDappRequest & { url: string; accountId: string }> {
  if (!request.url) {
    throw new Error('Missing `url` in request');
  }

  if (request.accountId) {
    return request as ApiDappRequest & { url: string; accountId: string };
  }

  const { network } = parseAccountId(await getCurrentAccountIdOrFail());
  const lastAccountId = await findLastConnectedAccount(network, request.url);

  if (!lastAccountId) {
    throw new Error('The connection is outdated, try relogin');
  }

  return {
    ...request,
    accountId: lastAccountId,
  } as ApiDappRequest & { url: string; accountId: string };
}

export function formatConnectError(id: number, error: unknown): {
  success: false;
  error: DappProtocolError;
} {
  let code = 0;
  let message = 'Unhandled error';

  if (error instanceof ApiUserRejectsError) {
    code = 300;
    message = error.message;
  }

  return {
    success: false,
    error: {
      code,
      message,
    },
  };
}

export function urlTrustStatusStatusFromWalletConnectVerify(
  verifyContext?: Verify.Context,
): ApiDappurlTrustStatusStatus {
  if (!verifyContext?.verified) {
    return 'unknown';
  }
  const { isScam, validation } = verifyContext.verified;
  if (isScam) {
    return 'dangerous';
  }
  if (validation === 'VALID') {
    // We cannot proof that the dApp is REALLY safe - os ignore WalletConnect VALID label for now
    return 'unknown';
  }
  if (validation === 'INVALID') {
    return 'invalid';
  }
  return 'unknown';
}

export function mergeStoredSessionChains(
  existing: StoredSessionChain[],
  incoming: StoredSessionChain[],
): StoredSessionChain[] {
  const byKey = new Map<string, StoredSessionChain>();

  for (const chain of existing) {
    byKey.set(`${chain.chain}:${chain.network}:${chain.address.toLowerCase()}`, chain);
  }

  for (const chain of incoming) {
    byKey.set(`${chain.chain}:${chain.network}:${chain.address.toLowerCase()}`, chain);
  }

  return [...byKey.values()];
}

export function getMissingInjectedRequestedChains(
  existing: StoredSessionChain[],
  requested: Array<{ chain: ApiChain; network: ApiNetwork }>,
): Array<{ chain: ApiChain; network: ApiNetwork }> {
  return requested.filter((req) =>
    !existing.some((row) => row.chain === req.chain && row.network === req.network),
  );
}
