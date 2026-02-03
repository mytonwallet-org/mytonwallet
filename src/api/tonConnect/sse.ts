import type {
  AppRequest,
  ConnectRequest,
  DisconnectEvent,
  RpcMethod,
  RpcRequests,
} from '@tonconnect/protocol';
import nacl, { randomBytes } from 'tweetnacl';

import type { ApiDappRequest, ApiSseOptions, OnApiUpdate } from '../types';
import { CONNECT_EVENT_ERROR_CODES } from './types';

import { IS_CAPACITOR, SSE_BRIDGE_URL } from '../../config';
import { parseAccountId } from '../../util/account';
import { handleFetchErrors } from '../../util/fetch';
import { extractKey } from '../../util/iteratees';
import { logDebug, logDebugError } from '../../util/logs';
import safeExec from '../../util/safeExec';
import { getCurrentNetwork, waitLogin } from '../common/accounts';
import { bytesToHex } from '../common/utils';
import { getDappsState, getSseLastEventId, setSseLastEventId } from '../methods/dapps';
import * as tonConnect from './index';

type SseDapp = {
  accountId: string;
  url: string;
} & ApiSseOptions;

// The `empty` strategy - a trick to solve the problem of long network connection initialization
// in the Capacitor version of the app when it resumes from the background.
// In this case, the client should show a loader, and once the real SSE connection starts,
// the loader will be hidden.
type ReturnStrategy = 'back' | 'none' | 'empty' | (string & {});

const TTL_SEC = 300;
const NONCE_SIZE = 24;
const MAX_CONFIRM_DURATION = 60 * 1000;
const SHOULD_SHOW_LOADER_ON_SSE_START = IS_CAPACITOR;
const ALLOWED_SSE_METHODS = new Set<RpcMethod>(['sendTransaction', 'disconnect', 'signData']);

let sseEventSource: EventSource | undefined;
let sseDapps: SseDapp[] = [];
let delayedReturnParams: {
  validUntil: number;
  url: string;
  isFromInAppBrowser?: boolean;
} | undefined;

let onUpdate: OnApiUpdate;

