import type { ApiInitArgs, OnApiUpdate } from '../types';

import { NO_MFA, NO_STAKING, NO_SWAP } from '../../config';
import { initWindowConnector } from '../../util/windowProvider/connector';
import * as ton from '../chains/ton';
import { fetchBackendReferrer } from '../common/backend';
import { connectUpdater, disconnectUpdater, tryMigrateStorage } from '../common/helpers';
import { initClientId } from '../common/other';
import { getProtocolManager, initProtocolManager } from '../dappProtocols';
import { setEnvironment } from '../environment';
import { addHooks } from '../hooks';
import { configureStorage, createStorage, withStorage } from '../storages';
import { destroyPolling } from './polling';
import * as methods from '.';

export default async function init(onUpdate: OnApiUpdate, args: ApiInitArgs) {
  const runtimeStorage = createStorage(args.storage);

  configureStorage(args.storage);
  connectUpdater(onUpdate);

  const environment = setEnvironment(args);
  initWindowConnector();

  await withStorage(runtimeStorage, async () => {
    await initClientId();
    await tryMigrateStorage(onUpdate, ton, args.accountIds);
  });

  methods.initAccounts(onUpdate);
  methods.initAuth(onUpdate);
  methods.initWallet(onUpdate);
  if (!NO_MFA) methods.initMfa(onUpdate);
  methods.initPolling(onUpdate);
  methods.initTransfer(onUpdate);
  methods.initTokens(onUpdate);
  if (!NO_STAKING) methods.initStaking();
  if (!NO_SWAP) methods.initSwap(onUpdate);
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
    void runtimeStorage.setItem('langCode', args.langCode);
  }

  void saveReferrer(args, runtimeStorage);
}

export function destroy() {
  void destroyPolling();
  disconnectUpdater();
}

async function saveReferrer(args: ApiInitArgs, runtimeStorage: ReturnType<typeof createStorage>) {
  const referrer = args.referrer ?? await fetchBackendReferrer();

  if (referrer) {
    await runtimeStorage.setItem('referrer', referrer);
    await withStorage(runtimeStorage, async () => {
      await initClientId();
    });
  }
}
