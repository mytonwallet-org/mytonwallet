import type {
  ApiEmulationResult,
  ApiInitArgs,
  ApiNetwork,
  OnApiUpdate,
} from '../../api/types';
import type { Connector } from '../../util/PostMessageConnector';

import { logDebugApi, logDebugError } from '../../util/logs';
import { createConnector } from '../../util/PostMessageConnector';

type MfaApiMethods = {
  ping: () => boolean;
  emulateMfaMessage: (
    network: ApiNetwork,
    walletAddress: string,
    boc: string,
  ) => Promise<Pick<ApiEmulationResult, 'activities' | 'realFee'>>;
};

let worker: Worker | undefined;
let connector: Connector<MfaApiMethods> | undefined;
let initPromise: Promise<void> | undefined;

export function initMfaApi(onUpdate: OnApiUpdate, initArgs: ApiInitArgs) {
  if (!connector) {
    worker = new Worker(
      /* webpackChunkName: "mfa-api-worker" */ new URL('./provider.ts', import.meta.url),
    );
    connector = createConnector<MfaApiMethods>(worker, onUpdate);
  }

  const currentConnector = connector;
  initPromise = currentConnector.init(initArgs);

  return initPromise;
}

export async function callMfaApi<T extends keyof MfaApiMethods>(
  fnName: T,
  ...args: Parameters<MfaApiMethods[T]>
): Promise<Awaited<ReturnType<MfaApiMethods[T]>> | undefined> {
  if (!connector) {
    logDebugError('MFA API is not initialized when calling', fnName);
    return undefined;
  }

  await initPromise;

  try {
    const result = await connector.request({
      name: fnName,
      args,
    } as never) as Awaited<ReturnType<MfaApiMethods[T]>>;

    logDebugApi(`callMfaApi: ${fnName}`, args, result);

    return result;
  } catch (err) {
    logDebugError(`callMfaApi: ${fnName}`, err);
    return undefined;
  }
}

export async function callMfaApiWithThrow<T extends keyof MfaApiMethods>(
  fnName: T,
  ...args: Parameters<MfaApiMethods[T]>
): Promise<Awaited<ReturnType<MfaApiMethods[T]>>> {
  if (!connector) {
    throw new Error(`MFA API is not initialized when calling ${fnName}`);
  }

  await initPromise;

  const result = await connector.request({
    name: fnName,
    args,
  } as never) as Awaited<ReturnType<MfaApiMethods[T]>>;

  logDebugApi(`callMfaApi: ${fnName}`, args, result);

  return result;
}
