import type { Storage } from '../storages/types';
import type { ClientTimingEvent } from './developmentTelemetry';
import type {
  AgentSemanticContentV1,
  AgentToolCall,
  AgentToolResultRequestV2,
} from './protocol/types';
import type { AgentWalletSnapshotV1 } from './protocol/types';
import type {
  AgentV2ClientUpdate,
  AgentV2HostContextSnapshot,
  AgentV2RunCommandInput,
} from './types';

import navigationActionFixture from '../../../tests/fixtures/agentV2/navigation-action-projection.v1.json';
import terminalStructuredOutputFixture from '../../../tests/fixtures/agentV2/terminal-structured-output-stream.v1.json';
import contractManifest from './generated/manifest.json';
import { hostUiCapabilities } from './testing/hostUiCapabilities';
import { runSafeAgentV2Operation } from './mutation';
import { AgentV2Runtime, type AgentV2ToolExecutionContext } from './runtime';
import { AgentV2WalletSession } from './walletSession';
import { AgentV2WalletToolDispatcher } from './walletTools';

const DEVICE_ID = '11111111-1111-4111-8111-111111111111';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const CLIENT_RUN_ID_2 = '22222222-2222-4222-8222-222222222223';
const RUN_ID = '33333333-3333-4333-8333-333333333333';
const RUN_ID_2 = '33333333-3333-4333-8333-333333333334';
const THREAD_ID = '44444444-4444-4444-8444-444444444444';
const THREAD_ID_2 = '44444444-4444-4444-8444-444444444445';
const MESSAGE_ID = '55555555-5555-4555-8555-555555555555';
const MESSAGE_ID_2 = '55555555-5555-4555-8555-555555555556';
const MESSAGE_ID_3 = '55555555-5555-4555-8555-555555555557';
const TOOL_CALL_ID = '66666666-6666-4666-8666-666666666666';
const TOOL_RESULT_ID = '77777777-7777-4777-8777-777777777777';
const WALLET_SESSION_ID = '88888888-8888-4888-8888-888888888888';
const SNAPSHOT_INSTANCE_ID = '99999999-9999-4999-8999-999999999999';
const PRIVATE_TOOL_ARGUMENT = 'PRIVATE_TOOL_ARGUMENT';
const PRIVATE_TOOL_REASON = 'PRIVATE_TOOL_REASON';
const PRIVATE_TOOL_STATUS_MESSAGE = 'PRIVATE_TOOL_STATUS_MESSAGE';

type TerminalFixtureEvent =
  | { type: 'run_start' | 'thread'; sequence: number }
  | { type: 'message_start'; sequence: number; messageId: string }
  | { type: 'text_delta'; sequence: number; messageId: string; delta: string }
  | { type: 'action'; sequence: number; messageId: string; structuredId: string }
  | { type: 'semantic_content'; sequence: number; messageId: string }
  | { type: 'message_end'; sequence: number; messageId: string; finishReason: 'complete' | 'cancelled' | 'error' }
  | { type: 'error'; sequence: number; messageId: string };

