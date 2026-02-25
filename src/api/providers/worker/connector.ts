import type { Connector } from '../../../util/PostMessageConnector';
import type { ApiInitArgs, OnApiUpdate } from '../../types';
import type {
  AllMethods,
  MethodArgsWithMaybePrefix,
  MethodResponseWithMaybePrefix,
} from '../../types/methods';

import { logDebugApi, logDebugError } from '../../../util/logs';
import { createConnector, createExtensionConnector } from '../../../util/PostMessageConnector';
import { pause } from '../../../util/schedulers';
import { IS_IOS } from '../../../util/windowEnvironment';
import { createWindowProvider, createWindowProviderForExtension } from '../../../util/windowProvider';
import { POPUP_PORT } from '../extension/config';

const HEALTH_CHECK_TIMEOUT = 150;
const HEALTH_CHECK_MIN_DELAY = 5000; // 5 sec

let updateCallback: OnApiUpdate;
let worker: Worker | undefined;
let connector: Connector | undefined;
let isInitialized = false;
let initPromise: Promise<void> | undefined;

export function initApi(onUpdate: OnApiUpdate, initArgs: ApiInitArgs) {
  updateCallback = onUpdate;

  if (!connector) {
    // We use process.env.IS_EXTENSION instead of IS_EXTENSION in order to remove the irrelevant code during bundling
    if (process.env.IS_EXTENSION) {
      const onReconnect = () => {
        initPromise = connector!.init(initArgs);
      };

      connector = createExtensionConnector(POPUP_PORT, onUpdate, undefined, onReconnect);

      createWindowProviderForExtension();
    } else {
      worker = new Worker(
        /* webpackChunkName: "worker" */ new URL('./provider.ts', import.meta.url),
      );
      connector = createConnector(worker, onUpdate);

      createWindowProvider(worker);
    }
  }

  if (!isInitialized) {
    if (IS_IOS) {
      setupIosHealthCheck();
    }
    isInitialized = true;
  }

  initPromise = connector.init(initArgs);
}

export async function callApi<T extends keyof AllMethods>(
  fnName: T,
  ...args: MethodArgsWithMaybePrefix<T>
) {
  if (!connector) {
    logDebugError('API is not initialized when calling', fnName);
    return undefined;
  }

  await initPromise!;

  try {
    const result = await (connector.request({
      name: fnName,
      args,
    }) as Promise<MethodResponseWithMaybePrefix<T>>);

    logDebugApi(`callApi: ${fnName}`, args, result);

    return result;
  } catch (err) {
    return undefined;
  }
}

export async function callApiWithThrow<T extends keyof AllMethods>(
  fnName: T,
  ...args: MethodArgsWithMaybePrefix<T>
) {
  await initPromise!;

  return (connector!.request({
    name: fnName,
    args,
  }) as MethodResponseWithMaybePrefix<T>);
}

const startedAt = Date.now();

// Workaround for iOS sometimes stops interacting with worker
function setupIosHealthCheck() {
  window.addEventListener('focus', () => {
    void ensureWorkerPing();
    // Sometimes a single check is not enough
    setTimeout(() => ensureWorkerPing(), 1000);
  });
}

async function ensureWorkerPing() {
  let isResolved = false;

  try {
    await Promise.race([
      callApiWithThrow('ping'),
      pause(HEALTH_CHECK_TIMEOUT)
        .then(() => (isResolved ? undefined : Promise.reject(new Error('HEALTH_CHECK_TIMEOUT')))),
    ]);
  } catch (err) {
    logDebugError('ensureWorkerPing', err);

    if (Date.now() - startedAt >= HEALTH_CHECK_MIN_DELAY) {
      worker?.terminate();
      worker = undefined;
      connector = undefined;
      initPromise = undefined;
      updateCallback({ type: 'requestReconnectApi' });
    }
  } finally {
    isResolved = true;
  }
}
