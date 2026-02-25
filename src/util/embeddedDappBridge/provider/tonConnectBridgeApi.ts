import type {
  AppRequest,
  ConnectEvent,
  ConnectEventError,
  ConnectRequest,
  RpcMethod,
  SignDataPayload,
  WalletResponse,
} from '@tonconnect/protocol';
import { getActions, getGlobal } from '../../../global';

import type { TonConnectTransactionPayload } from '../../../api/dappProtocols/adapters/tonConnect/types';

import { TONCONNECT_PROTOCOL_VERSION } from '../../../config';
import { callApi } from '../../../api';
import {
  CONNECT_EVENT_ERROR_CODES,
  SEND_TRANSACTION_ERROR_CODES,
} from '../../../api/dappProtocols/adapters/tonConnect/errors';
import { logDebugError } from '../../logs';

export interface BrowserTonConnectBridgeMethods {
  connect(protocolVersion: number, message: ConnectRequest): Promise<ConnectEvent>;

  restoreConnection(): Promise<ConnectEvent>;

  disconnect(): Promise<void>;

  send<T extends RpcMethod>(message: AppRequest<T>): Promise<WalletResponse<T>>;
}

let requestId = 0;

export function buildTonConnectBridgeApi(pageUrl: string): BrowserTonConnectBridgeMethods | undefined {
  const {
    openLoadingOverlay,
    closeLoadingOverlay,
  } = getActions();

  const url = new URL(pageUrl).origin.toLowerCase();

  return {
    connect: async (protocolVersion, request) => {
      try {
        if (protocolVersion > TONCONNECT_PROTOCOL_VERSION) {
          return buildConnectError(
            requestId,
            'Unsupported protocol version',
            CONNECT_EVENT_ERROR_CODES.BAD_REQUEST_ERROR,
          );
        }
        verifyConnectRequest(request);

        openLoadingOverlay();

        const response = await callApi(
          'tonConnect_connect',
          buildDappRequest(url),
          {
            protocolType: 'tonConnect',
            transport: 'inAppBrowser',
            protocolData: request,
            // We will rewrite permissions in connect method after parsing payload anyway
            permissions: {
              isAddressRequired: true,
              isPasswordRequired: false,
            },
            requestedChains: [{
              chain: 'ton',
              network: 'mainnet',
            }],
          },
          requestId,
        );

        closeLoadingOverlay();

        if (!response?.success) {
          return buildConnectError(
            requestId,
            response?.error?.message,
            CONNECT_EVENT_ERROR_CODES.BAD_REQUEST_ERROR,
          );
        }

        requestId++;

        return response.session.protocolData;
      } catch (err: any) {
        logDebugError('useDAppBridge:connect', err);

        if ('event' in err && 'id' in err && 'payload' in err) {
          return err;
        }

        return buildConnectError(
          requestId,
          err?.message,
          CONNECT_EVENT_ERROR_CODES.UNKNOWN_ERROR,
        );
      }
    },

    restoreConnection: async () => {
      try {
        const response = await callApi(
          'tonConnect_reconnect',
          buildDappRequest(url),
          requestId,
        );

        if (!response?.success) {
          return buildConnectError(
            requestId,
            response?.error?.message,
            CONNECT_EVENT_ERROR_CODES.BAD_REQUEST_ERROR,
          );
        }

        requestId++;

        return response.session.protocolData;
      } catch (err: any) {
        logDebugError('useDAppBridge:reconnect', err);

        if ('event' in err && 'id' in err && 'payload' in err) {
          return err;
        }

        return buildConnectError(
          requestId,
          err?.message,
          CONNECT_EVENT_ERROR_CODES.UNKNOWN_ERROR,
        );
      }
    },

    disconnect: async () => {
      requestId = 0;

      await callApi(
        'tonConnect_disconnect',
        buildDappRequest(url),
        {
          requestId: requestId.toString(),
        },
      );
    },

    send: async <T extends RpcMethod>(request: AppRequest<T>) => {
      requestId++;

      const global = getGlobal();
      const isConnected = global.byAccountId[global.currentAccountId!].dapps?.some((dapp) => dapp.url === url);

      if (!isConnected) {
        return {
          error: {
            code: SEND_TRANSACTION_ERROR_CODES.UNKNOWN_APP_ERROR,
            message: 'Unknown app',
          },
          id: request.id.toString(),
        };
      }

      const dappRequest = buildDappRequest(url);

      try {
        switch (request.method) {
          case 'disconnect': {
            await callApi(
              'tonConnect_disconnect',
              dappRequest,
              {
                requestId: request.id,
              },
            );

            return {
              result: {},
              id: request.id,
            };
          }

          case 'sendTransaction': {
            const response = (await callApi(
              'tonConnect_sendTransaction',
              dappRequest,
              {
                id: request.id,
                chain: 'ton',
                payload: JSON.parse(request.params[0]) as TonConnectTransactionPayload,
              },
            ))!;

            if (response.success) {
              return response.result;
            }

            return {
              id: request.id,
              error: {
                code: response.error.code,
                message: response.error.message,
              },
            };
          }

          case 'signData': {
            const response = (await callApi(
              'tonConnect_signData',
              dappRequest,
              {
                id: request.id,
                chain: 'ton',
                payload: JSON.parse(request.params[0]) as SignDataPayload,
              },
            ))!;

            if (response?.success) {
              return response.result;
            }

            return {
              id: request.id,
              error: {
                code: response.error.code,
                message: response.error.message,
              } as any,
            };
          }

          default: {
            const anyRequest = request;

            return {
              id: String(anyRequest.id),
              error: {
                code: SEND_TRANSACTION_ERROR_CODES.BAD_REQUEST_ERROR,
                message: `Method "${anyRequest.method}" is not supported`,
              },
            };
          }
        }
      } catch (err: any) {
        logDebugError('useDAppBridge:send', err);

        return {
          id: String(request.id),
          error: {
            code: SEND_TRANSACTION_ERROR_CODES.UNKNOWN_ERROR,
            message: err?.message,
          },
        };
      }
    },
  };
}

function buildConnectError(
  id: number,
  msg = 'Unknown error.',
  code?: CONNECT_EVENT_ERROR_CODES,
): ConnectEventError {
  return {
    event: 'connect_error',
    id,
    payload: {
      code: code || CONNECT_EVENT_ERROR_CODES.UNKNOWN_ERROR,
      message: msg,
    },
  };
}

function verifyConnectRequest(request: ConnectRequest) {
  if (!(request && request.manifestUrl && request.items?.length)) {
    throw new Error('Wrong request data');
  }
}

function buildDappRequest(origin: string) {
  return {
    url: origin,
    isUrlEnsured: true,
    accountId: getGlobal().currentAccountId,
  };
}
