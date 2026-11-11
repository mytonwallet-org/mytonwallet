import React, { type VirtualElementComponent } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type {
  AgentThreadListItemV2,
  AgentThreadListResponseV2,
  AgentThreadSummaryV2,
} from '../../api/agentV2/protocol/types';
import type { AgentV2MutationResult } from '../../api/agentV2/types';

import { agentThreadListListeners, resetAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import { publishAgentV2Update } from '../../util/agentV2Updates';
import { getIsInBackground } from '../../util/backgroundMode';
import Deferred from '../../util/Deferred';
import { pause, rafPromise, waitFor } from '../../util/schedulers';
import { callApi } from '../../api';
import * as agentThreadReadState from './agentThreadReadState';
import useAgentV2ThreadList from './useAgentV2ThreadList';

import useInterval from '../../hooks/useInterval';

import AgentThreadActivityTracker from './AgentThreadActivityTracker';

jest.mock('../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../util/backgroundMode', () => ({ getIsInBackground: jest.fn(() => false) }));
jest.mock('../../hooks/useBackgroundMode', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../hooks/useInterval', () => ({ __esModule: true, default: jest.fn() }));

// The delay after which the hook asks again for a first page that failed to load
const RETRY_DELAY_MS = 5000;

const callApiMock = jest.fn();
const getCachedThreadsMock = jest.fn();
const useIntervalMock = jest.mocked(useInterval);
const getIsInBackgroundMock = jest.mocked(getIsInBackground);

describe('useAgentV2ThreadList', () => {
  let root: HTMLDivElement;
  let result: ReturnType<typeof useAgentV2ThreadList>;

  function Harness() {
    result = useAgentV2ThreadList({ isEnabled: true, isVisible: true });
    return undefined;
  }

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    localStorage.clear();
    jest.clearAllMocks();
    callApiMock.mockReset();
    getCachedThreadsMock.mockReset().mockResolvedValue(undefined);
    jest.mocked(callApi).mockImplementation((method, ...args) => (
      method === 'getAgentV2CachedThreads' ? getCachedThreadsMock() : callApiMock(method, ...args)
    ));
    getIsInBackgroundMock.mockReturnValue(false);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
  });

  it('shows cached rows before the fresh page without marking them observed or enabling pagination', async () => {
    const cachedThread = buildThread('cached');
    const cachedItems = [{ thread: cachedThread }];
    const freshThread = buildThread('fresh');
    const freshPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    const observeCounts = jest.spyOn(agentThreadReadState, 'observeAgentThreadCounts');
    const releaseAnswered = jest.spyOn(AgentThreadActivityTracker.prototype, 'releaseAnswered');
    const listener = jest.fn();
    agentThreadListListeners.add(listener);
    getCachedThreadsMock.mockResolvedValue(cachedItems);
    callApiMock.mockReturnValueOnce(freshPage.promise)
      .mockResolvedValueOnce(buildListResponse(buildThread('second')));

    try {
      TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
      expect(await waitFor(() => result?.items === cachedItems, 10, 100)).toBe(true);
      expect(result.hasLoadFailed).toBe(false);
      expect(result.isCacheShown).toBe(true);
      expect(result.hasMore).toBe(false);
      result.loadMore();
      await pause(30);
      expect(callApiMock).toHaveBeenCalledTimes(1);
      expect(observeCounts).not.toHaveBeenCalled();
      expect(listener).not.toHaveBeenCalled();
      expect(releaseAnswered).not.toHaveBeenCalled();

      freshPage.resolve({
        ok: true, value: { protocolVersion: 3, threads: [{ thread: freshThread }], nextCursor: 'next-page' },
      });
      expect(await waitFor(() => result.items?.[0].thread.id === freshThread.id && result.hasMore, 10, 100)).toBe(true);
      expect(result.isCacheShown).toBe(false);
      expect(observeCounts).toHaveBeenCalledTimes(1);
      expect(listener).toHaveBeenCalledWith([freshThread]);
      expect(releaseAnswered).toHaveBeenCalledTimes(1);
      result.loadMore();
      expect(await waitFor(() => result.items?.length === 2, 10, 100)).toBe(true);
    } finally {
      agentThreadListListeners.delete(listener);
    }
  });

  it('ignores a cache read that finishes after the fresh page', async () => {
    const cachedPage = new Deferred<AgentThreadListItemV2[] | undefined>();
    const freshThread = buildThread('fresh-first');
    getCachedThreadsMock.mockReturnValue(cachedPage.promise);
    callApiMock.mockResolvedValueOnce(buildListResponse(freshThread));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result?.items?.[0].thread.id === freshThread.id, 10, 100)).toBe(true);
    const freshItems = result.items;
    cachedPage.resolve([{ thread: buildThread('late-cache') }]);
    await pause(50);
    expect(result.items).toBe(freshItems);
  });

  it.each(['request', 'localState'])('ignores a cache read superseded by %s', async (supersededBy) => {
    const cachedPage = new Deferred<AgentThreadListItemV2[] | undefined>();
    getCachedThreadsMock.mockReturnValueOnce(cachedPage.promise);
    callApiMock.mockReturnValue(new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>().promise);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => getCachedThreadsMock.mock.calls.length === 1, 10, 100)).toBe(true);
    if (supersededBy === 'request') {
      useIntervalMock.mock.calls.at(-1)![0]();
      expect(getCachedThreadsMock).toHaveBeenCalledTimes(2);
    } else {
      resetAgentV2LocalState();
    }
    cachedPage.resolve([{ thread: buildThread('stale-cache') }]);
    await pause(50);
    expect(result.items).toBeUndefined();
  });

  it.each([false, true])('keeps failure and Retry when cache arrives afterward: nonempty %s', async (hasRows) => {
    const cachedPage = new Deferred<AgentThreadListItemV2[] | undefined>();
    const retriedPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    const freshThread = buildThread('after-empty-cache');
    getCachedThreadsMock.mockReturnValueOnce(cachedPage.promise);
    callApiMock.mockResolvedValueOnce({ ok: false, error: { code: 'network_error', retryable: true } })
      .mockReturnValueOnce(retriedPage.promise);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result?.hasLoadFailed, 10, 100)).toBe(true);
    const cachedItems = hasRows ? [{ thread: buildThread('late-cache') }] : undefined;
    cachedPage.resolve(cachedItems ?? []);
    await pause(50);
    expect(result.hasLoadFailed).toBe(true);
    expect(result.items).toEqual(cachedItems);

    result.retry();
    expect(await waitFor(() => callApiMock.mock.calls.length === 2 && result.isRetrying, 10, 100)).toBe(true);
    retriedPage.resolve(buildListResponse(freshThread));
    expect(await waitFor(() => result.items?.[0].thread.id === freshThread.id, 10, 100)).toBe(true);
    expect(result.hasLoadFailed).toBe(false);
  });

  it('does not bring cached rows back over a fresh empty page on a refresh', async () => {
    callApiMock.mockResolvedValueOnce({ ok: true, value: { protocolVersion: 3, threads: [] } })
      .mockReturnValueOnce(new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>().promise);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => Array.isArray(result?.items), 10, 100)).toBe(true);
    getCachedThreadsMock.mockResolvedValue([{ thread: buildThread('stale-cache') }]);
    useIntervalMock.mock.calls.at(-1)![0]();
    await pause(50);
    expect(result.items).toEqual([]);
    expect(result.isCacheShown).toBe(false);
    expect(getCachedThreadsMock).toHaveBeenCalledTimes(1);
  });

  it('keeps cached rows after the fresh page fails and retries after the server delay', async () => {
    const cachedItems = [{ thread: buildThread('cached-failure') }];
    const failedPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    const freshThread = buildThread('after-cached-failure');
    getCachedThreadsMock.mockResolvedValue(cachedItems);
    callApiMock.mockReturnValueOnce(failedPage.promise)
      .mockResolvedValueOnce(buildListResponse(freshThread));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result?.items === cachedItems, 10, 100)).toBe(true);
    enableFakeRetryTimers();
    try {
      failedPage.resolve({ ok: false, error: { code: 'rate_limited', retryable: true, retryAfterMs: 8000 } });
      await jest.advanceTimersByTimeAsync(7999);
      await rafPromise();
      expect(result.items).toBe(cachedItems);
      expect(result.hasLoadFailed).toBe(true);
      expect(callApiMock).toHaveBeenCalledTimes(1);
      await jest.advanceTimersByTimeAsync(1);
      expect(callApiMock).toHaveBeenCalledTimes(2);
    } finally {
      jest.useRealTimers();
    }
    expect(await waitFor(() => result.items?.[0].thread.id === freshThread.id, 10, 100)).toBe(true);
    expect(getCachedThreadsMock).toHaveBeenCalledTimes(1);
  });

  it('publishes loaded support summaries and keeps unchanged row identities', async () => {
    const thread = { ...buildThread('support'), support: { state: 'waiting' as const } };
    const listener = jest.fn();
    agentThreadListListeners.add(listener);
    callApiMock.mockResolvedValueOnce(buildListResponse(thread));
    try {
      TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
      expect(await waitFor(() => Boolean(result?.items?.length), 10, 100)).toBe(true);
      const originalItem = result.items![0];
      expect(listener).toHaveBeenLastCalledWith([thread]);

      const support = { state: 'operator' as const, lastOperatorMessageAt: '2026-11-03T10:00:00.000Z' };
      callApiMock.mockResolvedValueOnce(buildListResponse({ ...thread, support }));
      useIntervalMock.mock.calls.at(-1)![0]();
      expect(await waitFor(() => result.items?.[0].thread.support?.state === 'operator', 10, 100)).toBe(true);
      const operatorItem = result.items![0];
      expect(operatorItem).not.toBe(originalItem);
      expect(listener).toHaveBeenLastCalledWith([{ ...thread, support }]);

      callApiMock.mockResolvedValueOnce(buildListResponse({ ...thread, support: { ...support } }));
      useIntervalMock.mock.calls.at(-1)![0]();
      expect(await waitFor(() => listener.mock.calls.length === 3, 10, 100)).toBe(true);
      expect(result.items![0]).toBe(operatorItem);

      const lastOperatorMessageAt = '2026-11-03T10:01:00.000Z';
      callApiMock.mockResolvedValueOnce(buildListResponse({
        ...thread, support: { ...support, lastOperatorMessageAt },
      }));
      useIntervalMock.mock.calls.at(-1)![0]();
      expect(await waitFor(() => (
        result.items?.[0].thread.support?.lastOperatorMessageAt === lastOperatorMessageAt
      ), 10, 100)).toBe(true);
      expect(result.items![0]).not.toBe(operatorItem);
    } finally {
      agentThreadListListeners.delete(listener);
    }
  });

  it.each([false, true])('shows the initial page after a thread update (background: %s)', async (isInBackground) => {
    const thread = buildThread('initial');
    const initialPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    callApiMock.mockReturnValueOnce(initialPage.promise);
    getIsInBackgroundMock.mockReturnValue(isInBackground);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => callApiMock.mock.calls.length === 1, 10, 100)).toBe(true);
    publishAgentV2Update({ kind: 'threadChanged', threadId: thread.id, thread: { ...thread, revision: 2 } });
    initialPage.resolve(buildListResponse(thread));

    expect(await waitFor(() => result.items?.[0].thread.id === thread.id, 10, 20)).toBe(true);
    expect(callApiMock).toHaveBeenCalledTimes(1);
  });

  it('adds a news discussion from its updates only once the user has written in it', async () => {
    const chat = buildThread('chat');
    const news = { eventId: 7, headline: 'News', publishedAt: '2026-10-21T10:00:00.000Z' };
    const discussion = { ...buildThread('discussion'), news, messageCount: 1 };
    callApiMock.mockResolvedValue(buildListResponse(chat));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result.items?.length === 1, 10, 100)).toBe(true);
    publishAgentV2Update({ kind: 'threadChanged', threadId: discussion.id, thread: discussion });
    await pause(50);
    expect(result.items!.map(({ thread }) => thread.id)).toEqual(['chat']);

    publishAgentV2Update({
      kind: 'threadChanged', threadId: discussion.id, thread: { ...discussion, revision: 2, messageCount: 3 },
    });
    expect(await waitFor(() => result.items?.length === 2, 10, 100)).toBe(true);
  });

  it('loads the chats again by itself five seconds after a failed first load', async () => {
    const thread = buildThread('after-failure');
    const failedPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2> | undefined>();
    callApiMock.mockReturnValueOnce(failedPage.promise)
      .mockResolvedValueOnce(buildListResponse(thread));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => callApiMock.mock.calls.length === 1, 10, 100)).toBe(true);
    expect(result.hasLoadFailed).toBe(false);

    enableFakeRetryTimers();
    try {
      failedPage.resolve(undefined);
      await jest.advanceTimersByTimeAsync(RETRY_DELAY_MS - 1);
      expect(callApiMock).toHaveBeenCalledTimes(1);
      expect(result.items).toBeUndefined();

      await jest.advanceTimersByTimeAsync(1);
      expect(callApiMock).toHaveBeenCalledTimes(2);
    } finally {
      jest.useRealTimers();
    }
    expect(await waitFor(() => result.items?.[0]?.thread.id === thread.id, 10, 100)).toBe(true);
    expect(result.hasLoadFailed).toBe(false);
  });

  it('shows the failure without trying again by itself a first load that retrying cannot fix', async () => {
    callApiMock.mockResolvedValueOnce({
      ok: false, error: { code: 'client_update_required', retryable: false },
    });

    enableFakeRetryTimers();
    try {
      TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
      await jest.advanceTimersByTimeAsync(RETRY_DELAY_MS * 2);
    } finally {
      jest.useRealTimers();
    }

    expect(await waitFor(() => result.hasLoadFailed, 10, 100)).toBe(true);
    expect(result.items).toBeUndefined();
    expect(callApiMock).toHaveBeenCalledTimes(1);
  });

  it('reads the chats at once on Retry after a failed first load, which a later failure keeps shown', async () => {
    const thread = buildThread('after-retry');
    const retriedPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    callApiMock.mockResolvedValueOnce({ ok: false, error: { code: 'network_error', retryable: true } })
      .mockResolvedValueOnce(undefined)
      .mockReturnValueOnce(retriedPage.promise);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result?.hasLoadFailed, 10, 100)).toBe(true);

    result.retry();
    expect(await waitFor(() => callApiMock.mock.calls.length === 2, 10, 100)).toBe(true);
    await pause(30);
    expect(result.hasLoadFailed).toBe(true);
    expect(result.isRetrying).toBe(false);

    result.retry();
    expect(await waitFor(() => callApiMock.mock.calls.length === 3 && result.isRetrying, 10, 100)).toBe(true);
    expect(result.hasLoadFailed).toBe(true);
    retriedPage.resolve(buildListResponse(thread));

    expect(await waitFor(() => result.items?.[0]?.thread.id === thread.id, 10, 100)).toBe(true);
    expect(result.hasLoadFailed).toBe(false);
    expect(result.isRetrying).toBe(false);
  });

  it('keeps the chats shown without a failure when a refresh fails', async () => {
    const thread = buildThread('kept');
    callApiMock.mockResolvedValueOnce(buildListResponse(thread))
      .mockResolvedValueOnce({ ok: false, error: { code: 'network_error', retryable: true } });

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => Boolean(result?.items?.length), 10, 100)).toBe(true);

    useIntervalMock.mock.calls.at(-1)![0]();
    expect(await waitFor(() => callApiMock.mock.calls.length === 2, 10, 100)).toBe(true);
    await pause(30);

    expect(result.items?.[0].thread.id).toBe(thread.id);
    expect(result.hasLoadFailed).toBe(false);
    expect(result.hasPageLoadFailed).toBe(false);
  });

  it('asks for a failed page again by itself once the delay the server asked for ends', async () => {
    callApiMock.mockResolvedValueOnce(buildFirstPageWithMore())
      .mockResolvedValueOnce({ ok: false, error: { code: 'rate_limited', retryable: true, retryAfterMs: 8000 } })
      .mockResolvedValueOnce(buildListResponse(buildThread('second')));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result?.hasMore, 10, 100)).toBe(true);

    enableFakeRetryTimers();
    try {
      result.loadMore();
      await jest.advanceTimersByTimeAsync(0);
      expect(callApiMock).toHaveBeenCalledTimes(2);

      // A scroll within the delay asks for nothing
      await jest.advanceTimersByTimeAsync(7999);
      result.loadMore();
      expect(callApiMock).toHaveBeenCalledTimes(2);

      // The user waits at the end of the list without scrolling
      await jest.advanceTimersByTimeAsync(1);
      expect(callApiMock).toHaveBeenCalledTimes(3);
      expect(callApiMock).toHaveBeenLastCalledWith('listAgentV2Threads', expect.objectContaining({
        cursor: 'next-page',
      }));
    } finally {
      jest.useRealTimers();
    }
    expect(await waitFor(() => result.items?.length === 2, 10, 100)).toBe(true);
    expect(result.hasPageLoadFailed).toBe(false);
  });

  it('asks for a page that retrying cannot fix only on Retry', async () => {
    callApiMock.mockResolvedValueOnce(buildFirstPageWithMore())
      .mockResolvedValueOnce({ ok: false, error: { code: 'client_update_required', retryable: false } })
      .mockResolvedValueOnce(buildListResponse(buildThread('second')));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result?.hasMore, 10, 100)).toBe(true);

    result.loadMore();
    expect(await waitFor(() => result.hasPageLoadFailed, 10, 100)).toBe(true);
    result.loadMore();
    await pause(30);
    expect(callApiMock).toHaveBeenCalledTimes(2);
    expect(result.items).toHaveLength(1);
    expect(result.hasLoadFailed).toBe(false);

    result.retry();
    expect(await waitFor(() => result.items?.length === 2, 10, 100)).toBe(true);
    expect(callApiMock).toHaveBeenCalledTimes(3);
    expect(callApiMock).toHaveBeenLastCalledWith('listAgentV2Threads', expect.objectContaining({
      cursor: 'next-page',
    }));
    expect(result.hasPageLoadFailed).toBe(false);
  });

  it('keeps a deleted chat and its read record absent when an older refresh finishes', async () => {
    const thread = buildThread('deleted');
    const staleRefresh = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    callApiMock.mockResolvedValueOnce(buildListResponse(thread))
      .mockReturnValueOnce(staleRefresh.promise)
      .mockResolvedValueOnce(undefined);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => Boolean(result?.items?.length), 10, 100)).toBe(true);

    useIntervalMock.mock.calls.at(-1)![0]();
    result.removeThread(thread.id);
    staleRefresh.resolve(buildListResponse(thread));
    await pause(30);

    expect(result.items).toEqual([]);
    expect(JSON.parse(localStorage.getItem('mytonwallet-agent-thread-read-state')!).records)
      .not.toHaveProperty(thread.id);
    expect(await waitFor(() => callApiMock.mock.calls.length === 3, 10, 100)).toBe(true);
    await pause(30);
    expect(result.items).toEqual([]);
  });

  it('keeps a pin change while the server update is still pending', async () => {
    const thread = buildThread('pinned');
    const staleRefresh = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    callApiMock.mockResolvedValueOnce(buildListResponse(thread))
      .mockReturnValueOnce(staleRefresh.promise)
      .mockResolvedValueOnce(buildListResponse(thread));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => Boolean(result?.items?.length), 10, 100)).toBe(true);

    useIntervalMock.mock.calls.at(-1)![0]();
    result.setThreadPinned(thread.id, true);
    staleRefresh.resolve(buildListResponse(thread));
    await pause(30);

    expect(result.items?.[0].thread.isPinned).toBe(true);
    await pause(700);
    expect(callApiMock).toHaveBeenCalledTimes(2);
    expect(result.items?.[0].thread.isPinned).toBe(true);
  });

  it('keeps a confirmed pin when a refresh started during the update finishes', async () => {
    const thread = buildThread('confirmed-pin');
    const staleRefresh = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    callApiMock.mockResolvedValueOnce(buildListResponse(thread))
      .mockReturnValueOnce(staleRefresh.promise)
      .mockResolvedValueOnce(undefined);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => Boolean(result?.items?.length), 10, 100)).toBe(true);

    result.setThreadPinned(thread.id, true);
    useIntervalMock.mock.calls.at(-1)![0]();
    publishAgentV2Update({
      kind: 'threadChanged', threadId: thread.id, thread: { ...thread, revision: 2, isPinned: true },
    });
    staleRefresh.resolve(buildListResponse(thread));
    await pause(30);

    expect(result.items?.[0].thread.isPinned).toBe(true);
    expect(await waitFor(() => callApiMock.mock.calls.length === 3, 10, 100)).toBe(true);
    await pause(30);
    expect(result.items?.[0].thread.isPinned).toBe(true);
  });

  it('refreshes after a failed pin restores the row and brings chats from the cancelled refresh', async () => {
    const thread = buildThread('pin-failed');
    const addedThread = buildThread('added');
    const staleRefresh = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    const refreshedList: AgentV2MutationResult<AgentThreadListResponseV2> = {
      ok: true, value: { protocolVersion: 3, threads: [{ thread }, { thread: addedThread }] },
    };
    callApiMock.mockResolvedValueOnce(buildListResponse(thread))
      .mockReturnValueOnce(staleRefresh.promise)
      .mockResolvedValueOnce(refreshedList);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => Boolean(result?.items?.length), 10, 100)).toBe(true);
    useIntervalMock.mock.calls.at(-1)![0]();
    result.setThreadPinned(thread.id, true);
    staleRefresh.resolve(refreshedList);
    await pause(30);
    expect(result.items).toHaveLength(1);

    result.setThreadPinned(thread.id, false);
    result.scheduleRefresh();
    expect(await waitFor(() => callApiMock.mock.calls.length === 3, 10, 100)).toBe(true);
    expect(await waitFor(() => result.items?.length === 2, 10, 20)).toBe(true);
    expect(result.items?.find((item) => item.thread.id === thread.id)?.thread.isPinned).not.toBe(true);
    expect(result.items?.some((item) => item.thread.id === addedThread.id)).toBe(true);
  });

  it.each([false, true])('ignores a page that finishes after full sign-out (next page: %s)', async (isNextPage) => {
    const pendingPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2>>();
    if (isNextPage) {
      callApiMock.mockResolvedValueOnce({
        ok: true, value: { protocolVersion: 3, threads: [], nextCursor: 'next-page' },
      });
    }
    callApiMock.mockReturnValueOnce(pendingPage.promise);

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    if (isNextPage) {
      expect(await waitFor(() => result?.hasMore, 10, 100)).toBe(true);
      result.loadMore();
    }
    expect(await waitFor(() => callApiMock.mock.calls.length === (isNextPage ? 2 : 1), 10, 100)).toBe(true);

    resetAgentV2LocalState();
    pendingPage.resolve(buildListResponse(buildThread('signed-out')));
    await pause(50);

    expect(localStorage.getItem('mytonwallet-agent-thread-read-state')).toBeNull();
    expect(result.items ?? []).toEqual([]);
  });
});

function buildThread(id: string): AgentThreadSummaryV2 {
  const timestamp = '2026-10-21T12:00:00.000Z';
  return {
    id, revision: 1, createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp, messageCount: 2,
  };
}

function buildListResponse(thread: AgentThreadSummaryV2): AgentV2MutationResult<AgentThreadListResponseV2> {
  return { ok: true, value: { protocolVersion: 3, threads: [{ thread }] } };
}

// Only the retry delays are faked. Rendering waits for animation frames, and a frame requested while frames are faked
// and never run would keep every later render of the file from happening.
function enableFakeRetryTimers() {
  jest.useFakeTimers({ doNotFake: ['requestAnimationFrame', 'cancelAnimationFrame'] });
}

function buildFirstPageWithMore(): AgentV2MutationResult<AgentThreadListResponseV2> {
  return {
    ok: true, value: { protocolVersion: 3, threads: [{ thread: buildThread('first') }], nextCursor: 'next-page' },
  };
}
