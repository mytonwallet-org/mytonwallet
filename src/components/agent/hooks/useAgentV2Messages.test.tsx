import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import type {
  AgentActionProposal,
  AgentThreadClearResponseV2,
  AgentThreadSummaryV2,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2HostContextSnapshot,
  AgentV2HydratedMessage,
  AgentV2MutationResult,
  AgentV2ResolvedAction,
  AgentV2RunResult,
} from '../../../api/agentV2/types';
import type { LangFn } from '../../../hooks/useLang';

import {
  cancelAgentV2ActiveRunReplays,
  publishAgentV2Update,
} from '../../../util/agentV2Updates';
import { processDeeplink } from '../../../util/deeplink';
import { openUrl } from '../../../util/openUrl';
import { pause, waitFor } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { buildAgentV2HostContext } from '../../agentV2/buildHostContext';
import useAgentV2Messages, { type UseAgentV2MessagesResult } from './useAgentV2Messages';

const mockSetAgentMeta = jest.fn();
const mockOpenReceiveModal = jest.fn();
const mockOpenTransactionInfo = jest.fn();
const mockShowTokenActivity = jest.fn();
const mockSetSwapAmountIn = jest.fn();
const mockSetSwapAmountOut = jest.fn();
const mockStartStaking = jest.fn();
const mockStartSwap = jest.fn();
const mockStartTransfer = jest.fn();
const mockSwitchToAgent = jest.fn();
const mockSwitchToWallet = jest.fn();
const mockToggleTokenVisibility = jest.fn();

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../../util/deeplink', () => ({ processDeeplink: jest.fn() }));
jest.mock('../../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../agentV2/buildHostContext', () => ({ buildAgentV2HostContext: jest.fn() }));
jest.mock('../../../global', () => ({
  ...jest.requireActual('../../../global'),
  getGlobal: () => ({}),
  getActions: () => ({
    openReceiveModal: mockOpenReceiveModal,
    openTransactionInfo: mockOpenTransactionInfo,
    setAgentMeta: mockSetAgentMeta,
    setSwapAmountIn: mockSetSwapAmountIn,
    setSwapAmountOut: mockSetSwapAmountOut,
    showTokenActivity: mockShowTokenActivity,
    startStaking: mockStartStaking,
    startSwap: mockStartSwap,
    startTransfer: mockStartTransfer,
    switchToAgent: mockSwitchToAgent,
    switchToWallet: mockSwitchToWallet,
    toggleTokenVisibility: mockToggleTokenVisibility,
  }),
}));

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const REPLACEMENT_THREAD_ID = '11111111-1111-4111-8111-111111111112';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const MESSAGE_ID = '33333333-3333-4333-8333-333333333333';
const ASSISTANT_MESSAGE_ID = '44444444-4444-4444-8444-444444444444';
const RUN_ID = '55555555-5555-4555-8555-555555555555';
const INPUT_MESSAGE_ID = '99999999-9999-4999-8999-999999999991';
const OLDER_MESSAGE_ID = '99999999-9999-4999-8999-999999999992';
const SECOND_USER_MESSAGE_ID = '99999999-9999-4999-8999-999999999993';
const SECOND_ASSISTANT_MESSAGE_ID = '99999999-9999-4999-8999-999999999994';
const callApiMock = jest.mocked(callApi);
const buildAgentV2HostContextMock = jest.mocked(buildAgentV2HostContext);
const processDeeplinkMock = jest.mocked(processDeeplink);
const openUrlMock = jest.mocked(openUrl);
const lang = Object.assign(
  (key: string) => key === '$agent_error_conversation_updated'
    ? 'The conversation was updated. Please try the request again.'
    : key,
  { code: 'en' as const },
) as LangFn;

