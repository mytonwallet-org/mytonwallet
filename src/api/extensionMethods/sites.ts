import type { RecordTonConnectEventInput } from '../dappProtocols/adapters/tonConnect/analytics';
import type { OnApiUpdate } from '../types';
import type { ApiSiteUpdate, OnApiSiteUpdate } from '../types/dappUpdates';

import { getCurrentAccountIdOrFail, waitLogin } from '../common/accounts';
import { resolveDappPromise } from '../common/dappPromises';
import { recordTonConnectEvent as recordTonConnectAnalyticsEvent } from '../methods/analytics';
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
    isFromInAppBrowser: true,
  });
}

export async function flushMemoryCache() {
  await clearCache();
}

// Routes the browser-extension page script's TON Connect analytics events to the worker recorder. The in-app
// browser bridge reaches the recorder directly via `callApi`, but the extension page script can only reach the
// worker through this content-script provider, so the method must be exposed here (and allow-listed in
// `providerForContentScript`). Fire-and-forget: the recorder never rejects, so nothing is awaited.
export function recordTonConnectEvent(input: RecordTonConnectEventInput) {
  void recordTonConnectAnalyticsEvent(input);
}
