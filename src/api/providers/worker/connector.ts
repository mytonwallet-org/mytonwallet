import type { Connector } from '../../../util/PostMessageConnector';
import type { ApiAccountInitialization, ApiInitArgs, OnApiUpdate } from '../../types';
import type {
  AllMethods,
  MethodArgsWithMaybePrefix,
  MethodResponseWithMaybePrefix,
} from '../../types/methods';

import { IS_GRAM_WALLET } from '../../../config';
import { reportApiChunkLoadError } from '../../../util/chunkLoading';
import { logDebugApi, logDebugError } from '../../../util/logs';
import { createConnector, createExtensionConnector } from '../../../util/PostMessageConnector';
import { pause } from '../../../util/schedulers';
import { IS_IOS } from '../../../util/windowEnvironment';
import { createWindowProvider, createWindowProviderForExtension } from '../../../util/windowProvider';
import { POPUP_PORT } from '../extension/config';
import ApiWorker from './provider?worker';

const HEALTH_CHECK_TIMEOUT = 150;
// How long a worker is allowed to spend booting before silence counts as death rather than
// as a slow start. Measured from the moment THIS worker was created.
const WORKER_BOOT_BUDGET = 5000; // 5 sec

let updateCallback: OnApiUpdate;
let worker: Worker | undefined;
let connector: Connector | undefined;
let isInitialized = false;
let initPromise: Promise<void> | undefined;
let isHealthCheckRunning = false;
let hasCompletedRestore = false;
let readUiRestoreState: (() => UiRestoreState) | undefined;
let initialization: { hasMigrationUpdate: boolean } | undefined;

type UiRestoreState = {
  current?: ApiAccountInitialization;
  isLegacyCoreMigrationCompleted?: boolean;
};

/**
 * What the health check knows about the worker currently in place. Readiness lives HERE rather
 * than in a module flag so it cannot outlive the worker it describes: a retired worker's `init`
 * settling late mutates the record nobody reads any more, instead of vouching for its successor.
 */
type WorkerState = { createdAt: number; isReady: boolean };

let workerState: WorkerState = { createdAt: 0, isReady: false };

