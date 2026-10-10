import { getGlobal, setGlobal } from '../../global';

import type { AgentV2HostContextSnapshot } from '../../api/agentV2/types';
import type { AgentV2ClientUpdate } from '../../api/agentV2/types';

import {
  cancelAgentV2ActiveRunReplays,
  publishAgentV2Update,
  subscribeToAgentV2Updates,
} from '../../util/agentV2Updates';
import { pause } from '../../util/schedulers';
import { waitForCondition } from '../../../tests/util/async';
import { callApi } from '../../api';
import { hostUiCapabilities } from '../../api/agentV2/testing/hostUiCapabilities';
import {
  type AgentV2HostContextDeliveryNotifier,
  type AgentV2HostContextDeliveryState,
  createAgentV2HostContextDeliveryController,
  startAgentV2HostContextSync,
} from './hostContextSync';

jest.mock('../../api', () => ({ callApi: jest.fn() }));

const callApiMock = jest.mocked(callApi);
const CLIENT_RUN_ID = '11111111-1111-4111-8111-111111111111';
const RUN_ID = '22222222-2222-4222-8222-222222222222';
const THREAD_ID = '33333333-3333-4333-8333-333333333333';

let stopSync: NoneToVoidFunction | undefined;
let initialGlobal: ReturnType<typeof getGlobal>;

beforeEach(() => {
  initialGlobal = getGlobal();
  stopSync = undefined;
  callApiMock.mockReset();
  cancelAgentV2ActiveRunReplays();
});

afterEach(() => {
  stopSync?.();
  setGlobal(initialGlobal);
  cancelAgentV2ActiveRunReplays();
});

describe('AgentV2HostContextSync', () => {
  it('updates wallet authority without an active Agent screen and clears background runs', async () => {
    publishAgentV2Update({ kind: 'runtimeReady', generation: 10 });
    callApiMock
      .mockResolvedValueOnce(deliveryResult(10))
      .mockResolvedValueOnce(deliveryResult(10, true));
    const updates: AgentV2ClientUpdate[] = [];
    const unsubscribe = subscribeToAgentV2Updates((update) => updates.push(update));

    setGlobal(walletGlobal('ton'));
    stopSync = startAgentV2HostContextSync();
    await waitForCondition(() => callApiMock.mock.calls.length === 1);
    publishAgentV2Update({
      kind: 'runStarted',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
      threadRevision: 1,
    });

    setGlobal(walletGlobal('ethereum'));
    await waitForCondition(() => callApiMock.mock.calls.length === 2 && updates.length > 0);

    expect(callApiMock).toHaveBeenNthCalledWith(1, 'updateAgentV2HostContext', expect.objectContaining({
      activeAccountId: '0-mainnet', activeNetwork: 'ton',
    }));
    expect(callApiMock).toHaveBeenNthCalledWith(2, 'updateAgentV2HostContext', expect.objectContaining({
      activeAccountId: '0-mainnet', activeNetwork: 'ethereum',
    }));
    expect(updates.at(-1)).toEqual({
      kind: 'runCancelled',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
    });

    const remountedUpdates: AgentV2ClientUpdate[] = [];
    const unsubscribeRemounted = subscribeToAgentV2Updates((update) => remountedUpdates.push(update));
    expect(remountedUpdates).toEqual([{ kind: 'runtimeReady', generation: 10 }]);
    unsubscribeRemounted();
    unsubscribe();
  });

  it('coalesces pending snapshots to the latest value while one delivery is in flight', async () => {
    const firstDelivery = createDeferred<ReturnType<typeof deliveryResult> | undefined>();
    const secondDelivery = createDeferred<ReturnType<typeof deliveryResult> | undefined>();
    const deliver = jest.fn()
      .mockReturnValueOnce(firstDelivery.promise)
      .mockReturnValueOnce(secondDelivery.promise);
    const first = hostContext('ton');
    const latest = { ...hostContext('ton'), theme: 'dark' as const, currencyRate: '2' };
    let currentSnapshot = first;
    const controller = createAgentV2HostContextDeliveryController({
      getSnapshot: () => currentSnapshot,
      deliver,
      notifier: new TestDeliveryNotifier({ generation: 1, isReady: true }),
    });
    controller.updateSnapshot();
    currentSnapshot = hostContext('ethereum');
    controller.updateSnapshot();
    currentSnapshot = { ...latest, currencyRate: '1' };
    controller.updateSnapshot();

    expect(deliver).toHaveBeenCalledTimes(1);
    expect(deliver).toHaveBeenNthCalledWith(1, first);

    // Pending delivery must also include changes not yet picked up by the polling batch
    currentSnapshot = latest;
    firstDelivery.resolve(deliveryResult(1));
    await flushPromises();

    expect(deliver).toHaveBeenCalledTimes(2);
    expect(deliver).toHaveBeenNthCalledWith(2, latest);

    secondDelivery.resolve(deliveryResult(1));
    await flushPromises();
    controller.destroy();
  });

  it('waits for readiness and resends after every runtime readiness event', async () => {
    const notifier = new TestDeliveryNotifier({ generation: 1, isReady: false });
    const deliver = jest.fn()
      .mockResolvedValueOnce(deliveryResult(1))
      .mockResolvedValueOnce(deliveryResult(1))
      .mockResolvedValueOnce(deliveryResult(2));
    const snapshot = hostContext('ton');
    const controller = createAgentV2HostContextDeliveryController({
      getSnapshot: () => ({ ...snapshot }),
      deliver,
      notifier,
    });

    controller.updateSnapshot();
    expect(deliver).not.toHaveBeenCalled();

    notifier.update({ generation: 1, isReady: true });
    await flushPromises();
    expect(deliver).toHaveBeenCalledTimes(1);

    controller.updateSnapshot();
    expect(deliver).toHaveBeenCalledTimes(1);

    notifier.update({ generation: 1, isReady: true });
    await flushPromises();
    expect(deliver).toHaveBeenCalledTimes(2);

    notifier.update({ generation: 2, isReady: true });
    await flushPromises();
    expect(deliver).toHaveBeenCalledTimes(3);
    expect(deliver).toHaveBeenLastCalledWith(snapshot);

    controller.destroy();
    expect(notifier.listenerCount).toBe(0);
  });

  it('cancels stale run replay before publishing runtime readiness', () => {
    const updates: AgentV2ClientUpdate[] = [];
    const unsubscribe = subscribeToAgentV2Updates((update) => updates.push(update));
    updates.length = 0;
    publishAgentV2Update({
      kind: 'runStarted',
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      threadId: THREAD_ID,
      threadRevision: 1,
    });
    publishAgentV2Update({ kind: 'runtimeReady', generation: 11 });

    expect(updates).toEqual([
      expect.objectContaining({ kind: 'runStarted', runId: RUN_ID }),
      expect.objectContaining({ kind: 'runCancelled', runId: RUN_ID }),
      { kind: 'runtimeReady', generation: 11 },
    ]);
    const remountedUpdates: AgentV2ClientUpdate[] = [];
    const unsubscribeRemounted = subscribeToAgentV2Updates((update) => remountedUpdates.push(update));
    expect(remountedUpdates).toEqual([{ kind: 'runtimeReady', generation: 11 }]);
    unsubscribeRemounted();
    unsubscribe();
  });

  it('retries undefined deliveries with capped exponential delays and clears the timer on destroy', async () => {
    jest.useFakeTimers();
    try {
      const deliver = jest.fn().mockResolvedValue(undefined);
      const controller = createAgentV2HostContextDeliveryController({
        getSnapshot: () => hostContext('ton'),
        deliver,
        notifier: new TestDeliveryNotifier({ generation: 1, isReady: true }),
      });

      controller.updateSnapshot();
      await flushPromises();
      expect(deliver).toHaveBeenCalledTimes(1);

      for (const [index, delay] of [250, 500, 1_000, 2_000, 4_000, 4_000].entries()) {
        jest.advanceTimersByTime(delay - 1);
        expect(deliver).toHaveBeenCalledTimes(index + 1);
        jest.advanceTimersByTime(1);
        expect(deliver).toHaveBeenCalledTimes(index + 2);
        await flushPromises();
      }

      controller.destroy();
      jest.advanceTimersByTime(4_000);
      await flushPromises();
      expect(deliver).toHaveBeenCalledTimes(7);
    } finally {
      jest.useRealTimers();
    }
  });

  it('does not acknowledge an explicit failed operation result', async () => {
    jest.useFakeTimers();
    try {
      const deliver = jest.fn()
        .mockResolvedValueOnce({
          ok: false as const,
          error: { code: 'network_error' as const, retryable: true },
        })
        .mockResolvedValueOnce(deliveryResult(1));
      const controller = createAgentV2HostContextDeliveryController({
        getSnapshot: () => hostContext('ton'),
        deliver,
        notifier: new TestDeliveryNotifier({ generation: 1, isReady: true }),
      });

      controller.updateSnapshot();
      await flushPromises();
      jest.advanceTimersByTime(250);
      await flushPromises();

      expect(deliver).toHaveBeenCalledTimes(2);
      controller.destroy();
    } finally {
      jest.useRealTimers();
    }
  });

  it('clears a pending retry when synchronization stops', async () => {
    callApiMock.mockResolvedValue(undefined);
    stopSync = startAgentV2HostContextSync(new TestDeliveryNotifier({ generation: 1, isReady: true }));
    await waitForCondition(() => callApiMock.mock.calls.length === 1);

    stopSync();
    await pause(300);
    expect(callApiMock).toHaveBeenCalledTimes(1);
  });
});

