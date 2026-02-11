import type { OnApiUpdate } from '../types';
import type { ApiSiteUpdate, OnApiSiteUpdate } from '../types/dappUpdates';

import { getCurrentAccountIdOrFail, waitLogin } from '../common/accounts';
import { resolveDappPromise } from '../common/dappPromises';
import storage from '../storages/extension';
import { clearCache, openPopupWindow } from './window';

let onPopupUpdate: OnApiUpdate;

// Sometimes (e.g. when Dev Tools is open) dapp needs more time to subscribe to provider
const INIT_UPDATE_DELAY = 50;

const siteUpdaters: OnApiSiteUpdate[] = [];

// This method is called from `initApi` which in turn is called when popup is open
export function initSiteMethods(_onPopupUpdate: OnApiUpdate) {
  onPopupUpdate = _onPopupUpdate;
  resolveDappPromise('whenPopupReady');
}

export async function connectSite(onSiteUpdate: OnApiSiteUpdate) {
  siteUpdaters.push(onSiteUpdate);
  const isDeeplinkHookEnabled = await storage.getItem('isDeeplinkHookEnabled');

  function sendUpdates() {
    onSiteUpdate({
      type: 'updateDeeplinkHook',
      isEnabled: Boolean(isDeeplinkHookEnabled),
    });
  }

  sendUpdates();
  setTimeout(sendUpdates, INIT_UPDATE_DELAY);
}

export function deactivateSite(onDappUpdate: OnApiSiteUpdate) {
  const index = siteUpdaters.findIndex((updater) => updater === onDappUpdate);
  if (index !== -1) {
    siteUpdaters.splice(index, 1);
  }
}

export function updateSites(update: ApiSiteUpdate) {
  siteUpdaters.forEach((onDappUpdate) => {
    onDappUpdate(update);
  });
}

export async function prepareTransaction(params: {
  to: string;
  amount?: string;
  comment?: string;
  binPayload?: string;
}) {
  await getCurrentAccountIdOrFail();

  const {
    to: toAddress,
    amount,
    comment,
    binPayload,
  } = params;

  await openPopupWindow();
  await waitLogin();

  onPopupUpdate({
    type: 'prepareTransaction',
    toAddress,
    amount: amount ? BigInt(amount) : undefined,
    comment,
    binPayload,
  });
}

export async function processDeeplink({ url }: {
  url: string;
}) {
  await getCurrentAccountIdOrFail();
  await openPopupWindow();
  await waitLogin();

  onPopupUpdate({
    type: 'processDeeplink',
    url,
  });
}

export async function flushMemoryCache() {
  await clearCache();
}
