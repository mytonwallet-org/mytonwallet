import type { StoredDappConnection } from './dappProtocols/storage';

import { logDebugError } from '../util/logs';

interface Hooks {
  onFirstLogin: AnyFunction;
  onFullLogout: AnyFunction;
  onWindowNeeded: AnyFunction;
  onDappDisconnected: (accountId: string, dapp: StoredDappConnection) => any;
  onDappsChanged: AnyFunction;
  onSwapCreated: (accountId: string, fromTimestamp: number) => any;
}

const hooks: Partial<{
  [K in keyof Hooks]: Hooks[K][];
}> = {};

export function addHooks(partial: Partial<Hooks>) {
  for (const [name, hook] of Object.entries(partial) as Entries<Hooks>) {
    hooks[name] = (hooks[name] ?? []).concat([hook]);
  }
}

export async function callHook<T extends keyof Hooks>(name: T, ...args: Parameters<Hooks[T]>) {
  for (const hook of hooks[name] ?? []) {
    try {
      // @ts-ignore
      await hook(...args);
    } catch (err) {
      logDebugError(`callHooks:${name}`, err);
    }
  }
}
