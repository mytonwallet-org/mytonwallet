import type { Storage } from '../storages/types';

import { AgentV2IdentityService, decodeHttpError } from './identity';

const DEVICE_ID = '11111111-1111-4111-8111-111111111111';
const TOKEN_1 = `adt_v2.${'a'.repeat(43)}`;
const TOKEN_2 = `adt_v2.${'b'.repeat(43)}`;

describe('AgentV2IdentityService', () => {
  it('single-flights issuance, states the protocol and never exposes credentials in the request body', async () => {
    const storage = createMemoryStorage();
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const fetchMock = jest.fn((url: string | URL | Request, init?: RequestInit) => {
      const requestUrl = getRequestUrl(url);
      calls.push({ url: requestUrl, init });
      return Promise.resolve(requestUrl.endsWith('/device-token')
        ? jsonResponse(tokenResponse(TOKEN_1))
        : jsonResponse({ ok: true }));
    }) as unknown as typeof fetch;
    const identity = new AgentV2IdentityService({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      randomUuid: () => DEVICE_ID,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });

    await Promise.all([
      identity.authenticatedFetch('https://agent.test/api/v2/hints'),
      identity.authenticatedFetch('https://agent.test/api/v2/threads/default'),
    ]);

    expect(calls.filter(({ url }) => url.endsWith('/device-token'))).toHaveLength(1);
    const issuanceBody = JSON.parse(calls[0].init?.body as string);
    expect(issuanceBody).toEqual({ protocolVersion: 3, deviceId: DEVICE_ID });
    expect(JSON.stringify(issuanceBody)).not.toContain(TOKEN_1);
    expect(calls.map(({ init }) => new Headers(init?.headers).get('Accept')))
      .toEqual(Array(3).fill('application/json; agent-protocol=3'));
  });

  it('performs one shared reissue after concurrent 401 responses', async () => {
    const storage = createMemoryStorage();
    let issuanceCount = 0;
    let protectedCount = 0;
    const fetchMock = jest.fn((url: string | URL | Request) => {
      if (getRequestUrl(url).endsWith('/device-token')) {
        issuanceCount += 1;
        return Promise.resolve(jsonResponse(tokenResponse(issuanceCount === 1 ? TOKEN_1 : TOKEN_2)));
      }
      protectedCount += 1;
      return Promise.resolve(protectedCount <= 2 ? jsonResponse({}, 401) : jsonResponse({ ok: true }));
    }) as unknown as typeof fetch;
    const identity = new AgentV2IdentityService({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      randomUuid: () => DEVICE_ID,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });

    await Promise.all([
      identity.authenticatedFetch('https://agent.test/a'),
      identity.authenticatedFetch('https://agent.test/b'),
    ]);

    expect(issuanceCount).toBe(2);
    expect(await storage.getItem('agentV2DeviceIdentity')).toContain(TOKEN_2);
  });

  it('does not replay an unauthorized request when recovery is explicitly skipped', async () => {
    let issuanceCount = 0;
    let protectedCount = 0;
    const fetchMock = jest.fn((url: string | URL | Request) => {
      if (getRequestUrl(url).endsWith('/device-token')) {
        issuanceCount += 1;
        return Promise.resolve(jsonResponse(tokenResponse(TOKEN_1)));
      }
      protectedCount += 1;
      return Promise.resolve(jsonResponse({}, 401));
    }) as unknown as typeof fetch;
    const identity = new AgentV2IdentityService({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      randomUuid: () => DEVICE_ID,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });

    const response = await identity.authenticatedFetch(
      'https://agent.test/api/v2/runs/run-1/tool-results',
      {},
      { shouldSkipUnauthorizedRecovery: true },
    );

    expect(response.status).toBe(401);
    expect(issuanceCount).toBe(1);
    expect(protectedCount).toBe(1);
  });

  it('reuses the rotated token when a delayed concurrent request receives 401', async () => {
    const storage = createMemoryStorage();
    let issuanceCount = 0;
    let resolveDelayedUnauthorized!: (response: Response) => void;
    let notifyDelayedRequestStarted!: () => void;
    const delayedUnauthorized = new Promise<Response>((resolve) => {
      resolveDelayedUnauthorized = resolve;
    });
    const delayedRequestStarted = new Promise<void>((resolve) => {
      notifyDelayedRequestStarted = resolve;
    });
    const protectedCalls: Array<{ body: BodyInit | null | undefined; token: string | null; url: string }> = [];
    const fetchMock = jest.fn((url: string | URL | Request, init?: RequestInit) => {
      const requestUrl = getRequestUrl(url);
      if (requestUrl.endsWith('/device-token')) {
        issuanceCount += 1;
        return Promise.resolve(jsonResponse(tokenResponse(issuanceCount === 1 ? TOKEN_1 : TOKEN_2)));
      }

      const token = new Headers(init?.headers).get('Authorization');
      protectedCalls.push({ body: init?.body, token, url: requestUrl });
      if (requestUrl.endsWith('/warmup')) return Promise.resolve(jsonResponse({ ok: true }));
      if (requestUrl.endsWith('/delayed') && token === `Bearer ${TOKEN_1}`) {
        notifyDelayedRequestStarted();
        return delayedUnauthorized;
      }
      if (requestUrl.endsWith('/fast') && token === `Bearer ${TOKEN_1}`) {
        return Promise.resolve(jsonResponse({}, 401));
      }
      return Promise.resolve(jsonResponse({ ok: true }));
    }) as unknown as typeof fetch;
    const identity = new AgentV2IdentityService({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      randomUuid: () => DEVICE_ID,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });
    const body = JSON.stringify({
      protocolVersion: 3,
      clientOperationId: '33333333-3333-4333-8333-333333333333',
    });

    await identity.authenticatedFetch('https://agent.test/warmup');
    const delayedRequest = identity.authenticatedFetch('https://agent.test/delayed', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body,
    });
    await delayedRequestStarted;
    await identity.authenticatedFetch('https://agent.test/fast');
    resolveDelayedUnauthorized(jsonResponse({}, 401));
    await delayedRequest;

    expect(issuanceCount).toBe(2);
    expect(protectedCalls.filter(({ url }) => url.endsWith('/delayed'))).toEqual([
      { body, token: `Bearer ${TOKEN_1}`, url: 'https://agent.test/delayed' },
      { body, token: `Bearer ${TOKEN_2}`, url: 'https://agent.test/delayed' },
    ]);
    expect(await storage.getItem('agentV2DeviceIdentity')).toContain(TOKEN_2);
  });

  it('replays a mutation with a byte-identical operation body after token reissue', async () => {
    let issuanceCount = 0;
    const mutationBodies: unknown[] = [];
    const fetchMock = jest.fn((url: string | URL | Request, init?: RequestInit) => {
      if (getRequestUrl(url).endsWith('/device-token')) {
        issuanceCount += 1;
        return Promise.resolve(jsonResponse(tokenResponse(issuanceCount === 1 ? TOKEN_1 : TOKEN_2)));
      }
      mutationBodies.push(init?.body);
      return Promise.resolve(mutationBodies.length === 1 ? jsonResponse({}, 401) : jsonResponse({ ok: true }));
    }) as unknown as typeof fetch;
    const identity = new AgentV2IdentityService({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      randomUuid: () => DEVICE_ID,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });
    const body = JSON.stringify({
      protocolVersion: 3,
      clientOperationId: '22222222-2222-4222-8222-222222222222',
    });

    await identity.authenticatedFetch('https://agent.test/api/v2/threads', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    });

    expect(mutationBodies).toEqual([body, body]);
    expect(issuanceCount).toBe(2);
  });

  it('preserves an HTML ingress size rejection as a non-retryable HTTP 413', async () => {
    const response = { status: 413, json: () => Promise.reject(new SyntaxError('Unexpected HTML')) } as Response;
    await expect(decodeHttpError(response)).resolves.toMatchObject({
      status: 413, code: 'invalid_request', retryable: false,
    });
    await expect(decodeHttpError({ ...response, status: 412 } as Response)).rejects.toThrow('Unexpected HTML');
  });

  it('reads a server request to update the app as the non-retryable update code', async () => {
    await expect(decodeHttpError(jsonResponse({
      protocolVersion: 3,
      error: { code: 'client_update_required', retryable: false },
    }, 426))).resolves.toMatchObject({ status: 426, code: 'client_update_required', retryable: false });
  });

  it('preserves invalid HTTP response decoding instead of inventing service unavailability', async () => {
    await expect(decodeHttpError(jsonResponse({ protocolVersion: 3, error: { code: 123 } }, 400)))
      .rejects.toThrow('Invalid Agent V2 contract');
    const invalidJson = new SyntaxError('Invalid JSON');
    await expect(decodeHttpError({ status: 400, json: () => Promise.reject(invalidJson) } as Response))
      .rejects.toBe(invalidJson);
  });

  it('reuses a valid in-memory identity when persistent storage stops responding', async () => {
    const storage = createMemoryStorage();
    await storage.setItem('agentV2DeviceIdentity', JSON.stringify({
      version: 1,
      deviceId: DEVICE_ID,
      deviceToken: TOKEN_1,
      expiresAt: '2026-10-14T00:00:00.000Z',
    }));
    const originalGetItem = storage.getItem.bind(storage);
    let isStorageResponsive = true;
    storage.getItem = jest.fn((name) => (
      isStorageResponsive ? originalGetItem(name) : new Promise(() => undefined)
    ));
    const fetchMock = jest.fn(() => Promise.resolve(jsonResponse({ ok: true }))) as unknown as typeof fetch;
    const identity = new AgentV2IdentityService({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });

    await identity.authenticatedFetch('https://agent.test/api/v2/runs');
    isStorageResponsive = false;

    await expect(identity.authenticatedFetch('https://agent.test/api/v2/runs/run-1/tool-results'))
      .resolves.toMatchObject({ ok: true });
    expect(storage.getItem).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not restore a pending issuance after persistent identity cleanup', async () => {
    const storage = createMemoryStorage();
    let issuanceSignal: AbortSignal | null | undefined;
    let resolveIssuance!: (response: Response) => void;
    let markIssuanceStarted!: () => void;
    const issuanceStarted = new Promise<void>((resolve) => {
      markIssuanceStarted = resolve;
    });
    const issuanceResponse = new Promise<Response>((resolve) => {
      resolveIssuance = resolve;
    });
    const fetchMock = jest.fn((_url: string | URL | Request, init?: RequestInit) => {
      issuanceSignal = init?.signal;
      markIssuanceStarted();
      return issuanceResponse;
    }) as unknown as typeof fetch;
    const identity = new AgentV2IdentityService({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      randomUuid: () => DEVICE_ID,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });

    const request = identity.authenticatedFetch('https://agent.test/api/v2/runs');
    await issuanceStarted;
    const destroy = identity.destroy({ shouldClearPersistentIdentity: true });
    expect(issuanceSignal?.aborted).toBe(true);
    resolveIssuance(jsonResponse(tokenResponse(TOKEN_1)));

    await destroy;
    await expect(request).rejects.toThrow('Agent V2 identity is destroyed');
    await expect(storage.getItem('agentV2DeviceIdentity')).resolves.toBeUndefined();
  });

  it('preserves persistent identity during runtime replacement', async () => {
    const storage = createMemoryStorage();
    const storedIdentity = JSON.stringify({
      version: 1,
      deviceId: DEVICE_ID,
      deviceToken: TOKEN_1,
      expiresAt: '2026-10-14T00:00:00.000Z',
    });
    await storage.setItem('agentV2DeviceIdentity', storedIdentity);
    const identity = new AgentV2IdentityService({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: jest.fn() as unknown as typeof fetch,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
    });

    await identity.destroy();

    await expect(storage.getItem('agentV2DeviceIdentity')).resolves.toBe(storedIdentity);
    await expect(identity.authenticatedFetch('https://agent.test/api/v2/runs'))
      .rejects.toThrow('Agent V2 identity is destroyed');
  });

  it('keeps HTTP error metadata separate from the safe error message', async () => {
    const error = await decodeHttpError(jsonResponse({
      protocolVersion: 3,
      error: {
        code: 'agent_capacity_exhausted',
        retryable: true,
        retryAfterMs: 2_500,
      },
    }, 503));

    expect(error).toMatchObject({
      status: 503,
      code: 'agent_capacity_exhausted',
      message: 'Agent request failed.',
      retryable: true,
      retryAfterMs: 2_500,
    });
    expect(error.message).not.toContain(error.code);
  });

  it('gives up on a device token issuance that gets no response', async () => {
    jest.useFakeTimers({ now: Date.parse('2026-07-16T00:00:00.000Z') });
    try {
      const fetchMock = jest.fn((_url: string | URL | Request, init?: RequestInit) => new Promise<Response>(
        (_resolve, reject) => init?.signal?.addEventListener('abort', () => reject(init.signal!.reason)),
      )) as unknown as typeof fetch;
      const identity = new AgentV2IdentityService({
        storage: createMemoryStorage(),
        baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock,
        randomUuid: () => DEVICE_ID,
        requestTimeoutMs: 1_000,
      });

      const request = identity.authenticatedFetch('https://agent.test/api/v2/threads/default');
      const failure = expect(request).rejects.toMatchObject({ name: 'TimeoutError' });
      await jest.advanceTimersByTimeAsync(1_000);

      await failure;
      expect(fetchMock).toHaveBeenCalledTimes(1);
    } finally {
      jest.useRealTimers();
    }
  });
});

function tokenResponse(deviceToken: string) {
  return {
    protocolVersion: 3,
    deviceId: DEVICE_ID,
    deviceToken,
    expiresAt: '2026-10-14T00:00:00.000Z',
  };
}

function jsonResponse(value: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: new Headers({ 'Content-Type': 'application/json' }),
    json: () => Promise.resolve(value),
  } as Response;
}

function createMemoryStorage(): Storage {
  const values = new Map<string, unknown>();
  return {
    getItem: (name) => Promise.resolve(values.get(name)),
    setItem(name, value) {
      values.set(name, value);
      return Promise.resolve();
    },
    removeItem(name) {
      values.delete(name);
      return Promise.resolve();
    },
    clear() {
      values.clear();
      return Promise.resolve();
    },
    getAll: () => Promise.resolve(Object.fromEntries(values)),
    getMany: (keys) => Promise.resolve(Object.fromEntries(keys.map((key) => [key, values.get(key)]))),
    setMany(items) {
      Object.entries(items).forEach(([key, value]) => values.set(key, value));
      return Promise.resolve();
    },
  } satisfies Storage;
}

function getRequestUrl(input: string | URL | Request) {
  return typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
}
