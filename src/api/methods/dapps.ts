import type { LangCode } from '../../global/types';
import type {
  StoredSessionChain } from '../dappProtocols/storage';
import type { DappProofRequest, UnifiedSignDataPayload } from '../dappProtocols/types';
import type { ApiDappTransfer, ApiNetwork, ApiSite, ApiSiteCategory, OnApiUpdate,
} from '../types';

import { parseAccountId } from '../../util/account';
import isEmptyObject from '../../util/isEmptyObject';
import { logDebugError } from '../../util/logs';
import chains from '../chains';
import {
  getAccountValue,
  removeAccountValue,
  removeNetworkAccountsValue,
  setAccountValue,
} from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { isUpdaterAlive } from '../common/helpers';
import {
  migrateLegacyConnection,
  type StoredDappConnection,
  type StoredDappsByUrl,
  type StoredDappsState,
} from '../dappProtocols/storage';
import { callHook } from '../hooks';
import { storage } from '../storages';

let onUpdate: OnApiUpdate;

export function initDapps(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function updateDapp(
  accountId: string,
  url: string,
  uniqueId: string,
  update: Partial<StoredDappConnection>,
) {
  const dapp = await getDapp(accountId, url, uniqueId);
  if (!dapp) return;
  await addDapp(accountId, { ...dapp, ...update }, uniqueId);
}

export async function getDapp(
  accountId: string,
  url: string,
  uniqueId: string,
): Promise<StoredDappConnection | undefined> {
  const byUrl = (
    await getAccountValue(accountId, 'dapps') as StoredDappsByUrl | undefined
  )?.[url];
  if (!byUrl) return undefined;

  return migrateLegacyConnection(byUrl[uniqueId]);
}

export async function addDapp(accountId: string, dapp: StoredDappConnection, uniqueId: string) {
  const dapps = await getDappsByUrl(accountId);

  if (!dapps[dapp.url]) {
    dapps[dapp.url] = {};
  }

  dapps[dapp.url][uniqueId] = dapp;
  await setAccountValue(accountId, 'dapps', dapps);
}

export async function deleteDapp(
  accountId: string,
  url: string,
  uniqueId: string,
  dontNotifyDapp?: boolean,
) {
  const dapps = await getDappsByUrl(accountId);
  if (!(url in dapps)) {
    return false;
  }

  const dapp = dapps[url][uniqueId];
  if (!dapp) {
    return false;
  }
  delete dapps[url][uniqueId];
  if (isEmptyObject(dapps[url])) {
    delete dapps[url];
  }

  await setAccountValue(accountId, 'dapps', dapps);

  if (onUpdate && isUpdaterAlive(onUpdate)) {
    onUpdate({
      type: 'dappDisconnect',
      accountId,
      url,
    });
  }

  if (!dontNotifyDapp) {
    await callHook('onDappDisconnected', accountId, dapp);
  }

  await callHook('onDappsChanged', dapp);

  return true;
}

export async function deleteAllDapps(accountId: string) {
  const dapps = await getDapps(accountId);
  await setAccountValue(accountId, 'dapps', {});

  dapps.forEach((dapp) => {
    onUpdate({
      type: 'dappDisconnect',
      accountId,
      url: dapp.url,
    });
    void callHook('onDappDisconnected', accountId, dapp);
  });

  await callHook('onDappsChanged');
}

export async function getDapps(accountId: string): Promise<StoredDappConnection[]> {
  const byUrl = await getDappsByUrl(accountId);
  return Object.values(byUrl)
    .flatMap((byId) => Object.values(byId)
      .map((dapp) => migrateLegacyConnection(dapp)));
}

export async function getDappsByUrl(accountId: string): Promise<StoredDappsByUrl> {
  return (await getAccountValue(accountId, 'dapps')) || {};
}

export async function findLastConnectedAccount(network: ApiNetwork, url: string) {
  const dapps = await getDappsState() || {};

  let connectedAt = 0;
  let lastConnectedAccountId: string | undefined;

  Object.entries(dapps).forEach(([accountId, byUrl]) => {
    const connections = byUrl[url];
    if (!connections) return;
    if (parseAccountId(accountId).network !== network) return;

    Object.values(connections).forEach((conn) => {
      if (conn.connectedAt > connectedAt) {
        connectedAt = conn.connectedAt;
        lastConnectedAccountId = accountId;
      }
    });
  });

  return lastConnectedAccountId;
}

export function getDappsState(): Promise<StoredDappsState | undefined> {
  return storage.getItem('dapps');
}

export async function removeAccountDapps(accountId: string) {
  await removeAccountValue(accountId, 'dapps');

  void callHook('onDappsChanged');
}

export async function removeAllDapps() {
  await storage.removeItem('dapps');

  await callHook('onDappsChanged');
}

export function removeNetworkDapps(network: ApiNetwork) {
  return removeNetworkAccountsValue(network, 'dapps');
}

export function getSseLastEventId(): Promise<string | undefined> {
  return storage.getItem('sseLastEventId');
}

export function setSseLastEventId(lastEventId: string) {
  return storage.setItem('sseLastEventId', lastEventId);
}

export function loadExploreSites(
  { isLandscape, langCode }: { isLandscape: boolean; langCode: LangCode },
): Promise<{ categories: ApiSiteCategory[]; sites: ApiSite[] }> {
  return callBackendGet('/v2/dapp/catalog', { isLandscape, langCode });
}

export async function signDappProof(
  dappChains: StoredSessionChain[] = [],
  accountId: string,
  proof: DappProofRequest,
  password?: string,
) {
  try {
    const signatures: string[] = [];
    for (const chain of dappChains) {
      const result = await chains[chain.chain].dapp?.signConnectionProof?.(accountId, proof, password);
      if (result && 'signature' in result) {
        signatures.push(result.signature);
      }
    }
    return { signatures };
  } catch (err) {
    logDebugError('signDappProof', err);
    return {
      error: err,
    };
  }
}

export async function signDappTransfers(
  dappChain: StoredSessionChain,
  accountId: string,
  transactions: ApiDappTransfer[],
  options: {
    password?: string;
    validUntil?: number;
    vestingAddress?: string;
    // Deal with solana b58/b64 issues based on requested method
    isLegacyOutput?: boolean;
  } = {},
) {
  return await chains[dappChain.chain].dapp?.signDappTransfers(accountId, transactions, options);
}

export async function signDappData(
  dappChain: StoredSessionChain,
  accountId: string,
  url: string,
  payload: UnifiedSignDataPayload,
  password?: string,
) {
  return await chains[dappChain.chain].dapp?.signDappData(accountId, url, payload, password);
}
