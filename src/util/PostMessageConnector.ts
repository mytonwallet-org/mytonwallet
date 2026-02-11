import { decodeError, decodeExtensionMessage, encodeExtensionMessage } from './extensionMessageSerializer';
import generateUniqueId from './generateUniqueId';
import { logDebugError } from './logs';

export interface CancellableCallback {
  (
    ...args: any[]
  ): void;

  isCanceled?: boolean;
  acceptsBuffer?: boolean;
}

type InitData = {
  channel?: string;
  type: 'init';
  messageId?: string;
  args: any[];
};

type CallMethodData = {
  channel?: string;
  type: 'callMethod';
  messageId?: string;
  name: string;
  args: any;
  withCallback?: boolean;
};

export type OriginMessageData = InitData | CallMethodData | {
  channel?: string;
  type: 'cancelProgress';
  messageId: string;
};

export interface OriginMessageEvent extends MessageEvent {
  data: OriginMessageData;
}

// eslint-disable-next-line @typescript-eslint/no-redundant-type-constituents
export type ApiUpdate = { type: string } & any;

export type WorkerMessageError = {
  name: string;
  message: string;
  stack?: string;
};

export type WorkerMessageData = {
  channel?: string;
  type: 'update';
  update: ApiUpdate;
} | {
  channel?: string;
  type: 'methodResponse';
  messageId: string;
  response?: any;
  error?: WorkerMessageError;
} | {
  channel?: string;
  type: 'methodCallback';
  messageId: string;
  callbackArgs: any[];
} | {
  channel?: string;
  type: 'unhandledError';
  error: WorkerMessageError;
};

export interface WorkerMessageEvent {
  data: WorkerMessageData;
}

interface RequestStates {
  messageId: string;
  resolve: AnyToVoidFunction;
  reject: AnyToVoidFunction;
  callback: AnyToVoidFunction;
}

type InputRequestTypes = Record<string, AnyFunction>;

type Values<T> = T[keyof T];
export type RequestTypes<T extends InputRequestTypes> = Values<{
  [Name in keyof (T)]: {
    name: Name & string;
    args: Parameters<T[Name]>;
  }
}>;

class ConnectorClass<T extends InputRequestTypes> {
  private requestStates = new Map<string, RequestStates>();

  private requestStatesByCallback = new Map<AnyToVoidFunction, RequestStates>();

  constructor(
    public target: Worker | Window | chrome.runtime.Port | DedicatedWorkerGlobalScope,
    private onUpdate?: (update: ApiUpdate) => void,
    private channel?: string,
    private shouldUseJson?: boolean,
    private targetOrigin = '*',
  ) {
  }

  public destroy() {
  }

  init(...args: any[]) {
    const { requestStates } = this;

    const messageId = generateUniqueId();
    const payload: InitData = {
      type: 'init',
      messageId,
      args,
    };

    const requestState = { messageId } as RequestStates;

    const promise = new Promise<void>((resolve, reject) => {
      Object.assign(requestState, { resolve, reject });
    });

    requestStates.set(messageId, requestState);
    promise
      .catch(() => undefined)
      .finally(() => {
        requestStates.delete(messageId);
      });

    this.postMessage(payload);

    return promise;
  }

  request(messageData: RequestTypes<T>) {
    const { requestStates, requestStatesByCallback } = this;

    const messageId = generateUniqueId();
    const payload: CallMethodData = {
      type: 'callMethod',
      messageId,
      ...messageData,
    };

    const requestState = { messageId } as RequestStates;

    // Re-wrap type because of `postMessage`
    const promise = new Promise<any>((resolve, reject) => {
      Object.assign(requestState, { resolve, reject });
    });

    if (typeof payload.args[payload.args.length - 1] === 'function') {
      payload.withCallback = true;

      const callback = payload.args.pop() as AnyToVoidFunction;
      requestState.callback = callback;
      requestStatesByCallback.set(callback, requestState);
    }

    requestStates.set(messageId, requestState);
    promise
      .catch(() => undefined)
      .finally(() => {
        requestStates.delete(messageId);

        if (requestState.callback) {
          requestStatesByCallback.delete(requestState.callback);
        }
      });

    this.postMessage(payload);

    return promise;
  }

