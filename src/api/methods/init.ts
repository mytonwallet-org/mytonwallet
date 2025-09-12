import type { ApiInitArgs, OnApiUpdate } from '../types';

import { initWindowConnector } from '../../util/windowProvider/connector';
import chains from '../chains';
import { fetchBackendReferrer } from '../common/backend';
import { connectUpdater, disconnectUpdater, startStorageMigration } from '../common/helpers';
import { setEnvironment } from '../environment';
import { addHooks } from '../hooks';
import { storage } from '../storages';
import * as tonConnect from '../tonConnect';
import * as tonConnectSse from '../tonConnect/sse';
import { destroyPolling } from './polling';
import * as methods from '.';

addHooks({
  onDappDisconnected: tonConnectSse.sendSseDisconnect,
  onDappsChanged: tonConnectSse.resetupSseConnection,
});

export default async function init(onUpdate: OnApiUpdate, args: ApiInitArgs) {
  connectUpdater(onUpdate);
  const environment = setEnvironment(args);

  initWindowConnector();

  methods.initAccounts(onUpdate);
  methods.initPolling(onUpdate);
  methods.initTransfer(onUpdate);
  methods.initStaking();
  methods.initSwap(onUpdate);
  methods.initNfts(onUpdate);

  if (environment.isDappSupported) {
    methods.initDapps(onUpdate);
    tonConnect.initTonConnect(onUpdate);
  }

  if (environment.isSseSupported) {
    tonConnectSse.initSse(onUpdate);
  }

  await startStorageMigration(onUpdate, chains.ton, args.accountIds);

  if (environment.isSseSupported) {
    void tonConnectSse.resetupSseConnection();
  }

  void saveReferrer(args);
}

export function destroy() {
  void destroyPolling();
  disconnectUpdater();
}

async function saveReferrer(args: ApiInitArgs) {
  let referrer = await storage.getItem('referrer');

  if (referrer) {
    return;
  }

  referrer = args.referrer ?? await fetchBackendReferrer();

  if (referrer) {
    await storage.setItem('referrer', referrer);
  }
}
