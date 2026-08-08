import type { Connector } from '../PostMessageConnector';
import type { WindowMethodArgs, WindowMethodResponse, WindowMethods } from './types';

import { IS_AIR_APP, IS_HEADLESS, WINDOW_PROVIDER_CHANNEL, WINDOW_PROVIDER_PORT } from '../../config';
import { airAppCallWindow } from '../../api/air/airAppCallWindow';

import { createReverseExtensionConnector } from '../PostMessageConnector';
import { createConnector } from '../PostMessageConnector';

let connector: Connector;

/**
 * Handlers served in-process instead of over a message channel. Headless runs the API and the
 * window side in one Node process, so there is no second thread to post to; whoever owns that
 * process registers what it can answer. An unregistered method still fails loudly below rather
 * than silently resolving, so a host that forgets one cannot ship a half-wired enclave.
 */
let directMethods: Partial<WindowMethods> | undefined;

export function setDirectWindowMethods(methods: Partial<WindowMethods>) {
  // The registry answers for secrets, so it must never become reachable where a real window thread
  // already serves them. Every app build folds `IS_HEADLESS` to `false`, which makes a stray call
  // from app code crash on the first run instead of quietly rerouting `exportSecret`.
  if (!IS_HEADLESS) {
    throw new Error('Direct window methods are available only in the headless runtime');
  }

  directMethods = methods;
}

export function initWindowConnector() {
  if (connector) {
    return;
  }

  // We use process.env.IS_EXTENSION instead of IS_EXTENSION in order to remove the irrelevant code during bundling
  if (process.env.IS_EXTENSION) {
    connector = createReverseExtensionConnector(WINDOW_PROVIDER_PORT);
    // connector.init() is not called here because the extension connector is available only when the popup is open
    return;
  }

  if (typeof self === 'undefined' || typeof self.addEventListener !== 'function') {
    return;
  }

  connector = createConnector(self as DedicatedWorkerGlobalScope, undefined, WINDOW_PROVIDER_CHANNEL);
  void connector.init();
}

export function callWindow<T extends keyof WindowMethods>(methodName: T, ...args: WindowMethodArgs<T>) {
  if (IS_AIR_APP) return airAppCallWindow(methodName, ...args) as EnsurePromise<WindowMethodResponse<T>>;

  // Read through `process.env` rather than the constant so bundling drops the branch outright, and
  // spell out the same comparison `IS_HEADLESS` makes: a truthiness test would keep the in-process
  // dispatch alive in a build whose flag is set to something falsey-looking but non-empty.
  if (process.env.IS_HEADLESS === '1') {
    const directMethod = directMethods?.[methodName];
    if (directMethod) {
      // The connector path reports a failure by rejecting; a handler that throws synchronously
      // would otherwise escape past the caller's `.catch` and surface somewhere else entirely.
      try {
        return Promise.resolve(
          (directMethod as (...methodArgs: WindowMethodArgs<T>) => WindowMethodResponse<T>)(...args),
        ) as EnsurePromise<WindowMethodResponse<T>>;
      } catch (err) {
        return Promise.reject(err) as EnsurePromise<WindowMethodResponse<T>>;
      }
    }
  }

  if (!connector) {
    throw new Error(`API is not initialized when calling ${methodName}`);
  }

  return connector.request({ name: methodName, args }) as EnsurePromise<WindowMethodResponse<T>>;
}