describe('AgentV2Runtime transport', () => {
  beforeEach(() => {
    sessionStorage.clear();
  });

  it.each(['active', 'closed', 'noConsent'] as const)(
    'resumes snapshot uploads after wallet context recovery only with eligible chat %s', async (chatState) => {
      jest.useFakeTimers({ now: Date.parse('2026-09-22T12:00:00.000Z') });
      let runtime: AgentV2Runtime | undefined;
      try {
        const storage = createMemoryStorage();
        await storeIdentity(storage);
        const snapshots: AgentWalletSnapshotV1[] = [];
        const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
          const url = getRequestUrl(input);
          if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
          if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
          if (url.endsWith('/wallet-snapshots')) {
            const snapshot = JSON.parse(init!.body as string) as AgentWalletSnapshotV1;
            snapshots.push(snapshot);
            const { instanceId, sessionId, revision, snapshotRevision } = snapshot;
            return Promise.resolve(jsonResponse({
              snapshotRef: { instanceId, sessionId, revision, snapshotRevision },
            }));
          }
          return Promise.reject(new Error(`Unexpected URL ${url}`));
        });
        runtime = new AgentV2Runtime({
          storage, baseUrl: 'https://agent.test/api/v2', fetch: fetchMock, onUpdate: jest.fn(),
        });
        const host = receiveHost('ton') as AgentV2HostContextSnapshot;
        await runtime.updateHostContext(host);
        if (chatState !== 'noConsent') await runtime.acceptConsent();
        await runtime.getHints();
        await runtime.setChatActive(true);
        await jest.advanceTimersByTimeAsync(0);
        const initialCount = chatState === 'active' || chatState === 'closed' ? 1 : 0;
        expect(snapshots).toHaveLength(initialCount);

        await runtime.updateHostContext();
        if (chatState === 'closed') await runtime.setChatActive(false);
        await jest.advanceTimersByTimeAsync(25_000);
        expect(snapshots).toHaveLength(initialCount);

        await runtime.updateHostContext(host);
        await jest.advanceTimersByTimeAsync(0);
        expect(snapshots).toHaveLength(initialCount + (chatState === 'active' ? 1 : 0));
        await jest.advanceTimersByTimeAsync(20_000);
        expect(snapshots).toHaveLength(initialCount + (chatState === 'active' ? 2 : 0));
        if (chatState === 'active') {
          expect(snapshots[1].revision).toBeGreaterThan(snapshots[0].revision);
          expect(snapshots[2].snapshotRevision).toBeGreaterThan(snapshots[1].snapshotRevision);
        }
      } finally {
        await runtime?.destroy();
        jest.useRealTimers();
      }
    },
  );

  it.each([
    ['missing', undefined, false],
    ['malformed', '{malformed', false],
    ['unknown version', JSON.stringify({ version: 1, accepted: true }), false],
    ['non-accepted', JSON.stringify({ version: 2, accepted: false }), false],
    ['accepted', JSON.stringify({ version: 2, accepted: true }), true],
  ] as const)('reads %s consent strictly', async (_name, stored, expected) => {
    const storage = createMemoryStorage();
    if (stored !== undefined) await storage.setItem('agentV2Consent', stored);
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: jest.fn() as unknown as typeof fetch,
      onUpdate: jest.fn(),
      now: () => Date.parse('2026-08-10T10:00:00.000Z'),
    });

    await expect(runtime.getConsent()).resolves.toBe(expected);
    await runtime.destroy();
  });

  it('fails a chat load that gets no response instead of waiting for it', async () => {
    jest.useFakeTimers({ now: Date.parse('2026-09-22T12:00:00.000Z') });
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((_input: string | URL | Request, init?: RequestInit) => new Promise<Response>(
      (_resolve, reject) => init?.signal?.addEventListener('abort', () => reject(init.signal!.reason)),
    )) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage, baseUrl: 'https://agent.test/api/v2', fetch: fetchMock, onUpdate: jest.fn(), requestTimeoutMs: 1_000,
    });
    try {
      await runtime.acceptConsent();
      const thread = runSafeAgentV2Operation(() => runtime.getDefaultThread());
      await jest.advanceTimersByTimeAsync(1_000);

      await expect(thread).resolves.toEqual({ ok: false, error: { code: 'network_error', retryable: true } });
    } finally {
      await runtime.destroy();
      jest.useRealTimers();
    }
  });

  it('fails a thread clear and a run cancel that get no response', async () => {
    jest.useFakeTimers({ now: Date.parse('2026-09-22T12:00:00.000Z') });
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: unansweredFetch(),
      onUpdate: jest.fn(),
      requestTimeoutMs: 1_000,
    });
    try {
      await runtime.acceptConsent();
      const clear = runSafeAgentV2Operation(() => runtime.clearThread(THREAD_ID, 1));
      const cancel = runSafeAgentV2Operation(() => runtime.cancelRun(RUN_ID));
      await jest.advanceTimersByTimeAsync(1_000);

      await expect(clear).resolves.toEqual({ ok: false, error: { code: 'network_error', retryable: true } });
      await expect(cancel).resolves.toEqual({ ok: false, error: { code: 'network_error', retryable: true } });
    } finally {
      await runtime.destroy();
      jest.useRealTimers();
    }
  });

  it('checks availability and quota again after a check that got no response', async () => {
    jest.useFakeTimers({ now: Date.parse('2026-09-22T12:00:00.000Z') });
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = unansweredFetch();
    const runtime = new AgentV2Runtime({
      storage, baseUrl: 'https://agent.test/api/v2', fetch: fetchMock, onUpdate: jest.fn(), requestTimeoutMs: 1_000,
    });
    try {
      await runtime.acceptConsent();
      const availability = runtime.getAvailability();
      const quota = runtime.getUserQuota();
      await jest.advanceTimersByTimeAsync(1_000);

      await expect(availability).resolves.toBeUndefined();
      await expect(quota).resolves.toBeUndefined();
      // These stay unanswered until the runtime is destroyed
      void runtime.getAvailability().catch(() => undefined);
      void runtime.getUserQuota().catch(() => undefined);
      await jest.advanceTimersByTimeAsync(0);
      expect(fetchMock.mock.calls.map(([input]) => getRequestUrl(input))).toEqual([
        'https://agent.test/api/v2/availability',
        'https://agent.test/api/v2/quota',
        'https://agent.test/api/v2/availability',
        'https://agent.test/api/v2/quota',
      ]);
    } finally {
      await runtime.destroy();
      jest.useRealTimers();
    }
  });

  it('persists one consent decision for the whole Agent runtime', async () => {
    const storage = createMemoryStorage();
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: jest.fn() as unknown as typeof fetch,
      onUpdate: jest.fn(),
      now: () => Date.parse('2026-08-10T10:00:00.000Z'),
    });

    await runtime.acceptConsent();

    await expect(runtime.getConsent()).resolves.toBe(true);
    const storedConsent = JSON.stringify({
      version: 2,
      accepted: true,
      updatedAt: '2026-08-10T10:00:00.000Z',
    });
    await expect(storage.getItem('agentV2Consent')).resolves.toBe(storedConsent);
    await runtime.destroy();
    await expect(storage.getItem('agentV2Consent')).resolves.toBe(storedConsent);
  });

  it('ordinary disposal preserves persistent wallet state', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const clear = jest.fn();
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: jest.fn() as unknown as typeof fetch,
      onUpdate: jest.fn(),
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
        clear,
      },
    });
    await runtime.acceptConsent();

    await runtime.destroy();

    expect(clear).toHaveBeenCalledWith();
  });

  it('does not start a run after runtime disposal during capability loading', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let resolveCapabilities!: (response: Response) => void;
    let markCapabilitiesRequested!: () => void;
    const capabilitiesRequested = new Promise<void>((resolve) => {
      markCapabilitiesRequested = resolve;
    });
    const capabilitiesResponse = new Promise<Response>((resolve) => {
      resolveCapabilities = resolve;
    });
    const requestedUrls: string[] = [];
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      requestedUrls.push(url);
      if (url.endsWith('/capabilities')) {
        markCapabilitiesRequested();
        return capabilitiesResponse;
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();

    const run = runtime.startRun({
      expectedThreadRevision: 0,
      input: { kind: 'append', text: 'Wallet balance' },
    });
    await capabilitiesRequested;
    await runtime.destroy({ shouldClearPersistentIdentity: true });
    resolveCapabilities(featureCapabilitiesResponse('disabled'));

    await expect(run).rejects.toThrow('Agent V2 runtime is destroyed');
    expect(requestedUrls).not.toContain('https://agent.test/api/v2/runs');
  });

  it('ignores delayed control-plane responses after disposal', async () => {
    jest.useFakeTimers();
    try {
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      const updates: AgentV2ClientUpdate[] = [];
      const pendingResponses = new Map<string, (response: Response) => void>();
      const requested = new Set<string>();
      let markAllRequested!: () => void;
      const allRequested = new Promise<void>((resolve) => {
        markAllRequested = resolve;
      });
      const fetchMock = jest.fn((input: string | URL | Request) => {
        const url = getRequestUrl(input);
        const operation = new Promise<Response>((resolve) => {
          pendingResponses.set(url, resolve);
          requested.add(url);
          if (requested.size === 2) markAllRequested();
        });
        return operation;
      }) as unknown as typeof fetch;
      const runtime = new AgentV2Runtime({
        storage,
        baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock,
        onUpdate: (update) => updates.push(update),
      });
      await runtime.acceptConsent();

      const quota = runtime.getUserQuota();
      const availability = runtime.getAvailability();
      await allRequested;
      expect(requested).toEqual(new Set([
        'https://agent.test/api/v2/quota',
        'https://agent.test/api/v2/availability',
      ]));

      await runtime.destroy();
      pendingResponses.get('https://agent.test/api/v2/quota')!(jsonResponse({
        protocolVersion: 3,
        quota: {
          limit: 20,
          used: 5,
          remaining: 15,
          resetAt: '2026-08-12T00:00:00.000Z',
        },
      }));
      pendingResponses.get('https://agent.test/api/v2/availability')!(jsonResponse({
        protocolVersion: 3,
        state: 'capacity_exhausted',
        resetAt: '2026-08-12T00:00:00.000Z',
      }));
      const results = await Promise.allSettled([quota, availability]);

      expect(results).toEqual([
        { status: 'rejected', reason: new Error('Agent V2 runtime is destroyed') },
        { status: 'rejected', reason: new Error('Agent V2 runtime is destroyed') },
      ]);
      expect(updates).toEqual([]);
      expect(jest.getTimerCount()).toBe(0);
      expect(() => runtime.getConsent()).toThrow('Agent V2 runtime is destroyed');
      expect(() => runtime.resolveAction(MESSAGE_ID, 'action')).toThrow('Agent V2 runtime is destroyed');
    } finally {
      jest.useRealTimers();
    }
  });

  it('aborts an active tool and skips terminal quota refresh during disposal', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let quotaRequests = 0;
    let executionSignal: AbortSignal | undefined;
    let markExecutionStarted!: () => void;
    const executionStarted = new Promise<void>((resolve) => {
      markExecutionStarted = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/quota')) {
        quotaRequests += 1;
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          quota: {
            limit: 20,
            used: quotaRequests,
            remaining: 20 - quotaRequests,
            resetAt: '2026-08-12T00:00:00.000Z',
          },
        }));
      }
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          toolCallEvent(2),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift()!,
      toolExecutor: {
        execute: jest.fn((_call, context) => {
          executionSignal = context.signal;
          markExecutionStarted();
          return new Promise(() => undefined);
        }),
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();
    await runtime.getUserQuota();

    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Search for TON' },
    });
    await executionStarted;
    await runtime.destroy();

    await expect(run).resolves.toMatchObject({ state: 'interrupted' });
    expect(executionSignal?.aborted).toBe(true);
    expect(quotaRequests).toBe(2);
  });

  it('rechecks availability when a known reset is reached', async () => {
    jest.useFakeTimers();
    let now = Date.parse('2026-07-29T12:00:00.000Z');
    const resetAt = now + 60_000;
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: unknown[] = [];
    let availabilityRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/availability')) {
        availabilityRequests += 1;
        return Promise.resolve(jsonResponse(availabilityRequests === 1
          ? {
            protocolVersion: 3,
            state: 'capacity_exhausted',
            resetAt: new Date(resetAt).toISOString(),
          }
          : { protocolVersion: 3, state: 'available' }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      now: () => now,
    });
    await runtime.acceptConsent();

    await runtime.getAvailability();
    expect(updates).toContainEqual({
      kind: 'availabilityChanged',
      availability: { state: 'capacity_exhausted', resetAt },
    });

    now = resetAt;
    await jest.advanceTimersByTimeAsync(60_000);
    expect(availabilityRequests).toBe(2);
    expect(updates).toContainEqual({
      kind: 'availabilityChanged',
      availability: { state: 'available' },
    });

    await runtime.destroy();
    jest.useRealTimers();
  });

  it('refreshes availability after a successful run and clears stale capacity without a reset', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    let availabilityRequests = 0;
    let resolveStaleAvailability!: (response: Response) => void;
    const staleAvailability = new Promise<Response>((resolve) => {
      resolveStaleAvailability = resolve;
    });
    let markStaleAvailabilityRequested!: () => void;
    const staleAvailabilityRequested = new Promise<void>((resolve) => {
      markStaleAvailabilityRequested = resolve;
    });
    let resolveTerminalAvailabilityRefreshed!: () => void;
    const terminalAvailabilityRefreshed = new Promise<void>((resolve) => {
      resolveTerminalAvailabilityRefreshed = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/availability')) {
        availabilityRequests += 1;
        if (availabilityRequests === 1) {
          return Promise.resolve(jsonResponse({ protocolVersion: 3, state: 'capacity_exhausted' }));
        }
        if (availabilityRequests === 2) {
          markStaleAvailabilityRequested();
          return staleAvailability;
        }
        return Promise.resolve(jsonResponse({ protocolVersion: 3, state: 'available' }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          textDelta('Ready'),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (
          update.kind === 'availabilityChanged'
          && update.availability.state === 'available'
          && availabilityRequests === 3
        ) {
          resolveTerminalAvailabilityRefreshed();
        }
      },
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    await runtime.getAvailability();
    expect(updates.at(-1)).toEqual({
      kind: 'availabilityChanged',
      availability: { state: 'capacity_exhausted' },
    });

    const staleProbe = runtime.getAvailability();
    await staleAvailabilityRequested;
    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Ready?' },
    })).resolves.toMatchObject({ state: 'completed' });
    resolveStaleAvailability(jsonResponse({ protocolVersion: 3, state: 'capacity_exhausted' }));
    await staleProbe;
    await terminalAvailabilityRefreshed;

    expect(availabilityRequests).toBe(3);
    expect(updates.filter(({ kind }) => kind === 'availabilityChanged')).toEqual([
      { kind: 'availabilityChanged', availability: { state: 'capacity_exhausted' } },
      { kind: 'availabilityChanged', availability: { state: 'available' } },
    ]);
    await runtime.destroy();
  });

  it('keeps a local capacity failure authoritative over an older in-flight availability probe', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    let availabilityRequests = 0;
    let resolveStaleAvailability!: (response: Response) => void;
    const staleAvailability = new Promise<Response>((resolve) => {
      resolveStaleAvailability = resolve;
    });
    let markStaleAvailabilityRequested!: () => void;
    const staleAvailabilityRequested = new Promise<void>((resolve) => {
      markStaleAvailabilityRequested = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/availability')) {
        availabilityRequests += 1;
        if (availabilityRequests === 1) {
          return Promise.resolve(jsonResponse({ protocolVersion: 3, state: 'available' }));
        }
        markStaleAvailabilityRequested();
        return staleAvailability;
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          event({
            type: 'error',
            sequence: 2,
            code: 'agent_capacity_exhausted',
            retryable: true,
          }),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    await runtime.getAvailability();
    const staleProbe = runtime.getAvailability();
    await staleAvailabilityRequested;
    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Try now' },
    })).resolves.toMatchObject({ state: 'failed' });

    expect(availabilityRequests).toBe(2);
    expect(updates.filter(({ kind }) => kind === 'availabilityChanged').at(-1)).toEqual({
      kind: 'availabilityChanged',
      availability: { state: 'capacity_exhausted' },
    });

    resolveStaleAvailability(jsonResponse({ protocolVersion: 3, state: 'available' }));
    await staleProbe;
    await Promise.resolve();

    expect(availabilityRequests).toBe(2);
    expect(updates.filter(({ kind }) => kind === 'availabilityChanged')).toEqual([
      { kind: 'availabilityChanged', availability: { state: 'available' } },
      { kind: 'availabilityChanged', availability: { state: 'capacity_exhausted' } },
    ]);
    await runtime.destroy();
  });

  it('refreshes weighted user quota after admission and completion, then resets without retry', async () => {
    jest.useFakeTimers();
    let now = Date.parse('2026-07-29T23:59:00.000Z');
    const resetAt = now + 60_000;
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: unknown[] = [];
    const runRequests: Record<string, any>[] = [];
    let quotaRequests = 0;
    let resolveTerminalQuotaRefreshed!: () => void;
    const terminalQuotaRefreshed = new Promise<void>((resolve) => {
      resolveTerminalQuotaRefreshed = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/quota')) {
        quotaRequests += 1;
        const isAfterReset = now >= resetAt;
        const used = quotaRequests === 1 ? 1 : 5;
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          quota: {
            limit: 20,
            used: isAfterReset ? 0 : used,
            remaining: isAfterReset ? 20 : 20 - used,
            resetAt: new Date(isAfterReset ? resetAt + 24 * 60 * 60_000 : resetAt).toISOString(),
          },
        }));
      }
      if (url.endsWith('/runs')) {
        runRequests.push(JSON.parse(init?.body as string));
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          textDelta('Done'),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'userQuotaChanged' && update.quota?.used === 5 && quotaRequests === 3) {
          resolveTerminalQuotaRefreshed();
        }
      },
      now: () => now,
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    await runtime.getUserQuota();
    expect(updates).toContainEqual({
      kind: 'userQuotaChanged',
      quota: {
        limit: 20,
        used: 1,
        remaining: 19,
        resetAt: new Date(resetAt).toISOString(),
      },
    });

    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Use quota' },
    });
    await terminalQuotaRefreshed;
    expect(quotaRequests).toBe(3);
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'userQuotaChanged',
      quota: expect.objectContaining({ used: 5, remaining: 15 }),
    }));

    now = resetAt;
    await jest.advanceTimersByTimeAsync(60_000);
    expect(quotaRequests).toBe(4);
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'userQuotaChanged',
      quota: expect.objectContaining({ used: 0, remaining: 20 }),
    }));
    expect(runRequests).toHaveLength(1);

    await runtime.destroy();
    jest.useRealTimers();
  });

  it('refreshes quota after admission even when the initial probe is still pending', async () => {
    const resetAt = '2026-07-30T00:00:00.000Z';
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: unknown[] = [];
    let resolveTerminalQuotaRefreshed!: () => void;
    const terminalQuotaRefreshed = new Promise<void>((resolve) => {
      resolveTerminalQuotaRefreshed = resolve;
    });
    let resolveQuotaRequested!: () => void;
    const quotaRequested = new Promise<void>((resolve) => {
      resolveQuotaRequested = resolve;
    });
    let quotaRequests = 0;
    let resolveInitialQuota!: (response: Response) => void;
    const initialQuota = new Promise<Response>((resolve) => {
      resolveInitialQuota = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/quota')) {
        quotaRequests += 1;
        if (quotaRequests === 1) {
          resolveQuotaRequested();
          return initialQuota;
        }
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          quota: { limit: 20, used: 1, remaining: 19, resetAt },
        }));
      }
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          textDelta('Done'),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'userQuotaChanged' && update.quota?.used === 1 && quotaRequests === 3) {
          resolveTerminalQuotaRefreshed();
        }
      },
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    const initialProbe = runtime.getUserQuota();
    await quotaRequested;
    expect(quotaRequests).toBe(1);
    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Use quota during probe' },
    });

    resolveInitialQuota(jsonResponse({
      protocolVersion: 3,
      quota: { limit: 20, used: 0, remaining: 20, resetAt },
    }));
    await initialProbe;
    await terminalQuotaRefreshed;

    expect(quotaRequests).toBe(3);
    expect(updates.at(-1)).toEqual({
      kind: 'userQuotaChanged',
      quota: { limit: 20, used: 1, remaining: 19, resetAt },
    });

    await runtime.destroy();
  });

  it('refreshes authoritative user quota after a terminal stream error', async () => {
    const now = Date.parse('2026-07-29T12:00:00.000Z');
    const resetAt = '2026-07-30T00:00:00.000Z';
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    let quotaRequests = 0;
    let resolveTerminalQuotaRefreshed!: () => void;
    const terminalQuotaRefreshed = new Promise<void>((resolve) => {
      resolveTerminalQuotaRefreshed = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/quota')) {
        quotaRequests += 1;
        const used = quotaRequests < 3 ? 1 : 5;
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          quota: { limit: 20, used, remaining: 20 - used, resetAt },
        }));
      }
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          event({ type: 'error', sequence: 2, code: 'provider_unavailable', retryable: true }),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'userQuotaChanged' && update.quota?.used === 5) {
          resolveTerminalQuotaRefreshed();
        }
      },
      now: () => now,
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();
    await runtime.getUserQuota();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Analyze price' },
    })).resolves.toMatchObject({ state: 'failed' });
    await terminalQuotaRefreshed;

    expect(quotaRequests).toBe(3);
    expect(updates).toContainEqual({
      kind: 'userQuotaChanged',
      quota: { limit: 20, used: 5, remaining: 15, resetAt },
    });
    await runtime.destroy();
  });

  it('reuses the original run and message IDs for a manual retry after HTTP 429', async () => {
    const now = Date.parse('2026-07-29T12:00:00.000Z');
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: unknown[] = [];
    const runRequests: Record<string, any>[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        runRequests.push(JSON.parse(init?.body as string));
        if (runRequests.length === 1) {
          return Promise.resolve(jsonResponse({
            protocolVersion: 3,
            error: {
              code: 'rate_limited',
              retryable: true,
              retryAfterMs: 5_000,
            },
          }, 429));
        }
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          textDelta('Done'),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      now: () => now,
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: MESSAGE_ID,
      state: 'failed',
    });
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      code: 'rate_limited',
      resetAt: now + 5_000,
    }));
    await expect(runtime.retryRun(CLIENT_RUN_ID)).resolves.toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: MESSAGE_ID,
      state: 'completed',
    });
    expect(runRequests).toHaveLength(2);
    expect(runRequests[1]).toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      input: {
        kind: 'append',
        message: { id: MESSAGE_ID, text: 'Hello' },
      },
    });
  });

  it('retains a pre-admission network failure for an exact manual retry', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const runRequests: Record<string, any>[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        runRequests.push(JSON.parse(init?.body as string));
        if (runRequests.length <= 3) return Promise.reject(new TypeError('Failed to fetch'));
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          textDelta('Recovered'),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Retry after reconnect' },
    })).resolves.toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: MESSAGE_ID,
      state: 'failed',
    });
    await expect(runtime.retryRun(CLIENT_RUN_ID)).resolves.toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: MESSAGE_ID,
      state: 'completed',
    });
    expect(runRequests).toHaveLength(4);
    expect(runRequests[3]).toEqual(runRequests[0]);
    await runtime.destroy();
  });

  it('removes an unclaimed failed-run request when its retry window expires', async () => {
    jest.useFakeTimers();
    try {
      let now = Date.parse('2026-07-29T12:00:00.000Z');
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      const fetchMock = jest.fn((input: string | URL | Request) => {
        const url = getRequestUrl(input);
        if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
        if (url.endsWith('/runs')) {
          return Promise.resolve(jsonResponse({
            protocolVersion: 3,
            error: {
              code: 'rate_limited',
              retryable: true,
              retryAfterMs: 5_000,
            },
          }, 429));
        }
        return Promise.reject(new Error(`Unexpected URL ${url}`));
      }) as unknown as typeof fetch;
      const ids = [CLIENT_RUN_ID, MESSAGE_ID];
      const runtime = new AgentV2Runtime({
        storage,
        baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock,
        onUpdate: jest.fn(),
        now: () => now,
        randomUuid: () => ids.shift() ?? DEVICE_ID,
      });
      await runtime.acceptConsent();
      await runtime.startRun({
        threadId: THREAD_ID,
        expectedThreadRevision: 1,
        input: { kind: 'append', text: 'Retry later' },
      });
      now += 5_000 + 5 * 60_000;
      jest.advanceTimersByTime(5_000 + 5 * 60_000);

      await expect(runtime.retryRun(CLIENT_RUN_ID)).resolves.toBeUndefined();
      await runtime.destroy();
    } finally {
      jest.useRealTimers();
    }
  });

  it('removes a thread-owned failed-run request when the thread is cleared', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          error: {
            code: 'rate_limited',
            retryable: true,
            retryAfterMs: 5_000,
          },
        }, 429));
      }
      if (url.endsWith(`/threads/${THREAD_ID}/clear`)) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary({ revision: 2 }),
          duplicate: false,
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, '66666666-6666-4666-8666-666666666666'];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();
    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Retry later' },
    });
    await runtime.clearThread(THREAD_ID, 1);

    await expect(runtime.retryRun(CLIENT_RUN_ID)).resolves.toBeUndefined();
    await runtime.destroy();
  });

  it('cancels a reconnecting answer before its clear and clears past the revision the answer moved', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    const clearRevisions: number[] = [];
    let reconnectSignal: AbortSignal | undefined;
    let markReconnecting!: () => void;
    const reconnecting = new Promise<void>((resolve) => {
      markReconnecting = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        if (!JSON.parse(init!.body as string).resumeAfterSequence) {
          return Promise.resolve(ndjsonResponse([runStart(), messageStart(), textDelta('Partial ')]));
        }
        reconnectSignal = init!.signal!;
        markReconnecting();
        return new Promise<Response>((_resolve, reject) => {
          reconnectSignal!.addEventListener('abort', () => reject(reconnectSignal!.reason));
        });
      }
      if (url.endsWith(`/threads/${THREAD_ID}/clear`)) {
        clearRevisions.push(JSON.parse(init!.body as string).expectedThreadRevision);
        return Promise.resolve(clearRevisions.length === 1
          ? jsonResponse({
            protocolVersion: 3,
            error: {
              code: 'thread_revision_conflict',
              retryable: true,
              threadId: THREAD_ID,
              currentThread: threadSummary({ revision: 3, messageCount: 2 }),
            },
          }, 409)
          : jsonResponse({ protocolVersion: 3, thread: threadSummary({ revision: 4 }), duplicate: false }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 0,
      input: { kind: 'append', text: 'Hello' },
    });
    await reconnecting;
    await expect(runtime.clearThread(THREAD_ID, 1)).resolves.toMatchObject({ thread: { revision: 4 } });

    await expect(run).resolves.toMatchObject({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'cancelled' });
    expect(reconnectSignal!.aborted).toBe(true);
    expect(clearRevisions).toEqual([1, 3]);
    const cancelledIndex = updates.findIndex(({ kind }) => kind === 'runCancelled');
    expect(updates[cancelledIndex]).toEqual({
      kind: 'runCancelled', clientRunId: CLIENT_RUN_ID, runId: RUN_ID, threadId: THREAD_ID,
    });
    expect(updates.slice(cancelledIndex + 1).filter(({ clientRunId }) => clientRunId)).toEqual([]);
    expect(updates.at(-1)).toMatchObject({ kind: 'threadChanged', thread: { revision: 4 } });
    await runtime.destroy();
  });

  it('keeps a clear that cancelled no answer bound to the revision its caller read', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn(() => Promise.resolve(jsonResponse({
      protocolVersion: 3,
      error: {
        code: 'thread_revision_conflict',
        retryable: true,
        threadId: THREAD_ID,
        currentThread: threadSummary({ revision: 3 }),
      },
    }, 409))) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();

    await expect(runtime.clearThread(THREAD_ID, 1)).rejects.toMatchObject({ code: 'thread_revision_conflict' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await runtime.destroy();
  });

  it('reports a problem with a trimmed comment and repeats an unanswered report under the same id', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const report = jsonResponse({ protocolVersion: 3, reportId: RUN_ID, duplicate: false });
    const fetchMock = jest.fn((_input: string | URL | Request, _init?: RequestInit) => Promise.resolve(report))
      .mockRejectedValueOnce(new TypeError('Failed to fetch'));
    const ids = [CLIENT_RUN_ID, CLIENT_RUN_ID_2];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock as unknown as typeof fetch,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift()!,
    });
    await runtime.acceptConsent();

    const answer = { messageId: MESSAGE_ID, comment: '  Wrong balance  ' };
    await expect(runtime.reportProblem(THREAD_ID, answer)).rejects.toThrow();
    await expect(runtime.reportProblem(THREAD_ID, answer))
      .resolves.toEqual({ protocolVersion: 3, reportId: RUN_ID, duplicate: false });
    await runtime.reportProblem(THREAD_ID, { comment: '   ' });

    const [[url, lostInit], [, retryInit], [, blankCommentInit]] = fetchMock.mock.calls;
    expect(getRequestUrl(url)).toBe(`https://agent.test/api/v2/threads/${THREAD_ID}/reports`);
    expect(retryInit!.method).toBe('POST');
    expect(JSON.parse(retryInit!.body as string)).toEqual({
      protocolVersion: 3, clientOperationId: CLIENT_RUN_ID, messageId: MESSAGE_ID, comment: 'Wrong balance',
    });
    expect(lostInit!.body).toBe(retryInit!.body);
    expect(JSON.parse(blankCommentInit!.body as string))
      .toEqual({ protocolVersion: 3, clientOperationId: CLIENT_RUN_ID_2 });
    await runtime.destroy();
  });

  it('removes a recovery phrase from a problem report comment', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((_input: string | URL | Request, _init?: RequestInit) => Promise.resolve(
      jsonResponse({ protocolVersion: 3, reportId: RUN_ID, duplicate: false }),
    ));
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock as unknown as typeof fetch,
      onUpdate: jest.fn(),
      randomUuid: () => CLIENT_RUN_ID,
    });
    await runtime.acceptConsent();

    await runtime.reportProblem(THREAD_ID, {
      comment: 'It cannot restore scheme spot photo card baby mountain device kick cradle pact join borrow',
    });

    expect(JSON.parse(fetchMock.mock.calls[0][1]!.body as string)).toEqual({
      protocolVersion: 3,
      clientOperationId: CLIENT_RUN_ID,
      comment: 'It cannot restore [secret words removed and not sent]',
    });
    await runtime.destroy();
  });

  it('keeps a later report retryable when an earlier one settles, and asks again whether reports are on', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const reports: Array<{ clientOperationId: string; messageId?: string }> = [];
    let resolveEarlier: ((response: Response) => void) | undefined;
    let capabilityRequestCount = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      if (getRequestUrl(input).endsWith('/capabilities')) {
        capabilityRequestCount += 1;
        return Promise.resolve(featureCapabilitiesResponse('disabled'));
      }
      const report = JSON.parse(init!.body as string) as (typeof reports)[number];
      reports.push(report);
      if (report.messageId) {
        return new Promise<Response>((resolve) => {
          resolveEarlier = resolve;
        });
      }
      if (reports.length === 2) return Promise.reject(new TypeError('Failed to fetch'));
      return Promise.resolve(jsonResponse({ protocolVersion: 3, reportId: RUN_ID_2, duplicate: true }));
    });
    const ids = [CLIENT_RUN_ID, CLIENT_RUN_ID_2];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock as unknown as typeof fetch,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift()!,
    });
    await runtime.acceptConsent();
    await runtime.getProblemReportAvailability();

    const earlier = runtime.reportProblem(THREAD_ID, { messageId: MESSAGE_ID });
    for (let attempt = 0; attempt < 20 && !resolveEarlier; attempt += 1) await Promise.resolve();
    await expect(runtime.reportProblem(THREAD_ID, { comment: 'Later' })).rejects.toThrow();
    resolveEarlier!(jsonResponse({ protocolVersion: 3, reportId: RUN_ID, duplicate: false }));
    await earlier;
    await runtime.reportProblem(THREAD_ID, { comment: 'Later' });
    await runtime.getProblemReportAvailability();

    expect(reports.map(({ clientOperationId }) => clientOperationId))
      .toEqual([CLIENT_RUN_ID, CLIENT_RUN_ID_2, CLIENT_RUN_ID_2]);
    expect(capabilityRequestCount).toBe(2);
    await runtime.destroy();
  });

  it.each([
    ['takes them', () => Promise.resolve(featureCapabilitiesResponse('disabled')), true],
    ['turned them off', () => Promise.resolve(jsonResponse({
      protocolVersion: 3, walletQuery: { status: 'disabled' }, problemReport: { status: 'disabled' },
    })), false],
    ['cannot be reached', () => Promise.reject(new TypeError('Failed to fetch')), false],
  ] as const)('offers problem reports only while the server takes them: it %s', async (_case, respond, expected) => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((_input: string | URL | Request) => respond());
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock as unknown as typeof fetch,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();

    await expect(runtime.getProblemReportAvailability()).resolves.toBe(expected);
    expect(getRequestUrl(fetchMock.mock.calls[0][0])).toBe('https://agent.test/api/v2/capabilities');
    await runtime.destroy();
  });

  it('cancels a run that a thread clear finds still being prepared', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let resolveCapabilities!: (response: Response) => void;
    let markCapabilitiesRequested!: () => void;
    const capabilitiesRequested = new Promise<void>((resolve) => {
      markCapabilitiesRequested = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/capabilities')) {
        markCapabilitiesRequested();
        return new Promise<Response>((resolve) => {
          resolveCapabilities = resolve;
        });
      }
      if (url.endsWith(`/threads/${THREAD_ID}/clear`)) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary({ revision: 2 }),
          duplicate: false,
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    });
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock as unknown as typeof fetch,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    });
    await capabilitiesRequested;
    await runtime.clearThread(THREAD_ID, 1);
    resolveCapabilities(featureCapabilitiesResponse('disabled'));

    await expect(run).resolves.toEqual({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: MESSAGE_ID,
      state: 'cancelled',
    });
    expect(fetchMock.mock.calls.some(([input]) => getRequestUrl(input).endsWith('/runs'))).toBe(false);
    await runtime.destroy();
  });

  it('keeps generic hints when wallet capabilities are unavailable', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        return Promise.resolve(starterHintsResponse([
          { id: 'learn.security' },
          { id: 'agent.capabilities', requiredCapabilities: ['wallet_read'] },
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();

    await expect(runtime.getHints('en')).resolves.toMatchObject({
      items: [{ id: 'learn.security' }],
    });
    await runtime.destroy();
  });

  it('keeps wallet-read hints when the server offers the pinned wallet filter catalog', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        return Promise.resolve(starterHintsResponse([
          { id: 'agent.capabilities', requiredCapabilities: ['wallet_read'] },
        ]));
      }
      if (url.endsWith('/capabilities')) {
        return Promise.resolve(featureCapabilitiesResponse('available'));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    await expect(runtime.getHints('en')).resolves.toMatchObject({
      items: [{ id: 'agent.capabilities', requiredCapabilities: ['wallet_read'] }],
    });
    await runtime.destroy();
  });

  it.each([
    ['disabled wallet-query feature', 'disabled', undefined],
    ['mismatched wallet-query catalog digest', 'available', '0'.repeat(64)],
  ] as const)('removes wallet-read hints for a %s', async (_name, walletQuery, digest) => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        return Promise.resolve(starterHintsResponse([
          { id: 'agent.capabilities', requiredCapabilities: ['wallet_read'] },
          { id: 'learn.security' },
        ]));
      }
      if (url.endsWith('/capabilities')) {
        return Promise.resolve(featureCapabilitiesResponse(walletQuery, digest));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    await expect(runtime.getHints()).resolves.toMatchObject({
      items: [{ id: 'learn.security' }],
    });
    await runtime.destroy();
  });

  it('removes receive hints when the latest wallet context does not advertise receive', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        return Promise.resolve(starterHintsResponse([
          { id: 'receive.tokens', requiredCapabilities: ['receive_action'] },
          { id: 'learn.security' },
        ]));
      }
      if (url.endsWith('/capabilities')) {
        return Promise.resolve(featureCapabilitiesResponse('disabled'));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext({ ...receiveHost('ton'), activeAccountId: undefined });

    await expect(runtime.getHints()).resolves.toMatchObject({
      items: [{ id: 'learn.security' }],
    });
    await runtime.destroy();
  });

  it('treats combined hint capability requirements as all-of', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        return Promise.resolve(starterHintsResponse([
          { id: 'receive.tokens', requiredCapabilities: ['receive_action'] },
          { id: 'learn.swap', requiredCapabilities: ['wallet_read', 'receive_action'] },
        ]));
      }
      if (url.endsWith('/capabilities')) {
        return Promise.resolve(featureCapabilitiesResponse('disabled'));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    await expect(runtime.getHints()).resolves.toMatchObject({
      items: [{ id: 'receive.tokens', requiredCapabilities: ['receive_action'] }],
    });
    await runtime.destroy();
  });

  it('preserves catalog, order, and requirement metadata while filtering hints', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const responseItems = [
      { id: 'learn.security' },
      { id: 'agent.capabilities', requiredCapabilities: ['wallet_read'] },
      { id: 'receive.tokens', requiredCapabilities: ['receive_action'] },
      { id: 'learn.swap' },
    ];
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        return Promise.resolve(starterHintsResponse(responseItems));
      }
      if (url.endsWith('/capabilities')) {
        return Promise.resolve(featureCapabilitiesResponse('disabled'));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    await expect(runtime.getHints()).resolves.toEqual({
      protocolVersion: 3,
      catalogVersion: 'agent-starter-hints-v1',
      items: [
        { id: 'learn.security' },
        { id: 'receive.tokens', requiredCapabilities: ['receive_action'] },
        { id: 'learn.swap' },
      ],
    });
    await runtime.destroy();
  });

  it('filters delayed hints against the latest wallet context', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let resolveHints!: (response: Response) => void;
    let markHintsRequested!: () => void;
    const hintsRequested = new Promise<void>((resolve) => {
      markHintsRequested = resolve;
    });
    const hintsResponse = new Promise<Response>((resolve) => {
      resolveHints = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        markHintsRequested();
        return hintsResponse;
      }
      if (url.endsWith('/capabilities')) {
        return Promise.resolve(featureCapabilitiesResponse('disabled'));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext({ ...receiveHost('ton'), activeAccountId: undefined });

    const hints = runtime.getHints();
    await hintsRequested;
    await runtime.updateHostContext(receiveHost('ton'));
    resolveHints(starterHintsResponse([
      { id: 'receive.tokens', requiredCapabilities: ['receive_action'] },
    ]));

    await expect(hints).resolves.toMatchObject({
      items: [{ id: 'receive.tokens', requiredCapabilities: ['receive_action'] }],
    });
    await runtime.destroy();
  });

  it('uses Android feature capabilities while filtering delayed hints', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let resolveHints!: (response: Response) => void;
    let markHintsRequested!: () => void;
    const hintsRequested = new Promise<void>((resolve) => {
      markHintsRequested = resolve;
    });
    const hintsResponse = new Promise<Response>((resolve) => {
      resolveHints = resolve;
    });
    let featureCapabilityRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        markHintsRequested();
        return hintsResponse;
      }
      if (url.endsWith('/capabilities')) {
        featureCapabilityRequests += 1;
        return Promise.resolve(featureCapabilitiesResponse('available'));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext({
      ...receiveHost('ton'),
      platform: 'android', uiCapabilities: hostUiCapabilities('android'),
      client: 'native',
    });

    const hints = runtime.getHints();
    await hintsRequested;
    expect(featureCapabilityRequests).toBe(1);
    await runtime.updateHostContext(receiveHost('ton'));
    resolveHints(starterHintsResponse([
      { id: 'agent.capabilities', requiredCapabilities: ['wallet_read'] },
    ]));

    await expect(hints).resolves.toMatchObject({
      items: [{ id: 'agent.capabilities', requiredCapabilities: ['wallet_read'] }],
    });
    expect(featureCapabilityRequests).toBe(1);
    await runtime.destroy();
  });

  it('shares one feature-capability request across concurrent hint filtering', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let featureCapabilityRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) {
        return Promise.resolve(starterHintsResponse([{ id: 'learn.security' }]));
      }
      if (url.endsWith('/capabilities')) {
        featureCapabilityRequests += 1;
        return Promise.resolve(featureCapabilitiesResponse('disabled'));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    await expect(Promise.all([
      runtime.getHints('en'),
      runtime.getHints('ru'),
    ])).resolves.toEqual([
      expect.objectContaining({ items: [{ id: 'learn.security' }] }),
      expect.objectContaining({ items: [{ id: 'learn.security' }] }),
    ]);
    expect(featureCapabilityRequests).toBe(1);
    await runtime.destroy();
  });

  it('runs the feature-capability preflight before a direct Classic V2 run', async () => {
    const walletSession = new AgentV2WalletSession();
    const requestedUrls: string[] = [];
    let runRequest: Record<string, unknown> | undefined;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      requestedUrls.push(url);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: DEVICE_ID,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      if (url.endsWith('/runs')) {
        runRequest = JSON.parse(init?.body as string);
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          textDelta('Answer'),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
      walletSession,
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 0,
      input: { kind: 'append', text: 'Search current news' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(requestedUrls.findIndex((url) => url.endsWith('/capabilities')))
      .toBeLessThan(requestedUrls.findIndex((url) => url.endsWith('/runs')));
    expect(runRequest).toHaveProperty('context.permissions', { agentConsentAccepted: true });
    expect(runRequest).toMatchObject({
      capabilities: {
        protocolVersion: 3,
        features: ['followups', 'sendRecipientWithoutAsset'],
      },
    });
  });

  it('removes a recovery phrase from a run request before it leaves the device', async () => {
    // The BIP39 test vector for entropy c0ba5a8e914111210f2bd131f3d5e08d, a public value that guards no funds
    const phrase = 'scheme spot photo card baby mountain device kick cradle pact join borrow';
    const runRequests: string[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: DEVICE_ID,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        runRequests.push(init?.body as string);
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          textDelta('Never share these words'),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: `My words: ${phrase}. Is my wallet safe?` },
      entryPoint: { kind: 'agentTab' },
    })).resolves.toMatchObject({ state: 'completed' });
    // The stream answers with the first run's ids, so only the edit's request is checked
    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 2,
      input: { kind: 'edit', targetUserMessageId: MESSAGE_ID, text: phrase.toUpperCase() },
    });

    expect(runRequests.map((body) => JSON.parse(body).input)).toEqual([
      {
        kind: 'append',
        message: { id: MESSAGE_ID, text: 'My words: [secret words removed and not sent]. Is my wallet safe?' },
      },
      {
        kind: 'edit',
        targetUserMessageId: MESSAGE_ID,
        message: { id: expect.any(String), text: '[secret words removed and not sent]' },
      },
    ]);
    for (const body of runRequests) expect(body.toLowerCase()).not.toContain('cradle pact');
    await runtime.destroy();
  });

  it('serializes a follow-up reference as the only run origin', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let runRequest: Record<string, unknown> | undefined;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        runRequest = JSON.parse(init?.body as string);
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          messageEnd(3),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Continue' },
      followupOf: {
        messageId: MESSAGE_ID_2,
        followupId: 'followup-1',
      },
    });

    expect(runRequest).toMatchObject({
      followupOf: {
        messageId: MESSAGE_ID_2,
        followupId: 'followup-1',
      },
      input: {
        kind: 'append',
        message: { id: MESSAGE_ID, text: 'Continue' },
      },
    });
    expect(runRequest).not.toHaveProperty('entryPoint');
  });

  it.each(['valid', 'delayed-text', 'unknown', 'duplicate', 'offset', 'after-end'] as const)(
    'handles inline table stream references: %s', async (mode) => {
      const table = { id: 't1', content: { kind: 'display', headers: ['Name', 'Network', 'Address'], notes: [],
        rows: [['Contact', 'ton', 'abcd…1234']] } };
      const reference = { tableId: mode === 'unknown' ? 't9' : 't1', textOffset: mode === 'offset' ? 1000 : 4 };
      const updates: AgentV2ClientUpdate[] = [];
      const events = [runStart(), event({ type: 'message_start', sequence: 2,
        messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown' }),
      event({ type: 'table_data', sequence: 3, messageId: MESSAGE_ID, table }),
      ...(mode === 'delayed-text' ? [event({ type: 'table_reference', sequence: 4,
        messageId: MESSAGE_ID, reference })] : []),
      event({ type: 'text_delta', sequence: 4, messageId: MESSAGE_ID, delta: '🪙\n\n' }),
      ...(mode === 'after-end' ? [event({ type: 'message_content_end', sequence: 5, messageId: MESSAGE_ID })] : []),
      ...(mode !== 'delayed-text' ? [event({ type: 'table_reference', sequence: mode === 'after-end' ? 6 : 5,
        messageId: MESSAGE_ID, reference })] : []),
      ...(mode === 'duplicate'
        ? [event({ type: 'table_reference', sequence: 6, messageId: MESSAGE_ID, reference })] : []),
      event({ type: 'text_delta', sequence: 7, messageId: MESSAGE_ID, delta: 'After' }), messageEnd(8)];
      const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
        const url = getRequestUrl(input);
        if (url.endsWith('/device-token')) {
          return Promise.resolve(jsonResponse({ protocolVersion: 3,
            deviceId: JSON.parse(init?.body as string).deviceId, deviceToken: `adt_v2.${'a'.repeat(43)}`,
            expiresAt: '2026-10-14T00:00:00.000Z' }));
        }
        if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
        if (url.endsWith('/runs')) {
          return Promise.resolve(ndjsonResponse(events.map((item, index) => ({ ...item, sequence: index + 1 }))));
        }
        return Promise.reject(new Error(`Unexpected URL ${url}`));
      }) as unknown as typeof fetch;
      const ids = [CLIENT_RUN_ID, MESSAGE_ID];
      const runtime = new AgentV2Runtime({ storage: createMemoryStorage(), baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock, onUpdate: (update) => updates.push(update), randomUuid: () => ids.shift() ?? DEVICE_ID });
      await runtime.acceptConsent();
      const result = await runtime.startRun({ threadId: THREAD_ID, expectedThreadRevision: 0,
        input: { kind: 'append', text: 'Show contacts' } });
      if (mode === 'valid' || mode === 'delayed-text') {
        expect(result.state).toBe('completed');
        expect(updates.filter(({ kind }) => kind === 'answerTablesChanged')).toEqual([
          expect.objectContaining({ tables: [table], tableReferences: [] }),
          expect.objectContaining({ tables: [table], tableReferences: [reference] }),
        ]);
        expect(updates.findIndex((update) => update.kind === 'answerTablesChanged'
          && update.tableReferences.length === 1)).toBeLessThan(
          updates.findIndex((update) => update.kind === 'textDelta' && update.delta === 'After'),
        );
      } else {
        expect(updates).toContainEqual(expect.objectContaining({ kind: 'runFailed', code: 'invalid_event' }));
      }
      await runtime.destroy();
    },
  );

  it('publishes the answer links it can place and completes the answer without the others', async () => {
    const link = { textOffset: 4, textLength: 4, url: 'https://help.mywallet.io/backup' };
    const updates: AgentV2ClientUpdate[] = [];
    const events = [runStart(), event({ type: 'message_start', sequence: 2,
      messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown' }),
    event({ type: 'text_link', sequence: 3, messageId: MESSAGE_ID, link }),
    event({ type: 'text_link', sequence: 4, messageId: MESSAGE_ID, link: { ...link, textOffset: 6 } }),
    event({ type: 'text_link', sequence: 5, messageId: MESSAGE_ID,
      link: { ...link, textOffset: 9, url: 'http://help.mywallet.io' } }),
    event({ type: 'text_delta', sequence: 6, messageId: MESSAGE_ID, delta: 'See Help or Docs' }),
    event({ type: 'message_content_end', sequence: 7, messageId: MESSAGE_ID }), messageEnd(8)];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({ protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId, deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z' }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse(events.map((item, index) => ({ ...item, sequence: index + 1 }))));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({ storage: createMemoryStorage(), baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock, onUpdate: (update) => updates.push(update), randomUuid: () => ids.shift() ?? DEVICE_ID });
    await runtime.acceptConsent();
    const result = await runtime.startRun({ threadId: THREAD_ID, expectedThreadRevision: 0,
      input: { kind: 'append', text: 'Where is the backup guide?' } });

    expect(result.state).toBe('completed');
    expect(updates.filter(({ kind }) => kind === 'answerLinkAdded'))
      .toEqual([expect.objectContaining({ messageId: MESSAGE_ID, link })]);
    expect(updates.findIndex(({ kind }) => kind === 'answerLinkAdded'))
      .toBeLessThan(updates.findIndex(({ kind }) => kind === 'textDelta'));
    await runtime.destroy();
  });

  it('publishes an operational notice atomically without text deltas', async () => {
    const content: AgentSemanticContentV1 = { kind: 'notice', schemaVersion: 1, code: 'content_over_budget' };
    const updates: AgentV2ClientUpdate[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          event({
            type: 'message_start',
            sequence: 2,
            messageId: MESSAGE_ID,
            role: 'assistant',
            contentKind: 'semantic',
          }),
          event({
            type: 'semantic_content',
            sequence: 3,
            messageId: MESSAGE_ID,
            content,
          }),
          messageEnd(4),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 0,
      input: { kind: 'append', text: 'Show my transactions' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(updates.filter(({ kind }) => kind === 'semanticContentAvailable')).toEqual([
      expect.objectContaining({
        kind: 'semanticContentAvailable',
        messageId: MESSAGE_ID,
        content,
      }),
    ]);
    expect(updates.filter(({ kind }) => kind === 'textDelta')).toEqual([]);
  });

  it('publishes semantic failure content but drops actions when the tool is unavailable', async () => {
    const content: AgentSemanticContentV1 = {
      kind: 'notice',
      schemaVersion: 1,
      code: 'agent_unavailable',
    };
    const updates: AgentV2ClientUpdate[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          event({
            type: 'message_start',
            sequence: 2,
            messageId: MESSAGE_ID,
            role: 'assistant',
            contentKind: 'semantic',
          }),
          event({
            type: 'semantic_content',
            sequence: 3,
            messageId: MESSAGE_ID,
            content,
          }),
          actionEvent(4),
          threadEvent(5),
          event({
            type: 'message_end',
            sequence: 6,
            messageId: MESSAGE_ID,
            finishReason: 'tool_unavailable',
          }),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Отправь 10 USDT маме' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(updates.filter(({ kind }) => kind === 'semanticContentAvailable')).toEqual([
      expect.objectContaining({
        kind: 'semanticContentAvailable',
        messageId: MESSAGE_ID,
        content,
      }),
    ]);
    expect(updates.some(({ kind }) => kind === 'actionAvailable')).toBe(false);
    expect(updates.filter(({ kind }) => kind === 'messageCompleted')).toEqual([
      expect.objectContaining({ finishReason: 'tool_unavailable' }),
    ]);
  });

  it('drops a pending action after an error and ignores trailing completion events', async () => {
    const updates: AgentV2ClientUpdate[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          actionEvent(3),
          event({
            type: 'error',
            sequence: 4,
            messageId: MESSAGE_ID,
            code: 'provider_unavailable',
            retryable: true,
          }),
          threadEvent(5),
          messageEnd(6),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Receive' },
    })).resolves.toMatchObject({ state: 'failed' });

    expect(updates.some(({ kind }) => kind === 'actionAvailable')).toBe(false);
    expect(updates.some(({ kind }) => kind === 'messageCompleted')).toBe(false);
    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({ kind: 'inactive' });
  });

  it('resolves a live Bitcoin Swap action against the current wallet without executing a tool', async () => {
    const walletSession = new AgentV2WalletSession();
    walletSession.update(stakeHost());
    const snapshot = walletSession.snapshot();
    const swapAction = {
      ...liveSwapAction(),
      url: 'https://my.tt/swap?in=toncoin&out=btc&amount=10',
      destinationAsset: { slug: 'btc', chain: 'bitcoin', symbol: 'BTC', decimals: 8 },
      contextBinding: {
        sessionId: snapshot.sessionId,
        revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('view-account')!,
      },
    };
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          event({ type: 'action', sequence: 3, messageId: MESSAGE_ID, action: swapAction }),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const execute = jest.fn();
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift()!,
      walletSession,
      toolExecutor: {
        execute,
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();
    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Swap 10 TON to BTC' },
    });

    expect(execute).not.toHaveBeenCalled();
    expect(runtime.resolveAction(MESSAGE_ID, swapAction.id)).toEqual({
      kind: 'openSwap',
      url: 'https://my.tt/swap?in=toncoin&out=btc&amount=10',
      tokenInSlug: 'toncoin',
      tokenOutSlug: 'btc',
      amount: '10',
      amountSide: 'source',
    });
  });

  it('revalidates a hydrated Bitcoin Swap action against the current wallet', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const persistedAction = {
      ...persistedSwapAction(),
      url: 'https://my.tt/swap?in=usdton&out=btc&amount=10',
      destinationAsset: { slug: 'btc', chain: 'bitcoin', symbol: 'BTC', decimals: 8 },
      amount: { value: '10', valueType: 'decimal' as const, side: 'source' as const },
    };
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary(),
          messages: [{
            id: MESSAGE_ID,
            threadId: THREAD_ID,
            role: 'assistant',
            status: 'complete',
            content: { kind: 'markdown', text: 'Open Swap' },
            createdAt: '2026-08-18T12:00:00.000Z',
            actions: [persistedAction],
          }],
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(stakeHost());
    await runtime.getMessages(THREAD_ID);

    expect(runtime.resolveAction(MESSAGE_ID, persistedAction.id)).toEqual({
      kind: 'openSwap',
      url: 'https://my.tt/swap?in=usdton&out=btc&amount=10',
      tokenInSlug: 'usdton',
      tokenOutSlug: 'btc',
      amount: '10',
      amountSide: 'source',
    });
    await runtime.updateHostContext({ ...stakeHost(), isTestnet: true });
    expect(runtime.resolveAction(MESSAGE_ID, persistedAction.id)).toEqual({ kind: 'inactive' });
  });

  it('keeps a hydrated Send review inactive without an in-memory draft', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const persistedAction = persistedSendAction();
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary(),
          messages: [{
            id: MESSAGE_ID,
            threadId: THREAD_ID,
            role: 'assistant',
            status: 'complete',
            content: { kind: 'markdown', text: 'Review transfer' },
            createdAt: '2026-08-18T12:00:00.000Z',
            actions: [persistedAction],
          }],
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();
    await runtime.getMessages(THREAD_ID);

    expect(runtime.getActionPresentation(MESSAGE_ID, persistedAction.id)).toEqual({ kind: 'inactive' });
  });

  it.each(['complete', 'cancelled'] as const)(
    'isolates a malformed action while preserving valid siblings and terminal %s',
    async (finishReason) => {
      const updates: AgentV2ClientUpdate[] = [];
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      const runtime = new AgentV2Runtime({
        storage,
        baseUrl: 'https://agent.test/api/v2',
        onUpdate: (update) => updates.push(update),
        fetch: jest.fn((input: string | URL | Request) => {
          if (getRequestUrl(input).includes('/hints')) return Promise.resolve(disabledHintsResponse());
          return Promise.resolve(ndjsonResponse([
            runStart(),
            event({ type: 'message_start', sequence: 2, messageId: MESSAGE_ID,
              role: 'assistant', contentKind: 'markdown' }),
            textDelta('Valid answer', 3),
            actionEvent(4),
            event({ type: 'action', sequence: 5, messageId: MESSAGE_ID, action: { kind: 'receive' } }),
            event({ type: 'message_end', sequence: 6, messageId: MESSAGE_ID, finishReason }),
          ]));
        }) as unknown as typeof fetch,
        randomUuid: () => CLIENT_RUN_ID,
      });
      await runtime.acceptConsent();
      const result = await runtime.startRun({ threadId: THREAD_ID, expectedThreadRevision: 1,
        input: { kind: 'append', text: 'Show receive' } });
      expect(result.state).toBe(finishReason === 'cancelled' ? 'cancelled' : 'failed');
      expect(updates.filter(({ kind }) => kind === 'actionAvailable'))
        .toHaveLength(finishReason === 'complete' ? 1 : 0);
      expect(updates.some(({ kind }) => kind === 'runCancelled')).toBe(finishReason === 'cancelled');
      if (finishReason === 'complete') {
        expect(updates).toContainEqual(expect.objectContaining({ kind: 'runFailed',
          code: 'invalid_event', retryable: false }));
      }
      expect(updates).toContainEqual(expect.objectContaining({ kind: 'messageCompleted',
        finishReason: finishReason === 'complete' ? 'error' : finishReason }));
    },
  );

  it.each(terminalStructuredOutputFixture.cases)(
    'executes the backend terminal fixture $id through the runtime state machine',
    async (fixtureCase) => {
      const updates: AgentV2ClientUpdate[] = [];
      const streamEvents = (fixtureCase.events as TerminalFixtureEvent[]).map((fixtureEvent) => {
        switch (fixtureEvent.type) {
          case 'run_start':
            return runStart();
          case 'message_start':
            return event({
              type: 'message_start',
              sequence: fixtureEvent.sequence,
              messageId: MESSAGE_ID,
              role: 'assistant',
              contentKind: fixtureCase.events.some(({ type }) => type === 'semantic_content')
                ? 'semantic'
                : 'markdown',
            });
          case 'text_delta':
            return textDelta(fixtureEvent.delta, fixtureEvent.sequence);
          case 'action':
            return actionEvent(fixtureEvent.sequence);
          case 'semantic_content':
            return event({
              type: 'semantic_content',
              sequence: fixtureEvent.sequence,
              messageId: MESSAGE_ID,
              content: {
                kind: 'notice',
                schemaVersion: 1,
                code: 'agent_unavailable',
              },
            });
          case 'thread':
            return threadEvent(fixtureEvent.sequence);
          case 'message_end':
            return event({
              type: 'message_end',
              sequence: fixtureEvent.sequence,
              messageId: MESSAGE_ID,
              finishReason: fixtureEvent.finishReason,
            });
          case 'error':
            return event({
              type: 'error',
              sequence: fixtureEvent.sequence,
              messageId: MESSAGE_ID,
              code: 'provider_unavailable',
              retryable: true,
            });
          default:
            return assertFixtureEvent(fixtureEvent);
        }
      });
      const fetchMock = jest.fn((input: string | URL | Request) => {
        const url = getRequestUrl(input);
        if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
        if (url.endsWith('/runs')) return Promise.resolve(ndjsonResponse(streamEvents));
        return Promise.reject(new Error(`Unexpected URL ${url}`));
      }) as unknown as typeof fetch;
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      const ids = [CLIENT_RUN_ID, MESSAGE_ID];
      const runtime = new AgentV2Runtime({
        storage,
        baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock,
        onUpdate: (update) => updates.push(update),
        randomUuid: () => ids.shift() ?? DEVICE_ID,
        toolExecutor: {
          execute: jest.fn(),
          discard: jest.fn(),
        },
      });
      await runtime.acceptConsent();

      const result = await runtime.startRun({
        threadId: THREAD_ID,
        expectedThreadRevision: 1,
        input: { kind: 'append', text: fixtureCase.id },
      });

      expect(result.state).toBe(fixtureCase.terminalOutcome === 'complete'
        ? 'completed'
        : fixtureCase.terminalOutcome === 'error'
          ? 'failed'
          : fixtureCase.terminalOutcome);
      expect(updates.filter(({ kind }) => kind === 'actionAvailable')).toHaveLength(
        fixtureCase.expectedHydration.actionIds.length,
      );
      expect(updates.filter(({ kind }) => kind === 'semanticContentAvailable')).toHaveLength(
        fixtureCase.expectedHydration.semanticContentCount,
      );
      expect(updates.filter(({ kind }) => kind === 'messageCompleted')).toHaveLength(
        fixtureCase.terminalOutcome === 'error' ? 0 : 1,
      );
    },
  );

  it('drops semantic content when text arrives after the structured bundle starts', async () => {
    const content: AgentSemanticContentV1 = {
      kind: 'notice',
      schemaVersion: 1,
      code: 'agent_unavailable',
    };
    const updates: AgentV2ClientUpdate[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          event({
            type: 'message_start',
            sequence: 2,
            messageId: MESSAGE_ID,
            role: 'assistant',
            contentKind: 'semantic',
          }),
          event({
            type: 'semantic_content',
            sequence: 3,
            messageId: MESSAGE_ID,
            content,
          }),
          textDelta('Late content', 4),
          threadEvent(5),
          messageEnd(6),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Show results' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(updates.filter(({ kind }) => kind === 'semanticContentAvailable')).toEqual([]);
    expect(updates.filter(({ kind }) => kind === 'textDelta')).toEqual([
      expect.objectContaining({
        kind: 'textDelta',
        messageId: MESSAGE_ID,
        delta: 'Late content',
      }),
    ]);
  });

  it('publishes a staged action only after a successful message end', async () => {
    const updates: AgentV2ClientUpdate[] = [];
    let markThreadChanged!: () => void;
    const threadChanged = new Promise<void>((resolve) => {
      markThreadChanged = resolve;
    });
    const stream = openNdjsonResponse([
      runStart(),
      messageStart(),
      actionEvent(3),
      threadEvent(4),
    ]);
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) return Promise.resolve(stream.response);
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'threadChanged') markThreadChanged();
      },
      randomUuid: () => ids.shift()!,
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();

    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Receive' },
    });
    await threadChanged;

    expect(updates.some(({ kind }) => kind === 'actionAvailable')).toBe(false);

    stream.finish([messageEnd(5)]);
    await expect(run).resolves.toMatchObject({ state: 'completed' });

    const actionUpdateIndex = updates.findIndex(({ kind }) => kind === 'actionAvailable');
    const completionUpdateIndex = updates.findIndex(({ kind }) => kind === 'messageCompleted');
    expect(actionUpdateIndex).toBeGreaterThan(-1);
    expect(completionUpdateIndex).toBeGreaterThan(actionUpdateIndex);
  });

  it('reconnects with the same client run and emits only safe updates', async () => {
    const storage = createMemoryStorage();
    const updates: unknown[] = [];
    const timings: ClientTimingEvent[] = [];
    const runRequests: Record<string, unknown>[] = [];
    const runHeaders: Headers[] = [];
    let runFetch = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: DEVICE_ID,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        runRequests.push(JSON.parse(init?.body as string));
        runHeaders.push(new Headers(init?.headers));
        runFetch += 1;
        return Promise.resolve(ndjsonResponse(runFetch === 1 ? [
          runStart(),
          messageStart(),
          textDelta('Hello '),
        ] : [
          textDelta('again', 4),
          threadEvent(5),
          messageEnd(6),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      telemetrySink: (batch) => timings.push(...batch),
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
      now: () => Date.parse('2026-07-16T00:00:00.000Z'),
      wait: async () => {},
    });
    await runtime.acceptConsent();

    const result = await runtime.startRun({
      expectedThreadRevision: 0,
      input: { kind: 'append', text: 'Hello' },
      entryPoint: {
        kind: 'emptyState',
        surface: 'agentTab',
        hintId: 'learn.staking',
        catalogVersion: 'agent-starter-hints-v1',
      },
    });

    expect(result).toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: MESSAGE_ID,
      state: 'completed',
    });
    expect(timings).toEqual(expect.arrayContaining([
      expect.objectContaining({ operation: 'client_reconnect_wait', outcome: 'success' }),
      expect.objectContaining({ operation: 'client_request', outcome: 'success' }),
      expect.objectContaining({ operation: 'client_first_text' }),
    ]));
    expect(timings.filter((event) => event.operation === 'client_first_text')).toHaveLength(1);
    const traceId = timings[0].traceId;
    expect(runHeaders.every((headers) => headers.get('x-agent-trace-id') === traceId)).toBe(true);
    expect(runHeaders.every((headers) => (
      /^[a-f0-9]{16}$/.test(headers.get('x-agent-parent-span-id') ?? '')
    ))).toBe(true);
    expect(JSON.stringify(timings)).not.toMatch(/Hello|adt_v2/);
    expect(runRequests).toHaveLength(2);
    expect(runRequests[0]).toMatchObject({
      input: { kind: 'append', message: { text: 'Hello' } },
      entryPoint: {
        kind: 'emptyState',
        surface: 'agentTab',
        hintId: 'learn.staking',
        catalogVersion: 'agent-starter-hints-v1',
      },
    });
    expect(runRequests[1]).toMatchObject({ clientRunId: CLIENT_RUN_ID, resumeAfterSequence: 3 });
    expect(updates.filter((update: any) => update.kind === 'runStarted')).toHaveLength(1);
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'runStarted', inputMessageId: MESSAGE_ID,
    }));
    expect(updates.filter((update: any) => update.kind === 'textDelta')).toHaveLength(2);
    expect(updates.filter((update: any) => update.runId)).toEqual(expect.arrayContaining([
      expect.objectContaining({ clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID }),
    ]));
    expect(updates.filter((update: any) => update.runId).every((update: any) => (
      update.clientRunId === CLIENT_RUN_ID && update.threadId === THREAD_ID
    ))).toBe(true);
    expect(JSON.stringify(updates)).not.toContain('adt_v2');
  });

  it('stops reconnecting when an admitted run replay has expired', async () => {
    const updates: unknown[] = [];
    const runRequests: Record<string, unknown>[] = [];
    const wait = jest.fn(() => Promise.resolve());
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: DEVICE_ID,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        runRequests.push(JSON.parse(init?.body as string));
        return Promise.resolve(runRequests.length === 1
          ? ndjsonResponse([
            runStart(),
            messageStart(),
            textDelta('Partial response'),
          ])
          : jsonResponse({
            protocolVersion: 3,
            error: {
              code: 'run_replay_expired',
              retryable: false,
            },
          }, 409));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
      wait,
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Continue' },
    })).resolves.toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      state: 'interrupted',
    });

    expect(runRequests).toHaveLength(2);
    expect(runRequests[1]).toMatchObject({
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      resumeAfterSequence: 3,
    });
    expect(wait).toHaveBeenCalledTimes(1);
    expect(updates.at(-1)).toMatchObject({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
      code: 'run_replay_expired',
      retryable: false,
    });
  });

  it('emits safe tool activity before execution and forwards the public status', async () => {
    const updates: unknown[] = [];
    let resolveExecution!: (result: AgentToolResultRequestV2) => void;
    let notifyExecutionStarted!: () => void;
    const executionStarted = new Promise<void>((resolve) => {
      notifyExecutionStarted = resolve;
    });
    const execution = new Promise<AgentToolResultRequestV2>((resolve) => {
      resolveExecution = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: DEVICE_ID,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/tool-results')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          runId: RUN_ID,
          toolCallId: TOOL_CALL_ID,
          clientToolResultId: TOOL_RESULT_ID,
          accepted: true,
          duplicate: false,
        }));
      }
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          privateToolCallEvent(2),
          toolStatusEvent(3, 'complete'),
          event({
            type: 'message_start', sequence: 4, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
          }),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const execute = jest.fn(() => {
      notifyExecutionStarted();
      return execution;
    });
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      toolExecutor: {
        execute,
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();

    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Search privately' },
    });
    await executionStarted;

    expect(execute).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ messageId: MESSAGE_ID }),
    );

    expect(updates.filter((update: any) => update.kind === 'toolActivityChanged')).toEqual([{
      kind: 'toolActivityChanged',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
      toolCallId: TOOL_CALL_ID,
      toolName: 'wallet.data.query',
      operation: 'assets.search',
      status: 'running',
    }]);

    resolveExecution({
      protocolVersion: 3,
      runId: RUN_ID,
      threadId: THREAD_ID,
      toolCallId: TOOL_CALL_ID,
      clientToolResultId: TOOL_RESULT_ID,
      completedAt: '2026-07-16T00:00:00.000Z',
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'current',
        activeNetwork: 'ton',
      },
      toolName: 'wallet.data.query',
      status: 'rejected',
      error: {
        code: 'tool_unsupported',
        retryable: false,
      },
    });
    await expect(run).resolves.toMatchObject({ state: 'completed' });

    const toolActivityUpdates = updates.filter((update: any) => update.kind === 'toolActivityChanged');
    expect(toolActivityUpdates).toEqual([
      expect.objectContaining({ toolName: 'wallet.data.query', status: 'running' }),
      expect.objectContaining({ toolName: 'wallet.data.query', status: 'complete' }),
    ]);
    expect(JSON.stringify(toolActivityUpdates)).not.toContain(PRIVATE_TOOL_ARGUMENT);
    expect(JSON.stringify(toolActivityUpdates)).not.toContain(PRIVATE_TOOL_REASON);
    expect(JSON.stringify(toolActivityUpdates)).not.toContain(PRIVATE_TOOL_STATUS_MESSAGE);
  });

  it('keeps the tool-result protocol running when a progress update cannot be delivered', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const toolResultRequests: AgentToolResultRequestV2[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/tool-results')) {
        const request = JSON.parse(init?.body as string) as AgentToolResultRequestV2;
        toolResultRequests.push(request);
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          runId: RUN_ID,
          toolCallId: TOOL_CALL_ID,
          clientToolResultId: request.clientToolResultId,
          accepted: true,
          duplicate: false,
        }));
      }
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          toolCallEvent(2),
          toolStatusEvent(3, 'complete'),
          event({
            type: 'message_start', sequence: 4, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
          }),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const execute = jest.fn((
      call: AgentToolCall,
      context: AgentV2ToolExecutionContext,
    ): Promise<AgentToolResultRequestV2> => Promise.resolve({
      protocolVersion: 3,
      runId: context.runId,
      threadId: context.threadId,
      toolCallId: call.id,
      clientToolResultId: TOOL_RESULT_ID,
      completedAt: '2026-07-16T00:00:00.000Z',
      ...(call.name === 'wallet.directory.query'
        ? { directorySession: call.directorySession, toolName: call.name }
        : { walletContextSession: call.walletContextSession, toolName: call.name }),
      status: 'rejected',
      error: { code: 'tool_unsupported', retryable: false },
    }));
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate(update) {
        if (update.kind === 'toolActivityChanged') throw new Error('update channel is unavailable');
      },
      randomUuid: () => ids.shift()!,
      toolExecutor: { execute, discard: jest.fn() },
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Search for TON' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(execute).toHaveBeenCalledTimes(1);
    expect(toolResultRequests).toHaveLength(1);
  });

  it('rejects a tool it does not know as unsupported and completes the run', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const toolResultRequests: AgentToolResultRequestV2[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/tool-results')) {
        const request = JSON.parse(init?.body as string) as AgentToolResultRequestV2;
        toolResultRequests.push(request);
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          runId: RUN_ID,
          toolCallId: TOOL_CALL_ID,
          clientToolResultId: request.clientToolResultId,
          accepted: true,
          duplicate: false,
        }));
      }
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          event({
            type: 'tool_call',
            sequence: 2,
            toolCall: {
              id: TOOL_CALL_ID,
              name: 'wallet.future.query',
              scopes: ['wallet.future.read'],
              timeoutMs: 1_000,
              futureSession: { sessionId: WALLET_SESSION_ID },
              arguments: {},
            },
          }),
          toolStatusEvent(3, 'rejected'),
          event({
            type: 'message_start', sequence: 4, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
          }),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const execute = jest.fn();
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, SNAPSHOT_INSTANCE_ID, TOOL_RESULT_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift()!,
      toolExecutor: { execute, discard: jest.fn() },
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Search for TON' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(execute).not.toHaveBeenCalled();
    expect(toolResultRequests).toEqual([{
      protocolVersion: 3,
      runId: RUN_ID,
      threadId: THREAD_ID,
      toolCallId: TOOL_CALL_ID,
      clientToolResultId: TOOL_RESULT_ID,
      toolName: 'wallet.future.query',
      status: 'rejected',
      completedAt: expect.any(String),
      error: { code: 'tool_unsupported', retryable: false },
    }]);
  });

  it.each<{ title: 'admits' | 'rejects'; source: string; command: AgentV2RunCommandInput }>([
    {
      title: 'rejects',
      source: 'a different user message',
      command: { input: { kind: 'append', text: 'Show all wallets' } },
    },
    {
      title: 'rejects',
      source: 'a regenerated request without its question',
      command: { input: { kind: 'regenerate', targetAssistantMessageId: MESSAGE_ID_3 } },
    },
    {
      title: 'rejects',
      source: 'a question other than the regenerated one',
      command: { input: { kind: 'regenerate', targetAssistantMessageId: MESSAGE_ID_3, userMessageId: MESSAGE_ID } },
    },
    {
      title: 'admits',
      source: 'the question a regenerated request answers',
      command: { input: { kind: 'regenerate', targetAssistantMessageId: MESSAGE_ID_3, userMessageId: MESSAGE_ID_2 } },
    },
  ])('$title cross-wallet intent from $source', async ({ title, command }) => {
    const isAdmitted = title === 'admits';
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let markExecutionStarted!: () => void;
    const executionStarted = new Promise<void>((resolve) => {
      markExecutionStarted = resolve;
    });
    const execute = jest.fn(() => {
      markExecutionStarted();
      return new Promise<never>(() => undefined);
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/runs')) {
        return Promise.resolve(ndjsonResponse([
          runStart(),
          event({
            type: 'tool_call',
            sequence: 2,
            toolCall: {
              id: TOOL_CALL_ID,
              name: 'wallet.data.query',
              arguments: {
                operation: 'account.inventory',
                accountSelector: { kind: 'explicitAll' },
                chains: [],
              },
              scopes: ['wallet.data.read'],
              timeoutMs: 1_000,
              walletContextSession: {
                sessionId: WALLET_SESSION_ID,
                revision: 1,
                accountScope: 'explicitAll',
                activeAccountRef: 'current',
                activeNetwork: 'ton',
              },
              intentSource: { kind: 'userMessage', messageId: MESSAGE_ID_2 },
              scopeIntent: { messageId: MESSAGE_ID_2, reason: 'explicit_all_wallet_query' },
            },
          }),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift()!,
      toolExecutor: { execute, discard: jest.fn() },
    });
    await runtime.acceptConsent();

    const run = runtime.startRun({ ...command, threadId: THREAD_ID, expectedThreadRevision: 1 });
    if (isAdmitted) {
      await Promise.race([executionStarted, run]);
      await runtime.destroy();
    }
    await expect(run).resolves.toMatchObject({ state: isAdmitted ? 'interrupted' : 'failed' });
    expect(execute).toHaveBeenCalledTimes(isAdmitted ? 1 : 0);
  });

  it('submits a timeout result when tool execution does not settle before its deadline', async () => {
    jest.useFakeTimers();
    try {
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      let executionSignal: AbortSignal | undefined;
      let resultSignal: AbortSignal | null | undefined;
      let toolResultRequest: AgentToolResultRequestV2 | undefined;
      let notifyExecutionStarted!: () => void;
      const executionStarted = new Promise<void>((resolve) => {
        notifyExecutionStarted = resolve;
      });
      const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
        const url = getRequestUrl(input);
        if (url.endsWith('/tool-results')) {
          const request = JSON.parse(init?.body as string) as AgentToolResultRequestV2;
          toolResultRequest = request;
          resultSignal = init?.signal;
          return Promise.resolve(jsonResponse({
            protocolVersion: 3,
            runId: RUN_ID,
            toolCallId: TOOL_CALL_ID,
            clientToolResultId: request.clientToolResultId,
            accepted: true,
            duplicate: false,
          }));
        }
        if (url.endsWith('/runs')) {
          return Promise.resolve(ndjsonResponse([
            runStart(),
            toolCallEvent(2),
            toolStatusEvent(3, 'complete'),
            event({
              type: 'message_start', sequence: 4, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
            }),
            messageEnd(5),
          ]));
        }
        return Promise.reject(new Error(`Unexpected URL ${url}`));
      }) as unknown as typeof fetch;
      const discard = jest.fn();
      const ids = [CLIENT_RUN_ID, MESSAGE_ID, SNAPSHOT_INSTANCE_ID, TOOL_RESULT_ID];
      const runtime = new AgentV2Runtime({
        storage,
        baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock,
        onUpdate: jest.fn(),
        randomUuid: () => ids.shift()!,
        toolExecutor: {
          execute: jest.fn((_call, context) => {
            executionSignal = context.signal;
            notifyExecutionStarted();
            return new Promise(() => undefined);
          }),
          discard,
        },
      });
      await runtime.acceptConsent();

      const run = runtime.startRun({
        threadId: THREAD_ID,
        expectedThreadRevision: 1,
        input: { kind: 'append', text: 'Search for TON' },
      });
      await executionStarted;
      await jest.advanceTimersByTimeAsync(834);

      await expect(run).resolves.toMatchObject({ state: 'completed' });
      expect(toolResultRequest).toMatchObject({
        clientToolResultId: TOOL_RESULT_ID,
        status: 'error',
        error: { code: 'tool_timeout', retryable: true },
      });
      expect(executionSignal?.aborted).toBe(true);
      expect(resultSignal).not.toBe(executionSignal);
      expect(resultSignal?.aborted).toBe(false);
      expect(discard).toHaveBeenCalledWith(TOOL_CALL_ID);
    } finally {
      jest.useRealTimers();
    }
  });

  it('retries a tool result submission that gets no response', async () => {
    // A stored identity and a fixed clock keep the short deadline to the tool result alone
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let runFetch = 0;
    let resultFetch = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/tool-results')) {
        resultFetch += 1;
        if (resultFetch === 1) {
          return new Promise<Response>((_resolve, reject) => {
            init?.signal?.addEventListener('abort', () => reject(init.signal!.reason));
          });
        }
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          runId: RUN_ID,
          toolCallId: TOOL_CALL_ID,
          clientToolResultId: TOOL_RESULT_ID,
          accepted: true,
          duplicate: false,
        }));
      }
      if (url.endsWith('/runs')) {
        runFetch += 1;
        return Promise.resolve(ndjsonResponse(runFetch === 1 ? [runStart(), toolCallEvent(2)] : [
          toolCallEvent(2),
          event({
            type: 'message_start', sequence: 3, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
          }),
          messageEnd(4),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const execute = jest.fn((
      call: AgentToolCall,
      context: AgentV2ToolExecutionContext,
    ): Promise<AgentToolResultRequestV2> => Promise.resolve({
      protocolVersion: 3,
      runId: context.runId,
      threadId: context.threadId,
      toolCallId: call.id,
      clientToolResultId: TOOL_RESULT_ID,
      completedAt: '2026-07-16T00:00:00.000Z',
      ...(call.name === 'wallet.directory.query'
        ? { directorySession: call.directorySession, toolName: call.name }
        : { walletContextSession: call.walletContextSession, toolName: call.name }),
      status: 'rejected',
      error: { code: 'tool_unsupported', retryable: false },
    }));
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      now: () => Date.parse('2026-09-22T12:00:00.000Z'),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
      requestTimeoutMs: 20,
      toolExecutor: { execute, discard: jest.fn() },
    });
    try {
      await runtime.acceptConsent();

      await expect(runtime.startRun({
        threadId: THREAD_ID,
        expectedThreadRevision: 1,
        input: { kind: 'append', text: 'Search for TON' },
      })).resolves.toMatchObject({ state: 'completed' });
      expect(resultFetch).toBe(2);
    } finally {
      await runtime.destroy();
    }
  });

  it('stops a run locally when its cancel gets no response', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    let markStarted!: () => void;
    const started = new Promise<void>((resolve) => {
      markStarted = resolve;
    });
    const stream = openNdjsonResponse([runStart(), messageStart()]);
    const unanswered = unansweredFetch();
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => (
      getRequestUrl(input).endsWith('/runs') ? Promise.resolve(stream.response) : unanswered(input, init)
    )) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'runStarted') markStarted();
      },
      now: () => Date.parse('2026-09-22T12:00:00.000Z'),
      randomUuid: () => ids.shift() ?? TOOL_RESULT_ID,
      requestTimeoutMs: 50,
    });
    try {
      await runtime.acceptConsent();
      const run = runtime.startRun({
        threadId: THREAD_ID,
        expectedThreadRevision: 1,
        input: { kind: 'append', text: 'Start response' },
      });
      await started;

      await expect(runSafeAgentV2Operation(() => runtime.cancelRun(RUN_ID)))
        .resolves.toEqual({ ok: false, error: { code: 'network_error', retryable: true } });
      stream.finish([textDelta('After the stop')]);
      await run;
      expect(updates.some((update) => update.kind === 'textDelta')).toBe(false);
    } finally {
      await runtime.destroy();
    }
  });

  it('replays a pending tool call and retries its byte-identical runtime result', async () => {
    const updates: unknown[] = [];
    const runRequests: Record<string, unknown>[] = [];
    const toolResultRequests: Record<string, unknown>[] = [];
    let runFetch = 0;
    let resultFetch = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: DEVICE_ID,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/tool-results')) {
        resultFetch += 1;
        toolResultRequests.push(JSON.parse(init?.body as string));
        if (resultFetch <= 3) return Promise.reject(new TypeError('offline'));
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          runId: RUN_ID,
          toolCallId: TOOL_CALL_ID,
          clientToolResultId: TOOL_RESULT_ID,
          accepted: true,
          duplicate: false,
        }));
      }
      if (url.endsWith('/runs')) {
        runRequests.push(JSON.parse(init?.body as string));
        runFetch += 1;
        return Promise.resolve(ndjsonResponse(runFetch === 1 ? [
          runStart(),
          toolCallEvent(2),
        ] : [
          toolCallEvent(2),
          event({
            type: 'message_start', sequence: 3, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
          }),
          messageEnd(4),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const execute = jest.fn((
      call: AgentToolCall,
      context: AgentV2ToolExecutionContext,
    ): Promise<AgentToolResultRequestV2> => {
      return Promise.resolve({
        protocolVersion: 3,
        runId: context.runId,
        threadId: context.threadId,
        toolCallId: call.id,
        clientToolResultId: TOOL_RESULT_ID,
        completedAt: '2026-07-16T00:00:00.000Z',
        ...(call.name === 'wallet.directory.query'
          ? { directorySession: call.directorySession, toolName: call.name }
          : { walletContextSession: call.walletContextSession, toolName: call.name }),
        status: 'rejected',
        error: {
          code: 'tool_unsupported',
          retryable: false,
        },
      });
    });
    const discard = jest.fn();
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
      toolExecutor: { execute, discard },
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Search for TON' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(runRequests).toHaveLength(2);
    expect(runRequests[1]).toMatchObject({ resumeAfterSequence: 1 });
    expect(execute).toHaveBeenCalledTimes(1);
    expect(updates.filter((update: any) => update.kind === 'toolActivityChanged')).toEqual([
      expect.objectContaining({ toolCallId: TOOL_CALL_ID, status: 'running' }),
    ]);
    expect(toolResultRequests).toHaveLength(4);
    expect(toolResultRequests.every((request) => (
      JSON.stringify(request) === JSON.stringify(toolResultRequests[0])
    ))).toBe(true);
    expect(discard).not.toHaveBeenCalled();
  });

  it.each(['html413', 'typedSizeError', 'errorResult413', 'conflict409', 'precondition412'] as const)(
    'recovers only explicit size refusal and preserves replacement identity through lost ACK: %s', async (failure) => {
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      const walletSession = new AgentV2WalletSession();
      const host: AgentV2HostContextSnapshot = { ...stakeHost(), timeZone: 'UTC', currencyRate: '1' };
      host.accounts[0].domainStates = { fungible: { state: 'fresh' } };
      host.accounts[0].holdings = [{ asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        balance: '7', valuationStatus: 'unpriced' }];
      walletSession.update(host);
      const snapshot = walletSession.snapshot();
      const call: AgentToolCall = {
        id: TOOL_CALL_ID, name: 'wallet.data.query', scopes: ['wallet.data.read'],
        timeoutMs: 1_000, maxResultBytes: 98_304,
        intentSource: { kind: 'userMessage', messageId: MESSAGE_ID }, arguments: {
          operation: 'positions.list', accountSelector: { kind: 'current' },
          chains: [], assetSelectors: [], positionKinds: ['fungible'], riskMode: 'all',
          visibilityMode: 'all', includeZero: false, sort: 'wallet_order', pageSize: 100,
        }, walletContextSession: {
          sessionId: snapshot.sessionId, revision: snapshot.revision, accountScope: 'current' as const,
          activeAccountRef: snapshot.accountRefs.get('view-account')!, activeNetwork: 'ton' as const,
        } };
      const updates: AgentV2ClientUpdate[] = [];
      const requests: AgentToolResultRequestV2[] = [];
      let runFetch = 0;
      const isSizeFailure = failure === 'html413' || failure === 'typedSizeError' || failure === 'errorResult413';
      const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => Promise.resolve().then(() => {
        const url = getRequestUrl(input);
        if (url.includes('/hints')) return disabledHintsResponse();
        if (url.endsWith('/capabilities')) return featureCapabilitiesResponse('available');
        if (url.endsWith('/tool-results')) {
          const result = JSON.parse(init!.body as string) as AgentToolResultRequestV2;
          requests.push(result);
          if (requests.length === 1 || failure === 'errorResult413') {
            if (failure === 'typedSizeError') {
              return jsonResponse({ protocolVersion: 3,
                error: { code: 'tool_result_too_large', retryable: false } }, 400);
            }
            if (failure === 'conflict409') {
              return jsonResponse({ protocolVersion: 3, error: { code: 'invalid_request', retryable: false } }, 409);
            }
            return { ...jsonResponse({}, isSizeFailure ? 413 : 412),
              json: () => Promise.reject(new SyntaxError('Unexpected HTML')) };
          }
          if (requests.length <= 4) throw new TypeError('offline');
          return jsonResponse({ protocolVersion: 3, runId: RUN_ID, toolCallId: TOOL_CALL_ID,
            clientToolResultId: result.clientToolResultId, accepted: true, duplicate: true });
        }
        if (url.endsWith('/runs')) {
          runFetch += 1;
          return ndjsonResponse(runFetch === 1 ? [
            runStart(),
            event({ type: 'message_start', sequence: 2, messageId: MESSAGE_ID,
              role: 'assistant', contentKind: 'markdown' }),
            event({ type: 'text_delta', sequence: 3, messageId: MESSAGE_ID, delta: 'Already visible answer.' }),
            event({ type: 'tool_call', sequence: 4, toolCall: call }),
            messageEnd(5),
          ] : [event({ type: 'tool_call', sequence: 4, toolCall: call }), messageEnd(5)]);
        }
        throw new Error(`Unexpected URL ${url}`);
      }));
      const ids = [CLIENT_RUN_ID, MESSAGE_ID, SNAPSHOT_INSTANCE_ID, CLIENT_RUN_ID_2];
      const dispatcher = new AgentV2WalletToolDispatcher({
        session: walletSession, getConsent: () => Promise.resolve(true), randomUuid: () => TOOL_RESULT_ID,
      });
      const execute = jest.fn(dispatcher.execute.bind(dispatcher));
      const discard = jest.fn();
      const runtime = new AgentV2Runtime({
        storage, baseUrl: 'https://agent.test/api/v2', fetch: fetchMock,
        onUpdate: (update) => updates.push(update), walletSession,
        randomUuid: () => ids.shift()!, wait: () => Promise.resolve(), toolExecutor: { execute, discard },
      });
      try {
        await runtime.acceptConsent();
        const outcome = await runtime.startRun({ threadId: THREAD_ID, expectedThreadRevision: 1,
          input: { kind: 'append', text: 'Find TON' } });
        expect(outcome).toMatchObject({
          state: isSizeFailure && failure !== 'errorResult413' ? 'completed' : 'failed',
        });
        expect(execute).toHaveBeenCalledTimes(1);
        expect(requests[0].status).toBe('success');
        expect(requests).toHaveLength(isSizeFailure ? (failure === 'errorResult413' ? 2 : 5) : 1);
        expect(JSON.stringify(updates)).toContain('Already visible answer.');
        if (isSizeFailure) {
          expect(runFetch).toBe(failure === 'errorResult413' ? 1 : 2);
          expect(requests[1]).toMatchObject({
            toolCallId: call.id, walletContextSession: call.walletContextSession,
            status: 'error', error: { code: 'result_too_large', retryable: false },
          });
          expect(requests[1]).not.toHaveProperty('result');
          expect(requests[1].clientToolResultId).not.toBe(requests[0].clientToolResultId);
          expect(requests.slice(1).every((value) => JSON.stringify(value) === JSON.stringify(requests[1]))).toBe(true);
          expect(discard).toHaveBeenCalledWith(call.id);
        }
      } finally {
        await runtime.destroy();
      }
    },
  );

  it('discards an unacknowledged tool result after an invalid acknowledgement', async () => {
    const updates: unknown[] = [];
    const rawResultMarker = 'PRIVATE_WALLET_RESULT';
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/tool-results')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          runId: RUN_ID,
          toolCallId: TOOL_CALL_ID,
          clientToolResultId: '77777777-7777-4777-8777-777777777778',
          accepted: true,
          duplicate: false,
        }));
      }
      return Promise.resolve(ndjsonResponse([runStart(), toolCallEvent(2)]));
    }) as unknown as typeof fetch;
    const execute = jest.fn((
      call: AgentToolCall,
      context: AgentV2ToolExecutionContext,
    ): Promise<AgentToolResultRequestV2> => Promise.resolve({
      protocolVersion: 3,
      runId: context.runId,
      threadId: context.threadId,
      toolCallId: call.id,
      clientToolResultId: TOOL_RESULT_ID,
      completedAt: '2026-07-16T00:00:00.000Z',
      ...(call.name === 'wallet.directory.query'
        ? { directorySession: call.directorySession, toolName: call.name }
        : { walletContextSession: call.walletContextSession, toolName: call.name }),
      status: 'rejected',
      error: {
        code: 'tool_failed',
        retryable: false,
      },
    }));
    const discard = jest.fn();
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
      toolExecutor: { execute, discard },
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Search for TON' },
    })).resolves.toMatchObject({ state: 'failed' });

    expect(discard).toHaveBeenCalledTimes(1);
    expect(discard).toHaveBeenCalledWith(TOOL_CALL_ID);
    expect(JSON.stringify(updates)).not.toContain(rawResultMarker);
  });

  it('keeps independent threads streaming while another thread completes in the background', async () => {
    const storage = createMemoryStorage();
    await storage.setItem('agentV2DeviceIdentity', JSON.stringify({
      version: 1,
      deviceId: DEVICE_ID,
      deviceToken: `adt_v2.${'a'.repeat(43)}`,
      expiresAt: '2026-10-14T00:00:00.000Z',
    }));
    const firstStream = openNdjsonResponse([
      boundEvent(RUN_ID, {
        type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1,
      }),
      boundEvent(RUN_ID, {
        type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
      }),
      boundEvent(RUN_ID, { type: 'text_delta', sequence: 3, messageId: MESSAGE_ID, delta: 'Still running' }),
    ]);
    const updates: any[] = [];
    let markFirstText!: () => void;
    const firstTextSeen = new Promise<void>((resolve) => {
      markFirstText = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const body = JSON.parse(init?.body as string);
      if (body.threadId === THREAD_ID) return Promise.resolve(firstStream.response);
      return Promise.resolve(ndjsonResponse([
        boundEvent(RUN_ID_2, {
          type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID_2, threadId: THREAD_ID_2, threadRevision: 1,
        }),
        boundEvent(RUN_ID_2, {
          type: 'message_start', sequence: 2, messageId: MESSAGE_ID_2, role: 'assistant', contentKind: 'markdown',
        }),
        boundEvent(RUN_ID_2, { type: 'text_delta', sequence: 3, messageId: MESSAGE_ID_2, delta: 'Done' }),
        boundEvent(RUN_ID_2, { type: 'message_end', sequence: 4, messageId: MESSAGE_ID_2, finishReason: 'complete' }),
      ]));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, CLIENT_RUN_ID_2, MESSAGE_ID_2];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'textDelta' && update.clientRunId === CLIENT_RUN_ID) markFirstText();
      },
      randomUuid: () => ids.shift()!,
    });
    await runtime.acceptConsent();

    let firstSettled = false;
    const first = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'First' },
    }).finally(() => {
      firstSettled = true;
    });
    const second = runtime.startRun({
      threadId: THREAD_ID_2,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Second' },
    });

    await firstTextSeen;
    await expect(second).resolves.toMatchObject({ clientRunId: CLIENT_RUN_ID_2, state: 'completed' });
    expect(firstSettled).toBe(false);
    firstStream.finish([
      boundEvent(RUN_ID, { type: 'message_end', sequence: 4, messageId: MESSAGE_ID, finishReason: 'complete' }),
    ]);
    await expect(first).resolves.toMatchObject({ clientRunId: CLIENT_RUN_ID, state: 'completed' });
    expect(updates.filter((update) => update.kind === 'textDelta')).toEqual(expect.arrayContaining([
      expect.objectContaining({ clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, delta: 'Still running' }),
      expect.objectContaining({ clientRunId: CLIENT_RUN_ID_2, threadId: THREAD_ID_2, delta: 'Done' }),
    ]));
  });

  it('degrades an incompatible critical host context to no-wallet and accepts recovery', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let requestBody: any;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        requestBody = JSON.parse(init?.body as string);
        return Promise.resolve(ndjsonResponse([runStart(), messageStart(), messageEnd(3)]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID];
        return () => values.shift()!;
      })(),
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    const incompatibleHost = {
      ...receiveHost('tron'),
      accounts: undefined,
    } as unknown as AgentV2HostContextSnapshot;
    await expect(runtime.updateHostContext(incompatibleHost)).resolves.toBe(true);
    await expect(runtime.startRun({
      expectedThreadRevision: 0,
      input: { kind: 'append', text: 'Explain staking' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(requestBody.walletContext).toEqual({ mode: 'none', reason: 'noWallet' });
    expect(requestBody).not.toHaveProperty('walletBucketHash');
    expect(requestBody.capabilities.features).toEqual([]);

    await expect(runtime.updateHostContext(receiveHost('tron'))).resolves.toBe(true);
    const internals = runtime as unknown as { walletSession: AgentV2WalletSession };
    expect(internals.walletSession.buildContext().walletContext).toMatchObject({
      mode: 'wallet',
      activeNetwork: 'tron',
    });
    await runtime.destroy();
  });

  it('keeps Receive valid across unrelated revisions and rejects relevant authority drift', async () => {
    const storage = createMemoryStorage();
    let requestBody: any;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        const body = JSON.parse(init?.body as string);
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: body.deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        requestBody = JSON.parse(init?.body as string);
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          event({
            type: 'action',
            sequence: 3,
            messageId: MESSAGE_ID,
            action: {
              id: '66666666-6666-4666-8666-666666666666',
              kind: 'receive',
              labelCode: 'open_receive',
              title: 'Review prepared action',
              effect: 'open_receive',
              contextBinding: {
                sessionId: requestBody.walletContext.sessionId,
                revision: requestBody.walletContext.revision,
                activeAccountRef: requestBody.walletContext.activeAccount.accountRef,
                activeNetwork: 'ton',
              },
              localDraftRequired: false,
              requiresConfirmation: false,
            },
          }),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: () => {},
      wait: () => Promise.resolve(),
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
    });
    await runtime.acceptConsent();
    const host = receiveHost('ton');
    await expect(runtime.updateHostContext(host)).resolves.toBe(true);
    await expect(runtime.updateHostContext({ ...host, theme: 'dark' })).resolves.toBe(false);
    await runtime.startRun({ expectedThreadRevision: 0, input: { kind: 'append', text: 'Receive' } });

    expect(runtime.resolveAction(MESSAGE_ID, '66666666-6666-4666-8666-666666666666')).toEqual({
      kind: 'openReceive', chain: 'ton',
    });
    await expect(runtime.updateHostContext({
      ...host,
    })).resolves.toBe(false);
    expect(runtime.resolveAction(MESSAGE_ID, '66666666-6666-4666-8666-666666666666')).toEqual({
      kind: 'openReceive', chain: 'ton',
    });
    await runtime.updateHostContext(receiveHost('tron'));
    expect(runtime.resolveAction(MESSAGE_ID, '66666666-6666-4666-8666-666666666666'))
      .toEqual({ kind: 'inactive' });
  });

  it('opens Staking only from a live action bound to the current local eligibility', async () => {
    const storage = createMemoryStorage();
    let requestBody: any;
    const actionId = '69696969-6969-4969-8969-696969696969';
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        const body = JSON.parse(init?.body as string);
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: body.deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        requestBody = JSON.parse(init?.body as string);
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          event({
            type: 'action',
            sequence: 3,
            messageId: MESSAGE_ID,
            action: {
              id: actionId,
              schemaVersion: 2,
              kind: 'stake',
              labelCode: 'open_staking',
              title: 'Review prepared action',
              effect: 'open_staking',
              contextBinding: {
                sessionId: requestBody.walletContext.sessionId,
                revision: requestBody.walletContext.revision,
                activeAccountRef: requestBody.walletContext.activeAccount.accountRef,
              },
              productId: 'liquid',
              asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
              amount: { kind: 'exact', value: '10' },
              localDraftRequired: false,
              requiresConfirmation: false,
            },
          }),
          threadEvent(4),
          messageEnd(5),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: () => {},
      wait: () => Promise.resolve(),
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
    });
    await runtime.acceptConsent();
    const host = {
      ...stakeHost(), platform: 'ios' as const, uiCapabilities: hostUiCapabilities('ios'), client: 'native' as const,
    };
    await expect(runtime.updateHostContext(host)).resolves.toBe(true);
    await runtime.startRun({ expectedThreadRevision: 0, input: { kind: 'append', text: 'Stake' } });

    expect(requestBody).not.toHaveProperty('walletBucketHash');
    expect(requestBody.capabilities.supportedActions).toContain('stake');
    expect(requestBody.walletContext.activeAccount.supportedActions).toContain('stake');
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    });

    const refreshedHost = {
      ...host,
    };
    await expect(runtime.updateHostContext(refreshedHost)).resolves.toBe(false);
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    });

    await expect(runtime.updateHostContext({
      ...refreshedHost,
      platform: 'android', uiCapabilities: hostUiCapabilities('android'),
    })).resolves.toBe(false);
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    });

    await expect(runtime.updateHostContext({
      ...refreshedHost,
      accounts: [...refreshedHost.accounts, {
        ...refreshedHost.accounts[0],
        accountId: 'secondary-account',
        addresses: { ton: 'EQ-secondary-address' },
      }],
      activeAccountId: 'secondary-account',
    })).resolves.toBe(true);
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    });

    await expect(runtime.updateHostContext(refreshedHost)).resolves.toBe(true);

    await expect(runtime.updateHostContext({
      ...refreshedHost,
      accounts: [...refreshedHost.accounts, {
        ...refreshedHost.accounts[0],
        accountId: 'view-only-account',
        accountType: 'viewOnly' as const,
        isViewOnly: true,
        addresses: { ton: 'EQ-view-only-address' },
      }],
      activeAccountId: 'view-only-account',
    })).resolves.toBe(true);
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({ kind: 'inactive' });

    await expect(runtime.updateHostContext(refreshedHost)).resolves.toBe(true);
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    });

    const ineligibleHost = { ...refreshedHost, isStakingDisabled: true };
    await expect(runtime.updateHostContext(ineligibleHost)).resolves.toBe(false);
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({ kind: 'inactive' });

    await expect(runtime.updateHostContext(refreshedHost)).resolves.toBe(false);
    expect(runtime.resolveAction(MESSAGE_ID, actionId)).toEqual({
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    });
  });

  it('revalidates current local staking eligibility for a hydrated action', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const walletSession = new AgentV2WalletSession();
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary(),
          messages: [{
            id: MESSAGE_ID,
            threadId: THREAD_ID,
            role: 'assistant',
            status: 'complete',
            content: { kind: 'markdown', text: 'Open Staking' },
            createdAt: '2026-08-13T12:00:00.000Z',
            actions: [{
              id: TOOL_CALL_ID,
              schemaVersion: 2,
              kind: 'stake',
              labelCode: 'open_staking',
              title: 'Review prepared action',
              effect: 'open_staking',
              productId: 'liquid',
              asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
              amount: { kind: 'all' },
              localDraftRequired: false,
              requiresConfirmation: false,
            }],
          }],
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      walletSession,
    });
    await runtime.acceptConsent();
    const host = stakeHost();
    await runtime.updateHostContext(host);
    await runtime.getMessages(THREAD_ID);

    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'all' },
    });

    await runtime.updateHostContext({
      ...host,
      isStakingDisabled: true,
    });
    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({ kind: 'inactive' });

    const ineligibleHost = { ...host, accounts: host.accounts.map((account) => ({ ...account, isViewOnly: true })) };
    await runtime.updateHostContext(ineligibleHost);
    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({ kind: 'inactive' });
  });

  it('opens targeted Receive V3 on an inactive account-supported network', async () => {
    const storage = createMemoryStorage();
    let requestBody: any;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        const body = JSON.parse(init?.body as string);
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: body.deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        requestBody = JSON.parse(init?.body as string);
        return Promise.resolve(ndjsonResponse([
          runStart(),
          messageStart(),
          event({
            type: 'action',
            sequence: 3,
            messageId: MESSAGE_ID,
            action: {
              id: '67676767-6767-4767-8767-676767676767',
              schemaVersion: 3,
              kind: 'receive',
              labelCode: 'open_receive',
              title: 'Review prepared action',
              effect: 'open_receive',
              contextBinding: {
                sessionId: requestBody.walletContext.sessionId,
                revision: requestBody.walletContext.revision,
                activeAccountRef: requestBody.walletContext.activeAccount.accountRef,
                activeNetwork: 'tron',
              },
              targetNetwork: 'ton',
              localDraftRequired: false,
              requiresConfirmation: false,
            },
          }),
          event({
            type: 'action',
            sequence: 4,
            messageId: MESSAGE_ID,
            action: {
              id: '68686868-6868-4868-8868-686868686868',
              schemaVersion: 3,
              kind: 'receive',
              labelCode: 'open_receive',
              title: 'Review prepared action',
              effect: 'open_receive',
              contextBinding: {
                sessionId: requestBody.walletContext.sessionId,
                revision: requestBody.walletContext.revision,
                activeAccountRef: requestBody.walletContext.activeAccount.accountRef,
                activeNetwork: 'tron',
              },
              targetNetwork: 'bitcoin',
              localDraftRequired: false,
              requiresConfirmation: false,
            },
          }),
          threadEvent(5),
          messageEnd(6),
        ]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: () => {},
      wait: () => Promise.resolve(),
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('tron', false));
    await runtime.startRun({ expectedThreadRevision: 0, input: { kind: 'append', text: 'Receive GRAM' } });

    expect(runtime.resolveAction(MESSAGE_ID, '67676767-6767-4767-8767-676767676767')).toEqual({
      kind: 'openReceive', chain: 'ton',
    });
    expect(runtime.resolveAction(MESSAGE_ID, '68686868-6868-4868-8868-686868686868'))
      .toEqual({ kind: 'inactive' });
  });

  it('preserves a targeted Receive network through message hydration', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const walletSession = new AgentV2WalletSession();
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary(),
          messages: [{
            id: MESSAGE_ID,
            threadId: THREAD_ID,
            role: 'assistant',
            status: 'complete',
            content: { kind: 'markdown', text: 'Receive on TRON' },
            createdAt: '2026-08-13T12:00:00.000Z',
            actions: [{
              id: TOOL_CALL_ID,
              schemaVersion: 3,
              kind: 'receive',
              labelCode: 'open_receive',
              title: 'Review prepared action',
              effect: 'open_receive',
              targetNetwork: 'tron',
              localDraftRequired: false,
              requiresConfirmation: false,
            }],
          }],
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      walletSession,
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton', false));

    await runtime.getMessages(THREAD_ID);

    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({
      kind: 'openReceive', chain: 'tron',
    });
    expect(walletSession.snapshot().host?.activeNetwork).toBe('ton');

    await runtime.updateHostContext(receiveHost('ton'));
    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({ kind: 'inactive' });
  });

  it('invalidates thread-bound local actions before edit or regenerate admission', async () => {
    const clear = jest.fn();
    const updates: any[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      return Promise.resolve(ndjsonResponse([
        runStart(),
        messageStart(),
        messageEnd(3),
      ]));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
        clear,
      },
    });
    await runtime.acceptConsent();

    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'edit', targetUserMessageId: MESSAGE_ID_2, text: 'Edited' },
    });

    expect(clear).toHaveBeenCalledWith(THREAD_ID);
    expect(updates).toContainEqual({ kind: 'walletAuthorityChanged', threadId: THREAD_ID });
  });

  it('announces wallet selection without retiring the active response', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    let markTextReceived!: () => void;
    const textReceived = new Promise<void>((resolve) => {
      markTextReceived = resolve;
    });
    const stream = openNdjsonResponse([runStart(), messageStart(), textDelta('Before')]);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) return Promise.resolve(stream.response);
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    });
    const runtime = new AgentV2Runtime({
      storage,
      randomUuid: () => CLIENT_RUN_ID,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock as unknown as typeof fetch,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'textDelta') markTextReceived();
      },
      walletSession: new AgentV2WalletSession({ randomUuid: () => WALLET_SESSION_ID }),
    });
    const host = receiveHost('ton');
    host.accounts.push({
      ...host.accounts[0],
      accountId: 'secondary-account',
      addresses: { ton: 'EQ-secondary', tron: 'T-secondary' },
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(host);
    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Start response' },
    });
    await textReceived;
    updates.length = 0;

    await runtime.updateHostContext({ ...host, activeAccountId: 'secondary-account' });
    expect(updates).toEqual([{ kind: 'walletAuthorityChanged', preservesActiveRuns: true }]);
    stream.finish([textDelta(' after', 4), actionEvent(5), messageEnd(6)]);
    await expect(run).resolves.toMatchObject({ state: 'completed' });
    expect(updates).toContainEqual(expect.objectContaining({ kind: 'textDelta', delta: ' after' }));
    expect(updates).toContainEqual(expect.objectContaining({ kind: 'messageCompleted', finishReason: 'complete' }));
    expect(updates).toContainEqual(expect.objectContaining({ kind: 'actionAvailable', messageId: MESSAGE_ID }));
    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({ kind: 'openReceive', chain: 'ton' });
    expect(fetchMock.mock.calls.some(([input]) => getRequestUrl(input).endsWith('/cancel'))).toBe(false);
    await runtime.destroy();
  });

  it('establishes the local authority barrier before remote cancellation settles', async () => {
    let resolveCancel!: () => void;
    const cancelPending = new Promise<void>((resolve) => {
      resolveCancel = resolve;
    });
    const discard = jest.fn();
    const clear = jest.fn();
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: jest.fn() as unknown as typeof fetch,
      onUpdate: jest.fn(),
      toolExecutor: {
        execute: jest.fn(),
        discard,
        clear,
      },
    });
    const host = receiveHost('ton');
    await runtime.updateHostContext({
      ...host,
      accounts: [...host.accounts, {
        ...host.accounts[0],
        accountId: 'secondary-account',
        addresses: { ton: 'EQ-secondary-address' },
      }],
    });
    clear.mockClear();

    const controller = new AbortController();
    const pendingToolCallIds = new Set([TOOL_CALL_ID]);
    const pendingToolResults = new Map([
      [TOOL_CALL_ID, { toolCallId: TOOL_CALL_ID } as AgentToolResultRequestV2],
    ]);
    const internals = runtime as unknown as {
      cancelRunRemotely: (runId: string) => Promise<void>;
      runs: Map<string, {
        binding: { runId: string };
        controller: AbortController;
        pendingToolCallIds: Set<string>;
        pendingToolResults: Map<string, AgentToolResultRequestV2>;
      }>;
    };
    const cancelRunRemotely = jest.fn(() => cancelPending);
    internals.cancelRunRemotely = cancelRunRemotely;
    internals.runs.set(CLIENT_RUN_ID, {
      binding: { runId: RUN_ID },
      controller,
      pendingToolCallIds,
      pendingToolResults,
    });

    await runtime.updateHostContext({
      ...host,
      accounts: host.accounts.map((account) => (
        account.accountId === host.activeAccountId
          ? { ...account, addresses: { ...account.addresses, ton: 'EQ-new-active-address' } }
          : account
      )),
    });

    expect(controller.signal.aborted).toBe(true);
    expect(pendingToolCallIds.size).toBe(0);
    expect(pendingToolResults.size).toBe(0);
    expect(discard).toHaveBeenCalledWith(TOOL_CALL_ID);
    expect(cancelRunRemotely).toHaveBeenCalledWith(RUN_ID);
    expect(clear).toHaveBeenCalledWith();

    resolveCancel();
    await Promise.resolve();
  });

  it.each(['direct', 'background'] as const)(
    'applies the authoritative thread returned by %s cancellation',
    async (cancellationKind) => {
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      const thread = threadSummary({ revision: 3, messageCount: 2 });
      const updates: AgentV2ClientUpdate[] = [];
      const fetchMock = jest.fn(() => Promise.resolve(jsonResponse({
        protocolVersion: 3,
        runId: RUN_ID,
        state: 'cancelled',
        lastSequence: 5,
        thread,
      }))) as unknown as typeof fetch;
      const runtime = new AgentV2Runtime({
        storage,
        baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock,
        onUpdate: (update) => updates.push(update),
        randomUuid: () => CLIENT_RUN_ID,
      });

      if (cancellationKind === 'direct') {
        await expect(runtime.cancelRun(RUN_ID)).resolves.toMatchObject({ thread });
      } else {
        const internals = runtime as unknown as {
          cancelRunRemotely: (runId: string) => Promise<void>;
        };
        await internals.cancelRunRemotely(RUN_ID);
      }

      expect(updates).toEqual([{ kind: 'threadChanged', threadId: THREAD_ID, thread }]);
      await runtime.destroy();
    },
  );

  it('ignores late stream output after an authority change without waiting for remote cancellation', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    let markThreadChanged!: () => void;
    const threadChanged = new Promise<void>((resolve) => {
      markThreadChanged = resolve;
    });
    let resolveCancel!: () => void;
    const cancelPending = new Promise<void>((resolve) => {
      resolveCancel = resolve;
    });
    const stream = openNdjsonResponse([
      runStart(),
      messageStart(),
      actionEvent(3),
      threadEvent(4),
    ]);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) return Promise.resolve(stream.response);
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'threadChanged') markThreadChanged();
      },
      randomUuid: () => ids.shift() ?? DEVICE_ID,
      toolExecutor: {
        execute: jest.fn(),
        discard: jest.fn(),
      },
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));
    const internals = runtime as unknown as {
      cancelRunRemotely: (runId: string) => Promise<void>;
    };
    const cancelRunRemotely = jest.fn(() => cancelPending);
    internals.cancelRunRemotely = cancelRunRemotely;

    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Receive' },
    });
    await threadChanged;
    const updatesBeforeSwitch = updates.length;

    await expect(runtime.updateHostContext(receiveHost('tron'))).resolves.toBe(true);
    expect(cancelRunRemotely).toHaveBeenCalledWith(RUN_ID);
    stream.finish([messageEnd(5)]);

    await expect(run).resolves.toMatchObject({ state: 'cancelled', inputMessageId: MESSAGE_ID });
    expect(updates.slice(updatesBeforeSwitch).map(({ kind }) => kind)).toEqual([
      'walletAuthorityChanged',
    ]);

    resolveCancel();
    await Promise.resolve();
  });

  it('continues an active run when the local swap policy changes', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    let markThreadChanged!: () => void;
    const threadChanged = new Promise<void>((resolve) => {
      markThreadChanged = resolve;
    });
    const stream = openNdjsonResponse([
      runStart(),
      messageStart(),
      threadEvent(3),
    ]);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) return Promise.resolve(stream.response);
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        updates.push(update);
        if (update.kind === 'threadChanged') markThreadChanged();
      },
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
    });
    await runtime.acceptConsent();
    const host = {
      ...receiveHost('ton', false),
      isTestnet: false,
      swapAssetCatalog: [
        { slug: 'toncoin', chain: 'ton' as const, symbol: 'TON', decimals: 9 },
        { slug: 'usdton', chain: 'ton' as const, symbol: 'USDT', decimals: 6 },
      ],
    };
    await runtime.updateHostContext(host);

    const run = runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Explain swaps' },
    });
    await threadChanged;
    const updatesBeforeRefresh = updates.length;

    await expect(runtime.updateHostContext({
      ...host,
      swapAssetCatalog: host.swapAssetCatalog.slice(0, 1),
    })).resolves.toBe(false);
    stream.finish([textDelta('Answer', 4), messageContentEnd(5), messageEnd(6)]);

    await expect(run).resolves.toMatchObject({ state: 'completed' });
    expect(updates.slice(updatesBeforeRefresh)).toEqual(expect.arrayContaining([
      expect.objectContaining({ kind: 'textDelta', delta: 'Answer' }),
      expect.objectContaining({ kind: 'messageContentEnded', messageId: MESSAGE_ID }),
      expect.objectContaining({ kind: 'messageCompleted' }),
    ]));
    expect(updates.findIndex(({ kind }) => kind === 'messageContentEnded'))
      .toBeLessThan(updates.findIndex(({ kind }) => kind === 'messageCompleted'));
  });

  it('rejects delayed message hydration before it restores persisted actions after authority change', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let resolveMessages!: (response: Response) => void;
    let markMessagesRequested!: () => void;
    const messagesRequested = new Promise<void>((resolve) => {
      markMessagesRequested = resolve;
    });
    const messagesPending = new Promise<Response>((resolve) => {
      resolveMessages = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        markMessagesRequested();
        return messagesPending;
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));

    const hydration = runtime.getMessages(THREAD_ID);
    await messagesRequested;
    await runtime.updateHostContext(receiveHost('tron'));
    resolveMessages(jsonResponse({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        id: MESSAGE_ID,
        threadId: THREAD_ID,
        role: 'assistant',
        status: 'complete',
        content: { kind: 'markdown', text: 'Receive' },
        createdAt: '2026-08-11T12:00:00.000Z',
        actions: [{
          id: TOOL_CALL_ID,
          kind: 'receive',
          labelCode: 'open_receive',
          title: 'Review prepared action',
          effect: 'open_receive',
          localDraftRequired: false,
          requiresConfirmation: false,
        }],
      }],
    }));

    await expect(hydration).rejects.toMatchObject({ code: 'wallet_context_changed' });
    expect(runtime.resolveAction(MESSAGE_ID, TOOL_CALL_ID)).toEqual({ kind: 'inactive' });
  });

  it('does not restore actions from delayed message hydration after the thread is cleared', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    let resolveMessages!: (response: Response) => void;
    let markMessagesRequested!: () => void;
    const messagesRequested = new Promise<void>((resolve) => {
      markMessagesRequested = resolve;
    });
    const messagesPending = new Promise<Response>((resolve) => {
      resolveMessages = resolve;
    });
    const action = {
      id: TOOL_CALL_ID,
      schemaVersion: 3 as const,
      kind: 'openUrl' as const,
      labelCode: 'open_external_link' as const,
      title: 'Review prepared action',
      url: 'https://example.com/help',
      requiresConfirmation: true,
    };
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        markMessagesRequested();
        return messagesPending;
      }
      if (url.endsWith(`/threads/${THREAD_ID}/clear`)) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary({ revision: 2 }),
          duplicate: false,
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();

    const hydration = runtime.getMessages(THREAD_ID);
    await messagesRequested;
    await runtime.clearThread(THREAD_ID, 1);
    resolveMessages(jsonResponse({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        id: MESSAGE_ID,
        threadId: THREAD_ID,
        role: 'assistant',
        status: 'complete',
        content: { kind: 'markdown', text: 'Open help' },
        createdAt: '2026-08-11T12:00:00.000Z',
        actions: [action],
      }],
    }));

    await expect(hydration).rejects.toMatchObject({ code: 'invalid_event' });
    expect(runtime.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
  });

  it('hydrates executable V3 navigation targets', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const persistedActions = navigationActionFixture.projectionCases
      .map(({ expectedPersisted }) => ({ ...expectedPersisted, title: 'Review prepared action' }));
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary(),
          messages: [{
            id: MESSAGE_ID,
            threadId: THREAD_ID,
            role: 'assistant',
            status: 'complete',
            content: { kind: 'markdown', text: 'Open' },
            createdAt: '2026-08-11T12:00:00.000Z',
            actions: persistedActions,
          }],
        }));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();
    const host: AgentV2HostContextSnapshot = { ...receiveHost('ton'), isTestnet: false };
    await runtime.updateHostContext(host);

    await runtime.getMessages(THREAD_ID);

    expect(persistedActions.map(({ id }) => runtime.resolveAction(MESSAGE_ID, id))).toEqual([
      { kind: 'openDapp', url: 'https://fragment.com/' },
    ]);

    await runtime.updateHostContext({
      ...host,
      swapAssetCatalog: [
        { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        { slug: 'usdton', chain: 'ton', symbol: 'USDT', decimals: 6 },
      ],
    });
    expect(runtime.resolveAction(MESSAGE_ID, persistedActions[0].id)).toEqual({
      kind: 'openDapp', url: 'https://fragment.com/',
    });
  });

  it('rejects retry admission when wallet authority changes during capability setup', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const runRequests: unknown[] = [];
    let now = Date.now();
    let resolveCapabilities!: (response: Response) => void;
    let markCapabilitiesStarted!: () => void;
    const capabilitiesStarted = new Promise<void>((resolve) => {
      markCapabilitiesStarted = resolve;
    });
    const capabilitiesPending = new Promise<Response>((resolve) => {
      resolveCapabilities = resolve;
    });
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/capabilities')) {
        if (!runRequests.length) return Promise.resolve(featureCapabilitiesResponse('disabled'));
        markCapabilitiesStarted();
        return capabilitiesPending;
      }
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        runRequests.push(JSON.parse(init?.body as string));
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          error: {
            code: 'rate_limited',
            retryable: true,
            retryAfterMs: 5_000,
          },
        }, 429));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      now: () => now,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift() ?? DEVICE_ID,
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(receiveHost('ton'));
    await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Retry me' },
    });

    now += 5 * 60_000;
    const retry = runtime.retryRun(CLIENT_RUN_ID);
    await capabilitiesStarted;
    await runtime.updateHostContext(receiveHost('tron'));
    resolveCapabilities(featureCapabilitiesResponse('disabled'));

    await expect(retry).rejects.toMatchObject({
      code: 'wallet_context_changed',
      retryable: false,
    });
    expect(runRequests).toHaveLength(1);
  });

  it('bounds best-effort remote cancellation to three seconds', async () => {
    jest.useFakeTimers();
    try {
      const storage = createMemoryStorage();
      await storeIdentity(storage);
      const fetchMock = jest.fn((_input: string | URL | Request, init?: RequestInit) => (
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () => reject(init.signal?.reason), { once: true });
        })
      )) as unknown as typeof fetch;
      const runtime = new AgentV2Runtime({
        storage,
        baseUrl: 'https://agent.test/api/v2',
        fetch: fetchMock,
        onUpdate: jest.fn(),
      });
      const internals = runtime as unknown as {
        cancelRunRemotely: (runId: string) => Promise<void>;
      };

      const cancellation = internals.cancelRunRemotely(RUN_ID);
      const cancellationExpectation = expect(cancellation).rejects.toMatchObject({ name: 'TimeoutError' });
      await jest.advanceTimersByTimeAsync(3_000);

      await cancellationExpectation;
      expect(fetchMock).toHaveBeenCalledTimes(1);
      await runtime.destroy();
    } finally {
      jest.useRealTimers();
    }
  });

  it('maps unknown finish reasons to interruption without reporting completion', async () => {
    const storage = createMemoryStorage();
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: DEVICE_ID,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      return Promise.resolve(ndjsonResponse([
        runStart(),
        messageStart(),
        event({ type: 'message_end', sequence: 3, messageId: MESSAGE_ID, finishReason: 'future_finish' }),
      ]));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: () => {},
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
    });
    await runtime.acceptConsent();

    const result = await runtime.startRun({ expectedThreadRevision: 0, input: { kind: 'append', text: 'Hi' } });

    expect(result).toMatchObject({ state: 'interrupted', inputMessageId: MESSAGE_ID });
  });

  it('omits a duplicate user message when regenerating', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (url.endsWith('/runs')) {
        expect(JSON.parse(init?.body as string).input).toEqual({
          kind: 'regenerate', targetAssistantMessageId: MESSAGE_ID,
        });
        return Promise.resolve(ndjsonResponse([runStart(), messageStart(), messageEnd(3)]));
      }
      return Promise.reject(new Error(`Unexpected URL ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => CLIENT_RUN_ID,
    });
    await runtime.updateHostContext(receiveHost('ton'));
    await runtime.acceptConsent();

    const result = await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'regenerate', targetAssistantMessageId: MESSAGE_ID, userMessageId: MESSAGE_ID_2 },
    });

    expect(result.state).toBe('completed');
    expect(result).not.toHaveProperty('inputMessageId');
    expect(updates.find(({ kind }) => kind === 'runStarted')).not.toHaveProperty('inputMessageId');
  });

  it('stops reconnecting after a terminal stream error and keeps thread routing', async () => {
    const updates: any[] = [];
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      runRequests += 1;
      return Promise.resolve(ndjsonResponse([
        runStart(),
        event({
          type: 'error',
          sequence: 2,
          code: 'provider_unavailable',
          retryable: true,
        }),
      ]));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ state: 'failed' });
    expect(runRequests).toBe(1);
    expect(updates).toContainEqual({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
      code: 'provider_unavailable',
      retryable: true,
    });
  });

  it.each([false, true])('bounds protocol retries despite transient activity, with journal progress: %s', async (
    shouldAdvance,
  ) => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const updates: AgentV2ClientUpdate[] = [];
    const cursors: (number | undefined)[] = [];
    const wait = jest.fn<Promise<void>, [number]>(() => Promise.resolve());
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.includes('/hints')) return Promise.resolve(disabledHintsResponse());
      if (!url.endsWith('/runs')) return Promise.reject(new Error(`Unexpected URL ${url}`));
      runRequests += 1;
      cursors.push((JSON.parse(init?.body as string) as { resumeAfterSequence?: number }).resumeAfterSequence);
      const sequence = shouldAdvance && runRequests >= 3 ? 3 : 2;
      if (runRequests >= 5) return Promise.resolve(ndjsonResponse([messageEnd(sequence + 1)]));
      return Promise.resolve(ndjsonResponse([
        ...(runRequests === 1 ? [runStart(), messageStart()] : []),
        ...(shouldAdvance && runRequests === 3 ? [textDelta('Recovered', 3)] : []),
        event({ type: 'run_activity', sequence, ephemeral: true, code: 'web.searching', status: 'active' }),
        textDelta('Gap', sequence + 2),
      ]));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID];
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      wait,
    });
    await runtime.acceptConsent();

    const result = await runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    });
    await runtime.destroy();

    expect(result.state).toBe(shouldAdvance ? 'completed' : 'failed');
    expect(cursors).toEqual(shouldAdvance ? [undefined, 2, 2, 3, 3] : [undefined, 2, 2]);
    expect(wait.mock.calls.map(([delay]) => delay)).toEqual(shouldAdvance ? [500, 1000, 500, 1000] : [500, 1000]);
    expect(updates.filter(({ kind }) => kind === 'runActivityChanged')).toHaveLength(shouldAdvance ? 4 : 3);
    if (!shouldAdvance) {
      expect(updates).toContainEqual(expect.objectContaining({
        kind: 'runFailed', code: 'invalid_event', retryable: false,
      }));
    }
  });

  it('surfaces a malformed replay event as a terminal safe failure', async () => {
    const updates: any[] = [];
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      runRequests += 1;
      return Promise.resolve(rawNdjsonResponse(`${JSON.stringify(runStart())}\n{malformed\n`));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ state: 'failed' });
    expect(runRequests).toBe(1);
    expect(updates).toContainEqual({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
      code: 'invalid_event',
      retryable: false,
    });
  });

  it('does not reconnect after an unexpected consumer programming error', async () => {
    const updates: any[] = [];
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      runRequests += 1;
      return Promise.resolve(ndjsonResponse([runStart()]));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => {
        if (update.kind === 'runStarted') throw new Error('consumer programming error');
        updates.push(update);
      },
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ state: 'failed' });

    expect(runRequests).toBe(1);
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'runFailed', code: 'internal_error', retryable: false,
    }));
  });

  it('retries a browser network exception before run admission', async () => {
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      runRequests += 1;
      if (runRequests === 1) return Promise.reject(new DOMException('Offline', 'NetworkError'));
      return Promise.resolve(ndjsonResponse([
        runStart(),
        event({ type: 'error', sequence: 2, code: 'provider_unavailable', retryable: true }),
      ]));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ state: 'failed' });
    expect(runRequests).toBe(2);
  });

  it.each([
    { status: 503, body: JSON.stringify({
      protocolVersion: 3,
      error: { code: 'provider_unavailable', retryable: true },
    }) },
    { status: 502, body: '<html>Bad Gateway</html>' },
    { status: 503, body: JSON.stringify({ error: 'Service unavailable' }) },
    { status: 408, body: '' },
  ])('retries pre-admission HTTP $status ($body) within the bounded attempt budget', async ({ status, body }) => {
    const updates: any[] = [];
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      runRequests += 1;
      if (runRequests < 3) {
        return Promise.resolve({
          ...jsonResponse(undefined, status),
          json: () => Promise.resolve().then(() => JSON.parse(body)),
        });
      }
      return Promise.resolve(ndjsonResponse([runStart(), messageStart(), messageEnd(3)]));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: (() => {
        const values = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
        return () => values.shift()!;
      })(),
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ state: 'completed' });

    expect(runRequests).toBe(3);
    expect(updates.some(({ kind }) => kind === 'runFailed')).toBe(false);
  });

  it('ignores an unknown optional event without reconnecting or failing the run', async () => {
    const updates: any[] = [];
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      runRequests += 1;
      return Promise.resolve(ndjsonResponse([
        runStart(),
        event({ type: 'run_activity', sequence: 2, code: 'web.searching', status: 'active' }),
        event({
          type: 'message_start', sequence: 3, messageId: MESSAGE_ID,
          role: 'assistant', contentKind: 'markdown',
        }),
        event({ type: 'future_optional', sequence: 4 }),
        event({ type: 'text_delta', sequence: 5, messageId: MESSAGE_ID, delta: 'Still running' }),
        messageEnd(6),
      ]));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ state: 'completed' });
    expect(runRequests).toBe(1);
    expect(updates.some(({ kind }) => kind === 'runFailed')).toBe(false);
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'textDelta',
      delta: 'Still running',
    }));
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'runActivityChanged',
      event: expect.objectContaining({ code: 'web.searching', status: 'active' }),
    }));
  });

  it('routes a pre-admission failure by client run and requested thread', async () => {
    const updates: any[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      return Promise.resolve(jsonResponse({
        protocolVersion: 3,
        error: {
          code: 'thread_not_found',
          retryable: false,
          threadId: THREAD_ID,
        },
      }, 404));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(updates).toContainEqual({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'thread_not_found',
      retryable: false,
    });
  });

  it('surfaces retryable semantic admission conflicts instead of replaying the same stale request', async () => {
    const updates: any[] = [];
    let runRequests = 0;
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      if (url.endsWith('/capabilities')) return Promise.resolve(featureCapabilitiesResponse('disabled'));
      runRequests += 1;
      return Promise.resolve(jsonResponse({
        protocolVersion: 3,
        error: {
          code: 'thread_revision_conflict',
          retryable: true,
          threadId: THREAD_ID,
          currentThread: threadSummary({ revision: 2 }),
        },
      }, 409));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
      wait: () => Promise.resolve(),
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(runRequests).toBe(1);
    expect(updates).toContainEqual(expect.objectContaining({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'thread_revision_conflict',
      retryable: true,
    }));
  });

  it('rejects a run_start that changes an explicitly requested thread binding', async () => {
    const updates: any[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      return Promise.resolve(ndjsonResponse([
        boundEvent(RUN_ID, {
          type: 'run_start',
          sequence: 1,
          clientRunId: CLIENT_RUN_ID,
          threadId: THREAD_ID_2,
          threadRevision: 1,
        }),
      ]));
    }) as unknown as typeof fetch;
    const ids = [CLIENT_RUN_ID, MESSAGE_ID, DEVICE_ID];
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: (update) => updates.push(update),
      randomUuid: () => ids.shift()!,
    });
    await runtime.acceptConsent();

    await expect(runtime.startRun({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: 'Hello' },
    })).resolves.toMatchObject({ state: 'failed' });
    expect(updates).toEqual([{
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
      code: 'invalid_event',
      retryable: false,
    }]);
  });

  it('uses only default, message-history and clear thread requests', async () => {
    const requests: { url: string; method?: string; body?: any }[] = [];
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      requests.push({
        url,
        ...(init?.method ? { method: init.method } : {}),
        ...(init?.body ? { body: JSON.parse(init.body as string) } : {}),
      });
      if (url.includes('/messages?')) {
        return Promise.resolve(jsonResponse({ protocolVersion: 3, thread: threadSummary(), messages: [] }));
      }
      if (url.endsWith('/clear')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary({ revision: 2 }),
          duplicate: false,
        }));
      }
      if (url.endsWith('/threads/default')) {
        return Promise.resolve(jsonResponse({ protocolVersion: 3, thread: threadSummary(), created: false }));
      }
      throw new Error(`Unexpected request: ${url}`);
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: () => {},
      randomUuid: () => DEVICE_ID,
    });
    await runtime.acceptConsent();
    await runtime.updateHostContext(stakeHost());
    await runtime.getDefaultThread();
    await runtime.getMessages(THREAD_ID, 'older_page', 20);
    await runtime.clearThread(THREAD_ID, 1);
    await runtime.getMessages(THREAD_ID);

    expect(requests).toEqual([
      { url: 'https://agent.test/api/v2/threads/default' },
      { url: `https://agent.test/api/v2/threads/${THREAD_ID}/messages?limit=20&cursor=older_page` },
      {
        url: `https://agent.test/api/v2/threads/${THREAD_ID}/clear`,
        method: 'POST',
        body: {
          protocolVersion: 3,
          expectedThreadRevision: 1,
          clientOperationId: expect.any(String),
        },
      },
      { url: `https://agent.test/api/v2/threads/${THREAD_ID}/messages?limit=100` },
    ]);
  });

  it('restores persisted capacity failures from message history', async () => {
    const storage = createMemoryStorage();
    await storeIdentity(storage);
    const fetchMock = jest.fn((input: string | URL | Request) => {
      const url = getRequestUrl(input);
      if (url.includes('/messages?')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          thread: threadSummary(),
          messages: [{
            id: MESSAGE_ID,
            threadId: THREAD_ID,
            role: 'user',
            status: 'complete',
            content: { kind: 'markdown', text: 'Try the Agent' },
            createdAt: '2026-08-15T12:00:00.000Z',
          }, {
            id: MESSAGE_ID_2,
            threadId: THREAD_ID,
            role: 'assistant',
            status: 'error',
            runId: RUN_ID,
            error: { code: 'agent_capacity_exhausted', retryable: true },
            createdAt: '2026-08-15T12:00:01.000Z',
          }, {
            id: MESSAGE_ID_3,
            threadId: THREAD_ID,
            role: 'assistant',
            status: 'error',
            runId: RUN_ID_2,
            error: { code: 'provider_error', retryable: true },
            createdAt: '2026-08-15T12:00:02.000Z',
          }],
        }));
      }
      return Promise.reject(new Error(`Unexpected request: ${url}`));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage,
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: jest.fn(),
    });
    await runtime.acceptConsent();

    const hydration = await runtime.getMessages(THREAD_ID);

    expect(hydration.messages.map(({ id }) => id)).toEqual([MESSAGE_ID, MESSAGE_ID_2, MESSAGE_ID_3]);
  });

  it('rejects message hydration that changes the requested thread binding', async () => {
    const fetchMock = jest.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = getRequestUrl(input);
      if (url.endsWith('/device-token')) {
        return Promise.resolve(jsonResponse({
          protocolVersion: 3,
          deviceId: JSON.parse(init?.body as string).deviceId,
          deviceToken: `adt_v2.${'a'.repeat(43)}`,
          expiresAt: '2026-10-14T00:00:00.000Z',
        }));
      }
      return Promise.resolve(jsonResponse({
        protocolVersion: 3,
        thread: threadSummary({ id: THREAD_ID_2 }),
        messages: [],
      }));
    }) as unknown as typeof fetch;
    const runtime = new AgentV2Runtime({
      storage: createMemoryStorage(),
      baseUrl: 'https://agent.test/api/v2',
      fetch: fetchMock,
      onUpdate: () => {},
      randomUuid: () => DEVICE_ID,
    });
    await runtime.acceptConsent();

    await expect(runtime.getMessages(THREAD_ID)).rejects.toMatchObject({
      code: 'invalid_event',
      retryable: false,
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});

