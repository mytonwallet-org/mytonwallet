import type { ApiInitArgs, OnApiUpdate } from '../types';

import { initWindowConnector } from '../../util/windowProvider/connector';
import * as ton from '../chains/ton';
import { fetchBackendReferrer } from '../common/backend';
import { connectUpdater, disconnectUpdater, tryMigrateStorage } from '../common/helpers';
import { initClientId } from '../common/other';
import { getProtocolManager, initProtocolManager } from '../dappProtocols';
import { setEnvironment } from '../environment';
import { addHooks } from '../hooks';
import { storage } from '../storages';
import { destroyPolling } from './polling';
import * as methods from '.';

export default async function init(onUpdate: OnApiUpdate, args: ApiInitArgs) {
  connectUpdater(onUpdate);

  const environment = setEnvironment(args);
  initWindowConnector();

  await initClientId();
  await tryMigrateStorage(onUpdate, ton, args.accountIds);

  methods.initAccounts(onUpdate);
  methods.initAuth(onUpdate);
  methods.initPolling(onUpdate);
  methods.initTransfer(onUpdate);
  methods.initTokens(onUpdate);
  methods.initStaking();
  methods.initSwap(onUpdate);
  methods.initNfts(onUpdate);

  await initProtocolManager(onUpdate, environment);

  if (environment.isDappSupported) {
    methods.initDapps(onUpdate);
  }

  const protocolManager = getProtocolManager();

  addHooks({
    onDappDisconnected: protocolManager.closeRemoteConnection.bind(protocolManager),
    onDappsChanged: protocolManager.resetupRemoteConnection.bind(protocolManager),
  });

  if (args.langCode) {
    void storage.setItem('langCode', args.langCode);
  }

  void saveReferrer(args);
}

export function destroy() {
  void destroyPolling();
  disconnectUpdater();
}

async function saveReferrer(args: ApiInitArgs) {
  const referrer = args.referrer ?? await fetchBackendReferrer();

  if (referrer) {
    await storage.setItem('referrer', referrer);
    await initClientId();
  }
}
