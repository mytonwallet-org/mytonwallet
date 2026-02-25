import type { Connector } from '../PostMessageConnector';
import type { WindowMethodArgs, WindowMethodResponse, WindowMethods } from './types';

import { IS_AIR_APP, WINDOW_PROVIDER_CHANNEL, WINDOW_PROVIDER_PORT } from '../../config';
import { airAppCallWindow } from '../../api/air/airAppCallWindow';

import { createReverseExtensionConnector } from '../PostMessageConnector';
import { createConnector } from '../PostMessageConnector';

let connector: Connector;

export function initWindowConnector() {
  if (!connector) {
    // We use process.env.IS_EXTENSION instead of IS_EXTENSION in order to remove the irrelevant code during bundling
    if (process.env.IS_EXTENSION) {
      connector = createReverseExtensionConnector(WINDOW_PROVIDER_PORT);
      // connector.init() is not called here because the extension connector is available only when the popup is open
    } else {
      connector = createConnector(self as DedicatedWorkerGlobalScope, undefined, WINDOW_PROVIDER_CHANNEL);
      void connector.init();
    }
  }
}

export function callWindow<T extends keyof WindowMethods>(methodName: T, ...args: WindowMethodArgs<T>) {
  if (IS_AIR_APP) return airAppCallWindow(methodName, ...args) as EnsurePromise<WindowMethodResponse<T>>;

  if (!connector) {
    throw new Error(`API is not initialized when calling ${methodName}`);
  }

  return connector.request({ name: methodName, args }) as EnsurePromise<WindowMethodResponse<T>>;
}
