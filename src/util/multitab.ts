import type { BottomSheetKeys } from '@mytonwallet/native-bottom-sheet';
import { addCallback as onGlobalChange } from '../lib/teact/teactn';
import { getActions, getGlobal, setGlobal } from '../global';

import type { AllMethodArgs, AllMethodResponse, AllMethods } from '../api/types/methods';
import type { ActionPayloads, GlobalState } from '../global/types';
import type { Log } from './logs';

import { MULTITAB_DATA_CHANNEL_NAME } from '../config';
import { callApi } from '../api';
import { deepDiff } from './deepDiff';
import { deepMerge } from './deepMerge';
import { omit } from './iteratees';
import { getLogs } from './logs';
import { IS_DELEGATED_BOTTOM_SHEET, IS_DELEGATING_BOTTOM_SHEET, IS_MULTITAB_SUPPORTED } from './windowEnvironment';

import { isBackgroundModeActive } from '../hooks/useBackgroundMode';

type Recipient = 'main' | 'native';
type ActionMeta = {
  sheetKey?: BottomSheetKeys;
};

interface BroadcastChannelGlobalDiff {
  type: 'globalDiffUpdate';
  diff: any;
}

interface BroadcastChannelCallAction<K extends keyof ActionPayloads> {
  type: 'callAction';
  recipient: Recipient;
  name: K;
  options?: ActionPayloads[K];
  sheetKey?: BottomSheetKeys;
}

interface BroadcastChannelCallApiRequest<K extends keyof AllMethods> {
  type: 'callApiRequest';
  messageId: number;
  recipient: Recipient;
  name: K;
  args: AllMethodArgs<K>;
}

interface BroadcastChannelCallApiResponse<K extends keyof AllMethods> {
  type: 'callApiResponse';
  messageId: number;
  result: PromiseSettledResult<AllMethodResponse<K>>;
}

interface BroadcastChannelNativeLogsRequest {
  type: 'getLogsFromNative';
}

interface BroadcastChannelNativeLogsResponse {
  type: 'logsFromNative';
  logs: Log[];
}

interface BroadcastChannelNativeReady {
  type: 'nativeReady';
}

type BroadcastChannelMessage = BroadcastChannelGlobalDiff
  | BroadcastChannelCallAction<keyof ActionPayloads>
  | BroadcastChannelCallApiRequest<keyof AllMethods>
  | BroadcastChannelCallApiResponse<keyof AllMethods>
  | BroadcastChannelNativeLogsRequest
  | BroadcastChannelNativeLogsResponse
  | BroadcastChannelNativeReady;
type EventListener = (type: 'message', listener: (event: { data: BroadcastChannelMessage }) => void) => void;

export type TypedBroadcastChannel = {
  postMessage: (message: BroadcastChannelMessage) => void;
  addEventListener: EventListener;
  removeEventListener: EventListener;
};

const channel = IS_MULTITAB_SUPPORTED
  ? new BroadcastChannel(MULTITAB_DATA_CHANNEL_NAME) as TypedBroadcastChannel
  : undefined;

let currentGlobal = getGlobal();
let messageIndex = 0;
/** In main is always `true`, in NBS is `false` until the global state is initialized */
let isDelegatedGlobalReady = !IS_DELEGATED_BOTTOM_SHEET;
/** Non-empty only in NBS. Stores action payloads requested from main to be executed on NBS */
const pendingNativeActions: Array<BroadcastChannelCallAction<keyof ActionPayloads>> = [];
/** In NBS is always `true`, in main is `false` until NBS is ready */
let isNativeReady = !IS_DELEGATING_BOTTOM_SHEET;
/** Non-empty only in main. Stores action requests to be executed on NBS. If we send send before NBS reports it's ready, they will be dropped, so we need to store them and send later. */
const pendingCallsToNative: Array<BroadcastChannelCallAction<keyof ActionPayloads>> = [];
let delegatingBottomSheetKey: string | undefined;
let delegatedBottomSheetKey: BottomSheetKeys | undefined;

