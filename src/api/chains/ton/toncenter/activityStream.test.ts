import type { FallbackPollingOptions } from '../../../common/polling/fallbackPollingScheduler';
import type { DefaultActivitiesUpdate, WalletWatcher } from '../../../common/websocket/abstractWsClient';
import type { ApiActivity } from '../../../types';
import type { SocketFinality } from './types';

import { makeMockTransactionActivity } from '../../../../../tests/mocks';
import { fetchActions, fetchPendingActions } from './actions';
import { ActivityStream } from './activityStream';
import { getToncenterSocket } from './socket';

jest.mock('./actions', () => ({ fetchActions: jest.fn(), fetchPendingActions: jest.fn() }));
jest.mock('./socket', () => ({ getToncenterSocket: jest.fn() }));
// The real throttler coalesces socket updates over 250 ms; that delay has its own test and only adds noise here.
jest.mock('./throttleSocketActions', () => ({
  throttleToncenterSocketActions: (_delayMs: number, onUpdates: (updates: DefaultActivitiesUpdate[]) => void) => {
    return (update: DefaultActivitiesUpdate) => onUpdates([update]);
  },
}));

const ADDRESS = 'UQAcAoZUYbLuiFhSbnJUlIfHiuOsuiIYbeYFVSaYCfmjYUnw';
const TIMESTAMP = 1_700_000_000_000;
const TRACE_HASH = 'trace-hash-1';
const MIN_POLL_DELAY = 1000;

const OPTIONS: FallbackPollingOptions = {
  pollOnStart: true,
  minPollDelay: MIN_POLL_DELAY,
  pollingStartDelay: 3000,
  pollingPeriod: 3000,
  forcedPollingPeriod: 60_000,
};

type SocketCallbacks = Parameters<ReturnType<typeof getToncenterSocket>['watchWallets']>[1];

describe('ActivityStream history restoration', () => {
  let callbacks: SocketCallbacks | undefined;
  let updates: { finalized: ApiActivity[]; pending: readonly ApiActivity[] }[];

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
    updates = [];
    callbacks = undefined;
    const watcher: WalletWatcher = { isConnected: false, destroy: jest.fn() };
    jest.mocked(getToncenterSocket).mockReturnValue({
      watchWallets: (_wallets: unknown, _callbacks: SocketCallbacks) => {
        callbacks = _callbacks;
        return watcher;
      },
    } as unknown as ReturnType<typeof getToncenterSocket>);
    jest.mocked(fetchPendingActions).mockResolvedValue([]);
    jest.mocked(fetchActions).mockResolvedValue([]);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  function createStream() {
    const stream = new ActivityStream('mainnet', ADDRESS, TIMESTAMP, OPTIONS);
    stream.onUpdate((finalized, pending) => {
      updates.push({ finalized, pending });
    });
    return stream;
  }

  function emit(finality: SocketFinality, activities: ApiActivity[]) {
    callbacks!.onNewActivities!({ address: ADDRESS, messageHashNormalized: TRACE_HASH, finality, activities });
  }

  /** Sends a trace through the socket the way Toncenter does: a pending version, then the finalized one */
  async function playTrace() {
    const shared = { externalMsgHashNorm: TRACE_HASH, timestamp: TIMESTAMP + 1000 };
    const pending = makeMockTransactionActivity({ ...shared, id: `${TRACE_HASH}:100-0`, status: 'pending' });
    const finalized = makeMockTransactionActivity({ ...shared, id: 'trace-id-1:100-0', status: 'completed' });

    emit('pending', [pending]);
    emit('finalized', [finalized]);
    await jest.advanceTimersByTimeAsync(0);

    return finalized;
  }

  function expectTraceSettled(finalized: ApiActivity) {
    expect(updates[updates.length - 1].pending).toEqual([]);
    expect(updates.flatMap((update) => update.finalized)).toEqual([finalized]);
  }

  it('prunes a pending activity when the socket subscribes after the initial poll answers', async () => {
    const stream = createStream();
    await jest.advanceTimersByTimeAsync(0);
    expect(fetchPendingActions).toHaveBeenCalledTimes(1);

    callbacks!.onConnect!();
    await jest.advanceTimersByTimeAsync(2 * MIN_POLL_DELAY);

    expectTraceSettled(await playTrace());

    stream.destroy();
  });

  it('prunes a pending activity when the socket subscribes while the initial poll is in flight', async () => {
    // The in-flight poll answers with data from before the subscription, so it must not be taken for the catch-up one.
    let resolvePoll: (activities: ApiActivity[]) => void;
    jest.mocked(fetchPendingActions).mockReturnValueOnce(new Promise((resolve) => {
      resolvePoll = resolve;
    }));

    const stream = createStream();
    callbacks!.onConnect!();
    resolvePoll!([]);
    await jest.advanceTimersByTimeAsync(2 * MIN_POLL_DELAY);

    expect(fetchPendingActions).toHaveBeenCalledTimes(2);
    expectTraceSettled(await playTrace());

    stream.destroy();
  });

  it('resumes the catch-up poll from before the subscription, not from later socket traffic', async () => {
    let resolvePoll: (activities: ApiActivity[]) => void;
    jest.mocked(fetchPendingActions).mockReturnValueOnce(new Promise((resolve) => {
      resolvePoll = resolve;
    }));

    const stream = createStream();
    callbacks!.onConnect!();
    resolvePoll!([]);
    await jest.advanceTimersByTimeAsync(0);

    // Socket traffic must not move the resume point while the gap is still open.
    emit('finalized', [makeMockTransactionActivity({
      id: 'trace-id-2:200-0', externalMsgHashNorm: 'trace-hash-2', status: 'completed', timestamp: TIMESTAMP + 5000,
    })]);
    await jest.advanceTimersByTimeAsync(2 * MIN_POLL_DELAY);

    const catchUpCall = jest.mocked(fetchActions).mock.calls[jest.mocked(fetchActions).mock.calls.length - 1][0];
    expect(catchUpCall.fromTimestamp).toBe(TIMESTAMP);

    stream.destroy();
  });

  it('keeps the resume point when the stale poll answers after the socket has stashed activities', async () => {
    let resolvePoll: (activities: ApiActivity[]) => void;
    jest.mocked(fetchPendingActions).mockReturnValueOnce(new Promise((resolve) => {
      resolvePoll = resolve;
    }));

    const stream = createStream();
    callbacks!.onConnect!();

    // Stashed while the pre-connect poll is still running, so that poll must not consume them on its way out.
    emit('finalized', [makeMockTransactionActivity({
      id: 'trace-id-2:200-0', externalMsgHashNorm: 'trace-hash-2', status: 'completed', timestamp: TIMESTAMP + 5000,
    })]);
    resolvePoll!([]);
    await jest.advanceTimersByTimeAsync(2 * MIN_POLL_DELAY);

    const catchUpCall = jest.mocked(fetchActions).mock.calls[jest.mocked(fetchActions).mock.calls.length - 1][0];
    expect(catchUpCall.fromTimestamp).toBe(TIMESTAMP);

    stream.destroy();
  });
});
