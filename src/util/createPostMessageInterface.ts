import type InAppBrowserPostMessageAdapter from './embeddedDappBridge/provider/InAppBrowserPostMessageAdapter';
import type {
  ApiUpdate,
  CancellableCallback,
  OriginMessageData,
  OriginMessageEvent,
  WorkerMessageData,
} from './PostMessageConnector';

import { decodeExtensionMessage, encodeError, encodeExtensionMessage } from './extensionMessageSerializer';
import { logDebugError } from './logs';

declare const self: WorkerGlobalScope;

const callbackState = new Map<string, CancellableCallback>();

type ApiConfig =
// eslint-disable-next-line @typescript-eslint/no-redundant-type-constituents
  ((name: string, ...args: any[]) => any | [any, ArrayBuffer[]])
  | Record<string, AnyFunction>;
type SendToOrigin = (data: WorkerMessageData, transferables?: Transferable[]) => void;

/**
 * Provides functions, defined in this messenger (a window, a worker), to another messenger.
 * The other messenger can call the functions using `createConnector`.
 */
export function createPostMessageInterface(
  api: ApiConfig,
  channel?: string,
  target: DedicatedWorkerGlobalScope | Worker | InAppBrowserPostMessageAdapter = self as DedicatedWorkerGlobalScope,
  shouldIgnoreErrors?: boolean,
) {
  function sendToOrigin(data: WorkerMessageData, transferables?: Transferable[]) {
    data.channel = channel;

    if (transferables) {
      target.postMessage(data, transferables);
    } else {
      target.postMessage(data);
    }
  }

  if (!shouldIgnoreErrors) {
    handleErrors(sendToOrigin);
  }

  function handleMessage(e: OriginMessageEvent) {
    if (e.data?.channel === channel) {
      void onMessage(api, e.data, sendToOrigin);
    }
  }

  // Correct for any target, but TypeScript weirdly complains
  (target as DedicatedWorkerGlobalScope).addEventListener('message', handleMessage);

  return () => {
    (target as DedicatedWorkerGlobalScope).removeEventListener('message', handleMessage);
  };
}

/**
 * Provides functions, defined in the main window, to an IFrame.
 */
export function createReverseIFrameInterface(
  api: ApiConfig,
  targetOrigin: string,
  target: Window,
  channel?: string,
) {
  function sendToOrigin(data: WorkerMessageData, transferables?: Transferable[]) {
    data.channel = channel;

    if (transferables) {
      throw new Error('Cannot send `Transferable` to `Window`');
    } else {
      target.postMessage(data, targetOrigin);
    }
  }

  function handleMessage(e: OriginMessageEvent) {
    if (targetOrigin && e.origin !== targetOrigin) return;

    if (e.data?.channel === channel) {
      void onMessage(api, e.data, sendToOrigin);
    }
  }

  window.addEventListener('message', handleMessage);

  return () => {
    window.removeEventListener('message', handleMessage);
  };
}

/**
 * Provides functions, defined in this extension service worker, to a window.
 * The window can call the functions using `createExtensionConnector`.
 */
export function createExtensionInterface(
  portName: string,
  api: ApiConfig,
  channel?: string,
  cleanUpdater?: (onUpdate: (update: ApiUpdate) => void) => void,
  withAutoInit = false,
) {
  chrome.runtime.onConnect.addListener((port) => {
    if (port.name !== portName) {
      return;
    }

    const url = port.sender?.url;
    const origin = url ? new URL(url).origin : undefined;

    const dAppUpdater = (update: ApiUpdate) => {
      sendToOrigin({
        type: 'update',
        update,
      });
    };

    function sendToOrigin(data: WorkerMessageData) {
      data.channel = channel;
      port.postMessage(encodeExtensionMessage(data));
    }

    handleErrors(sendToOrigin);

    port.onMessage.addListener((data: OriginMessageData | string) => {
      data = decodeExtensionMessage(data);
      if (data.channel === channel) {
        void onMessage(api, data, sendToOrigin, dAppUpdater, origin);
      }
    });

    port.onDisconnect.addListener(() => {
      cleanUpdater?.(dAppUpdater);
    });

    if (withAutoInit) {
      void onMessage(api, { type: 'init', args: [] }, sendToOrigin, dAppUpdater);
    }
  });
}

