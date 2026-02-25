import {
  APP_NAME,
  EMBEDDED_DAPP_BRIDGE_CHANNEL,
  TONCONNECT_PROTOCOL_VERSION,
  TONCONNECT_WALLET_JSBRIDGE_KEY,
} from '../../../config';
import { registerSolanaInjectedWallet, solanaConnectorIcon } from '../../injectedConnector/solanaConnector';
import { tonConnectGetDeviceInfo } from '../../tonConnectEnvironment';
import { initConnector } from './connector';

export function initIframeBridgeConnector() {
  initConnector(
    TONCONNECT_WALLET_JSBRIDGE_KEY,
    EMBEDDED_DAPP_BRIDGE_CHANNEL,
    window.parent,
    {
      deviceInfo: tonConnectGetDeviceInfo(),
      protocolVersion: TONCONNECT_PROTOCOL_VERSION,
      isWalletBrowser: true,
    },
    APP_NAME,
    solanaConnectorIcon,
    registerSolanaInjectedWallet,
  );
}
