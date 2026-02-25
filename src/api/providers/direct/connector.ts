import type { ApiInitArgs, OnApiUpdate } from '../../types';
import type { MethodArgsWithMaybePrefix, MethodResponseWithMaybePrefix } from '../../types/methods';
import { type AllMethods, recognizeDappMethod } from '../../types/methods';

import { getProtocolManager } from '../../dappProtocols';
import * as methods from '../../methods';
import init from '../../methods/init';

let initPromise: Promise<void> | undefined;

export function initApi(onUpdate: OnApiUpdate, initArgs: ApiInitArgs | (() => ApiInitArgs)) {
  const args = typeof initArgs === 'function' ? initArgs() : initArgs;
  initPromise = init(onUpdate, args);
}

export async function callApi<T extends keyof AllMethods>(
  fnName: T,
  ...args: MethodArgsWithMaybePrefix<T>
): Promise<MethodResponseWithMaybePrefix<T>> {
  await initPromise!;

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
}
