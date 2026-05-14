import type { ApiInitArgs, OnApiUpdate } from '../../types';
import type { MethodArgsWithMaybePrefix, MethodResponseWithMaybePrefix } from '../../types/methods';
import { type AllMethods, recognizeDappMethod } from '../../types/methods';

import { getProtocolManager } from '../../dappProtocols';
import * as methods from '../../methods';
import init from '../../methods/init';
import { createStorage, withStorage } from '../../storages';

export function createDirectApiConnector() {
  let initPromise: Promise<void> | undefined;
  let runtimeStorage = createStorage();

  function initApi(onUpdate: OnApiUpdate, initArgs: ApiInitArgs | (() => ApiInitArgs)) {
    const args = typeof initArgs === 'function' ? initArgs() : initArgs;

    runtimeStorage = createStorage(args.storage);
    initPromise = withStorage(runtimeStorage, () => init(onUpdate, args));
  }

  async function callApi<T extends keyof AllMethods>(
    fnName: T,
    ...args: MethodArgsWithMaybePrefix<T>
  ): Promise<MethodResponseWithMaybePrefix<T>> {
    await initPromise!;

    return withStorage(runtimeStorage, () => {
      const parsedRequest = recognizeDappMethod(fnName);

      if (parsedRequest.isDapp) {
        const adapter = getProtocolManager().getAdapter(parsedRequest.protocolType);
        if (!adapter) {
          throw new Error('No dApp adapter found for request');
        }
        const method = adapter[parsedRequest.fnName].bind(adapter);

        // @ts-ignore
        return method(...args);
      }
      // @ts-ignore
      return methods[fnName](...args) as MethodResponseWithMaybePrefix<T>;
    });
  }

  return {
    initApi,
    callApi,
  };
}

const defaultConnector = createDirectApiConnector();

export const { initApi, callApi } = defaultConnector;
