import type { StoredDappConnection } from '../api/dappProtocols/storage';
import type { ApiDappRequest } from '../api/types';

export function getDappConnectionUniqueId(request: ApiDappRequest | StoredDappConnection): string {
  return (request as ApiDappRequest).sseOptions?.appClientId
    || (request as StoredDappConnection).sse?.appClientId
    || (request as StoredDappConnection).wcPairingTopic
    || 'jsbridge';
}
