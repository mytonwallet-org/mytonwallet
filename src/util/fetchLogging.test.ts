import { describeRequest, describeTarget, installFetchLogging, redactPath } from './fetchLogging';

// A real path from the SDK's own staking calls, which is what makes the redaction load-bearing:
// the address is a path segment, so dropping the query string alone would not have removed it.
const WALLET_ADDRESS = 'UQDblBmVhYA7El2pBcViUpRJvbtf4IoygDdSIMFrvQPoHlwo';

// JSDOM ships no fetch, so neither type exists here. The logger reads a url, a method and a status
// and nothing else, so standing in for exactly those three also states what it is allowed to touch.
const originalRequest = globalThis.Request;
const originalResponse = globalThis.Response;

beforeEach(() => {
  globalThis.Request = class {
    readonly url: string;
    readonly method: string;
    constructor(url: string, init?: RequestInit) {
      this.url = url;
      this.method = init?.method ?? 'GET';
    }
  } as typeof Request;

  globalThis.Response = class {
    readonly status: number;
    constructor(_body: unknown, init: ResponseInit) {
      this.status = init.status ?? 200;
    }
  } as typeof Response;
});

afterEach(() => {
  globalThis.Request = originalRequest;
  globalThis.Response = originalResponse;
});

describe('redactPath', () => {
  it('keeps route segments and replaces anything address-shaped', () => {
    expect(redactPath('/api/v2/device-token')).toBe('/api/v2/device-token');
    expect(redactPath(`/staking/state/${WALLET_ADDRESS}`)).toBe('/staking/state/<redacted>');
  });

  it('replaces every long segment, not only the last', () => {
    expect(redactPath(`/${WALLET_ADDRESS}/nfts/${WALLET_ADDRESS}`)).toBe('/<redacted>/nfts/<redacted>');
  });

  // A backend id is short and innocuous-looking, and names one user's swap just as the address
  // beside it does, so route words are recognised by shape rather than measured for length.
  it('replaces a short identifier as readily as an address', () => {
    expect(redactPath(`/swap/history/${WALLET_ADDRESS}/2545651`)).toBe('/swap/history/<redacted>/<redacted>');
    expect(redactPath('/dns/getDomains')).toBe('/dns/getDomains');
  });
});

describe('describeTarget', () => {
  it('drops the query string, which is the other place an address travels', () => {
    expect(describeTarget(`https://api.mywallet.io/dns/getDomains?address=${WALLET_ADDRESS}`))
      .toBe('https://api.mywallet.io/dns/getDomains');
  });

  it('reports a target it cannot parse instead of printing it raw', () => {
    expect(describeTarget(`not a url ${WALLET_ADDRESS}`)).toBe('<unparsed>');
  });

  it('resolves a relative target against the document it was issued from', () => {
    expect(describeTarget('/api/v2/hints', 'https://agent-beta.mytonwallet.org/'))
      .toBe('https://agent-beta.mytonwallet.org/api/v2/hints');
  });
});

describe('describeRequest', () => {
  it('reports the method fetch will send when init overrides the request', () => {
    const request = new Request('https://agent.mywallet.io/api/v2/hints', { method: 'GET' });

    expect(describeRequest(request, { method: 'POST' }))
      .toBe('POST https://agent.mywallet.io/api/v2/hints');
  });

  it('falls back to the request method, then to GET', () => {
    const request = new Request('https://agent.mywallet.io/api/v2/runs', { method: 'POST' });

    expect(describeRequest(request, undefined)).toBe('POST https://agent.mywallet.io/api/v2/runs');
    expect(describeRequest('https://agent.mywallet.io/api/v2/hints', undefined))
      .toBe('GET https://agent.mywallet.io/api/v2/hints');
  });
});

describe('installFetchLogging', () => {
  function hostWith(fetchImpl: typeof fetch) {
    const lines: string[] = [];
    const host = { fetch: fetchImpl, location: { href: 'https://agent-beta.mytonwallet.org/' } };
    let clock = 0;
    installFetchLogging(host, (line) => lines.push(line), () => (clock += 250));
    return { host, lines };
  }

  it('logs the status of a request that completes', async () => {
    const { host, lines } = hostWith(() => Promise.resolve(new Response('', { status: 426 })));

    await host.fetch('/api/v2/device-token', { method: 'POST' });

    expect(lines).toEqual([
      'net status=426 time=0.250 @ POST https://agent-beta.mytonwallet.org/api/v2/device-token',
    ]);
  });

  it('logs a request that never reached a status, and rethrows it', async () => {
    const { host, lines } = hostWith(() => Promise.reject(new TypeError('Load failed')));

    await expect(host.fetch(`/staking/state/${WALLET_ADDRESS}`)).rejects.toThrow('Load failed');
    expect(lines).toEqual([
      'net failed=TypeError time=0.250 @ GET https://agent-beta.mytonwallet.org/staking/state/<redacted>',
    ]);
  });
});
