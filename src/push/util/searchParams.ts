export function getSearchParameter(key: string) {
  if (typeof window === 'undefined') return;
  const params = new URLSearchParams(window.location.search);
  return params.get(key);
}

export function extractAndPurgeToken(param = 'token') {
  if (typeof window === 'undefined') return undefined;
  const url = new URL(window.location.href);
  const value = url.searchParams.get(param);
  if (value) {
    url.searchParams.delete(param);
    window.history.replaceState(undefined, '', url.toString());
  }
  return value;
}