function runStart() {
  return event({
    type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1,
  });
}

function messageStart() {
  return event({
    type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown',
  });
}

function textDelta(delta: string, sequence = 3) {
  return event({ type: 'text_delta', sequence, messageId: MESSAGE_ID, delta });
}

function messageContentEnd(sequence: number) {
  return event({ type: 'message_content_end', sequence, messageId: MESSAGE_ID });
}

function actionEvent(sequence: number) {
  return event({
    type: 'action',
    sequence,
    messageId: MESSAGE_ID,
    action: {
      id: TOOL_CALL_ID,
      kind: 'receive',
      labelCode: 'open_receive',
      title: 'Review prepared action',
      effect: 'open_receive',
      contextBinding: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        activeAccountRef: 'current',
        activeNetwork: 'ton',
      },
      localDraftRequired: false,
      requiresConfirmation: false,
    },
  });
}

function toolCallEvent(sequence: number) {
  return event({
    type: 'tool_call',
    sequence,
    toolCall: {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      arguments: {
        operation: 'assets.search',
        query: 'TON',
        chains: ['ton'],
        pageSize: 10,
      },
      scopes: ['wallet.data.read'],
      timeoutMs: 1_000,
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'current',
        activeNetwork: 'ton',
      },
      intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
    },
  });
}

