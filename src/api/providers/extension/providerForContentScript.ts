import type {
  SiteMethodArgs,
  SiteMethods,
} from '../../extensionMethods/types';
import type { TonConnectMethodArgs, TonConnectMethods } from '../../tonConnect/types/misc';
import type { ApiDappRequest } from '../../types';
import type { OnApiSiteUpdate } from '../../types/dappUpdates';

import { CONTENT_SCRIPT_PORT, PAGE_CONNECTOR_CHANNEL } from './config';
import { createExtensionInterface } from '../../../util/createPostMessageInterface';
import * as siteApi from '../../extensionMethods/sites';
import * as tonConnectApi from '../../tonConnect';

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

  if (name.startsWith('tonConnect_')) {
    name = name.replace('tonConnect_', '');

    const method = tonConnectApi[name as keyof TonConnectMethods];
    const request: ApiDappRequest = { url: origin, isUrlEnsured: true };

    // @ts-ignore
    return method(...[request].concat(args) as TonConnectMethodArgs<keyof TonConnectMethods>);
  }

  const method = siteApi[name as keyof SiteMethods];
  // @ts-ignore
  return method(...args as SiteMethodArgs<keyof SiteMethods>);
}, PAGE_CONNECTOR_CHANNEL, (onUpdate: OnApiSiteUpdate) => {
  siteApi.deactivateSite(onUpdate);
}, true);