describe('useAgentV2Messages', () => {
  let root: HTMLDivElement;
  let result: UseAgentV2MessagesResult | undefined;
  let resolvedAction: unknown;
  let resolvedActionPromise: Promise<unknown> | undefined;
  let actionPresentationPromise: Promise<AgentV2ActionPresentation | undefined>;
  let clearThreadResponse:
    | AgentV2MutationResult<AgentThreadClearResponseV2>
    | Promise<AgentV2MutationResult<AgentThreadClearResponseV2> | undefined>
    | undefined;
  let hydratedMessages: AgentV2HydratedMessage[];
  let hydrationNextCursor: string | undefined;
  let olderHydratedMessages: AgentV2HydratedMessage[];
  let olderNextCursor: string | undefined;
  let shouldFailOlderMessages: boolean;
  let hasAuthorityChanged: boolean | undefined;
  let isConsentAccepted: boolean;
  let retryRunResponse: AgentV2RunResult | Promise<AgentV2RunResult | undefined> | undefined;
  let setConsentResult: true | undefined;
  let startRunResponses: Array<AgentV2RunResult | Promise<AgentV2RunResult | undefined>>;
  let defaultThreadId: string;
  let threadRevision: number;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    result = undefined;
    resolvedAction = undefined;
    resolvedActionPromise = undefined;
    actionPresentationPromise = Promise.resolve(undefined);
    clearThreadResponse = undefined;
    hydratedMessages = [persistedUserMessage()];
    hydrationNextCursor = undefined;
    olderHydratedMessages = [];
    olderNextCursor = undefined;
    shouldFailOlderMessages = false;
    hasAuthorityChanged = false;
    isConsentAccepted = true;
    retryRunResponse = undefined;
    setConsentResult = true;
    startRunResponses = [];
    defaultThreadId = THREAD_ID;
    threadRevision = 5;
    mockSetAgentMeta.mockReset();
    mockOpenReceiveModal.mockReset();
    mockOpenTransactionInfo.mockReset();
    mockShowTokenActivity.mockReset();
    mockSetSwapAmountIn.mockReset();
    mockSetSwapAmountOut.mockReset();
    mockStartStaking.mockReset();
    mockStartSwap.mockReset();
    mockStartTransfer.mockReset();
    mockSwitchToAgent.mockReset();
    mockSwitchToWallet.mockReset();
    mockToggleTokenVisibility.mockReset();
    processDeeplinkMock.mockReset();
    processDeeplinkMock.mockResolvedValue(true);
    openUrlMock.mockReset();
    buildAgentV2HostContextMock.mockReset();
    buildAgentV2HostContextMock.mockReturnValue(hostContext());
    callApiMock.mockReset();
    callApiMock.mockImplementation((...args) => {
      const method = args[0];
      switch (method) {
        case 'getAgentV2Consent':
          return Promise.resolve(isConsentAccepted);
        case 'acceptAgentV2Consent':
          return Promise.resolve(setConsentResult);
        case 'getAgentV2DefaultThread':
          return Promise.resolve({
            protocolVersion: 2,
            thread: { ...threadSummary(threadRevision), id: defaultThreadId },
            created: false,
          });
        case 'getAgentV2Messages':
          if (args[2]) {
            if (shouldFailOlderMessages) {
              return Promise.resolve({
                ok: false,
                error: { code: 'network_error', retryable: true },
              });
            }
            return Promise.resolve({
              ok: true,
              value: {
                thread: { ...threadSummary(threadRevision), id: defaultThreadId },
                messages: olderHydratedMessages,
                nextCursor: olderNextCursor,
              },
            });
          }
          return Promise.resolve({
            ok: true,
            value: {
              thread: { ...threadSummary(threadRevision), id: defaultThreadId },
              messages: hydratedMessages,
              nextCursor: hydrationNextCursor,
            },
          });
        case 'getAgentV2Hints':
        case 'getAgentV2Availability':
        case 'getAgentV2UserQuota':
          return Promise.resolve(undefined);
        case 'startAgentV2Run':
          return Promise.resolve(startRunResponses.shift() ?? {
            clientRunId: CLIENT_RUN_ID,
            state: 'failed',
          }) as never;
        case 'retryAgentV2Run':
          return Promise.resolve(retryRunResponse) as never;
        case 'clearAgentV2Thread':
          return Promise.resolve(clearThreadResponse) as never;
        case 'getAgentV2ActionPresentation':
          return actionPresentationPromise as never;
        case 'updateAgentV2HostContext':
          return Promise.resolve({
            ok: true,
            value: { authorityChanged: Boolean(hasAuthorityChanged), generation: 1 },
          }) as never;
        case 'resolveAgentV2Action':
          return (resolvedActionPromise ?? Promise.resolve(resolvedAction)) as never;
        default:
          return Promise.resolve(undefined);
      }
    });
    cancelAgentV2ActiveRunReplays();
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    cancelAgentV2ActiveRunReplays();
  });

  it('hydrates after Agent consent is persisted', async () => {
    isConsentAccepted = false;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isConsentAccepted === false, 10, 20)).toBe(true);

    expect(result!.isConsentAccepted).toBe(false);
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2DefaultThread');

    result!.acceptConsent();
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);

    expect(callApiMock).toHaveBeenCalledWith('acceptAgentV2Consent');
    expect(result!.isConsentAccepted).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2DefaultThread');
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Messages', THREAD_ID);
  });

  it('keeps Agent consent rejected when persistence fails', async () => {
    isConsentAccepted = false;
    setConsentResult = undefined;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isConsentAccepted === false, 10, 20)).toBe(true);

    result!.acceptConsent();
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'acceptAgentV2Consent'),
      10,
      20,
    )).toBe(true);

    expect(callApiMock).toHaveBeenCalledWith('acceptAgentV2Consent');
    expect(result!.isConsentAccepted).toBe(false);
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2DefaultThread');
    expect(callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages')).toBe(false);
  });

  it('coalesces an older-page request and prepends normalized messages', async () => {
    hydratedMessages = [persistedMessage(MESSAGE_ID, 'user', 'Latest request', 20)];
    hydrationNextCursor = 'older-page';
    olderHydratedMessages = [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Oldest response', 10)];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.hasOlderMessages === true, 10, 20)).toBe(true);

    const firstRequest = result!.loadOlderMessages();
    const coalescedRequest = result!.loadOlderMessages();
    expect(coalescedRequest).toBe(firstRequest);
    await firstRequest;
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);

    expect(result!.messages.map(({ text }) => text)).toEqual(['Oldest response', 'Latest request']);
    expect(result!.hasOlderMessages).toBe(false);
    expect(result!.isLoadingOlderMessages).toBe(false);
    expect(callApiMock.mock.calls.filter(([method, , cursor]) => (
      method === 'getAgentV2Messages' && cursor === 'older-page'
    ))).toHaveLength(1);
  });

  it('keeps pagination failures separate from the composer and allows retry', async () => {
    hydrationNextCursor = 'older-page';
    shouldFailOlderMessages = true;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.hasOlderMessages === true, 10, 20)).toBe(true);

    await result!.loadOlderMessages();
    expect(await waitFor(() => result?.isLoadingOlderMessages === false, 10, 20)).toBe(true);
    expect(result!.messages.map(({ text }) => text)).toEqual(['Persisted request']);
    expect(result!.isInputDisabled).toBe(false);
    expect(result!.hasOlderMessages).toBe(true);

    shouldFailOlderMessages = false;
    olderHydratedMessages = [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Recovered history', 5)];
    await result!.loadOlderMessages();
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(result!.messages[0].text).toBe('Recovered history');
  });

  it('drops a stale older page after runtime recovery replaces the cursor', async () => {
    hydrationNextCursor = 'older-page';
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.hasOlderMessages === true, 10, 20)).toBe(true);
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const stalePage = createDeferred<unknown>();
    callApiMock.mockImplementation((...args) => (
      args[0] === 'getAgentV2Messages' && args[2] === 'older-page'
        ? stalePage.promise as never
        : defaultImplementation(...args)
    ));

    const pageRequest = result!.loadOlderMessages();
    hydrationNextCursor = undefined;
    publishAgentV2Update({ kind: 'runtimeReady', generation: 103 });
    expect(await waitFor(() => result?.hasOlderMessages === false, 10, 20)).toBe(true);
    stalePage.resolve({
      ok: true,
      value: {
        thread: threadSummary(threadRevision),
        messages: [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Stale history', 5)],
      },
    });
    await pageRequest;

    expect(result!.messages.some(({ text }) => text === 'Stale history')).toBe(false);
  });

  it('does not preserve live content when interrupted recovery replaces the thread', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    result!.sendMessage('Old-thread optimistic request');
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: SECOND_ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: SECOND_ASSISTANT_MESSAGE_ID,
      delta: 'Old-thread live response',
    });
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Old-thread live response'
    ))), 10, 20)).toBe(true);

    defaultThreadId = REPLACEMENT_THREAD_ID;
    hydratedMessages = [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Replacement response', 30)];
    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'interrupted',
    });
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Replacement response'
    ))), 10, 20)).toBe(true);

    expect(result!.messages.some(({ text }) => text === 'Persisted request')).toBe(false);
    expect(result!.messages.some(({ text }) => text === 'Old-thread live response')).toBe(false);
    expect(result!.messages.some(({ text }) => text === 'Old-thread optimistic request')).toBe(false);
  });

  it('invokes browser animation frame methods with the global receiver', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    const requestFrameSpy = jest.spyOn(window, 'requestAnimationFrame').mockImplementation(
      function (this: typeof window) {
        expect(this).toBe(window);
        return 42;
      },
    );
    const cancelFrameSpy = jest.spyOn(window, 'cancelAnimationFrame').mockImplementation(
      function (this: typeof window) {
        expect(this).toBe(window);
      },
    );

    try {
      expect(() => publishAgentV2Update({
        kind: 'textDelta',
        ...routing(),
        messageId: ASSISTANT_MESSAGE_ID,
        delta: 'Buffered response',
      })).not.toThrow();
      expect(requestFrameSpy).toHaveBeenCalledTimes(1);

      TeactDOM.render(undefined, root);
      expect(cancelFrameSpy).toHaveBeenCalledWith(42);
    } finally {
      TeactDOM.render(undefined, root);
      requestFrameSpy.mockRestore();
      cancelFrameSpy.mockRestore();
    }
  });

  it('rehydrates a stale thread before allowing the next request', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);

    result!.sendMessage('Optimistic stale request');
    await pause(0);
    threadRevision = 6;
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'thread_revision_conflict',
      retryable: true,
    });
    await pause(20);

    expect(result!.messages.map(({ text }) => text)).toEqual([
      'Persisted request',
      'The conversation was updated. Please try the request again.',
    ]);
    expect(result!.isInputDisabled).toBe(false);

    result!.sendMessage('Request after refresh');
    await pause(0);

    const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(runCalls.at(-1)?.[1]).toMatchObject({
      threadId: THREAD_ID,
      expectedThreadRevision: 6,
      input: { kind: 'append', text: 'Request after refresh' },
    });
  });

  it('blocks clear, send and retry commands while a thread clear is pending', async () => {
    let resolveClear!: (value: AgentV2MutationResult<AgentThreadClearResponseV2>) => void;
    clearThreadResponse = new Promise((resolve) => {
      resolveClear = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    const messageId = result!.messages[0].id;
    result!.clearChat();
    result!.clearChat();
    result!.sendMessage('Concurrent request');
    result!.retryMessage(messageId);

    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'clearAgentV2Thread')).toHaveLength(1);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(0);

    resolveClear(successfulClear(6));
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 0,
      10,
      20,
    )).toBe(true);
  });

  it('preserves messages and allows retry after a thread clear failure', async () => {
    clearThreadResponse = {
      ok: false,
      error: { code: 'network_error', retryable: true },
    };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.clearChat();
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 2,
      10,
      20,
    )).toBe(true);

    expect(result!.messages.map(({ text }) => text)).toEqual([
      'Persisted request',
      'Agent connection was interrupted.',
    ]);

    result!.sendMessage('Retry after clear failure');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run')
        && !result?.messages.some(({ text }) => text === 'Agent connection was interrupted.'),
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: 'Retry after clear failure' },
    }));
  });

  it('synchronizes newly saved addresses before starting a run', async () => {
    const currentHostContext = hostContext();
    const savedAddress = {
      id: 'account-one-saved-0',
      name: 'Andry',
      chain: 'ton' as const,
      address: 'EQ-andry',
    };
    currentHostContext.accounts[0].savedAddresses = [savedAddress];
    currentHostContext.savedAddresses = [savedAddress];
    buildAgentV2HostContextMock.mockReturnValue(currentHostContext);
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.sendMessage('Send Andry 0.2 GRAM');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'),
      10,
      20,
    )).toBe(true);

    const synchronizeIndex = callApiMock.mock.calls.findIndex(([method]) => (
      method === 'updateAgentV2HostContext'
    ));
    const startIndex = callApiMock.mock.calls.findIndex(([method]) => method === 'startAgentV2Run');
    expect(synchronizeIndex).toBeGreaterThanOrEqual(0);
    expect(synchronizeIndex).toBeLessThan(startIndex);
    expect(callApiMock.mock.calls[synchronizeIndex]).toEqual([
      'updateAgentV2HostContext',
      expect.objectContaining({ savedAddresses: [savedAddress] }),
    ]);
  });

  it('ignores a pending clear completion after authoritative thread replacement', async () => {
    let resolveClear!: (value: AgentV2MutationResult<AgentThreadClearResponseV2>) => void;
    clearThreadResponse = new Promise((resolve) => {
      resolveClear = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.clearChat();
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'threadChanged',
      threadId: REPLACEMENT_THREAD_ID,
      thread: { ...threadSummary(9), id: REPLACEMENT_THREAD_ID },
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages.map(({ text }) => text)).toEqual(['Persisted request']);

    result!.sendMessage('Request on replacement thread');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'),
      10,
      20,
    )).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').at(-1)).toEqual([
      'startAgentV2Run', expect.objectContaining({
        threadId: REPLACEMENT_THREAD_ID,
        expectedThreadRevision: 9,
      }),
    ]);

    const clearMetaCallsBeforeCompletion = mockSetAgentMeta.mock.calls
      .filter(([meta]) => meta.messageCount === 0).length;
    resolveClear(successfulClear(6));
    await pause(20);

    expect(result!.messages.map(({ text }) => text)).toEqual([
      'Persisted request',
      'Request on replacement thread',
    ]);
    expect(mockSetAgentMeta.mock.calls.filter(([meta]) => meta.messageCount === 0)).toHaveLength(
      clearMetaCallsBeforeCompletion,
    );
  });

  it('binds an admitted append to its canonical input ID without ordinary hydration', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    const hydrationCallsBeforeRun = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.sendMessage('Optimistic request');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const optimisticMessageId = result!.messages.at(-1)!.id;
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRun,
    );
    result!.sendMessage('Edited request', optimisticMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'Edited request' },
    }));
  });

  it('truncates an edited suffix only after admission and rebinds the edited message', async () => {
    hydratedMessages = conversationMessages();
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);
    const editedMessageId = result!.messages[2].id;

    result!.sendMessage('Edited second request', editedMessageId);
    await pause(0);
    expect(result!.messages.map(({ text }) => text)).toEqual([
      'First request', 'First response', 'Second request', 'Second response',
    ]);

    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    expect(await waitFor(() => result?.messages.length === 3, 10, 20)).toBe(true);
    expect(result!.messages.map(({ text }) => text)).toEqual([
      'First request', 'First response', 'Edited second request',
    ]);
    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    result!.sendMessage('Edited again', editedMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'Edited again' },
    }));
  });

  it('truncates a regeneration target and suffix only after admission', async () => {
    hydratedMessages = conversationMessages();
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);

    result!.retryMessage(result!.messages[1].id);
    await pause(0);
    expect(result!.messages).toHaveLength(4);
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6 });
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    expect(result!.messages[0].text).toBe('First request');

    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'completed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
  });

  it('offers retry for a retryable persisted assistant failure after hydration', async () => {
    hydratedMessages = [
      persistedUserMessage(),
      {
        ...persistedAssistantTextMessage(),
        status: 'error',
        error: { code: 'provider_error', retryable: true },
      },
    ];

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);

    expect(result!.messages.at(-1)).toMatchObject({
      error: { code: 'provider_error', retryable: true },
      isRetryAvailable: true,
    });
  });

  it('renders a pre-admission network failure as an assistant message and retries the exact admission', async () => {
    let resolveInitial!: (result: AgentV2RunResult) => void;
    let resolveRetry!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveInitial = resolve;
    })];
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Retry after reconnect');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'network_error',
      retryable: true,
    });
    resolveInitial({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'failed',
    });
    expect(await waitFor(() => result?.messages.at(-1)?.error?.code === 'network_error', 10, 20)).toBe(true);

    expect(result!.composerStatus).toBeUndefined();
    expect(result!.messages).toHaveLength(3);
    expect(result!.messages.at(-2)).toMatchObject({
      text: 'Retry after reconnect',
      isOutgoing: true,
    });
    expect(result!.messages.at(-1)).toMatchObject({
      isOutgoing: false,
      error: { code: 'network_error', retryable: true },
      isRetryAvailable: true,
    });
    result!.retryMessage(result!.messages.at(-1)!.id);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run'),
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    resolveRetry({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.composerStatus === undefined,
      10,
      20,
    )).toBe(true);
    expect(result!.messages.filter(({ text }) => text === 'Retry after reconnect')).toHaveLength(1);
  });

  it('keeps a rejected retry on its existing failed assistant message', async () => {
    let resolveRetryRequest!: (result: AgentV2RunResult) => void;
    hydratedMessages = [
      persistedUserMessage(),
      {
        ...persistedAssistantTextMessage(),
        status: 'error',
        error: { code: 'provider_error', retryable: true },
      },
    ];
    startRunResponses = [new Promise((resolve) => {
      resolveRetryRequest = resolve;
    })];

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const failedMessageId = result!.messages.at(-1)!.id;

    result!.retryMessage(failedMessageId);
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'network_error',
      retryable: true,
    });
    resolveRetryRequest({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    expect(result!.composerStatus).toBeUndefined();
    expect(result!.messages).toHaveLength(2);
    expect(result!.messages.at(-1)).toMatchObject({
      id: failedMessageId,
      error: { code: 'provider_error', retryable: true },
      isRetryAvailable: true,
    });

    result!.retryMessage(failedMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run'),
      10,
      20,
    )).toBe(true);
  });

  it('removes an unadmitted optimistic message when the user starts a different request', async () => {
    let resolveInitial!: (result: AgentV2RunResult) => void;
    let resolveNext!: (result: AgentV2RunResult) => void;
    startRunResponses = [
      new Promise((resolve) => {
        resolveInitial = resolve;
      }),
      new Promise((resolve) => {
        resolveNext = resolve;
      }),
    ];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Request that was not admitted');
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'network_error',
      retryable: true,
    });
    resolveInitial({ clientRunId: CLIENT_RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'failed' });
    expect(await waitFor(() => result?.messages.at(-1)?.error?.code === 'network_error', 10, 20)).toBe(true);

    result!.sendMessage('Different request');
    expect(await waitFor(() => Boolean(
      result?.messages.some(({ text }) => text === 'Different request'),
    ), 10, 20))
      .toBe(true);
    expect(result!.messages.some(({ text }) => text === 'Request that was not admitted')).toBe(false);
    resolveNext({ clientRunId: CLIENT_RUN_ID, state: 'completed' });
  });

  it('reuses append admission and canonical binding after a pre-admission quota retry', async () => {
    let resolveInitial!: (result: AgentV2RunResult) => void;
    let resolveRetry!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveInitial = resolve;
    })];
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Quota-delayed request');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const optimisticMessageId = result!.messages.at(-1)!.id;
    publishRetryableQuota();
    resolveInitial({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'failed',
    });
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run')
        && result?.isInputDisabled === true,
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    resolveRetry({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages.filter(({ text }) => text === 'Quota-delayed request')).toHaveLength(1);

    result!.sendMessage('After retry edit', optimisticMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').at(-1)).toEqual([
      'startAgentV2Run', expect.objectContaining({
        input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'After retry edit' },
      }),
    ]);
  });

  it('offers quota replay only for a pre-run denial', async () => {
    const resetAt = Date.parse('2026-08-08T00:00:00.000Z');
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAgentV2Update({
      kind: 'userQuotaChanged',
      quota: {
        limit: 20,
        used: 19,
        remaining: 1,
        resetAt: new Date(resetAt).toISOString(),
      },
    });
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'user_quota_exhausted',
      retryable: true,
      resetAt,
    });
    await pause(20);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });

    publishAgentV2Update({
      kind: 'runFailed',
      ...routing(),
      code: 'user_quota_exhausted',
      retryable: true,
      resetAt,
    });
    await pause(20);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', resetAt });
    expect(result!.composerStatus).not.toHaveProperty('clientRunId');
    result!.retryAdmission();
    await pause(0);
    expect(callApiMock).not.toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
  });

  it('unlocks the composer after a successful quota replay and accepts the next request', async () => {
    retryRunResponse = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'completed' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);
    const hydrationCallsBeforeRetry = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run')
        && result?.isInputDisabled === false
        && result.composerStatus === undefined,
      10,
      20,
    )).toBe(true);

    expect(callApiMock).toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRetry,
    );
    expect(result!.composerStatus).toBeUndefined();
    expect(result!.activity).toBeUndefined();

    result!.sendMessage('Request after replay');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'),
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: 'Request after replay' },
    }));
  });

  it('prevents duplicate limit replays while the first replay is pending', async () => {
    let resolveRetry!: (result: AgentV2RunResult) => void;
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    result!.retryAdmission();
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    result!.retryAdmission();

    expect(callApiMock.mock.calls.filter(([method]) => method === 'retryAgentV2Run')).toHaveLength(1);
    resolveRetry({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
  });

  it.each([
    ['failed', { clientRunId: CLIENT_RUN_ID, state: 'failed' } as AgentV2RunResult],
    ['missing', undefined],
  ])('unlocks the composer and preserves replay metadata after a %s retry result', async (_name, response) => {
    retryRunResponse = response;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run')
        && result?.isInputDisabled === false,
      10,
      20,
    )).toBe(true);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
  });

  it('preserves replay metadata when a failed replay emitted runStarted', async () => {
    let resolveRetry!: (value: AgentV2RunResult) => void;
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: threadRevision + 1,
    });
    resolveRetry({ clientRunId: CLIENT_RUN_ID, state: 'failed' });

    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
  });

  it('terminalizes partial streaming state when only the cancelled result arrives', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => (
      result?.isInputDisabled === false && result.messages.length === 1
    ), 10, 20)).toBe(true);
    const hydrationCallsBeforeRun = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.sendMessage('Cancel this request');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run')
        && result?.isInputDisabled === true,
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      delta: 'Partial cancelled response',
    });
    expect(await waitFor(() => result?.messages.at(-1)?.isStreaming === true, 10, 20)).toBe(true);
    const assistantMessageId = result!.messages.at(-1)!.id;

    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'cancelled',
    });
    expect(await waitFor(() => (
      result?.isInputDisabled === false
      && result.messages.at(-1)?.text === 'Partial cancelled response'
      && result.messages.at(-1)?.isStreaming === undefined
    ), 10, 20)).toBe(true);

    expect(result!.messages.at(-1)).toMatchObject({
      id: assistantMessageId,
      text: 'Partial cancelled response',
    });
    expect(result!.messages.at(-1)?.isStreaming).toBeUndefined();
    expect(result!.messages.at(-1)?.isTyping).toBeUndefined();
    expect(result!.textRevealPresentations[assistantMessageId]).toMatchObject({ status: 'error' });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRun,
    );
  });

  it('settles a cancelled replay without authoritative hydration', async () => {
    retryRunResponse = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'cancelled' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);
    const hydrationCallsBeforeRetry = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.retryAdmission();
    expect(await waitFor(
      () => result?.isInputDisabled === false
        && result.composerStatus === undefined,
      10,
      20,
    )).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRetry,
    );
  });

  it('treats an interrupted replay as a retryable failure and preserves its error after hydration', async () => {
    retryRunResponse = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'interrupted' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);
    hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
    const hydrationCallsBeforeRetry = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length
        > hydrationCallsBeforeRetry
        && result?.isInputDisabled === false
        && result.messages.length === 3,
      10,
      20,
    )).toBe(true);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
    expect(result!.messages.slice(0, 2).map(({ text }) => text)).toEqual([
      'Persisted request',
      'Retried response',
    ]);
    expect(result!.messages.at(-1)).toMatchObject({
      text: '',
      error: { code: 'network_error', retryable: true },
    });
  });

  it('does not let an earlier run settlement unlock a newer run', async () => {
    let resolveFirst!: (result: AgentV2RunResult) => void;
    let resolveSecond!: (result: AgentV2RunResult) => void;
    startRunResponses = [
      new Promise((resolve) => {
        resolveFirst = resolve;
      }),
      new Promise((resolve) => {
        resolveSecond = resolve;
      }),
    ];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.sendMessage('First request');
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 100)).toBe(true);
    publishAgentV2Update({
      kind: 'runFailed',
      ...routing(),
      code: 'agent_capacity_exhausted',
      retryable: true,
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.composerStatus).toEqual({ kind: 'capacity', mode: 'degraded' });
    expect(result!.messages.at(-1)).toMatchObject({ text: 'First request', isOutgoing: true });

    result!.sendMessage('Second request');
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2
        && result?.isInputDisabled === true,
      10,
      20,
    )).toBe(true);

    resolveFirst({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    await pause(20);
    expect(result!.isInputDisabled).toBe(true);

    resolveSecond({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
  });

  it('keeps a V1 reveal session active until the streamed response settles visually', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);

    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      delta: 'Streamed answer',
    });
    await pause(20);

    const assistantMessage = result!.messages.at(-1)!;
    const presentation = result!.textRevealPresentations[assistantMessage.id];
    expect(assistantMessage).toMatchObject({ text: 'Streamed answer', isStreaming: true });
    expect(presentation).toMatchObject({ status: 'active', shouldRevealFromStart: true });

    result!.consumeTextRevealSession(assistantMessage.id, presentation.key);
    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      finishReason: 'complete',
    });
    await pause(20);

    expect(result!.messages.at(-1)?.isStreaming).toBeUndefined();
    expect(result!.textRevealPresentations[assistantMessage.id]).toMatchObject({
      status: 'active',
      shouldRevealFromStart: false,
    });

    result!.settleTextRevealSession(assistantMessage.id, presentation.key);
    await pause(20);

    expect(result!.textRevealPresentations[assistantMessage.id]).toMatchObject({
      status: 'settled',
      shouldRevealFromStart: false,
    });
  });

  it('terminates the V1 reveal session when a V2 stream fails', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);

    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      delta: 'Partial answer',
    });
    await pause(20);

    const assistantMessageId = result!.messages.at(-1)!.id;
    publishAgentV2Update({
      kind: 'runFailed',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      code: 'agent_capacity_exhausted',
      retryable: true,
    });
    await pause(20);

    expect(result!.messages.at(-1)?.isStreaming).toBeUndefined();
    expect(result!.textRevealPresentations[assistantMessageId]).toMatchObject({
      status: 'error',
      shouldRevealFromStart: false,
    });
  });

  it('opens the existing transfer review for an activated Send action', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    actionPresentationPromise = Promise.resolve(sendPresentation());
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'semantic',
    });
    publishAgentV2Update({
      kind: 'actionAvailable',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      action,
    });
    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      finishReason: 'complete',
    });
    await pause(20);
    const message = result!.messages.at(-1)!;
    expect(message.actions).toEqual([action]);
    expect(message.actionPresentations?.[action.id]).toEqual(sendPresentation());
    resolvedAction = {
      kind: 'reviewSend',
      draftId: action.draftId,
      chain: 'ton',
      review: {
        tokenSlug: 'usd-tether',
        amountAtomic: '100000000',
        toAddress: 'EQ-mom-private',
        comment: 'Спасибо',
      },
    };

    result!.activateAction(message.id, action);
    await pause(20);

    const synchronizeCall = callApiMock.mock.calls.findIndex(([method]) => method === 'updateAgentV2HostContext');
    const resolveCall = callApiMock.mock.calls.findIndex(([method]) => method === 'resolveAgentV2Action');
    expect(synchronizeCall).toBeGreaterThanOrEqual(0);
    expect(resolveCall).toBeGreaterThan(synchronizeCall);
    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'usd-tether',
      amount: 100000000n,
      toAddress: 'EQ-mom-private',
      comment: 'Спасибо',
      shouldRequireFreshAuth: true,
    });
  });

  it('opens Send without an amount through the direct Open Send action', async () => {
    resolvedAction = {
      kind: 'sendForm',
      tokenSlug: 'gram',
      toAddress: 'EQ-defi-private',
    } satisfies AgentV2ResolvedAction;
    actionPresentationPromise = Promise.resolve(sendFormPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendFormAction();

    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'semantic',
    });
    publishAgentV2Update({
      kind: 'actionAvailable',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      action,
    });
    await pause(20);

    expect(callApiMock).not.toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    const message = result!.messages.find(({ actions }) => actions?.some(({ id }) => id === action.id))!;
    expect(message.actionPresentations?.[action.id]).toEqual(sendFormPresentation());
    result!.activateAction(message.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'gram',
      amount: undefined,
      toAddress: 'EQ-defi-private',
      comment: undefined,
      shouldRequireFreshAuth: true,
    });
  });

  it.each([
    {
      name: 'Receive',
      action: receiveAction(),
      resolved: { kind: 'openReceive', chain: 'ton' } satisfies AgentV2ResolvedAction,
      verify: () => expect(mockOpenReceiveModal).toHaveBeenCalledWith({ chain: 'ton' }),
    },
    {
      name: 'Hide spam assets',
      action: hideSpamAssetsAction(),
      resolved: { kind: 'hideSpamAssets', slugs: ['spam-one', 'spam-two'] } satisfies AgentV2ResolvedAction,
      verify: () => expect(mockToggleTokenVisibility.mock.calls).toEqual([
        [{ slug: 'spam-one', shouldShow: false }],
        [{ slug: 'spam-two', shouldShow: false }],
      ]),
    },
    {
      name: 'Open URL',
      action: openUrlAction(),
      resolved: { kind: 'openUrl', url: 'https://example.com/help' } satisfies AgentV2ResolvedAction,
      verify: () => expect(openUrlMock).toHaveBeenCalledWith(
        'https://example.com/help',
        { isExternal: true },
      ),
    },
    {
      name: 'Open token',
      action: openTokenAction(),
      resolved: { kind: 'openToken', slug: 'toncoin', chain: 'ton' } satisfies AgentV2ResolvedAction,
      verify: () => {
        expect(mockShowTokenActivity).toHaveBeenCalledWith({ slug: 'toncoin' });
        expect(mockSwitchToWallet).toHaveBeenCalledTimes(1);
      },
    },
    {
      name: 'Open transaction',
      action: openTransactionAction(),
      resolved: {
        kind: 'openTransaction',
        chain: 'ton',
        transactionRef: 'transaction-hash',
      } satisfies AgentV2ResolvedAction,
      verify: () => expect(mockOpenTransactionInfo).toHaveBeenCalledWith({
        txHash: 'transaction-hash',
        chain: 'ton',
      }),
    },
    {
      name: 'Open Agent',
      action: openAgentAction(),
      resolved: { kind: 'openAgent', entryPoint: { kind: 'agentTab' } } satisfies AgentV2ResolvedAction,
      verify: () => expect(mockSwitchToAgent).toHaveBeenCalledTimes(1),
    },
  ])('dispatches a resolved $name action after an explicit click', async ({ action, resolved, verify }) => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    resolvedAction = resolved;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    verify();
  });

  it('marks an action inactive when explicit resolution rejects it', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = receiveAction();
    publishAction(action);
    await pause(20);
    resolvedAction = { kind: 'inactive' } satisfies AgentV2ResolvedAction;
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    await pause(20);

    expect(mockOpenReceiveModal).not.toHaveBeenCalled();
    expect(result!.messages.at(-1)?.actionPresentations?.[action.id]).toEqual({ kind: 'inactive' });
  });

  it.each([
    {
      name: 'source-sided Swap',
      action: swapAction('source'),
      resolved: {
        kind: 'openSwap',
        tokenInSlug: 'toncoin',
        tokenOutSlug: 'usdton',
        amount: '10',
        amountSide: 'source',
      } satisfies AgentV2ResolvedAction,
      verify: () => {
        expect(mockStartSwap).toHaveBeenCalledWith({
          tokenInSlug: 'toncoin', tokenOutSlug: 'usdton', amountIn: '10',
        });
        expect(mockSetSwapAmountIn).toHaveBeenCalledWith({ amount: '10' });
        expect(mockSetSwapAmountOut).not.toHaveBeenCalled();
      },
    },
    {
      name: 'destination-sided Swap',
      action: swapAction('destination'),
      resolved: {
        kind: 'openSwap',
        tokenInSlug: 'usdton',
        tokenOutSlug: 'toncoin',
        amount: '10',
        amountSide: 'destination',
      } satisfies AgentV2ResolvedAction,
      verify: () => {
        expect(mockStartSwap).toHaveBeenCalledWith({ tokenInSlug: 'usdton', tokenOutSlug: 'toncoin' });
        expect(mockSetSwapAmountOut).toHaveBeenCalledWith({ amount: '10' });
        expect(mockSetSwapAmountIn).not.toHaveBeenCalled();
      },
    },
  ])('revalidates and opens $name in the existing Swap flow', async ({ action, resolved, verify }) => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    resolvedAction = resolved;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockSwitchToWallet).toHaveBeenCalledTimes(1);
    expect(processDeeplinkMock).not.toHaveBeenCalled();
    verify();
  });

  it('revalidates exact Staking before opening its exact deeplink', async () => {
    const action = exactStakeAction();
    const resolved = {
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    } satisfies AgentV2ResolvedAction;
    const deeplink = 'mtw://stake?product=liquid&asset=toncoin&amount=10';
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    resolvedAction = resolved;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(processDeeplinkMock).toHaveBeenCalledWith(deeplink);
    expect(mockSwitchToWallet).toHaveBeenCalledTimes(1);
  });

  it('uses current runtime authority for Swap without Send-specific host synchronization', async () => {
    const action = swapAction('source');
    resolvedAction = {
      kind: 'openSwap',
      tokenInSlug: 'toncoin',
      tokenOutSlug: 'usdton',
      amount: '10',
      amountSide: 'source',
    } satisfies AgentV2ResolvedAction;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartSwap).toHaveBeenCalledWith({
      tokenInSlug: 'toncoin', tokenOutSlug: 'usdton', amountIn: '10',
    });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(0);
  });

  it('does not open Swap when current wallet authority rejects the action', async () => {
    const action = swapAction('source');
    resolvedAction = { kind: 'inactive' } satisfies AgentV2ResolvedAction;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartSwap).not.toHaveBeenCalled();
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it('does not apply an account action after the active account changes during resolution', async () => {
    const resolution = createDeferred<unknown>();
    resolvedActionPromise = resolution.promise;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = hideSpamAssetsAction();
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    buildAgentV2HostContextMock.mockReturnValue(hostContext('account-two'));
    resolution.resolve({ kind: 'hideSpamAssets', slugs: ['spam-one'] });
    await pause(20);

    expect(mockToggleTokenVisibility).not.toHaveBeenCalled();
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(0);
  });

  it('keeps a hydrated Send action inactive without its local draft', async () => {
    const action = sendAction();
    hydratedMessages = [
      persistedUserMessage(),
      persistedAssistantMessage(action),
    ];
    actionPresentationPromise = Promise.resolve({ kind: 'inactive' });

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    await pause(20);

    const message = result!.messages.at(-1)!;
    expect(message.actionPresentations?.[action.id]).toEqual({ kind: 'inactive' });
    result!.activateAction(message.id, action);
    await pause(0);

    expect(callApiMock).not.toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartTransfer).not.toHaveBeenCalled();
  });

  it('opens a hydrated Send action when its local draft was restored', async () => {
    const action = sendAction();
    hydratedMessages = [
      persistedUserMessage(),
      persistedAssistantMessage(action),
    ];
    actionPresentationPromise = Promise.resolve(sendPresentation());
    resolvedAction = {
      kind: 'reviewSend',
      draftId: action.draftId,
      chain: 'ton',
      review: {
        tokenSlug: 'gram',
        amountAtomic: '500000000',
        toAddress: 'EQ-mom-private',
      },
    } satisfies AgentV2ResolvedAction;

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    await pause(20);

    const message = result!.messages.at(-1)!;
    expect(message.actionPresentations?.[action.id]).toEqual(sendPresentation());
    result!.activateAction(message.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'gram',
      amount: 500000000n,
      toAddress: 'EQ-mom-private',
      comment: undefined,
      shouldRequireFreshAuth: true,
    });
  });

  it('reloads Send presentation after wallet authority changes and ignores the stale result', async () => {
    let resolvePresentation!: (presentation: AgentV2ActionPresentation) => void;
    actionPresentationPromise = new Promise((resolve) => {
      resolvePresentation = resolve;
    });
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2ActionPresentation'),
      10,
      20,
    )).toBe(true);
    expect(await waitFor(
      () => Boolean(result!.messages.at(-1)?.actions?.some(({ id }) => id === action.id)),
      10,
      20,
    )).toBe(true);

    actionPresentationPromise = Promise.resolve(sendPresentation());
    publishAgentV2Update({ kind: 'walletAuthorityChanged' });
    await pause(20);
    resolvePresentation(sendPresentation());
    await pause(20);

    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2ActionPresentation')).toHaveLength(2);
    expect(result!.messages.at(-1)?.actionPresentations?.[action.id]).toEqual(sendPresentation());
  });

  it('opens Send after an unrelated wallet-profile authority update', async () => {
    actionPresentationPromise = Promise.resolve(sendPresentation());
    resolvedAction = {
      kind: 'reviewSend',
      draftId: sendAction().draftId,
      chain: 'ton',
      review: {
        tokenSlug: 'gram',
        amountAtomic: '500000000',
        toAddress: 'EQ-mom-private',
      },
    } satisfies AgentV2ResolvedAction;
    hasAuthorityChanged = true;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'gram',
      amount: 500000000n,
      toAddress: 'EQ-mom-private',
      shouldRequireFreshAuth: true,
    });
  });

  it('opens Send when an unrelated wallet-profile update arrives during action resolution', async () => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({ kind: 'walletAuthorityChanged' });
    resolveSend({
      kind: 'reviewSend',
      draftId: action.draftId,
      chain: 'ton',
      review: {
        tokenSlug: 'gram',
        amountAtomic: '500000000',
        toAddress: 'EQ-mom-private',
      },
    });
    await pause(20);

    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'gram',
      amount: 500000000n,
      toAddress: 'EQ-mom-private',
      shouldRequireFreshAuth: true,
    });
  });

  it('does not open Send when wallet authority changes during action resolution', async () => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    buildAgentV2HostContextMock.mockReturnValue(hostContext('account-two'));
    hasAuthorityChanged = true;
    resolveSend({
      kind: 'reviewSend',
      draftId: action.draftId,
      chain: 'ton',
      review: {
        tokenSlug: 'toncoin',
        amountAtomic: '1500000000',
        toAddress: 'EQ-private',
      },
    });
    await pause(20);

    expect(mockStartTransfer).not.toHaveBeenCalled();
    expect(result!.messages.at(-1)?.actionPresentations?.[action.id]).toEqual({ kind: 'inactive' });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(2);
  });

  it('does not open Send when the active sending address changes during resolution', async () => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    const changedContext = hostContext();
    changedContext.accounts[0].addresses.ton = 'EQ-changed-public-address';
    buildAgentV2HostContextMock.mockReturnValue(changedContext);
    hasAuthorityChanged = true;
    resolveSend({
      kind: 'reviewSend',
      draftId: action.draftId,
      chain: 'ton',
      review: {
        tokenSlug: 'toncoin',
        amountAtomic: '1500000000',
        toAddress: 'EQ-private',
      },
    });
    await pause(20);

    expect(mockStartTransfer).not.toHaveBeenCalled();
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(2);
  });

  it('invalidates pending action resolutions when the runtime changes', async () => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 98 });
    resolveSend({
      kind: 'reviewSend',
      draftId: action.draftId,
      chain: 'ton',
      review: {
        tokenSlug: 'toncoin',
        amountAtomic: '1500000000',
        toAddress: 'EQ-private',
      },
    });
    await pause(20);

    expect(mockStartTransfer).not.toHaveBeenCalled();

    let resolveReceive!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveReceive = resolve;
    });
    const receive = receiveAction();
    publishAction(receive);
    const receiveMessage = result!.messages.at(-1)!;
    result!.activateAction(receiveMessage.id, receive);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 99 });
    resolveReceive({ kind: 'openReceive', chain: 'ton' });
    await pause(20);

    expect(mockOpenReceiveModal).not.toHaveBeenCalled();
  });

  it('does not apply an action that resolves after the Agent view is disposed', async () => {
    const resolution = createDeferred<unknown>();
    resolvedActionPromise = resolution.promise;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = receiveAction();
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    TeactDOM.render(undefined, root);
    resolution.resolve({ kind: 'openReceive', chain: 'ton' });
    await pause(20);

    expect(mockOpenReceiveModal).not.toHaveBeenCalled();
  });

  it('ignores a stale hydration after a newer runtime hydration settles', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Persisted request'
    ))), 10, 20)).toBe(true);
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const staleHydration = createDeferred<unknown>();
    const currentHydration = createDeferred<unknown>();
    let hydrationCount = 0;
    callApiMock.mockImplementation((...args) => {
      if (args[0] !== 'getAgentV2Messages') return defaultImplementation(...args);
      hydrationCount += 1;
      return (hydrationCount === 1 ? staleHydration.promise : currentHydration.promise) as never;
    });

    publishAgentV2Update({ kind: 'runtimeReady', generation: 101 });
    expect(await waitFor(() => hydrationCount === 1, 10, 20)).toBe(true);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 102 });
    expect(await waitFor(() => hydrationCount === 2, 10, 20)).toBe(true);
    currentHydration.resolve(hydrationResult('Current runtime response'));
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Current runtime response'
    ))), 10, 20)).toBe(true);
    staleHydration.resolve(hydrationResult('Stale runtime response'));
    await pause(20);

    expect(result?.messages.some(({ text }) => text === 'Stale runtime response')).toBe(false);
  });

  it('rehydrates an accepted conversation when a new runtime becomes ready', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    expect(await waitFor(() => (
      callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages')
    ), 10, 20)).toBe(true);
    const initialHydrationCount = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    publishAgentV2Update({ kind: 'runtimeReady', generation: 100 });

    expect(await waitFor(() => (
      callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length
      > initialHydrationCount
    ), 10, 20)).toBe(true);
  });

  function Harness() {
    result = useAgentV2Messages({ isActive: true, lang });
    return <div />;
  }

  function publishSendAction(action: ReturnType<typeof sendAction>) {
    publishAction(action);
  }

  function publishAction(action: AgentActionProposal) {
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'semantic',
    });
    publishAgentV2Update({
      kind: 'actionAvailable',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      action,
    });
    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      finishReason: 'complete',
    });
  }

  function publishRetryableQuota() {
    const resetAt = Date.now() - 1_000;
    publishAgentV2Update({
      kind: 'userQuotaChanged',
      quota: {
        limit: 20,
        used: 19,
        remaining: 1,
        resetAt: new Date(resetAt).toISOString(),
      },
    });
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'user_quota_exhausted',
      retryable: true,
      resetAt,
    });
  }
});

