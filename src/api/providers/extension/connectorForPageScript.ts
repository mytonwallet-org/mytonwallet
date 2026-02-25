import type { Connector } from '../../../util/PostMessageConnector';
import type { SiteMethodResponse, SiteMethods } from '../../extensionMethods/types';
import type { OnApiSiteUpdate } from '../../types/dappUpdates';

import { PAGE_CONNECTOR_CHANNEL } from './config';
import { logDebugError } from '../../../util/logs';
import { createConnector } from '../../../util/PostMessageConnector';

let connector: Connector;
export function initApi(onUpdate: OnApiSiteUpdate) {
  // The connection is established with `window` instead of the Chrome port, because `chrome.runtime` is unavailable in
  // scripts injected using a <script> tag (the page script is of that kind). The `pageContentProxy.ts` file listens to
  // the `window` messages and proxies them to the Chrome port.
  connector = createConnector(window, onUpdate, PAGE_CONNECTOR_CHANNEL, window.location.href);
  return connector;
}

export function callApi<T extends keyof SiteMethods>(methodName: T, ...args: any[]) {
  if (!connector) {
    logDebugError('API is not initialized when calling', methodName);
    return undefined;
  }

  const promise = connector.request({
    name: methodName,
    args,
  });

  return promise as SiteMethodResponse<T>;
}