  cancelCallback(progressCallback: CancellableCallback) {
    progressCallback.isCanceled = true;

    const { messageId } = this.requestStatesByCallback.get(progressCallback) || {};
    if (!messageId) {
      return;
    }

    this.postMessage({
      type: 'cancelProgress',
      messageId,
    });
  }

  onMessage(data: WorkerMessageData | string) {
    try {
      data = decodeExtensionMessage(data);
    } catch (err: any) {
      logDebugError('PostMessageConnector: Failed to parse message', err);
      return;
    }

    const { requestStates, channel } = this;
    if (data.channel !== channel) {
      return;
    }

    if (data.type === 'update' && this.onUpdate) {
      this.onUpdate(data.update);
    }
    if (data.type === 'methodResponse') {
      const requestState = requestStates.get(data.messageId);
      if (requestState) {
        if (data.error) {
          requestState.reject(decodeError(data.error));
        } else {
          requestState.resolve(data.response);
        }
      }
    } else if (data.type === 'methodCallback') {
      const requestState = requestStates.get(data.messageId);
      requestState?.callback?.(...data.callbackArgs);
    } else if (data.type === 'unhandledError') {
      throw decodeError(data.error);
    }
  }

  private postMessage(data: OriginMessageData) {
    data.channel = this.channel;

    let rawData: OriginMessageData | string = data;
    if (this.shouldUseJson) {
      rawData = encodeExtensionMessage(data);
    }

    if ('open' in this.target) { // Is Window
      this.target.postMessage(rawData, this.targetOrigin);
    } else {
      this.target.postMessage(rawData);
    }
  }
}

/**
 * Allows to call functions, provided by another messenger (a window, a worker), in this messenger.
 * The other messenger must provide the functions using `createPostMessageInterface`.
 */
export function createConnector<T extends InputRequestTypes>(
  worker: Worker | Window | DedicatedWorkerGlobalScope,
  onUpdate?: (update: ApiUpdate) => void,
  channel?: string,
  targetOrigin?: string,
) {
  const connector = new ConnectorClass<T>(worker, onUpdate, channel, undefined, targetOrigin);

  function handleMessage({ data }: WorkerMessageEvent | MessageEvent) {
    connector.onMessage(data);
  }

  worker.addEventListener('message', handleMessage as any); // TS weirdly complains here

  connector.destroy = () => {
    worker.removeEventListener('message', handleMessage as any);
  };

  return connector;
}

/**
 * Allows to call functions, provided by the extension service worker, in this window.
 * The service worker must provide the functions using `createExtensionInterface`.
 */
export function createExtensionConnector(
  name: string,
  onUpdate?: (update: ApiUpdate) => void,
  channel?: string,
  onReconnect?: () => void,
) {
  const connector = new ConnectorClass(connect(), onUpdate, channel, true);

  function connect() {
    const port = self.chrome.runtime.connect({ name });

    port.onMessage.addListener((data: string | WorkerMessageData) => {
      connector.onMessage(data);
    });

    // For some reason port can suddenly get disconnected
    port.onDisconnect.addListener(() => {
      connector.target = connect();
      onReconnect?.();
    });

    return port;
  }

  return connector;
}

/**
 * Allows to call functions, provided by a window, in this service worker.
 * The window must provide the functions using `createReverseExtensionInterface`.
 *
 * Warning: the connector is able to send messages only when the popup window is open.
 */
export function createReverseExtensionConnector(portName: string) {
  const nullWorker = {
    postMessage() {
      throw new Error('The popup window is not connected');
    },
  } as Pick<Worker, 'postMessage'> as Worker;

  const connector = new ConnectorClass(nullWorker, undefined, undefined, true);

  chrome.runtime.onConnect.addListener((port) => {
    if (port.name !== portName) {
      return;
    }

    connector.target = port;

    port.onMessage.addListener((data: string | WorkerMessageData) => {
      connector.onMessage(data);
    });

    port.onDisconnect.addListener(() => {
      connector.target = nullWorker;
    });
  });

  return connector;
}

export type Connector<T extends InputRequestTypes = InputRequestTypes> = ReturnType<typeof createConnector<T>>;