function threadSummary(revision: number): AgentThreadSummaryV2 {
  return {
    id: THREAD_ID,
    revision,
    metadataRevision: 1,
    titleSource: 'none',
    isPinned: false,
    isDefault: true,
    createdAt: '2026-08-07T10:00:00.000Z',
    updatedAt: '2026-08-07T10:00:00.000Z',
    lastActivityAt: '2026-08-07T10:00:00.000Z',
    messageCount: 1,
  };
}

function successfulClear(revision: number): AgentV2MutationResult<AgentThreadClearResponseV2> {
  return {
    ok: true,
    value: {
      protocolVersion: 2,
      thread: threadSummary(revision),
      duplicate: false,
    },
  };
}

function routing() {
  return {
    clientRunId: CLIENT_RUN_ID,
    runId: RUN_ID,
    threadId: THREAD_ID,
  };
}

function sendAction() {
  return {
    id: '66666666-6666-4666-8666-666666666666',
    kind: 'send' as const,
    labelCode: 'review_transfer' as const,
    draftId: '77777777-7777-4777-8777-777777777777',
    draftExpiresAt: '2099-08-07T10:10:00.000Z',
    sourceToolCallId: '88888888-8888-4888-8888-888888888888',
    effect: 'open_wallet_review' as const,
    localDraftRequired: true as const,
    requiresConfirmation: true as const,
  };
}

