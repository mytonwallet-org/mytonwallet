import type { DappTransportType } from '../../types';

export function resolveWalletConnectDappUrl(params: {
  requestUrl?: string;
  metadataUrl: string;
  transport: DappTransportType;
}): string {
  if (params.transport === 'relay') {
    return params.metadataUrl;
  }

  if (!params.requestUrl) {
    throw new Error('Missing authenticated dApp URL');
  }

  return resolveAuthenticatedDappOrigin(params.requestUrl);
}

export function resolveWalletConnectMethodDappUrl(requestUrl?: string): string {
  if (!requestUrl) {
    throw new Error('Missing authenticated dApp URL');
  }

  return resolveAuthenticatedDappOrigin(requestUrl);
}

function resolveAuthenticatedDappOrigin(url: string): string {
  const parsedUrl = new URL(url);
  if (parsedUrl.protocol !== 'http:' && parsedUrl.protocol !== 'https:') {
    throw new Error('Invalid authenticated dApp URL');
  }

  return parsedUrl.origin;
}
