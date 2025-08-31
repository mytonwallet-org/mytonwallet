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

interface BroadcastChannelGlobalDiff {
  type: 'globalDiffUpdate';
  diff: any;
}

interface BroadcastChannelCallAction<K extends keyof ActionPayloads> {
  type: 'callAction';
  recipient: Recipient;
  name: K;
  options?: ActionPayloads[K];
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

type BroadcastChannelMessage = BroadcastChannelGlobalDiff
  | BroadcastChannelCallAction<keyof ActionPayloads>
  | BroadcastChannelCallApiRequest<keyof AllMethods>
  | BroadcastChannelCallApiResponse<keyof AllMethods>
  | BroadcastChannelNativeLogsRequest
  | BroadcastChannelNativeLogsResponse;
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
      const { recipient, name, options } = data;

      if (!doesMessageRecipientMatch(recipient)) return;

      getActions()[name](options as never);
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

export function callActionInNative<K extends keyof ActionPayloads>(name: K, options?: ActionPayloads[K]) {
  channel!.postMessage({
    type: 'callAction',
    recipient: 'native',
    name,
    options,
  });
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
          resolve(data.result.value);
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
