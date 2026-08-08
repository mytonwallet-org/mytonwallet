import './provider';

import type { Connector } from '../../../util/PostMessageConnector';
import type * as EnclaveApi from '../../enclave';

import { CHANNEL_NAME } from '../../config';
import { createConnector } from '../../../util/PostMessageConnector';

let connector: Connector;

initConnector();

export function initConnector() {
  connector = createConnector(self, undefined, CHANNEL_NAME, location.href);
}

export default new Proxy({}, {
  get(_target, prop) {
    if (typeof prop !== 'string') return undefined;

    return (...args: any) => {
      // TODO Replace with real direct EnclaveApi calls
      return connector.request({ name: prop, args });
    };
  },
}) as typeof EnclaveApi;
