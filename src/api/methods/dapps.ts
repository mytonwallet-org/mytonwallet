import type { LangCode } from '../../global/types';
import type {
  ApiDapp, ApiDappsByUrl, ApiDappsState, ApiNetwork, ApiSite, ApiSiteCategory, OnApiUpdate,
} from '../types';

import { parseAccountId } from '../../util/account';
import isEmptyObject from '../../util/isEmptyObject';
import {
  getAccountValue,
  removeAccountValue,
  removeNetworkAccountsValue,
  setAccountValue,
} from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { isUpdaterAlive } from '../common/helpers';
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
  update: Partial<ApiDapp>,
) {
  const dapp = await getDapp(accountId, url, uniqueId);
  if (!dapp) return;
  await addDapp(accountId, { ...dapp, ...update }, uniqueId);
}

export async function getDapp(
  accountId: string,
  url: string,
  uniqueId: string,
): Promise<ApiDapp | undefined> {
  const byUrl = (
    await getAccountValue(accountId, 'dapps') as ApiDappsByUrl | undefined
  )?.[url];
  if (!byUrl) return undefined;

  return byUrl[uniqueId];
}

export async function addDapp(accountId: string, dapp: ApiDapp, uniqueId: string) {
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
    await callHook('onDappDisconnected', accountId, url);
  }

  await callHook('onDappsChanged');

  return true;
}

export async function deleteAllDapps(accountId: string) {
  const urls = Object.keys(await getDappsByUrl(accountId));
  await setAccountValue(accountId, 'dapps', {});

  urls.forEach((url) => {
    onUpdate({
      type: 'dappDisconnect',
      accountId,
      url,
    });
    void callHook('onDappDisconnected', accountId, url);
  });

  await callHook('onDappsChanged');
}

export async function getDapps(accountId: string): Promise<ApiDapp[]> {
  const byUrl = await getDappsByUrl(accountId);
  return Object.values(byUrl).flatMap((byId) => Object.values(byId));
}

export async function getDappsByUrl(accountId: string): Promise<ApiDappsByUrl> {
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

export function getDappsState(): Promise<ApiDappsState | undefined> {
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
