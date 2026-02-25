export function parseHashParams(): { theme?: string; addresses?: string; baseCurrency?: string } {
  const hash = window.location.hash.slice(1);
  const params = new URLSearchParams(hash);

  return {
    theme: params.get('theme') || undefined,
    addresses: params.get('addresses') || undefined,
    baseCurrency: params.get('baseCurrency') || undefined,
  };
}