export function initApi(
  onUpdate: OnApiUpdate,
  initArgs: ApiInitArgs,
  getUiRestoreState?: () => UiRestoreState,
) {
  updateCallback = onUpdate;
  readUiRestoreState = getUiRestoreState;

  if (!connector) {
    // We use process.env.IS_EXTENSION instead of IS_EXTENSION in order to remove the irrelevant code during bundling
    if (process.env.IS_EXTENSION) {
      const onReconnect = () => {
        initialize(initArgs);
      };

      const extensionUpdate: OnApiUpdate = IS_GRAM_WALLET ? (update) => {
        if (initialization && update.type === 'migrateLegacyCoreApplication') {
          initialization.hasMigrationUpdate = true;
        }
        updateCallback(update);
      } : onUpdate;
      connector = createExtensionConnector(POPUP_PORT, extensionUpdate, undefined, onReconnect);

      createWindowProviderForExtension();
    } else {
      worker = new ApiWorker();
      workerState = { createdAt: Date.now(), isReady: false };
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

  initialize(initArgs);
}

function initialize(initArgs: ApiInitArgs) {
  const attempt = { hasMigrationUpdate: !hasCompletedRestore && Boolean(initialization?.hasMigrationUpdate) };
  initialization = attempt;
  const sdkInit = connector!.init(initArgs);
  if (!process.env.IS_EXTENSION || !IS_GRAM_WALLET) {
    initPromise = trackReadiness(sdkInit);
    return;
  }

  if (hasCompletedRestore) {
    const reconnect = (async () => {
      await sdkInit;
      if (initialization !== attempt) throw new Error('API initialization was replaced');
      await connector!.request({ name: 'resumeCurrentAccountAfterWorkerStart', args: [] });
      if (initialization !== attempt) throw new Error('API initialization was replaced');
    })();
    initPromise = trackReadiness(reconnect);
    return;
  }

  const restore = (async () => {
    await sdkInit;
    if (initialization !== attempt) throw new Error('API initialization was replaced');
    const state = readUiRestoreState?.();
    if (!state) throw new Error('Missing account initialization state');
    if (attempt.hasMigrationUpdate && !state.isLegacyCoreMigrationCompleted) {
      throw new Error('Legacy wallet migration has not completed');
    }
    await connector!.request({
      name: 'restoreAccountAfterInitialization',
      args: [state.current, attempt.hasMigrationUpdate],
    });
    if (initialization !== attempt) throw new Error('API initialization was replaced');
    if (attempt.hasMigrationUpdate) {
      await connector!.request({ name: 'confirmLegacyCoreMigration', args: [] });
      if (initialization !== attempt) throw new Error('API initialization was replaced');
    }
    if (attempt.hasMigrationUpdate && state.current) {
      updateCallback({ type: 'legacyCoreMigrationReady', accountId: state.current.accountId });
    }
    hasCompletedRestore = true;
  })();
  initPromise = trackReadiness(restore);
}

/**
 * A worker counts as ready once its `init` has settled. Until then it cannot answer a ping,
 * and the health check must not read that silence as death.
 */
function trackReadiness(promise: Promise<void>) {
  const state = workerState;

  void promise.then(
    () => { state.isReady = true; },
    () => undefined,
  );

  return promise;
}

export async function callApi<T extends keyof AllMethods>(
  fnName: T,
  ...args: MethodArgsWithMaybePrefix<T>
) {
  if (!connector) {
    logDebugError('API is not initialized when calling', fnName);
    return undefined;
  }

  try {
    await initPromise!;
    const result = await (connector.request({
      name: fnName,
      args,
    }) as Promise<MethodResponseWithMaybePrefix<T>>);

    if (isAgentV2Method(fnName)) {
      logDebugApi(`callApi: ${fnName}`, { status: 'completed' });
    } else {
      logDebugApi(`callApi: ${fnName}`, args, result);
    }

    return result;
  } catch (err) {
    // Callers treat `undefined` as a transport failure, so record the swallowed cause for support logs.
    // Args are deliberately not logged: they may carry sensitive payloads.
    logDebugError(`callApi: ${fnName}`, err);
    reportApiChunkLoadError(err);
    return undefined;
  }
}

export function isAgentV2Method(fnName: PropertyKey): boolean {
  return typeof fnName === 'string' && fnName.includes('AgentV2');
}

export async function callApiWithThrow<T extends keyof AllMethods>(
  fnName: T,
  ...args: MethodArgsWithMaybePrefix<T>
) {
  await initPromise!;

  const response = connector!.request({
    name: fnName,
    args,
  });
  void response.catch(reportApiChunkLoadError);

  return response as MethodResponseWithMaybePrefix<T>;
}

/**
 * Whether an unanswered ping is evidence that the worker is gone. A worker that has not
 * finished initialising is silent for a mundane reason, so silence only proves death once the
 * worker has had its whole boot budget. Exported for the test that pins this distinction.
 */
export function isSilenceConclusive(isReady: boolean, workerAgeMs: number) {
  return isReady || workerAgeMs >= WORKER_BOOT_BUDGET;
}

// Workaround for iOS sometimes stops interacting with worker
function setupIosHealthCheck() {
  window.addEventListener('focus', () => {
    void ensureWorkerPing();
    // Sometimes a single check is not enough
    setTimeout(() => ensureWorkerPing(), 1000);
  });
}

async function ensureWorkerPing() {
  // Each focus fires two checks, and a focus can arrive while an earlier one is still racing.
  // Without this, concurrent checks each terminate in turn, so one gesture destroys a chain of
  // workers instead of one.
  if (isHealthCheckRunning) {
    return;
  }

  if (!isSilenceConclusive(workerState.isReady, Date.now() - workerState.createdAt)) {
    return;
  }

  isHealthCheckRunning = true;
  let isResolved = false;

  try {
    await Promise.race([
      callApiWithThrow('ping'),
      pause(HEALTH_CHECK_TIMEOUT)
        .then(() => (isResolved ? undefined : Promise.reject(new Error('HEALTH_CHECK_TIMEOUT')))),
    ]);
  } catch (err) {
    logDebugError('ensureWorkerPing', err);

    worker?.terminate();
    worker = undefined;
    connector = undefined;
    initPromise = undefined;
    workerState = { createdAt: Date.now(), isReady: false };
    updateCallback({ type: 'requestReconnectApi' });
  } finally {
    isResolved = true;
    isHealthCheckRunning = false;
  }
}
