export function resolveTonConnectDappUrl(params: {
  requestUrl?: string;
  manifestUrl: string;
  declaredUrl: string;
}): string {
  if (params.requestUrl) {
    return new URL(params.requestUrl).origin;
  }

  const manifestOrigin = new URL(params.manifestUrl).origin;
  const declaredOrigin = new URL(params.declaredUrl).origin;

  return declaredOrigin === manifestOrigin ? declaredOrigin : manifestOrigin;
}