export function initSse(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function startSseConnection({
  url, isFromInAppBrowser, identifier,
}: {
  url: string;
  isFromInAppBrowser?: boolean;
  identifier?: string;
}): Promise<ReturnStrategy | undefined> {
  const { searchParams: params, origin: connectionOrigin } = new URL(url);

  const ret: ReturnStrategy = params.get('ret') || 'back';
  const version = Number(params.get('v') as string);
  const appClientId = params.get('id') as string;
  // `back` strategy cannot be implemented
  const shouldOpenUrl = ret !== 'back' && ret !== 'none';
  const r = params.get('r');

  if (!r) {
    if (shouldOpenUrl) {
      delayedReturnParams = {
        validUntil: Date.now() + MAX_CONFIRM_DURATION,
        url: ret,
        isFromInAppBrowser,
      };
    }

    return SHOULD_SHOW_LOADER_ON_SSE_START ? 'empty' : undefined;
  }

  const connectRequest: ConnectRequest | null = safeExec(() => JSON.parse(r)) || JSON.parse(decodeURIComponent(r));

  logDebug('SSE Start connection:', {
    version, appClientId, connectRequest, ret, connectionOrigin, identifier,
  });

  const { secretKey: secretKeyArray, publicKey: publicKeyArray } = nacl.box.keyPair();
  const secretKey = bytesToHex(secretKeyArray);
  const clientId = bytesToHex(publicKeyArray);

  const lastOutputId = 0;
  const request: ApiDappRequest = {
    url: undefined,
    identifier,
    sseOptions: {
      clientId,
      appClientId,
      secretKey,
      lastOutputId,
    },
  };

  await waitLogin();

  if (!connectRequest) {
    onUpdate({
      type: 'showError',
      error: 'Invalid TON Connect link',
    });

    return undefined;
  }

  const result = await tonConnect.connect(request, connectRequest, lastOutputId);

  if (result.event === 'connect_error') {
    const { code } = result.payload;

    if ([
      CONNECT_EVENT_ERROR_CODES.MANIFEST_CONTENT_ERROR,
      CONNECT_EVENT_ERROR_CODES.MANIFEST_NOT_FOUND_ERROR,
      CONNECT_EVENT_ERROR_CODES.BAD_REQUEST_ERROR,
      CONNECT_EVENT_ERROR_CODES.UNKNOWN_APP_ERROR,
      CONNECT_EVENT_ERROR_CODES.METHOD_NOT_SUPPORTED,
    ].includes(code)) {
      onUpdate({
        type: 'showError',
        error: result.payload.message,
      });
    }
  }

  await sendMessage(result, secretKey, clientId, appClientId);

  if (result.event !== 'connect_error') {
    await resetupSseConnection();
  }

  if (!shouldOpenUrl) {
    return undefined;
  }

  return ret;
}

export async function resetupSseConnection() {
  const [lastEventId, dappsState, network] = await Promise.all([
    getSseLastEventId(),
    getDappsState(),
    getCurrentNetwork(),
  ]);

  if (!dappsState || !network) {
    return;
  }

  sseDapps = Object.entries(dappsState).reduce((result, [accountId, dappsByUrl]) => {
    if (parseAccountId(accountId).network !== network) {
      return result;
    }

    for (const byUniqueId of Object.values(dappsByUrl)) {
      for (const dapp of Object.values(byUniqueId)) {
        if (dapp.sse?.clientId) {
          result.push({
            ...dapp.sse,
            accountId,
            url: dapp.url,
          });
        }
      }
    }

    return result;
  }, [] as SseDapp[]);

  const clientIds = extractKey(sseDapps, 'clientId').filter(Boolean);
  if (!clientIds.length) {
    return;
  }

  closeEventSource();
  sseEventSource = openEventSource(clientIds, lastEventId);

  sseEventSource.onopen = () => {
    if (SHOULD_SHOW_LOADER_ON_SSE_START) {
      onUpdate({
        type: 'tonConnectOnline',
      });
    }
    logDebug('EventSource opened');
  };

  sseEventSource.onerror = (e) => {
    logDebugError('EventSource', e.type);
  };

  sseEventSource.onmessage = async (event) => {
    const { from, message: encryptedMessage } = JSON.parse(event.data);

    const sseDapp = sseDapps.find(({ appClientId }) => appClientId === from);
    if (!sseDapp) {
      logDebug(`Dapp with clientId ${from} not found`);
      return;
    }

    const {
      accountId, clientId, appClientId, secretKey, url, lastOutputId,
    } = sseDapp;
    const message = decryptMessage(encryptedMessage, appClientId, secretKey) as AppRequest<keyof RpcRequests>;

    logDebug('SSE Event:', message);

    await setSseLastEventId(event.lastEventId);
    const sseOptions = {
      clientId,
      appClientId,
      secretKey,
      lastOutputId,
    };

    if (!ALLOWED_SSE_METHODS.has(message.method)) {
      logDebug(`Unsupported SSE method: ${message.method}`);
      return;
    }

    const handler = tonConnect[message.method] as (
      request: ApiDappRequest, message: AppRequest<keyof RpcRequests>,
    ) => Promise<AnyLiteral>;
    const result = await handler({ url, accountId, sseOptions }, message);

    await sendMessage(result, secretKey, clientId, appClientId);

    if (delayedReturnParams) {
      const { validUntil, url, isFromInAppBrowser } = delayedReturnParams;
      if (validUntil > Date.now()) {
        onUpdate({ type: 'openUrl', url, isExternal: !isFromInAppBrowser });
      }
      delayedReturnParams = undefined;
    }
  };
}

export async function sendSseDisconnect(accountId: string, url: string) {
  const sseDapp = sseDapps.find((d) => d.url === url && d.accountId === accountId);
  if (!sseDapp) return;

  const { secretKey, clientId, appClientId } = sseDapp;
  const lastOutputId = sseDapp.lastOutputId + 1;

  const response: DisconnectEvent = {
    event: 'disconnect',
    id: lastOutputId,
    payload: {},
  };

  await sendMessage(response, secretKey, clientId, appClientId);
}

function sendMessage(
  message: AnyLiteral, secretKey: string, clientId: string, toId: string, topic?: 'signTransaction' | 'signData',
) {
  const buffer = Buffer.from(JSON.stringify(message));
  const encryptedMessage = encryptMessage(buffer, toId, secretKey);
  return sendRawMessage(encryptedMessage, clientId, toId, topic);
}

async function sendRawMessage(body: string, clientId: string, toId: string, topic?: 'signTransaction' | 'signData') {
  const url = new URL(`${SSE_BRIDGE_URL}message`);
  url.searchParams.set('client_id', clientId);
  url.searchParams.set('to', toId);
  url.searchParams.set('ttl', TTL_SEC.toString());
  if (topic) {
    url.searchParams.set('topic', topic);
  }

  const response = await fetch(url, { method: 'POST', body });
  await handleFetchErrors(response);
}

function closeEventSource() {
  if (!sseEventSource) return;

  safeExec(() => {
    sseEventSource!.close();
  });
  sseEventSource = undefined;
}

function openEventSource(clientIds: string[], lastEventId?: string) {
  const url = new URL(`${SSE_BRIDGE_URL}events`);
  url.searchParams.set('client_id', clientIds.join(','));
  if (lastEventId) {
    url.searchParams.set('last_event_id', lastEventId);
  }
  return new EventSource(url);
}

function encryptMessage(message: Uint8Array, publicKey: string, secretKey: string) {
  const nonce = randomBytes(NONCE_SIZE);
  const encrypted = nacl.box(
    message, nonce, Buffer.from(publicKey, 'hex'), Buffer.from(secretKey, 'hex'),
  );
  return Buffer.concat([nonce, encrypted]).toString('base64');
}

function decryptMessage(message: string, publicKey: string, secretKey: string) {
  const fullBuffer = Buffer.from(message, 'base64');
  const nonce = fullBuffer.subarray(0, NONCE_SIZE);
  const encrypted = fullBuffer.subarray(NONCE_SIZE);
  const decrypted = nacl.box.open(
    encrypted,
    nonce,
    Buffer.from(publicKey, 'hex'),
    Buffer.from(secretKey, 'hex'),
  );
  const jsonText = new TextDecoder('utf-8').decode(decrypted!);
  return JSON.parse(jsonText);
}
