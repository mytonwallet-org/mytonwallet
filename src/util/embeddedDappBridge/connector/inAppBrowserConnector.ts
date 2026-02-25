import {
  APP_NAME,
  EMBEDDED_DAPP_BRIDGE_CHANNEL,
  TONCONNECT_PROTOCOL_VERSION,
  TONCONNECT_WALLET_JSBRIDGE_KEY,
} from '../../../config';
import { registerSolanaInjectedWallet, solanaConnectorIcon } from '../../injectedConnector/solanaConnector';
import { tonConnectGetDeviceInfo } from '../../tonConnectEnvironment';
import { initConnectorString } from './connector';

export function buildInAppBrowserBridgeConnectorCode() {
  return `
(${initConnectorString})(
  '${TONCONNECT_WALLET_JSBRIDGE_KEY}',
  '${EMBEDDED_DAPP_BRIDGE_CHANNEL}',
  'cordova_iab' in window ? window.cordova_iab : window.webkit.messageHandlers.cordova_iab,
  {
    deviceInfo: ${JSON.stringify(tonConnectGetDeviceInfo())},
    protocolVersion: ${TONCONNECT_PROTOCOL_VERSION},
    isWalletBrowser: true,
  },
  '${APP_NAME}',
  '${solanaConnectorIcon}',
  ${registerSolanaInjectedWallet.toString()}
);
  `;
}