function privateToolCallEvent(sequence: number) {
  return event({
    type: 'tool_call',
    sequence,
    toolCall: {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      arguments: {
        operation: 'assets.search',
        query: PRIVATE_TOOL_ARGUMENT,
        chains: ['ton'],
        pageSize: 10,
      },
      scopes: ['wallet.data.read'],
      timeoutMs: 1_000,
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'current',
        activeNetwork: 'ton',
      },
      reason: PRIVATE_TOOL_REASON,
    },
  });
}

function toolStatusEvent(
  sequence: number,
  status: 'complete' | 'failed' | 'timeout' | 'rejected' | 'cancelled',
) {
  return event({ type: 'tool_status', sequence, toolCallId: TOOL_CALL_ID, status });
}

function threadEvent(sequence: number) {
  return event({
    type: 'thread',
    sequence,
    thread: threadSummary({
      revision: 2,
      messageCount: 2,
    }),
  });
}

function messageEnd(sequence: number) {
  return event({ type: 'message_end', sequence, messageId: MESSAGE_ID, finishReason: 'complete' });
}

function event(extra: Record<string, unknown>) {
  return { protocolVersion: 3, runId: RUN_ID, ...extra };
}

function boundEvent(runId: string, extra: Record<string, unknown>) {
  return { protocolVersion: 3, runId, ...extra };
}