function receiveAction(): Extract<AgentActionProposal, { kind: 'receive' }> {
  return {
    id: '66666666-6666-4666-8666-666666666661',
    kind: 'receive',
    labelCode: 'open_receive',
    effect: 'open_receive',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
      activeNetwork: 'ton',
    },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function exactStakeAction(): Extract<AgentActionProposal, { kind: 'stake' }> {
  return {
    id: '66666666-6666-4666-8666-666666666660',
    schemaVersion: 2,
    kind: 'stake',
    labelCode: 'open_staking',
    effect: 'open_staking',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
    },
    productId: 'liquid',
    asset: {
      slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9,
    },
    amount: { kind: 'exact', value: '10' },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function swapAction(side: 'source' | 'destination'): Extract<AgentActionProposal, { kind: 'swap' }> {
  const isSource = side === 'source';
  return {
    id: isSource
      ? '66666666-6666-4666-8666-666666666667'
      : '66666666-6666-4666-8666-666666666668',
    schemaVersion: 1,
    kind: 'swap',
    labelCode: 'open_swap',
    effect: 'open_swap',
    sourceToolCallId: '88888888-8888-4888-8888-888888888888',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
    },
    sourceAsset: isSource
      ? { slug: 'toncoin', chain: 'ton', symbol: 'TON' }
      : { slug: 'usdton', chain: 'ton', symbol: 'USDT' },
    destinationAsset: isSource
      ? { slug: 'usdton', chain: 'ton', symbol: 'USDT' }
      : { slug: 'toncoin', chain: 'ton', symbol: 'TON' },
    amount: { value: '10', valueType: 'decimal', side },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function sendFormAction(): Extract<AgentActionProposal, { kind: 'send'; effect: 'open_send' }> {
  return {
    id: '66666666-6666-4666-8666-666666666660',
    kind: 'send',
    labelCode: 'open_send',
    effect: 'open_send',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
      activeNetwork: 'ton',
    },
    asset: { slug: 'gram', chain: 'ton' },
    recipient: { kind: 'savedAddress', addressRef: 'address-defi' },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function hideSpamAssetsAction(): Extract<AgentActionProposal, { kind: 'hideSpamAssets' }> {
  return {
    id: '66666666-6666-4666-8666-666666666662',
    kind: 'hideSpamAssets',
    labelCode: 'hide_spam_assets',
    sourceToolCallId: '88888888-8888-4888-8888-888888888888',
    assetRefs: ['spam-one', 'spam-two'],
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
    },
    effect: 'hide_spam_assets',
    localMutationRequired: true,
    requiresConfirmation: false,
  };
}

function openUrlAction(): Extract<AgentActionProposal, { kind: 'openUrl' }> {
  return {
    id: '66666666-6666-4666-8666-666666666663',
    kind: 'openUrl',
    labelCode: 'open_external_link',
    url: 'https://example.com/help',
    requiresConfirmation: true,
  };
}

function openTokenAction(): Extract<AgentActionProposal, { kind: 'openToken' }> {
  return {
    id: '66666666-6666-4666-8666-666666666664',
    kind: 'openToken',
    labelCode: 'open_token',
    slug: 'toncoin',
    chain: 'ton',
    requiresConfirmation: true,
  };
}

function openTransactionAction(): Extract<AgentActionProposal, { kind: 'openTransaction' }> {
  return {
    id: '66666666-6666-4666-8666-666666666665',
    kind: 'openTransaction',
    labelCode: 'open_transaction',
    chain: 'ton',
    transactionRef: 'transaction-hash',
    requiresConfirmation: true,
  };
}

function openAgentAction(): Extract<AgentActionProposal, { kind: 'openAgent' }> {
  return {
    id: '66666666-6666-4666-8666-666666666666',
    kind: 'openAgent',
    labelCode: 'open_agent',
    entryPoint: { kind: 'agentTab' },
    requiresConfirmation: true,
  };
}

function sendPresentation(): AgentV2ActionPresentation {
  return {
    kind: 'send',
    status: 'active',
    amount: { value: '1.5', symbol: 'TON' },
    network: 'ton',
    accountLabel: 'Main',
    recipient: { kind: 'savedAddress', label: 'Mom' },
    feeStatus: 'calculated_in_wallet',
    warningCodes: ['new_address'],
    expiresAt: '2099-08-07T10:10:00.000Z',
  };
}

function sendFormPresentation(): AgentV2ActionPresentation {
  return {
    kind: 'send',
    status: 'active',
    network: 'ton',
    accountLabel: 'Main',
    recipient: { kind: 'savedAddress', label: 'DeFi' },
    feeStatus: 'calculated_in_wallet',
    warningCodes: [],
  };
}

function persistedUserMessage(): AgentV2HydratedMessage {
  return {
    id: MESSAGE_ID,
    threadId: THREAD_ID,
    role: 'user',
    status: 'complete',
    content: { kind: 'markdown', text: 'Persisted request' },
    createdAt: '2026-08-07T10:00:00.000Z',
  };
}

function persistedAssistantTextMessage(): AgentV2HydratedMessage {
  return {
    id: ASSISTANT_MESSAGE_ID,
    threadId: THREAD_ID,
    role: 'assistant',
    status: 'complete',
    content: { kind: 'markdown', text: 'Retried response' },
    createdAt: '2026-08-07T10:00:01.000Z',
  };
}

function persistedAssistantMessage(action: ReturnType<typeof sendAction>): AgentV2HydratedMessage {
  return {
    id: ASSISTANT_MESSAGE_ID,
    threadId: THREAD_ID,
    role: 'assistant',
    status: 'complete',
    actions: [action],
    createdAt: '2026-08-07T10:00:01.000Z',
  };
}

function persistedMessage(
  id: string,
  role: 'user' | 'assistant',
  text: string,
  timestamp: number,
): AgentV2HydratedMessage {
  return {
    id,
    threadId: THREAD_ID,
    role,
    status: 'complete',
    content: { kind: 'markdown', text },
    createdAt: new Date(timestamp * 1_000).toISOString(),
  };
}

function conversationMessages() {
  return [
    persistedMessage(MESSAGE_ID, 'user', 'First request', 1),
    persistedMessage(ASSISTANT_MESSAGE_ID, 'assistant', 'First response', 2),
    persistedMessage(SECOND_USER_MESSAGE_ID, 'user', 'Second request', 3),
    persistedMessage(SECOND_ASSISTANT_MESSAGE_ID, 'assistant', 'Second response', 4),
  ];
}

function hostContext(accountId = 'account-one'): AgentV2HostContextSnapshot {
  return {
    platform: 'classic',
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    activeAccountId: accountId,
    activeNetwork: 'ton',
    isTestnet: false,
    stakingOffers: [{
      productId: 'liquid',
      asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
      annualYield: '14.09',
      yieldType: 'APY',
      availability: 'available',
    }],
    accounts: [{
      accountId,
      label: 'Main',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-public' },
      holdings: [{
        asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        balance: '10',
      }],
    }],
    savedAddresses: [],
  };
}

function hydrationResult(text: string) {
  return {
    ok: true as const,
    value: {
      thread: threadSummary(5),
      messages: [{
        ...persistedAssistantTextMessage(),
        content: { kind: 'markdown' as const, text },
      }],
    },
  };
}

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}
