import { getActions, getGlobal } from '../../../global';

import type {
  DappConnectionRequest,
  DappConnectionResult,
  DappMethodResult,
  DappProtocolType,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../../api/dappProtocols';
import type { DappProtocolError } from '../../../api/dappProtocols/errors';

import { callApi } from '../../../api';
import { logDebugError } from '../../logs';

let wcRequestId = 0;

type WalletConnectConnectionResult = DappConnectionResult<DappProtocolType.WalletConnect>;

type WalletConnectMethodResult = DappMethodResult<DappProtocolType.WalletConnect>;

type WcBridgeFailure = { success: false; error: DappProtocolError };

export interface BrowserEvmConnectBridgeMethods {
  reconnect(wcRequestId: number): Promise<
    WalletConnectConnectionResult | undefined | WcBridgeFailure
  >;

  connect(
    message: DappConnectionRequest<DappProtocolType.WalletConnect>,
  ): Promise<WalletConnectConnectionResult | undefined | WcBridgeFailure>;

  sendTransaction(
    unifiedPayload: DappTransactionRequest<DappProtocolType.WalletConnect>,
  ): Promise<WalletConnectMethodResult | undefined | WcBridgeFailure>;

  signData(
    unifiedPayload: DappSignDataRequest<DappProtocolType.WalletConnect>,
  ): Promise<WalletConnectMethodResult | undefined | WcBridgeFailure>;
}

export function buildEvmConnectBridgeApi(pageUrl: string): BrowserEvmConnectBridgeMethods {
  const {
    openLoadingOverlay,
    closeLoadingOverlay,
  } = getActions();

  const url = new URL(pageUrl).origin.toLowerCase();

  return {
    reconnect: async (requestId) => {
      try {
        const response = await callApi(
          'walletConnect_reconnect',
          buildDappRequest(url),
          requestId,
        );

        return response;
      } catch (err) {
        logDebugError('evmConnectBridgeApi:wcReconnect', err);
        return { success: false, error: { code: 0, message: 'Unknown error' } };
      }
    },

    connect: async (message) => {
      try {
        openLoadingOverlay();

        const patched: DappConnectionRequest<DappProtocolType.WalletConnect> = {
          ...message,
          transport: 'inAppBrowser',
        };

        const response = await callApi(
          'walletConnect_connect',
          buildDappRequest(url),
          patched,
          wcRequestId,
        );

        wcRequestId++;

        return response;
      } catch (err) {
        logDebugError('evmConnectBridgeApi:wcConnect', err);
        return { success: false, error: { code: 0, message: 'Unknown error' } };
      } finally {
        closeLoadingOverlay();
      }
    },

    sendTransaction: async (unifiedPayload) => {
      try {
        return await callApi(
          'walletConnect_sendTransaction',
          buildDappRequest(url),
          unifiedPayload,
        );
      } catch (err) {
        logDebugError('evmConnectBridgeApi:wcSendTransaction', err);
        return { success: false, error: { code: 0, message: 'Unknown error' } };
      }
    },

    signData: async (unifiedPayload) => {
      try {
        return await callApi(
          'walletConnect_signData',
          buildDappRequest(url),
          unifiedPayload,
        );
      } catch (err) {
        logDebugError('evmConnectBridgeApi:wcSignData', err);
        return { success: false, error: { code: 0, message: 'Unknown error' } };
      }
    },
  };
}

function buildDappRequest(origin: string) {
  return {
    url: origin,
    isUrlEnsured: true,
    accountId: getGlobal().currentAccountId,
  };
}
