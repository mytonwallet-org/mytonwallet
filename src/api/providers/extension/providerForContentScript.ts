import type {
  SiteMethodArgs,
  SiteMethods,
} from '../../extensionMethods/types';
import type { ApiDappRequest } from '../../types';
import type { OnApiSiteUpdate } from '../../types/dappUpdates';
import { recognizeDappMethod } from '../../types/methods';

import { CONTENT_SCRIPT_PORT, PAGE_CONNECTOR_CHANNEL } from './config';
import { createExtensionInterface } from '../../../util/createPostMessageInterface';
import { getProtocolManager } from '../../dappProtocols';
import * as siteApi from '../../extensionMethods/sites';

const ALLOWED_METHODS = new Set([
  'flushMemoryCache',
  'prepareTransaction',
  'processDeeplink',
  'tonConnect_connect',
  'tonConnect_reconnect',
  'tonConnect_disconnect',
  'tonConnect_sendTransaction',
  'tonConnect_deactivate',
  'tonConnect_signData',
  'walletConnect_connect',
  'walletConnect_reconnect',
  'walletConnect_disconnect',
  'walletConnect_sendTransaction',
  'walletConnect_deactivate',
  'walletConnect_signData',
]);

createExtensionInterface(CONTENT_SCRIPT_PORT, (
  name: string, origin?: string, ...args: any[]
) => {
  if (name === 'init') {
    return siteApi.connectSite(args[0] as OnApiSiteUpdate);
  }

  if (!ALLOWED_METHODS.has(name)) {
    throw new Error('Method not allowed');
  }

  const parsedRequest = recognizeDappMethod(name);

  if (parsedRequest.isDapp) {
    const adapter = getProtocolManager().getAdapter(parsedRequest.protocolType);
    if (!adapter) {
      throw new Error('No dApp adapter found for request');
    }

    const method = adapter[parsedRequest.fnName].bind(adapter);

    const request: ApiDappRequest = { url: origin, isUrlEnsured: true };

    // @ts-ignore
    return method(...[request].concat(args));
  }

  const method = siteApi[name as keyof SiteMethods];
  // @ts-ignore
  return method(...args as SiteMethodArgs<keyof SiteMethods>);
}, PAGE_CONNECTOR_CHANNEL, (onUpdate: OnApiSiteUpdate) => {
  siteApi.deactivateSite(onUpdate);
}, true);