export function markDelegatedGlobalReady() {
  if (!IS_DELEGATED_BOTTOM_SHEET || isDelegatedGlobalReady) {
    return;
  }

  const global = getGlobal();
  const omitted: GlobalState = omit(global as GlobalState & { isInited?: false }, ['isInited' as const]);
  setGlobal(omitted);

  isDelegatedGlobalReady = true;
  flushPendingNativeActions();
}

export function resetDelegatedGlobalReady() {
  if (!IS_DELEGATED_BOTTOM_SHEET || !isDelegatedGlobalReady) {
    return;
  }

  isDelegatedGlobalReady = false;
}

export function notifyNativeReady() {
  if (!IS_DELEGATED_BOTTOM_SHEET || !channel) {
    return;
  }

  // Send to main that NBS is ready
  channel.postMessage({ type: 'nativeReady' });
}

function runAction(payload: BroadcastChannelCallAction<keyof ActionPayloads>) {
  if (!IS_DELEGATED_BOTTOM_SHEET) {
    getActions()[payload.name](payload.options as never);
    return;
  }

  if (!shouldRunActionNow(payload)) {
    pendingNativeActions.push(payload);
    return;
  }

  getActions()[payload.name](payload.options as never);
}

export function initMultitab({ noPubGlobal }: { noPubGlobal?: boolean } = {}) {
  if (!channel) return;

  if (!noPubGlobal) {
    onGlobalChange(handleGlobalChange);
  }

  channel.addEventListener('message', handleMultitabMessage);
}

function handleGlobalChange(global: GlobalState) {
  if (global === currentGlobal) return;

  // One of the goals of this check is preventing the Delegated Bottom Sheet global state initialization (performed by
  // src/global/init.ts) from propagating to the main WebView. Normally this is prevented by `isBackgroundModeActive()`
  // (the Sheet should be out of focus during the initialization), but we suspect that this approach is not fully
  // reliable, because the focus may be in the Sheet during the initialization. So an extra `isInited` check is used -
  // `isInited: false` appears only in the initial Teactn global state (see src/lib/teact/teactn.tsx) and we expect the
  // first global change to be the initialization.
  if (isBackgroundModeActive() || (currentGlobal as AnyLiteral).isInited === false) {
    currentGlobal = global;
    return;
  }

  const diff = deepDiff(omitLocalOnlyKeys(currentGlobal), omitLocalOnlyKeys(global));

  if (typeof diff !== 'symbol') {
    channel!.postMessage({
      type: 'globalDiffUpdate',
      diff,
    });
  }

  currentGlobal = global;
}

function omitLocalOnlyKeys(global: GlobalState) {
  return omit(global, ['DEBUG_randomId']);
}

async function handleMultitabMessage({ data }: { data: BroadcastChannelMessage }) {
  switch (data.type) {
    case 'globalDiffUpdate': {
      if (IS_DELEGATED_BOTTOM_SHEET) return;

      currentGlobal = deepMerge(getGlobal(), data.diff);

      setGlobal(currentGlobal);

      break;
    }

    case 'callAction': {
      const { recipient } = data;

      if (!doesMessageRecipientMatch(recipient)) return;

      runAction(data);
      break;
    }

    case 'callApiRequest': {
      const { recipient, messageId, name, args } = data;

      if (!doesMessageRecipientMatch(recipient)) return;

      const [result] = await Promise.allSettled([callApi(name, ...args)]);
      channel!.postMessage({ type: 'callApiResponse', messageId, result });
      break;
    }

    case 'getLogsFromNative': {
      if (!IS_DELEGATED_BOTTOM_SHEET) return;

      channel!.postMessage({ type: 'logsFromNative', logs: getLogs() });
      break;
    }

    case 'nativeReady': {
      if (!IS_DELEGATING_BOTTOM_SHEET || isNativeReady) return;

      isNativeReady = true;
      pendingCallsToNative.splice(0).forEach((message) => {
        channel!.postMessage(message);
      });
      break;
    }
  }
}

