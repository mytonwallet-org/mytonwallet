import type { AppRequest, RpcRequests } from '@tonconnect/protocol';

import type { ApiParsedPayload } from '../../../types';
import type {
  DappDisconnectRequest,
  DappMethodResult,
  DappProtocolType,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../types';

import { isNftTransferPayload, isTokenTransferPayload } from '../../../../util/ton/transfer';

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

export function getTransferActualToAddress(toAddress: string, payload: ApiParsedPayload | undefined) {
  // This function implementation is not complete. That is, other transfer types may have another actual "to" address.
  if (isNftTransferPayload(payload)) {
    return payload.newOwner;
  }
  if (isTokenTransferPayload(payload)) {
    return payload.destination;
  }
  return toAddress;
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

export function transformUnifiedMethodResponseToTonConnect(payload: DappMethodResult<DappProtocolType.TonConnect>) {
  if (payload.success) {
    return payload.result;
  }
  return {
    id: '0',
    error: payload.error,
  };
}
