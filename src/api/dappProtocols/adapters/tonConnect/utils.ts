import type { AppRequest, RpcRequests } from '@tonconnect/protocol';

import type { ApiParsedPayload } from '../../../types';
import type {
  DappDisconnectRequest,
  DappMethodResult,
  DappProtocolType,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../types';

// https://stackoverflow.com/a/417184
const URL_MAX_LENGTH = 2000;

export function isValidString(value: any, maxLength = 100) {
  return typeof value === 'string' && value.length <= maxLength;
}

export function isValidUrl(url: string) {
  const isString = isValidString(url, URL_MAX_LENGTH);
  if (!isString) return false;

  try {
    new URL(url);
    return true;
  } catch (err) {
    return false;
  }
}

export function isTransferPayloadDangerous(payload: ApiParsedPayload | undefined) {
  return payload?.type === 'unknown';
}

export function transformTonConnectMessageToUnified(message: AppRequest<keyof RpcRequests>) {
  switch (message.method) {
    case 'sendTransaction': {
      const unified: DappTransactionRequest<DappProtocolType.TonConnect> = {
        id: message.id,
        chain: 'ton',
        payload: JSON.parse(message.params[0]),
      };
      return unified;
    }
    case 'signData': {
      const unified: DappSignDataRequest<DappProtocolType.TonConnect> = {
        id: message.id,
        chain: 'ton',
        payload: JSON.parse(message.params[0]),
      };
      return unified;
    }
    case 'disconnect': {
      const unified: DappDisconnectRequest = {
        requestId: message.id,
      };
      return unified;
    }
    default:
      throw new Error(`Cannot parse unknown tonConnect message: ${JSON.parse(message)}`);
  }
}

export function transformUnifiedMethodResponseToTonConnect(
  payload: DappMethodResult<DappProtocolType.TonConnect>,
  id: string,
) {
  if (payload.success) {
    return payload.result;
  }
  // The error response must echo the request id, otherwise the dapp can't correlate it and keeps waiting.
  return {
    id,
    error: payload.error,
  };
}