function ndjsonResponse(events: unknown[]): Response {
  const contents = events.map((item) => JSON.stringify(item)).join('\n').concat('\n');
  return rawNdjsonResponse(contents);
}

function rawNdjsonResponse(contents: string): Response {
  return {
    ok: true,
    status: 200,
    headers: new Headers({ 'Content-Type': 'application/x-ndjson; charset=utf-8' }),
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(contents));
        controller.close();
      },
    }),
  } as Response;
}

function openNdjsonResponse(initialEvents: unknown[]) {
  let streamController!: ReadableStreamDefaultController<Uint8Array>;
  const encode = (events: unknown[]) => new TextEncoder().encode(
    events.map((item) => JSON.stringify(item)).join('\n').concat('\n'),
  );
  const response = {
    ok: true,
    status: 200,
    headers: new Headers({ 'Content-Type': 'application/x-ndjson; charset=utf-8' }),
    body: new ReadableStream<Uint8Array>({
      start(controller) {
        streamController = controller;
        controller.enqueue(encode(initialEvents));
      },
    }),
  } as Response;
  return {
    response,
    finish(events: unknown[]) {
      streamController.enqueue(encode(events));
      streamController.close();
    },
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

function disabledHintsResponse(): Response {
  return starterHintsResponse([]);
}

function starterHintsResponse(items: unknown[]): Response {
  return jsonResponse({
    protocolVersion: 3,
    catalogVersion: 'agent-starter-hints-v1',
    items,
  });
}

function featureCapabilitiesResponse(
  walletQuery: 'available' | 'disabled',
  digest = contractManifest.walletFilterCatalogSha256,
): Response {
  return jsonResponse({
    protocolVersion: 3,
    portfolioPositions: 'disabled',
    walletQuery: walletQuery === 'available'
      ? { status: 'available', filterCatalog: { version: 1, digest, requiresClientTimeZone: true } }
      : { status: 'disabled' },
    problemReport: { status: 'available' },
  });
}

function threadSummary(extra: Record<string, unknown> = {}) {
  return {
    id: THREAD_ID,
    revision: 1,
    createdAt: '2026-07-16T00:00:00.000Z',
    updatedAt: '2026-07-16T00:00:00.000Z',
    lastActivityAt: '2026-07-16T00:00:00.000Z',
    messageCount: 0,
    ...extra,
  };
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
  };
}

async function storeIdentity(storage: Storage) {
  await storage.setItem('agentV2DeviceIdentity', JSON.stringify({
    version: 1,
    deviceId: DEVICE_ID,
    deviceToken: `adt_v2.${'a'.repeat(43)}`,
    expiresAt: '2026-10-14T00:00:00.000Z',
  }));
}

function getRequestUrl(input: string | URL | Request) {
  return typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
}

/** A server that never answers: each request ends only when its signal aborts */
function unansweredFetch() {
  return jest.fn((_input: string | URL | Request, init?: RequestInit) => new Promise<Response>(
    (_resolve, reject) => init?.signal?.addEventListener('abort', () => reject(init.signal!.reason)),
  ));
}

function receiveHost(activeNetwork: 'ton' | 'tron', isViewOnly = true) {
  return {
    platform: 'classic' as const, uiCapabilities: hostUiCapabilities('classic'),
    client: 'web' as const,
    lang: 'en',
    baseCurrency: 'USD',
    activeAccountId: 'view-account',
    activeNetwork,
    accounts: [{
      accountId: 'view-account',
      state: 'active' as const,
      accountType: isViewOnly ? 'viewOnly' as const : 'regular' as const,
      isViewOnly,
      chains: ['ton', 'tron'],
      addresses: { ton: 'EQ-view', tron: 'T-view' },
      holdings: [],
    }],
    savedAddresses: [],
  };
}

function stakeHost() {
  return {
    ...receiveHost('ton', false),
    isTestnet: false,
    assetCatalog: [{
      slug: 'toncoin', chain: 'ton' as const, symbol: 'TON', decimals: 9,
    }],
  };
}

function liveSwapAction() {
  return {
    id: '69696969-6969-4969-8969-696969696968',
    schemaVersion: 2 as const,
    kind: 'swap' as const,
    labelCode: 'open_swap' as const,
    title: 'Review prepared action',
    effect: 'open_swap' as const,
    url: 'https://my.tt/swap?in=toncoin&out=usdton&amount=10',
    contextBinding: {
      sessionId: WALLET_SESSION_ID,
      revision: 4,
      activeAccountRef: 'account_current',
    },
    sourceAsset: { slug: 'toncoin', chain: 'ton' as const, symbol: 'TON', decimals: 9 },
    destinationAsset: { slug: 'usdton', chain: 'ton' as const, symbol: 'USDT', decimals: 6 },
    amount: { value: '10', valueType: 'decimal' as const, side: 'source' as const },
    localDraftRequired: false as const,
    requiresConfirmation: false as const,
  };
}

function persistedSwapAction() {
  return {
    id: '69696969-6969-4969-8969-696969696967',
    schemaVersion: 2 as const,
    kind: 'swap' as const,
    labelCode: 'open_swap' as const,
    title: 'Review prepared action',
    effect: 'open_swap' as const,
    url: 'https://my.tt/swap?in=usdton&out=toncoin&amountOut=10',
    sourceAsset: { slug: 'usdton', chain: 'ton' as const, symbol: 'USDT', decimals: 6 },
    destinationAsset: { slug: 'toncoin', chain: 'ton' as const, symbol: 'TON', decimals: 9 },
    amount: { value: '10', valueType: 'decimal' as const, side: 'destination' as const },
    localDraftRequired: false as const,
    requiresConfirmation: false as const,
  };
}

function persistedSendAction() {
  return {
    id: '69696969-6969-4969-8969-696969696966', kind: 'send' as const,
    labelCode: 'open_send' as const, title: 'Open transfer', effect: 'live_only' as const,
    localDraftRequired: false as const, requiresConfirmation: false as const,
  };
}

function assertFixtureEvent(value: never): never {
  throw new Error(`Unexpected terminal fixture event: ${JSON.stringify(value)}`);
}
