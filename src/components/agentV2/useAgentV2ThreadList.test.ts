import React, { type VirtualElementComponent } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentThreadListResponseV2, AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentV2MutationResult } from '../../api/agentV2/types';

import { resetAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import { publishAgentV2Update } from '../../util/agentV2Updates';
import { getIsInBackground } from '../../util/backgroundMode';
import Deferred from '../../util/Deferred';
import { pause, waitFor } from '../../util/schedulers';
import { callApi } from '../../api';
import useAgentV2ThreadList from './useAgentV2ThreadList';

import useInterval from '../../hooks/useInterval';

jest.mock('../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../util/backgroundMode', () => ({ getIsInBackground: jest.fn(() => false) }));
jest.mock('../../hooks/useBackgroundMode', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../hooks/useInterval', () => ({ __esModule: true, default: jest.fn() }));

// The delay after which the hook asks again for a first page that failed to load
const RETRY_DELAY_MS = 5000;

const callApiMock = jest.mocked(callApi);
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
    getIsInBackgroundMock.mockReturnValue(false);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
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

  it('keeps the placeholder after a failed first load and loads the chats again five seconds later', async () => {
    const thread = buildThread('after-failure');
    const failedPage = new Deferred<AgentV2MutationResult<AgentThreadListResponseV2> | undefined>();
    callApiMock.mockReturnValueOnce(failedPage.promise)
      .mockResolvedValueOnce(buildListResponse(thread));

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => callApiMock.mock.calls.length === 1, 10, 100)).toBe(true);

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
  });

  it('shows no chats rather than retrying a first load that retrying cannot fix', async () => {
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

    expect(await waitFor(() => Array.isArray(result.items), 10, 100)).toBe(true);
    expect(result.items).toEqual([]);
    expect(callApiMock).toHaveBeenCalledTimes(1);
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
  });

  it('stops asking for pages after a failure that retrying cannot fix', async () => {
    callApiMock.mockResolvedValueOnce(buildFirstPageWithMore())
      .mockResolvedValueOnce({ ok: false, error: { code: 'client_update_required', retryable: false } });

    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    expect(await waitFor(() => result?.hasMore, 10, 100)).toBe(true);

    result.loadMore();
    expect(await waitFor(() => !result.hasMore, 10, 100)).toBe(true);
    result.loadMore();
    await pause(30);
    expect(callApiMock).toHaveBeenCalledTimes(2);
    expect(result.items).toHaveLength(1);
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
