import type { ApiSiteUpdate } from '../../api/types/dappUpdates';

import { initApi } from '../../api/providers/extension/connectorForPageScript';
import { doDeeplinkHook } from './deeplinkHook';

import { initEvmConnect } from './EvmConnector';
import { initSolanaConnect } from './SolanaConnector';
import { initTonConnect } from './TonConnect';

const siteOrigin = window.origin;
const apiConnector = initApi(onUpdate);
const solanaWallet = initSolanaConnect(apiConnector);
const evmWallet = initEvmConnect(apiConnector);

const tonConnect = initTonConnect(apiConnector);

function onUpdate(update: ApiSiteUpdate) {
  if (update.type === 'updateDeeplinkHook') {
    doDeeplinkHook(update.isEnabled);
    return;
  }

  if (update.type === 'disconnectSite') {
    if (update.url === siteOrigin) {
      tonConnect.onDisconnect();
      solanaWallet.onDisconnect?.();
      evmWallet.onDisconnect();
    }
  }
}