function walletGlobal(chain: 'ton' | 'ethereum'): ReturnType<typeof getGlobal> {
  return {
    ...getGlobal(),
    currentAccountId: '0-mainnet',
    accounts: { byId: {
      '0-mainnet': { type: 'view', byChain: { [chain]: { address: 'public-address' } } },
    } },
  };
}

function hostContext(activeNetwork: 'ton' | 'ethereum'): AgentV2HostContextSnapshot {
  return {
    platform: 'classic', uiCapabilities: hostUiCapabilities('classic'),
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    activeAccountId: 'account-1',
    activeNetwork,
    accounts: [{
      accountId: 'account-1',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton', 'ethereum'],
      addresses: { ton: 'EQ-public', ethereum: '0xpublic' },
      holdings: [],
    }],
    savedAddresses: [],
  };
}

class TestDeliveryNotifier implements AgentV2HostContextDeliveryNotifier {
  private readonly listeners = new Set<(state: AgentV2HostContextDeliveryState) => void>();

  constructor(private state: AgentV2HostContextDeliveryState) {}

  get listenerCount() {
    return this.listeners.size;
  }

  getCurrent() {
    return this.state;
  }

  subscribe(listener: (state: AgentV2HostContextDeliveryState) => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  update(state: AgentV2HostContextDeliveryState) {
    this.state = state;
    this.listeners.forEach((listener) => listener(state));
  }
}

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((promiseResolve) => {
    resolve = promiseResolve;
  });
  return { promise, resolve };
}

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
}

function deliveryResult(generation: number, authorityChanged = false) {
  return {
    ok: true as const,
    value: { authorityChanged, generation },
  };
}