/**
 * Provides functions, defined in this window, to the extension service worker.
 * The service worker can call the functions using `createReverseExtensionConnector`.
 */
export function createReverseExtensionInterface(
  portName: string,
  api: ApiConfig,
) {
  let port: chrome.runtime.Port;

  function sendToServiceWorker(data: WorkerMessageData) {
    port.postMessage(encodeExtensionMessage(data));
  }

  function connect() {
    port = chrome.runtime.connect({ name: portName });

    port.onMessage.addListener((data: OriginMessageData | string) => {
      data = decodeExtensionMessage(data);
      void onMessage(api, data, sendToServiceWorker);
    });

    // For some reason port can suddenly get disconnected
    port.onDisconnect.addListener(() => {
      connect();
    });
  }

  connect();
}

async function onMessage(
  api: ApiConfig,
  data: OriginMessageData,
  sendToOrigin: SendToOrigin,
  onUpdate?: (update: ApiUpdate) => void,
  origin?: string,
) {
  if (!onUpdate) {
    onUpdate = (update: ApiUpdate) => {
      sendToOrigin({
        type: 'update',
        update,
      });
    };
  }

  switch (data.type) {
    case 'init': {
      const { args, messageId } = data;
      const promise = typeof api === 'function'
        ? api('init', origin, onUpdate, ...args)
        : api.init?.(onUpdate, ...args);
      await promise;

      if (messageId) {
        sendToOrigin({
          type: 'methodResponse',
          messageId,
          response: undefined,
        });
      }

      break;
    }
    case 'callMethod': {
      const {
        messageId, name, args, withCallback,
      } = data;
      try {
        // This method is probably from another worker
        if (typeof api !== 'function' && !api[name]) return;

        if (messageId && withCallback) {
          const callback = (...callbackArgs: any[]) => {
            const lastArg = callbackArgs[callbackArgs.length - 1];

            sendToOrigin({
              type: 'methodCallback',
              messageId,
              callbackArgs,
            }, isTransferable(lastArg) ? [lastArg] : undefined);
          };

          callbackState.set(messageId, callback);

          args.push(callback as never);
        }

        const response = typeof api === 'function'
          ? await api(name, origin, ...args)
          : await api[name](...args);
        const { arrayBuffer } = (typeof response === 'object' && response && 'arrayBuffer' in response) || {};

        if (messageId) {
          sendToOrigin(
            {
              type: 'methodResponse',
              messageId,
              response,
            },
            arrayBuffer ? [arrayBuffer] : undefined,
          );
        }
      } catch (err: any) {
        logDebugError(name, err);

        if (messageId) {
          sendToOrigin({
            type: 'methodResponse',
            messageId,
            error: encodeError(err),
          });
        }
      }

      if (messageId) {
        callbackState.delete(messageId);
      }

      break;
    }
    case 'cancelProgress': {
      const callback = callbackState.get(data.messageId);
      if (callback) {
        callback.isCanceled = true;
      }

      break;
    }
  }
}

function isTransferable(obj: any) {
  return obj instanceof ArrayBuffer || obj instanceof ImageBitmap;
}

function handleErrors(sendToOrigin: SendToOrigin) {
  self.addEventListener('error', (e) => {
    const error = e.error || { name: 'Error', message: 'Uncaught exception in worker' };
    logDebugError(error.message, e.error);

    sendToOrigin({
      type: 'unhandledError',
      error: encodeError(error),
    });
  });

  self.addEventListener('unhandledrejection', (e) => {
    const error = e.reason || { name: 'Error', message: 'Unhandled rejection in worker' };
    logDebugError(error.message, e.reason);

    sendToOrigin({
      type: 'unhandledError',
      error: encodeError(error),
    });
  });
}
