import { boundedRead, jsonResponseSizeAllowed, readBoundedUtf8 } from './bounded.js';
import type { ReadTransport } from './getgems.js';
import { boundedJson } from './privacy.js';

export class ProviderReadError extends Error {
  constructor(readonly status: number, readonly retryAfterSeconds: number | null) {
    super(status === 401 ? 'Provider authorization required' : status === 402 ? 'Provider subscription required'
      : status === 429 ? 'Provider rate limited' : 'Provider unavailable');
    this.name = 'ProviderReadError';
  }
}
export function retryAfter(value: string | null, now = Date.now()): number | null {
  if (value === null || value.length > 100 || !Number.isFinite(now)) return null;
  if (/^\d{1,6}$/.test(value)) return Math.min(86400, Number(value));
  if (!/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$/.test(value)) return null;
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.min(86400,Math.max(0,Math.ceil((date-now)/1000))) : null;
}

/** Read-only transport for an explicitly configured wallet backend. No marketplace API secret,
 * browser credentials, redirect or arbitrary provider-supplied URL is accepted.
 * Configuration must come from the wallet, never an NFT, deep link or marketplace response.
 */
export function createOfferReadTransport(origin: string, approvedOrigins: readonly string[], fetcher: typeof fetch = globalThis.fetch): ReadTransport {
  const base = new URL(origin);
  if (!Array.isArray(approvedOrigins) || approvedOrigins.length < 1 || approvedOrigins.length > 16
    || !approvedOrigins.includes(origin) || base.protocol !== 'https:' || base.origin !== origin
    || base.username || base.password || base.port) throw Error('Unapproved provider origin');
  const request = fetcher;
  return (path, signal) => boundedRead(signal, async scoped => {
    if (typeof path !== 'string' || path.length > 6500
      || !/^\/v1\/offers\/(nft|collection)\/0%3A[0-9a-f]{64}\?limit=100(?:&after=(?:[A-Za-z0-9_.!~*'()-]|%[0-9A-F]{2})+)?$/.test(path)) throw Error('Unapproved read endpoint');
    const url = new URL(path, base);
    if (url.origin !== base.origin) throw Error('Provider origin changed');
    const response = await request(url.href, {
      method: 'GET', credentials: 'omit', redirect: 'error', cache: 'no-store', referrerPolicy: 'no-referrer',
      headers: { Accept: 'application/json' }, signal: scoped,
    });
    const body = response.body;
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      scoped.throwIfAborted();
      if (response.redirected || (response.url && new URL(response.url).origin !== base.origin)) throw Error('Provider read failed');
      if (!response.ok) throw new ProviderReadError(response.status, retryAfter(response.headers.get('retry-after')));
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '')) throw Error('Expected provider JSON');
      if (!jsonResponseSizeAllowed(response.headers.get('content-length'))) throw Error('Provider response too large');
      if (!body) throw Error('Missing provider response');
      reader = body.getReader();
      const text = await readBoundedUtf8(reader, scoped, 'Provider');
      scoped.throwIfAborted();
      // Response bodies and addresses are intentionally not logged or sent to analytics here.
      return boundedJson(text);
    } finally {
      if (reader) {
        void reader.cancel().catch(() => {});
        reader.releaseLock();
      } else {
        void body?.cancel().catch(() => {});
      }
    }
  }, 10000);
}