function doesMessageRecipientMatch(recipient: Recipient) {
  return (IS_DELEGATING_BOTTOM_SHEET && recipient === 'main')
    || (IS_DELEGATED_BOTTOM_SHEET && recipient === 'native');
}

export function callActionInMain<K extends keyof ActionPayloads>(name: K, options?: ActionPayloads[K]) {
  channel!.postMessage({
    type: 'callAction',
    recipient: 'main',
    name,
    options,
  });
}

export function callActionInNative<K extends keyof ActionPayloads>(
  name: K,
  options?: ActionPayloads[K],
  meta?: ActionMeta,
) {
  const message: BroadcastChannelCallAction<K> = {
    type: 'callAction',
    recipient: 'native',
    name,
    options,
    sheetKey: meta?.sheetKey,
  };

  if (IS_DELEGATING_BOTTOM_SHEET && !isNativeReady) {
    pendingCallsToNative.push(message as BroadcastChannelCallAction<keyof ActionPayloads>);
    return;
  }

  channel!.postMessage(message);
}

export function setDelegatingBottomSheetKey(key?: string) {
  delegatingBottomSheetKey = key;
}

export function getDelegatingBottomSheetKey() {
  return delegatingBottomSheetKey;
}

export function clearDelegatingBottomSheetKey(key?: string) {
  if (!key || delegatingBottomSheetKey !== key) {
    return;
  }

  delegatingBottomSheetKey = undefined;
}

export function setDelegatedBottomSheetKey(key?: BottomSheetKeys) {
  delegatedBottomSheetKey = key;
}

function shouldRunActionNow(payload: BroadcastChannelCallAction<keyof ActionPayloads>) {
  if (!isDelegatedGlobalReady) {
    return false;
  }

  return !payload.sheetKey || payload.sheetKey === delegatedBottomSheetKey;
}

function flushPendingNativeActions() {
  if (!pendingNativeActions.length) {
    return;
  }

  const remaining: typeof pendingNativeActions = [];
  pendingNativeActions.splice(0).forEach((payload) => {
    if (!shouldRunActionNow(payload)) {
      remaining.push(payload);
      return;
    }

    getActions()[payload.name](payload.options as never);
  });

  if (remaining.length) {
    pendingNativeActions.push(...remaining);
  }
}

export function callApiInMain<T extends keyof AllMethods>(name: T, ...args: AllMethodArgs<T>) {
  if (!IS_DELEGATED_BOTTOM_SHEET) {
    return callApi(name, ...args);
  }

  const messageId = ++messageIndex;

  return new Promise<AllMethodResponse<T>>((resolve, reject) => {
    const handleMessage = ({ data }: { data: BroadcastChannelMessage }) => {
      if (data.type === 'callApiResponse' && data.messageId === messageId) {
        channel!.removeEventListener('message', handleMessage);
        if (data.result.status === 'fulfilled') {
          resolve(data.result.value as AllMethodResponse<T>);
        } else {
          reject(data.result.reason);
        }
      }
    };

    channel!.addEventListener('message', handleMessage);
    channel!.postMessage({ type: 'callApiRequest', recipient: 'main', messageId, name, args });
  });
}

export function getLogsFromNative() {
  if (!IS_DELEGATING_BOTTOM_SHEET) return Promise.resolve([]);

  return new Promise<Log[]>((resolve) => {
    const handleMessage = ({ data }: { data: BroadcastChannelMessage }) => {
      if (data.type === 'logsFromNative') {
        channel!.removeEventListener('message', handleMessage);
        resolve(data.logs);
      }
    };

    channel!.addEventListener('message', handleMessage);
    channel!.postMessage({ type: 'getLogsFromNative' });
  });
}
