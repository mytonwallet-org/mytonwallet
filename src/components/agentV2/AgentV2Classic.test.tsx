import React, { useState, type VirtualElementComponent } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentPublicFollowUpV2, AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import type { AgentConversation, AgentConversationShellProps } from '../agent/AgentConversationShell';
import type { UseAgentV2MessagesResult } from '../agent/hooks/useAgentV2Messages';

import { getAgentV2LocalState, resetAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import Deferred from '../../util/Deferred';
import { openUrl } from '../../util/openUrl';
import { pause, rafPromise, waitFor } from '../../util/schedulers';
import { shareUrl } from '../../util/share';
import { formatAgentTime } from '../agent/helpers/agentDateFormat';
import { copyAgentText } from '../agent/helpers/copyAgentText';
import { markAgentThreadShown } from './agentThreadReadState';

import useAgentV2Messages from '../agent/hooks/useAgentV2Messages';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentInputBar from '../agent/AgentInputBar';
import AgentNewsPost from './AgentNewsPost';
import { AgentV2Classic } from './AgentV2Classic';
import AgentV2IncomingMessage from './AgentV2IncomingMessage';

const mockSwitchToWallet = jest.fn();

jest.mock('../../global', () => ({
  ...jest.requireActual('../../global'),
  getActions: () => ({ switchToWallet: mockSwitchToWallet }),
  withGlobal: () => (Component: unknown) => Component,
}));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string, value?: string) => (
    key === '$agent_daily_limit_resets_at' ? `${key}:${value}` : key
  ), { code: 'en' }),
}));
jest.mock('../agent/hooks/useAgentV2Messages', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../util/share', () => ({ shareUrl: jest.fn() }));
jest.mock('../agent/helpers/copyAgentText', () => ({ copyAgentText: jest.fn() }));
jest.mock('../agent/AgentConversationShell', () => ({
  __esModule: true,
  default: jest.fn((props: AgentConversationShellProps) => props.composer!.render?.({
    inputRef: { current: undefined },
    inputValue: '',
    isDisabled: false,
    onInput: jest.fn(),
    onKeyDown: jest.fn(),
    onSend: jest.fn(),
    onRequestConsent: props.composer!.onRequestConsent,
  })),
}));
jest.mock('../agent/AgentInputBar', () => ({
  __esModule: true,
  default: jest.fn(() => undefined),
}));
jest.mock('./AgentV2IncomingMessage', () => ({
  __esModule: true,
  default: jest.fn(() => undefined),
}));

const NEWS = {
  eventId: 5,
  headline: 'News headline',
  body: 'Complete **news** body',
  publishedAt: '2026-10-21T09:00:00.000Z',
  sources: [{ name: 'Source', url: 'https://example.com' }],
};
const NEWS_POST: AgentMessage = {
  id: -2,
  text: '**News headline**\n\nComplete **news** body',
  isOutgoing: false,
  isNewsPost: true,
  timestamp: 1,
};
const DIGEST = {
  id: 'digest-1', windowEnd: '2026-10-21T21:00:00.000Z', total: 1, top: [{ eventId: 5, headline: 'News headline' }],
};
const NEWS_FOLLOWUP: AgentPublicFollowUpV2 = {
  id: 'news-followup-1', kind: 'suggested_prompt', text: 'What does this news mean for TON?',
};

const useAgentV2MessagesMock = jest.mocked(useAgentV2Messages);
const AgentConversationShellMock = jest.mocked(AgentConversationShell);
const AgentInputBarMock = jest.mocked(AgentInputBar);
const AgentV2IncomingMessageMock = jest.mocked(AgentV2IncomingMessage);

describe('AgentV2Classic', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(portals);
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult());
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
    jest.clearAllMocks();
  });

  it.each(['opening', 'failed', 'consent', 'empty'] as const)(
    'offers deletion with synchronous cancellation for a bound %s chat', async (status) => {
      const timestamp = '2026-10-21T12:00:00.000Z';
      const thread = status === 'empty' ? {
        id: 'empty-thread', revision: 1, messageCount: 0,
        createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
      } : undefined;
      const messagesResult = buildMessagesResult({
        messages: [],
        thread,
        isInitialLoadComplete: status === 'empty' || status === 'failed',
        isConsentAccepted: status === 'consent' ? false : undefined,
        historyFailure: status === 'failed' ? { text: 'Load failed', isRetrying: false } : undefined,
      });
      useAgentV2MessagesMock.mockReturnValue(messagesResult);
      const onDelete = jest.fn();
      TeactDOM.render(
        <AgentV2Classic
          isActive
          animationLevel={0}
          target={thread ? { kind: 'thread', threadId: thread.id } : { kind: 'new' }}
          onDelete={onDelete}
        />,
        root,
      );
      await pause(20);

      const { header, actions } = AgentConversationShellMock.mock.calls.at(-1)![0];
      expect(header?.hasMenu).toBe(true);
      expect(actions?.onDelete).toBeDefined();
      actions.onDelete!();
      expect(onDelete).toHaveBeenCalledWith(thread, messagesResult.cancelPendingRequests);
      expect(messagesResult.cancelPendingRequests).not.toHaveBeenCalled();
    },
  );

  it.each([false, true])('waits for a chat\'s history in its placeholder unless it is cached: %s', async (isCached) => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ isOpenedWithCachedHistory: isCached }));
    TeactDOM.render(
      <AgentV2Classic isActive animationLevel={0} target={{ kind: 'thread', threadId: 'thread' }} />,
      root,
    );
    await pause(20);

    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.hasHistoryPlaceholder).toBe(!isCached);
  });

  it.each([false, true])('tells the list of the question a new chat opens with: %s', async (hasPendingQuestion) => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ hasPendingQuestion }));
    TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={{ kind: 'new' }}
        initialMessage={hasPendingQuestion ? 'Question' : undefined}
      />,
      root,
    );
    await pause(20);

    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.hasOpeningQuestion).toBe(hasPendingQuestion);
  });

  it('shapes the placeholder once as the chat\'s list row tells: its message count and its news', async () => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ isOpenedWithCachedHistory: false }));
    const timestamp = '2026-10-21T12:00:00.000Z';
    const listed: AgentThreadSummaryV2 = {
      id: 'thread', revision: 1, createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp, messageCount: 2,
      news: { eventId: 5, headline: 'Headline', publishedAt: timestamp },
    };
    const render = (initialThread: AgentThreadSummaryV2) => TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={{ kind: 'thread', threadId: 'thread' }}
        initialThread={initialThread}
      />,
      root,
    );
    render(listed);
    await pause(20);
    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.historyPlaceholderLayout)
      .toEqual({ messageCount: 2, isNews: true });

    // A newer list row doesn't reshape the placeholder on screen
    render({ ...listed, messageCount: 3 });
    await pause(20);
    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.historyPlaceholderLayout)
      .toEqual({ messageCount: 2, isNews: true });
  });

  it('opens with the hint tapped under the chat list and sends a hint tapped in the empty chat', async () => {
    const hint = {
      id: 'action.swap', langCode: 'en' as const, title: 'Swap tokens', subtitle: '', prompt: 'Swap tokens',
    };
    const entryPoint = {
      kind: 'emptyState', surface: 'agentTab', hintId: 'action.swap', catalogVersion: 'agent-starter-hints-v2',
    } as const;
    const sendHint = jest.fn();
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ hints: [hint], sendHint }));
    TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={{ kind: 'new' }}
        initialMessage="Swap tokens"
        initialHintEntryPoint={entryPoint}
      />,
      root,
    );
    await pause(20);

    expect(useAgentV2MessagesMock).toHaveBeenLastCalledWith(expect.objectContaining({
      initialMessage: 'Swap tokens', initialHintEntryPoint: entryPoint,
    }));
    const shellProps = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(shellProps.conversation.hints).toEqual([hint]);
    shellProps.composer!.onSendHint(hint);
    expect(sendHint).toHaveBeenCalledWith(hint);
  });

  it('does not offer deletion for an untouched composer without a target or thread', async () => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ messages: [], thread: undefined }));
    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} onDelete={jest.fn()} />, root);
    await pause(20);
    const { header, actions } = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(header).toBeUndefined();
    expect(actions?.onDelete).toBeUndefined();
  });

  it.each([
    { hasConsent: false, hasQuestion: false, canDelete: false },
    { hasConsent: true, hasQuestion: false, canDelete: false },
    { hasConsent: true, hasQuestion: true, canDelete: true },
    { hasConsent: false, hasQuestion: false, canDelete: false, isDigest: true },
    { hasConsent: true, hasQuestion: false, canDelete: false, isDigest: true },
    { hasConsent: true, hasQuestion: true, canDelete: true, isDigest: true },
  ])('offers deletion in a news discussion once the user writes there: %o', async ({
    hasConsent, hasQuestion, canDelete, isDigest = false,
  }) => {
    const timestamp = '2026-10-21T12:00:00.000Z';
    const question: AgentMessage = { id: 1, text: 'Why?', isOutgoing: true, timestamp: 2 };
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      news: isDigest ? undefined : NEWS,
      // The thread still counts the post alone: the question sent here counts before the thread learns of it
      thread: {
        id: 'news-thread', revision: 1, messageCount: 1,
        createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
        ...(isDigest ? { digest: { id: 'digest', windowEnd: timestamp, total: 1, top: [] } } : { news: NEWS }),
      },
      messages: hasQuestion ? [NEWS_POST, question] : [NEWS_POST],
    }));
    TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={{ kind: 'thread', threadId: 'news-thread' }}
        hasConsent={hasConsent}
        onDelete={jest.fn()}
        onRequestConsent={jest.fn()}
      />,
      root,
    );
    await pause(20);

    const { header, actions } = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(header?.hasMenu).toBe(true);
    expect(Boolean(actions?.onDelete)).toBe(canDelete);
    // Problem reports, which also need consent, are checked once it comes
    expect(useAgentV2MessagesMock).toHaveBeenLastCalledWith(expect.objectContaining({ hasConsent }));
  });

  it.each((['news', 'digest'] as const).flatMap((kind) => [
    { kind, hasNaming: false }, { kind, hasNaming: true },
  ]))('uses feed naming and report availability until a discussion thread exists: %o', async ({ kind, hasNaming }) => {
    const discussionNaming = hasNaming ? { title: 'Discuss TON news', icon: '💎', followups: [] } : undefined;
    const isDigest = kind === 'digest';
    const result = buildMessagesResult({
      ...(isDigest ? { digest: DIGEST } : { news: NEWS }),
      messages: [NEWS_POST], isOpeningNews: true, reportProblem: undefined,
    });
    useAgentV2MessagesMock.mockReturnValue(result);
    const target = {
      ...(isDigest
        ? { kind: 'digest' as const, digest: { id: DIGEST.id }, digestPreview: DIGEST }
        : { kind: 'news' as const, news: { eventId: 5, locale: 'ru' as const }, preview: NEWS }),
      shouldDeferCreation: true, discussionNaming,
    };
    const onThreadResolved = jest.fn();
    TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={target}
        onDelete={jest.fn()}
        chatKey={5}
        onThreadResolved={onThreadResolved}
      />,
      root,
    );
    await pause(20);
    const notifyThreadResolved = useAgentV2MessagesMock.mock.calls.at(-1)![0].onThreadResolved!;

    const { header, actions, composer } = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(header?.title).toBe(discussionNaming?.title ?? (isDigest ? '$agent_digest_title' : NEWS.headline));
    expect(header?.icon).toBe(discussionNaming?.icon);
    expect(actions?.onReportProblem).toBeUndefined();
    expect(actions?.onDelete).toBeUndefined();
    expect(composer?.isDisabled).toBe(false);
    expect(composer?.shouldHide).toBe(false);
    const post = AgentConversationShellMock.mock.calls.at(-1)![0].conversation.renderMessage(NEWS_POST, {
      shouldAnimateTextStreaming: false, isJustAdded: false,
      onEditMessage: jest.fn(), onTextRevealProgress: jest.fn(), onRequestLiveTail: jest.fn(),
    }) as unknown as VirtualElementComponent;
    expect(post.props.shouldShowFollowups).toBe(false);
    // The post shares the news in the language the discussion opened it in, apart from the app's
    expect(post.props.locale).toBe(isDigest ? undefined : 'ru');

    const timestamp = '2026-10-21T12:00:00.000Z';
    const reportProblem = jest.fn(() => Promise.resolve('sent' as const));
    useAgentV2MessagesMock.mockReturnValue({
      ...result,
      reportProblem,
      thread: {
        id: 'news-thread', revision: 1, messageCount: 1, title: 'Saved news title', icon: '📰',
        ...(isDigest ? { digest: DIGEST } : { news: NEWS }),
        createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
      },
    });
    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} target={target} />, root);
    expect(await waitFor(() => (
      AgentConversationShellMock.mock.calls.at(-1)?.[0].header?.title === 'Saved news title'
    ), 10, 300)).toBe(true);
    expect(AgentConversationShellMock.mock.calls.at(-1)![0].header?.icon).toBe('📰');
    expect(AgentConversationShellMock.mock.calls.at(-1)![0].actions?.onReportProblem).toBe(reportProblem);
    TeactDOM.render(undefined, root);
    await rafPromise();
    notifyThreadResolved('created-news-thread');
    expect(onThreadResolved).toHaveBeenCalledWith(5, 'created-news-thread', target);
  });

  it('ends the chat with provider capacity as its status line and leaves the input bar to the draft', async () => {
    const onInitialMessageSent = jest.fn();
    TeactDOM.render(
      <AgentV2Classic isActive chatKey={7} animationLevel={0} onInitialMessageSent={onInitialMessageSent} />,
      root,
    );
    await pause(20);

    useAgentV2MessagesMock.mock.calls.at(-1)![0].onInitialMessageSent!();
    expect(onInitialMessageSent).toHaveBeenCalledTimes(1);
    expect(onInitialMessageSent).toHaveBeenCalledWith(7);
    const inputBarProps = AgentInputBarMock.mock.calls.at(-1)![0];
    expect(inputBarProps.isDimmed).toBe(false);

    const shellProps = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(shellProps.slots?.messageListFooter).toBeDefined();
    expect(shellProps.slots?.beforeComposer).toBeUndefined();
    expect(shellProps.history).toMatchObject({
      hasOlderMessages: false,
      isLoading: false,
      mode: 'continuous',
    });
  });

  it('hands the composer the consent request until consent is given, and draws it again then', async () => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult());
    const onRequestConsent = jest.fn();
    const render = (hasConsent: boolean) => TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={{ kind: 'thread', threadId: 'thread' }}
        hasConsent={hasConsent}
        onRequestConsent={onRequestConsent}
      />,
      root,
    );
    render(false);
    await pause(20);
    const awaiting = AgentConversationShellMock.mock.calls.at(-1)![0].composer!;
    expect(awaiting.onRequestConsent).toBe(onRequestConsent);
    expect(AgentInputBarMock.mock.calls.at(-1)![0].isDictationHeld).toBe(true);

    render(true);
    await pause(20);
    const allowed = AgentConversationShellMock.mock.calls.at(-1)![0].composer!;
    // The composer changes, so the list draws it again, with the same drawing function
    expect(allowed).not.toBe(awaiting);
    expect(allowed.render).toBe(awaiting.render);
    expect(allowed.onRequestConsent).toBeUndefined();
    expect(AgentInputBarMock.mock.calls.at(-1)![0].isDictationHeld).toBe(false);
  });

  it.each([false, true])('asks for consent at once; Allow reads it again, closing leaves: support=%s', async (
    shouldRequestSupport,
  ) => {
    const checkConsentAgain = jest.fn();
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      isConsentAccepted: false, isInitialLoadComplete: false, checkConsentAgain,
    }));
    const onRequestConsent = jest.fn();
    const onBack = jest.fn();
    TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={{ kind: 'new' }}
        initialMessage={shouldRequestSupport ? undefined : 'What is TON?'}
        shouldRequestSupport={shouldRequestSupport}
        hasConsent={false}
        onRequestConsent={onRequestConsent}
        onBack={onBack}
      />,
      root,
    );
    await pause(20);
    expect(useAgentV2MessagesMock).toHaveBeenLastCalledWith(expect.objectContaining({ shouldRequestSupport }));
    expect(onRequestConsent).toHaveBeenCalledTimes(1);
    const [allow, field, decline] = onRequestConsent.mock.calls[0];
    expect(field).toBeUndefined();
    allow();
    expect(checkConsentAgain).toHaveBeenCalledTimes(1);
    expect(onBack).not.toHaveBeenCalled();
    decline();
    expect(onBack).toHaveBeenCalledTimes(1);
  });

  it('gives the composer the stop of the answer being produced, and a send that queues behind it', async () => {
    const messagesResult = buildMessagesResult({
      isRunActive: true, canStopRun: true, isInputDisabled: true, isSendQueued: true,
    });
    useAgentV2MessagesMock.mockReturnValue(messagesResult);
    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
    await pause(20);

    const { composer } = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(composer).toMatchObject({ canStop: true, isDisabled: false, isQueueing: true });
    composer!.onStop!();
    expect(messagesResult.stopRun).toHaveBeenCalledTimes(1);
  });

  it('keeps the indicator a moment after a Stop while the Agent thinks, for its top to show the Stop', async () => {
    const question: AgentMessage = { id: 10, text: 'Question', isOutgoing: true, timestamp: 1 };
    const thinking = buildMessagesResult({
      messages: [question],
      isRunActive: true,
      canStopRun: true,
      activity: { kind: 'analyzingRequest' },
      composerStatus: undefined,
    });
    useAgentV2MessagesMock.mockReturnValue(thinking);
    TeactDOM.render(<AgentV2Classic isActive animationLevel={2} />, root);
    await pause(20);
    const getActivity = () => AgentConversationShellMock.mock.calls.at(-1)![0].slots?.runActivity as {
      props: { activity?: unknown; isStopped?: boolean };
    } | undefined;
    expect(getActivity()?.props).toMatchObject({ isStopped: false });

    AgentConversationShellMock.mock.calls.at(-1)![0].composer!.onStop!();
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ messages: [question], composerStatus: undefined }));
    TeactDOM.render(<AgentV2Classic isActive animationLevel={2} />, root);
    await pause(20);

    expect(thinking.stopRun).toHaveBeenCalledTimes(1);
    expect(getActivity()?.props).toMatchObject({ activity: { kind: 'analyzingRequest' }, isStopped: true });

    await pause(1700);
    expect(getActivity()?.props).toMatchObject({ activity: undefined, isStopped: false });
  });

  it('opens at the first answer the user has not seen and tells where it stands', async () => {
    const question: AgentMessage = { id: 10, text: 'Question', isOutgoing: true, timestamp: 1 };
    const answer: AgentMessage = { id: 11, text: 'Answer', isOutgoing: false, timestamp: 2 };
    const timestamp = '2026-10-21T12:00:00.000Z';
    const thread = {
      id: 'thread',
      revision: 1,
      messageCount: 4,
      createdAt: timestamp,
      updatedAt: timestamp,
      lastActivityAt: timestamp,
    };
    // The device's copy of the history that stays after a failed load does not place the line; the history does
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      messages: [question, { ...answer, id: 9 }],
      thread,
      isHistoryCached: true,
      historyFailure: { text: 'History failed', isRetrying: false },
    }));
    const onUnreadStartResolved = jest.fn();
    const chat = (
      <AgentV2Classic
        isActive
        chatKey={3}
        animationLevel={0}
        unreadStart="latestAnswer"
        onUnreadStartResolved={onUnreadStartResolved}
      />
    );
    TeactDOM.render(chat, root);
    await pause(20);

    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation)
      .toMatchObject({ isInitialLoadComplete: true, unreadMessageId: undefined });
    expect(onUnreadStartResolved).not.toHaveBeenCalled();

    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ messages: [question, answer], thread }));
    TeactDOM.render(chat, root);
    await pause(20);

    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.unreadMessageId).toBe(11);
    expect(onUnreadStartResolved).toHaveBeenCalledWith(3, 3);

    // A later answer leaves the line where it is
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      messages: [question, answer, { ...question, id: 12 }, { ...answer, id: 13 }],
    }));
    TeactDOM.render(<AgentV2Classic isActive chatKey={3} animationLevel={0} unreadStart={3} />, root);
    await pause(20);
    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.unreadMessageId).toBe(11);
  });

  it('shows the suggestions of the cached history out of reach, hides them with a failure, and offers them once the '
    + 'history loads', async () => {
    const answer: AgentMessage = {
      id: 2, text: 'Answer', isOutgoing: false, isComplete: true, timestamp: 2, followups: [NEWS_FOLLOWUP],
    };
    const messagesRoot = document.createElement('div');
    document.body.appendChild(messagesRoot);
    const renderAnswer = async (
      isHistoryCached: boolean, historyFailure?: UseAgentV2MessagesResult['historyFailure'],
    ) => {
      useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
        messages: [answer], isHistoryCached, isInputDisabled: isHistoryCached, historyFailure,
      }));
      TeactDOM.render(
        <AgentV2Classic isActive animationLevel={0} target={{ kind: 'thread', threadId: 'thread' }} />, root,
      );
      await pause(20);
      const { conversation } = AgentConversationShellMock.mock.calls.at(-1)![0];
      TeactDOM.render(conversation.renderMessage(answer, {
        shouldAnimateTextStreaming: false,
        isJustAdded: false,
        onEditMessage: jest.fn(),
        onTextRevealProgress: jest.fn(),
        onRequestLiveTail: jest.fn(),
      }) as unknown as VirtualElementComponent, messagesRoot);
      await pause(20);
      return AgentV2IncomingMessageMock.mock.calls.at(-1)![0];
    };

    try {
      expect(await renderAnswer(true))
        .toMatchObject({ message: answer, isLatest: true, areFollowupsHeld: false, areFollowupsInactive: true });
      expect(await renderAnswer(true, { text: 'History failed', isRetrying: false }))
        .toMatchObject({ areFollowupsHeld: true });
      expect(await renderAnswer(true, { text: 'History failed', isRetrying: true }))
        .toMatchObject({ areFollowupsHeld: true });
      expect(await renderAnswer(false))
        .toMatchObject({ isDisabled: false, areFollowupsHeld: false, areFollowupsInactive: false });
    } finally {
      TeactDOM.render(undefined, messagesRoot);
      messagesRoot.remove();
    }
  });

  describe('with the real conversation shell', () => {
    const timestamp = '2026-10-21T12:00:00.000Z';
    let frames: Map<number, FrameRequestCallback>;
    let spies: jest.SpyInstance[];
    let shellImplementation: NonNullable<ReturnType<typeof AgentConversationShellMock.getMockImplementation>>;
    let geometry: { scrollTop: number } | undefined;

    beforeEach(() => {
      const { default: Shell } = jest.requireActual<{ default: typeof AgentConversationShell }>(
        '../agent/AgentConversationShell',
      );
      shellImplementation = AgentConversationShellMock.getMockImplementation()!;
      AgentConversationShellMock.mockImplementation((props) => <Shell {...props} />);
      jest.useFakeTimers();
      frames = new Map();
      geometry = undefined;
      let nextFrameId = 0;
      spies = [
        jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
          frames.set(++nextFrameId, callback);
          return nextFrameId;
        }),
        jest.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => {
          frames.delete(id);
        }),
        // eslint-disable-next-line no-null/no-null
        jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null),
        // Each message stands 100 px below the one before it, as many pixels from the content's top as its id says
        jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
          const id = (this as HTMLElement).dataset?.agentV2MessageId;
          const top = id ? Number(id) * 100 - (geometry?.scrollTop ?? 0) : 0;
          return {
            top, bottom: top + 100, left: 0, right: 300, x: 0, y: top, width: 300, height: 100, toJSON: () => undefined,
          };
        }),
      ];
    });

    afterEach(async () => {
      TeactDOM.render(undefined, root);
      await flushFrames(frames);
      AgentConversationShellMock.mockImplementation(shellImplementation);
      spies.forEach((spy) => spy.mockRestore());
      jest.useRealTimers();
    });

    it.each((['news', 'digest'] as const).flatMap((kind) => [
      { kind, isQuotaBlocked: false }, { kind, isQuotaBlocked: true },
    ]))('prepares the first discussion send after consent without losing a blocked draft: %o', async ({
      kind, isQuotaBlocked,
    }) => {
      const quotaRead = new Deferred<void>();
      const sendMessage = jest.fn();
      const prepareSend = jest.fn();
      const onRequestConsent = jest.fn();
      const resetAt = Date.now() + 60_000;
      const quota = { limit: 20, used: 20, remaining: 0, resetAt: new Date(resetAt).toISOString() };
      const session = { initial: { draft: 'Discuss this news' }, save: jest.fn() };
      let hasConsent = false;
      useAgentV2MessagesMock.mockImplementation(function useMessages() {
        const [isLoadingStatus, setIsLoadingStatus] = useState(false);
        const [isStatusLoaded, setIsStatusLoaded] = useState(false);
        prepareSend.mockImplementation(async () => {
          setIsLoadingStatus(true);
          await quotaRead.promise;
          setIsStatusLoaded(true);
          setIsLoadingStatus(false);
          return !isQuotaBlocked;
        });
        const isDisabled = isLoadingStatus || (isStatusLoaded && isQuotaBlocked);
        return buildMessagesResult({
          ...(kind === 'digest' ? { digest: DIGEST } : { news: NEWS }), messages: [NEWS_POST], isOpeningNews: true,
          isSendDisabled: isDisabled, isInputDisabled: isDisabled,
          prepareSend, sendMessage,
          composerStatus: isStatusLoaded && isQuotaBlocked
            ? { kind: 'userQuota', mode: 'blocked', quota, resetAt } : undefined,
        });
      });

      renderChat();
      await flushFrames(frames);
      AgentInputBarMock.mock.calls.at(-1)![0].onSend();
      await flushFrames(frames);
      expect(onRequestConsent).toHaveBeenCalledTimes(1);
      expect(AgentInputBarMock.mock.calls.at(-1)![0].inputValue).toBe('Discuss this news');

      hasConsent = true;
      renderChat();
      onRequestConsent.mock.calls[0][0]();
      await flushFrames(frames);
      expect(prepareSend).toHaveBeenCalledTimes(1);
      expect(AgentInputBarMock.mock.calls.at(-1)![0].isDisabled).toBe(true);
      expect(AgentInputBarMock.mock.calls.at(-1)![0].isDictationHeld).toBe(false);
      quotaRead.resolve();
      await flushFrames(frames);

      if (isQuotaBlocked) {
        expect(root.textContent).toContain(`$agent_daily_limit_resets_at:${formatAgentTime('en', resetAt)}`);
        expect(AgentInputBarMock.mock.calls.at(-1)![0].inputValue).toBe('Discuss this news');
        expect(sendMessage).not.toHaveBeenCalled();
      } else {
        expect(sendMessage).toHaveBeenCalledTimes(1);
        expect(sendMessage).toHaveBeenCalledWith('Discuss this news', undefined);
        expect(AgentInputBarMock.mock.calls.at(-1)![0].inputValue).toBe('');
      }

      function renderChat() {
        TeactDOM.render(
          <AgentV2Classic
            isActive
            animationLevel={0}
            target={kind === 'digest'
              ? { kind, digest: { id: DIGEST.id }, shouldDeferCreation: true, digestPreview: DIGEST }
              : { kind, news: { eventId: 5, locale: 'en' }, shouldDeferCreation: true, preview: NEWS }}
            hasConsent={hasConsent}
            onRequestConsent={onRequestConsent}
            session={session}
          />,
          root,
        );
        mockList();
      }
    });

    it.each([false, true])(
      'opens an unread chat at its first unread message once the history replaces the cached copy (failed: %s)',
      async (isFailed) => {
        const thread = {
          id: 'thread', revision: 1, messageCount: 10,
          createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
        };
        const messages = buildIncomingMessages(10);
        // The copy holds none of the messages the user has not seen
        renderChat({ thread, messages: messages.slice(0, 5), isHistoryCached: true, isInitialLoadComplete: false });
        await flushFrames(frames);
        if (isFailed) {
          renderChat({
            thread,
            messages: messages.slice(0, 5),
            isHistoryCached: true,
            historyFailure: { text: 'History failed', isRetrying: false },
          });
          await flushFrames(frames);
          // The failure shows with its Retry, as in a chat without the copy
          expect(root.textContent).toContain('History failed');
          expect(Array.from(root.querySelectorAll('button')).some(({ textContent }) => textContent === 'Retry'))
            .toBe(true);
        }

        renderChat({ thread, messages });
        await flushFrames(frames);

        expect(root.textContent).toContain('$agent_news_new');
        expect(geometry!.scrollTop).toBe(700);

        function renderChat(overrides: Partial<UseAgentV2MessagesResult>) {
          useAgentV2MessagesMock.mockReturnValue(buildMessagesResult(overrides));
          TeactDOM.render(
            <AgentV2Classic
              isActive
              chatKey={4}
              animationLevel={0}
              target={{ kind: 'thread', threadId: thread.id }}
              unreadStart={6}
            />,
            root,
          );
          mockList();
        }
      },
    );

    it('restores the question in edit from the history rather than from a cached copy without it', async () => {
      const thread = {
        id: 'thread', revision: 1, messageCount: 60,
        createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
      };
      const messages = buildIncomingMessages(60).map((message) => (
        message.id % 2 ? { ...message, isOutgoing: true, isComplete: undefined } : message
      ));
      const sendMessage = jest.fn();
      const session = {
        initial: { draft: 'Edited message', editedMessage: { indexFromEnd: 59, text: 'Message 1' } },
        save: jest.fn(),
      };
      const renderChat = (overrides: Partial<UseAgentV2MessagesResult>) => {
        useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ thread, sendMessage, ...overrides }));
        TeactDOM.render(
          <AgentV2Classic
            isActive
            chatKey={5}
            animationLevel={0}
            target={{ kind: 'thread', threadId: thread.id }}
            session={session}
          />,
          root,
        );
        mockList();
      };

      // The copy holds the latest 50 messages, without the question in edit
      renderChat({ messages: messages.slice(-50), isHistoryCached: true, isInitialLoadComplete: false });
      await flushFrames(frames);
      renderChat({ messages });
      await flushFrames(frames);
      AgentInputBarMock.mock.calls.at(-1)![0].onSend();
      await flushFrames(frames);

      expect(sendMessage).toHaveBeenCalledWith('Edited message', 1);
    });

    // The list is 3000 px tall in a 500 px viewport and scrolls as the shell asks
    function mockList() {
      const element = root.querySelector<HTMLElement>('.custom-scroll');
      if (!element || Object.getOwnPropertyDescriptor(element, 'scrollTop')) return;
      const listGeometry = { scrollTop: 0 };
      geometry = listGeometry;
      const setScrollTop = (value: number) => {
        listGeometry.scrollTop = Math.min(Math.max(value, 0), 2500);
      };
      Object.defineProperties(element, {
        scrollTop: { configurable: true, get: () => listGeometry.scrollTop, set: setScrollTop },
        scrollHeight: { configurable: true, value: 3000 },
        clientHeight: { configurable: true, value: 500 },
        scrollTo: {
          configurable: true, value: ({ top }: ScrollToOptions) => setScrollTop(top ?? listGeometry.scrollTop),
        },
      });
    }
  });

  it.each(['answer', 'operator'])('resolves the first unread %s on the fresh history frame', async (kind) => {
    resetAgentV2LocalState();
    const timestamp = '2026-10-21T12:00:00.000Z';
    const thread = {
      id: 'cached-unread', revision: 2, messageCount: kind === 'answer' ? 6 : 4,
      createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
      ...(kind === 'operator' && { support: { state: 'operator' as const, lastOperatorMessageAt: timestamp } }),
    };
    getAgentV2LocalState().threadReadState = {
      records: { [thread.id]: { seenMessageCount: 4, isBaselineNeeded: false, isMarkedUnread: false } },
      order: [thread.id],
    };
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      thread: { ...thread, revision: 1, messageCount: 4, support: undefined }, isInitialLoadComplete: false,
    }));
    const onUnreadStartResolved = jest.fn();
    const onThreadLoaded = jest.fn(() => markAgentThreadShown(thread.id));
    const props = {
      isActive: true, chatKey: 3, animationLevel: 0 as const, isUnreadStateUnknown: true, onUnreadStartResolved,
      onThreadLoaded,
    };
    TeactDOM.render(<AgentV2Classic {...props} />, root);
    expect(await waitFor(() => AgentConversationShellMock.mock.calls.length > 0, 10, 100)).toBe(true);
    await rafPromise();
    await rafPromise();
    expect(onThreadLoaded).not.toHaveBeenCalled();
    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.unreadMessageId).toBeUndefined();
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      thread: { ...thread, revision: 1, messageCount: 4, support: undefined },
      historyFailure: { text: 'Offline', isRetrying: false },
    }));
    TeactDOM.render(<AgentV2Classic {...props} />, root);
    await rafPromise();
    await rafPromise();
    expect(onThreadLoaded).not.toHaveBeenCalled();
    expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation.unreadMessageId).toBeUndefined();
    const renderCount = AgentConversationShellMock.mock.calls.length;
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      thread, messages: [
        { id: 10, text: 'Question', isOutgoing: true, timestamp: 1 },
        { id: 11, text: 'Answer', isOutgoing: false, timestamp: 2 },
      ],
    }));
    TeactDOM.render(<AgentV2Classic {...props} />, root);
    expect(await waitFor(() => onUnreadStartResolved.mock.calls.length > 0, 10, 100)).toBe(true);
    expect(AgentConversationShellMock.mock.calls[renderCount][0].conversation.unreadMessageId)
      .toBe(kind === 'answer' ? 10 : 11);
    expect(onUnreadStartResolved).toHaveBeenCalledWith(3, kind === 'answer' ? 4 : 3);
    resetAgentV2LocalState();
  });

  it.each([false, true])(
    'keeps the cached history of a chat opened from a cached list row off the list (failed: %s)',
    async (isFailed) => {
      const question: AgentMessage = { id: 10, text: 'Question', isOutgoing: true, timestamp: 1 };
      const timestamp = '2026-10-21T12:00:00.000Z';
      // The list row is the device's copy too, so whether the chat opens at an unread message is not known yet
      useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
        messages: [question],
        thread: {
          id: 'thread', revision: 1, messageCount: 4,
          createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
        },
        isHistoryCached: true,
        isInitialLoadComplete: isFailed,
        historyFailure: isFailed ? { text: 'History failed', isRetrying: false } : undefined,
      }));
      TeactDOM.render(
        <AgentV2Classic
          isActive
          chatKey={3}
          animationLevel={0}
          target={{ kind: 'thread', threadId: 'thread' }}
          isUnreadStateUnknown
        />,
        root,
      );
      await pause(20);

      expect(AgentConversationShellMock.mock.calls.at(-1)![0].conversation)
        .toMatchObject({ messages: [], isInitialLoadComplete: isFailed });
    },
  );

  it('hands a history that did not load to the list, with its Retry', async () => {
    const retryHistory = jest.fn();
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      historyFailure: { text: 'History failed', isRetrying: false },
      retryHistory,
    }));
    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
    await pause(20);

    const { loadFailure } = AgentConversationShellMock.mock.calls.at(-1)![0].conversation;
    expect(loadFailure).toMatchObject({ text: 'History failed', isRetrying: false });
    loadFailure!.onRetry();
    expect(retryHistory).toHaveBeenCalledTimes(1);
  });

  it('offers the held quota Retry after a non-retryable support failure', async () => {
    const retryAdmission = jest.fn();
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      retryAdmission,
      composerStatus: { kind: 'userQuota', mode: 'informational', clientRunId: 'held', resetAt: 1,
        quota: { limit: 20, used: 20, remaining: 0, resetAt: '2026-08-01T00:00:00.000Z' } },
      messages: [{ id: -1, text: '', isOutgoing: false, timestamp: 1,
        error: { code: 'network_error', retryable: false }, isRetryAvailable: false }],
    }));
    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
    await pause(20);
    const footer = document.createElement('div');
    root.appendChild(footer);
    try {
      const content = AgentConversationShellMock.mock.calls.at(-1)![0].slots?.messageListFooter;
      TeactDOM.render(content as unknown as VirtualElementComponent, footer);
      await pause(20);
      const button = footer.querySelector<HTMLButtonElement>('button[aria-label="$agent_retry_request"]');
      expect(button).not.toBeNull();
      button!.click();
      expect(retryAdmission).toHaveBeenCalledTimes(1);
    } finally {
      TeactDOM.render(undefined, footer);
      footer.remove();
    }
  });

  it('keeps current capacity status visible beside the historical failed message', async () => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      messages: [{
        id: 1,
        text: '',
        isOutgoing: false,
        timestamp: Date.now(),
        error: { code: 'agent_capacity_exhausted', retryable: true },
      }],
    }));

    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
    await pause(20);

    const shellProps = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(shellProps.slots?.messageListFooter).toBeDefined();
  });

  it.each([undefined, 'waiting', 'operator'] as const)(
    'wires message retry only when the normalized message grants it and the agent answers: %s',
    async (supportState) => {
      const retryMessage = jest.fn();
      useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
        retryMessage,
        ...(supportState ? { support: { state: supportState } } : {}),
      }));

      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
      await pause(20);

      const renderMessage = AgentConversationShellMock.mock.calls.at(-1)![0].conversation.renderMessage;
      const context = {
        shouldAnimateTextStreaming: false,
        textRevealPresentation: undefined,
        isJustAdded: false,
        onEditMessage: jest.fn(),
        onReportMessage: jest.fn(),
        onTextRevealProgress: jest.fn(),
        onRequestLiveTail: jest.fn(),
      } as Parameters<AgentConversation['renderMessage']>[1];
      const providerFailure = renderMessage({
        id: 1,
        text: '',
        isOutgoing: false,
        timestamp: Date.now(),
        error: { code: 'provider_error', retryable: true },
        isRetryAvailable: true,
      }, context) as { props: { onRetry?: (messageId: number) => void } };

      // Support answers the chat, so a failed agent answer offers no retry, as it offers no regenerate
      if (supportState) {
        expect(providerFailure.props.onRetry).toBeUndefined();
        return;
      }
      providerFailure.props.onRetry?.(1);
      expect(retryMessage).toHaveBeenCalledWith(1);
    });

  it('shows the run\'s activity under the question being answered, above the questions that wait', async () => {
    const question: AgentMessage = {
      id: 1, text: 'Question', isOutgoing: true, timestamp: 1,
    };
    const answer: AgentMessage = {
      id: 2, text: '', isOutgoing: false, timestamp: 2, isStreaming: true,
    };
    const waiting: AgentMessage = {
      id: 3, text: 'Waiting question', isOutgoing: true, timestamp: 3,
    };
    const activity = { kind: 'analyzingRequest' } as const;
    const renderChat = async (messages: AgentMessage[]) => {
      useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
        messages, queuedMessageCount: 1, isRunActive: true, activity, composerStatus: undefined,
      }));
      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
      await pause(20);
      return AgentConversationShellMock.mock.calls.at(-1)![0];
    };

    // Before the answer's message comes, the activity follows the question rather than ending the chat
    const { slots } = await renderChat([question, waiting]);
    expect(slots?.runActivity).toBeDefined();
    expect(slots?.messageListFooter).toBeUndefined();

    // The answer's message hosts it once it comes, though a question waits after the answer
    const { slots: answerSlots, conversation } = await renderChat([question, answer, waiting]);
    expect(answerSlots?.runActivity).toBeUndefined();
    const context: Parameters<AgentConversation['renderMessage']>[1] = {
      shouldAnimateTextStreaming: false,
      isJustAdded: false,
      onEditMessage: jest.fn(),
      onTextRevealProgress: jest.fn(),
      onRequestLiveTail: jest.fn(),
    };
    const answerBubble = conversation.renderMessage(answer, context) as unknown as VirtualElementComponent;
    expect(answerBubble.props.isActivityHost).toBe(true);
    expect(answerBubble.props.activity).toBe(activity);
    const waitingBubble = conversation.renderMessage(waiting, context) as unknown as VirtualElementComponent;
    expect(waitingBubble.props.isActivityHost).toBe(false);
    expect(waitingBubble.props.activity).toBeUndefined();
  });

  describe('Edit', () => {
    const QUESTION: AgentMessage = {
      id: 1, text: 'Stored question', isOutgoing: true, timestamp: 1,
    };
    const ANSWER: AgentMessage = {
      id: 2, text: 'Stored answer', isOutgoing: false, timestamp: 2,
    };
    const WAITING_QUESTION: AgentMessage = {
      id: 3, text: 'Waiting question', isOutgoing: true, timestamp: 3,
    };
    // A question that waits, or failed to go, has no stored message to edit
    const isMessageEditable = (messageId: number) => messageId === QUESTION.id;

    async function renderEditMenuChat(overrides: Partial<UseAgentV2MessagesResult>) {
      useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ isMessageEditable, ...overrides }));
      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
      await pause(20);

      const { renderMessage } = AgentConversationShellMock.mock.calls.at(-1)![0].conversation;
      const context: Parameters<AgentConversation['renderMessage']>[1] = {
        shouldAnimateTextStreaming: false,
        isJustAdded: false,
        onEditMessage: jest.fn(),
        onTextRevealProgress: jest.fn(),
        onRequestLiveTail: jest.fn(),
      };
      return (message: AgentMessage) => (
        renderMessage(message, context) as unknown as VirtualElementComponent
      ).props.onEdit;
    }

    it('offers Edit on a stored question while the chat is free', async () => {
      const getOnEdit = await renderEditMenuChat({ messages: [QUESTION, ANSWER] });
      expect(getOnEdit(QUESTION)).toBeDefined();
    });

    it('offers no Edit while an answer is being produced', async () => {
      const getOnEdit = await renderEditMenuChat({
        messages: [QUESTION, ANSWER], isRunActive: true, isInputDisabled: true, isSendQueued: true, canStopRun: true,
      });
      expect(getOnEdit(QUESTION)).toBeUndefined();
    });

    it('offers no Edit on a queued question, nor on a stored one while a question waits', async () => {
      const getOnEdit = await renderEditMenuChat({
        messages: [QUESTION, ANSWER, WAITING_QUESTION],
        isRunActive: true,
        isInputDisabled: true,
        isSendQueued: true,
        queuedMessageCount: 1,
      });
      expect(getOnEdit(WAITING_QUESTION)).toBeUndefined();
      expect(getOnEdit(QUESTION)).toBeUndefined();
    });

    it('offers no Edit on a question a wallet switch failed, while a stored one keeps it, as on mobile', async () => {
      const failure: AgentMessage = {
        id: 4, text: '', isOutgoing: false, timestamp: 4, failureText: 'Switched wallet', isRetryAvailable: true,
      };
      const getOnEdit = await renderEditMenuChat({
        messages: [QUESTION, ANSWER, WAITING_QUESTION, failure],
        failedQueueFailureId: failure.id,
        queuedMessageCount: 2,
      });
      expect(getOnEdit(WAITING_QUESTION)).toBeUndefined();
      expect(getOnEdit(QUESTION)).toBeDefined();
    });
  });

  it.each(['news', 'digest'] as const)('renders a %s post without message controls or an opening question', async (
    kind,
  ) => {
    const news = kind === 'news' ? NEWS : undefined;
    const message = NEWS_POST;
    const timestamp = '2026-10-21T12:00:00.000Z';
    const digest = { id: 'digest', windowEnd: timestamp, total: 3, top: [{ eventId: 5, headline: 'News headline' }] };
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      news,
      ...(kind === 'digest' && {
        thread: {
          id: 'digest-thread', revision: 1, messageCount: 1,
          createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp, digest,
        },
      }),
      messages: [message],
      isOpeningNews: kind === 'news',
      isInitialLoadComplete: kind === 'digest',
      composerStatus: undefined,
    }));

    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
    await pause(20);

    const { conversation } = AgentConversationShellMock.mock.calls.at(-1)![0];
    const post = conversation.renderMessage(message, {
      shouldAnimateTextStreaming: false,
      isJustAdded: false,
      onEditMessage: jest.fn(),
      onReportMessage: jest.fn(),
      onTextRevealProgress: jest.fn(),
      onRequestLiveTail: jest.fn(),
    }) as unknown as VirtualElementComponent;

    expect(post.componentInstance.Component).toBe(AgentNewsPost);
    expect(post.props.news).toBe(news);
    // A digest's discussion opens with the digest's post, which its thread describes
    expect(post.props.digest).toBe(kind === 'digest' ? digest : undefined);
    expect(post.props.onEdit).toBeUndefined();
    expect(post.props.onRate).toBeUndefined();
    expect(post.props.onReport).toBeUndefined();
    expect(post.props.onRetry).toBeUndefined();
    expect(conversation.isInitialLoadComplete).toBe(true);
    expect(conversation.isRunActive).toBe(false);
    expect(conversation).not.toHaveProperty('isOpeningWithQuestion');
    // A news discussion asks for anything, as every chat does on mobile
    expect(AgentInputBarMock.mock.calls.at(-1)![0].placeholder).toBeUndefined();
  });

  it.each(['news', 'digest'] as const)('shows %s followups by shared controls, not in a run or after an answer', async (
    kind,
  ) => {
    const message = { ...NEWS_POST, followups: [NEWS_FOLLOWUP] };
    const sendFollowup = jest.fn();
    const onRequestLiveTail = jest.fn();
    const isDigest = kind === 'digest';
    const result = buildMessagesResult({
      ...(isDigest ? { digest: DIGEST } : { news: NEWS }), messages: [message], sendFollowup, composerStatus: undefined,
    });
    // A digest's discussion without a thread offers the suggestions of the feed's naming
    const target = isDigest ? {
      kind: 'digest' as const, digest: { id: DIGEST.id }, digestPreview: DIGEST, shouldDeferCreation: true,
      discussionNaming: { title: 'Discuss the digest', followups: [NEWS_FOLLOWUP.text] },
    } : undefined;
    const messagesRoot = document.createElement('div');
    document.body.appendChild(messagesRoot);
    const renderPost = async (overrides: Partial<UseAgentV2MessagesResult> = {}) => {
      useAgentV2MessagesMock.mockReturnValue({ ...result, ...overrides });
      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} target={target} />, root);
      await pause(20);
      const { conversation } = AgentConversationShellMock.mock.calls.at(-1)![0];
      TeactDOM.render(conversation.renderMessage(message, {
        shouldAnimateTextStreaming: false,
        isJustAdded: false,
        onEditMessage: jest.fn(),
        onTextRevealProgress: jest.fn(),
        onRequestLiveTail,
      }) as unknown as VirtualElementComponent, messagesRoot);
      await pause(20);
    };

    try {
      await renderPost();
      const button = messagesRoot.querySelector<HTMLButtonElement>('[data-agent-followup-id]');
      expect(button?.textContent).toBe(NEWS_FOLLOWUP.text);
      expect(button?.disabled).toBe(false);
      button!.click();
      // The suggestion turns into its question where it was before the list takes the question up
      expect(onRequestLiveTail).toHaveBeenCalledTimes(1);
      expect(onRequestLiveTail).toHaveBeenCalledWith(NEWS_FOLLOWUP.id);
      expect(sendFollowup).toHaveBeenCalledWith(message.id, NEWS_FOLLOWUP);

      await renderPost({ isRunActive: true, isInputDisabled: true });
      expect(messagesRoot.querySelector('[data-agent-followup-id]')).not.toBeNull();
      expect(await waitFor(
        () => !messagesRoot.querySelector('[data-agent-followup-id]'), 20, 100,
      )).toBe(true);

      await renderPost({ messages: [message, {
        id: 3, text: 'Agent answer', isOutgoing: false, timestamp: 3,
      }] });
      expect(messagesRoot.querySelector('[data-agent-followup-id]')).toBeNull();
    } finally {
      TeactDOM.render(undefined, messagesRoot);
      messagesRoot.remove();
    }
  });

  it('does not render an unchanged historical bubble when the active message streams', async () => {
    const historicalMessage: AgentMessage = {
      id: 1,
      text: 'Historical answer',
      isOutgoing: false,
      timestamp: 1,
    };
    const streamingMessage: AgentMessage = {
      id: 2,
      text: 'Streaming',
      isOutgoing: false,
      isStreaming: true,
      timestamp: 2,
    };
    const messagesResult = buildMessagesResult({
      messages: [historicalMessage, streamingMessage],
    });
    useAgentV2MessagesMock.mockReturnValue(messagesResult);
    const messagesRoot = document.createElement('div');
    document.body.appendChild(messagesRoot);
    const context = {
      shouldAnimateTextStreaming: false,
      textRevealPresentation: undefined,
      isJustAdded: false,
      onEditMessage: jest.fn(),
      onReportMessage: jest.fn(),
      onTextRevealProgress: jest.fn(),
      onRequestLiveTail: jest.fn(),
    } as Parameters<AgentConversation['renderMessage']>[1];

    try {
      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
      await pause(20);
      let renderMessage = AgentConversationShellMock.mock.calls.at(-1)![0].conversation.renderMessage;
      TeactDOM.render(
        <>{[historicalMessage, streamingMessage].map((message) => (
          renderMessage(message, context)
        ))}
        </>, messagesRoot);
      await pause(20);
      expect(AgentV2IncomingMessageMock).toHaveBeenCalledTimes(2);

      const updatedStreamingMessage = { ...streamingMessage, text: 'Streaming update' };
      useAgentV2MessagesMock.mockReturnValue({
        ...messagesResult,
        messages: [historicalMessage, updatedStreamingMessage],
      });
      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
      await pause(20);
      renderMessage = AgentConversationShellMock.mock.calls.at(-1)![0].conversation.renderMessage;
      TeactDOM.render(
        <>{[historicalMessage, updatedStreamingMessage].map((message) => (
          renderMessage(message, context)
        ))}
        </>, messagesRoot);
      await pause(20);

      expect(AgentV2IncomingMessageMock).toHaveBeenCalledTimes(3);
    } finally {
      TeactDOM.render(undefined, messagesRoot);
      messagesRoot.remove();
    }
  });

  describe('regeneration', () => {
    const question: AgentMessage = { id: 1, text: 'Question', isOutgoing: true, timestamp: 1 };
    const answer: AgentMessage = { id: 2, text: 'Answer', isOutgoing: false, timestamp: 2 };
    const context = {
      shouldAnimateTextStreaming: false,
      isJustAdded: false,
      onEditMessage: jest.fn(),
      onTextRevealProgress: jest.fn(),
      onRequestLiveTail: jest.fn(),
    } as Parameters<AgentConversation['renderMessage']>[1];

    async function renderChat(result: UseAgentV2MessagesResult, overrides: Partial<UseAgentV2MessagesResult> = {}) {
      useAgentV2MessagesMock.mockReturnValue({ ...result, ...overrides });
      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
      await pause(20);
      return AgentConversationShellMock.mock.calls.at(-1)![0].conversation;
    }

    function regenerate(conversation: AgentConversation, message: AgentMessage) {
      const bubble = conversation.renderMessage(message, context) as {
        props: { onRegenerate?: (messageId: number) => void };
      };
      bubble.props.onRegenerate!(message.id);
    }

    it('shows the answer it removes once more, for the list to turn it to dust', async () => {
      const retryMessage = jest.fn();
      const result = buildMessagesResult({
        messages: [question, answer], isMessageRegenerable: () => true, retryMessage,
      });

      regenerate(await renderChat(result), answer);
      expect(retryMessage).toHaveBeenCalledWith(answer.id);
      expect((await renderChat(result, { isRunActive: true })).dissolvingMessageIds).toBeUndefined();

      // The server takes the regeneration and the answer leaves the messages
      let conversation = await renderChat(result, { isRunActive: true, messages: [question] });
      expect(conversation.messages).toEqual([question, answer]);
      expect(conversation.dissolvingMessageIds).toEqual([answer.id]);

      conversation.onDissolveStart!();
      await pause(20);
      conversation = AgentConversationShellMock.mock.calls.at(-1)![0].conversation;
      expect(conversation.messages).toEqual([question]);
      expect(conversation.dissolvingMessageIds).toBeUndefined();
    });

    it('turns nothing to dust after a regeneration the server never took', async () => {
      const result = buildMessagesResult({ messages: [question, answer], isMessageRegenerable: () => true });

      regenerate(await renderChat(result), answer);
      await renderChat(result, { isRunActive: true });
      await renderChat(result, { isRunActive: false });
      await pause(20);

      const conversation = await renderChat(result, { messages: [question] });
      expect(conversation.messages).toEqual([question]);
      expect(conversation.dissolvingMessageIds).toBeUndefined();
    });
  });

  it('shares the post of a listed news discussion in the language it was opened in, not the app\'s', async () => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ news: NEWS, messages: [NEWS_POST] }));
    TeactDOM.render(
      <AgentV2Classic
        isActive
        animationLevel={0}
        target={{ kind: 'thread', threadId: 'news-thread', isNews: true, newsLocale: 'ru' }}
      />,
      root,
    );
    await pause(20);
    const post = AgentConversationShellMock.mock.calls.at(-1)![0].conversation.renderMessage(NEWS_POST, {
      shouldAnimateTextStreaming: false, isJustAdded: false,
      onEditMessage: jest.fn(), onTextRevealProgress: jest.fn(), onRequestLiveTail: jest.fn(),
    });
    TeactDOM.render(<div>{post}</div>, root);
    await pause(20);

    root.querySelector('h3')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2 }));
    await pause(20);
    Array.from(document.body.querySelectorAll('button')).find(({ textContent }) => textContent === 'Share')!.click();
    expect(shareUrl).toHaveBeenCalledWith(
      'https://my.tt/agent?news=5&lang=ru&utm_source=pulse_share', 'News headline', 'News headline',
    );
  });

  it.each([
    { url: 'https://example.com/news', canOpenSource: true },
    { url: 'javascript:alert(1)', canOpenSource: false },
  ])('copies a news post\'s text and the link of its source $url', async ({ url, canOpenSource }) => {
    const news = {
      eventId: 5,
      headline: 'News headline',
      body: 'Complete **news** body',
      publishedAt: '2026-10-21T09:00:00.000Z',
      sources: [{ name: 'Source', url }],
    };
    TeactDOM.render(
      <AgentNewsPost news={news} locale="ru" message={NEWS_POST} isDisabled={false} shouldShowFollowups={false} />,
      root,
    );
    await pause(20);

    // The post does not name its source, which opens from its menu
    expect(root.querySelector('a')).toBeNull();
    expect(root.textContent).not.toContain('Source');
    root.querySelector('h3')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2 }));
    await pause(20);

    const buttons = Array.from(document.body.querySelectorAll('button'));
    expect(buttons.map(({ textContent }) => textContent)).toEqual([
      ...(canOpenSource ? ['$agent_news_sources'] : []),
      'Copy',
      'Share',
    ]);
    buttons.find(({ textContent }) => textContent === 'Copy')!.click();
    expect(copyAgentText).toHaveBeenCalledWith('News headline\n\nComplete news body');
    expect(shareUrl).not.toHaveBeenCalled();
    // Share sends the headline and the link of the news in the language the discussion shows it in
    buttons.find(({ textContent }) => textContent === 'Share')!.click();
    expect(shareUrl).toHaveBeenCalledWith(
      'https://my.tt/agent?news=5&lang=ru&utm_source=pulse_share', 'News headline', 'News headline',
    );
    if (canOpenSource) {
      // With a pointer, Sources shows the sources in a menu beside it, each opening its link
      buttons[0].click();
      await pause(20);
      expect(buttons[0].getAttribute('aria-expanded')).toBe('true');
      const menus = Array.from(document.body.querySelectorAll('.menu-bubble'));
      expect(menus.at(-1)!.textContent).toBe('Source');
      menus.at(-1)!.querySelector('button')!.click();
      expect(openUrl).toHaveBeenCalledTimes(1);
      expect(openUrl).toHaveBeenCalledWith(url);
    }
  });

  describe('support request', () => {
    async function renderChat(overrides: Partial<UseAgentV2MessagesResult> = {}, hasWallet = true) {
      const messagesResult = buildMessagesResult(overrides);
      useAgentV2MessagesMock.mockReturnValue(messagesResult);
      TeactDOM.render(
        <AgentV2Classic
          isActive
          animationLevel={0}
          hasWallet={hasWallet}
          target={{ kind: 'thread', threadId: 'thread-1' }}
        />,
        root,
      );
      await pause(20);
      return messagesResult;
    }

    function getShellProps() {
      return AgentConversationShellMock.mock.calls.at(-1)![0];
    }

    async function openSheet() {
      getShellProps().actions.onRequestSupport!('header');
      await pause(50);
      return {
        text: portals.querySelector('p')?.textContent,
        cancel: findPortalButton('Cancel')!,
        call: findPortalButton('$agent_support_confirm_action')!,
      };
    }

    function findPortalButton(text: string) {
      return [...portals.querySelectorAll('button')].find(({ textContent }) => textContent === text);
    }

    it('keeps support in the header of an empty chat whose hints did not load', async () => {
      await renderChat({
        messages: [], hints: undefined, isSupportRequestVisible: true, canRequestSupport: true,
      });
      expect(getShellProps().conversation.hints).toBeUndefined();
      expect(getShellProps().actions.onRequestSupport).toBeDefined();
      expect(getShellProps().header!.canRequestSupport).toBe(true);
    });

    it('offers support in the header while the chat shows it and enables it while the chat can call it', async () => {
      await renderChat({ canRequestSupport: false });
      expect(getShellProps().actions.onRequestSupport).toBeDefined();
      expect(getShellProps().header!.canRequestSupport).toBe(false);

      await renderChat({ isSupportRequestVisible: false });
      expect(getShellProps().actions.onRequestSupport).toBeUndefined();
    });

    it('asks before calling support from the header', async () => {
      const messagesResult = await renderChat();

      const sheet = await openSheet();
      expect(portals.textContent).toContain('$agent_support_confirm_title');
      expect(sheet.text).toBe('$agent_support_confirm_text');
      sheet.cancel.click();
      await pause(50);
      expect(messagesResult.requestSupport).not.toHaveBeenCalled();

      (await openSheet()).call.click();
      expect(messagesResult.requestSupport).toHaveBeenCalledTimes(1);
      expect(messagesResult.requestSupport).toHaveBeenCalledWith('header');
    });

    it('sends nothing once the chat cannot call support with the sheet open', async () => {
      const messagesResult = await renderChat();
      await openSheet();

      await renderChat({ requestSupport: messagesResult.requestSupport, canRequestSupport: false });
      const call = findPortalButton('$agent_support_confirm_action')!;
      expect(call.disabled).toBe(true);
      call.click();
      expect(messagesResult.requestSupport).not.toHaveBeenCalled();
    });

    it.each([
      ['without consent', { isConsentAccepted: false }, true],
      ['without a wallet', {}, false],
    ] as const)('tells that the operator gets no addresses %s', async (_, overrides, hasWallet) => {
      await renderChat(overrides, hasWallet);
      expect((await openSheet()).text).toBe('$agent_support_confirm_text_no_wallet');
    });
  });
});

function buildIncomingMessages(count: number) {
  return Array.from({ length: count }, (_, index): AgentMessage => ({
    id: index + 1, text: `Message ${index + 1}`, isOutgoing: false, isComplete: true, timestamp: index + 1,
  }));
}

async function flushFrames(frames: Map<number, FrameRequestCallback>) {
  for (let i = 0; i < 20; i++) {
    await jest.advanceTimersByTimeAsync(20);
    const callbacks = Array.from(frames.values());
    frames.clear();
    callbacks.forEach((callback) => callback(i * 16));
    await Promise.resolve();
  }
}

function buildMessagesResult(overrides: Partial<UseAgentV2MessagesResult> = {}): UseAgentV2MessagesResult {
  return {
    messages: [],
    isOpeningNews: false,
    isInitialLoadComplete: true,
    isHistoryCached: false,
    isOpenedWithCachedHistory: false,
    hasPendingQuestion: false,
    isInputDisabled: false,
    isSendDisabled: false,
    isSendQueued: false,
    queuedMessageCount: 0,
    isMessageRegenerable: () => false,
    isMessageEditable: () => false,
    isRunActive: false,
    canStopRun: false,
    stopRun: jest.fn(),
    textRevealPresentations: {},
    hasOlderMessages: false,
    isLoadingOlderMessages: false,
    isConsentAccepted: true,
    checkConsentAgain: jest.fn(),
    prepareSend: jest.fn(() => Promise.resolve(true)),
    composerStatus: { kind: 'capacity', mode: 'degraded' },
    loadOlderMessages: jest.fn(() => Promise.resolve()),
    retryHistory: jest.fn(),
    sendMessage: jest.fn(),
    sendHint: jest.fn(),
    requestSupport: jest.fn(),
    isSupportRequestVisible: true,
    canRequestSupport: true,
    sendFollowup: jest.fn(),
    clearChat: jest.fn(),
    cancelPendingRequests: jest.fn(() => Promise.resolve(undefined)),
    reportProblem: jest.fn(() => Promise.resolve('sent' as const)),
    rateMessage: jest.fn(),
    retryMessage: jest.fn(),
    retryAdmission: jest.fn(),
    refreshExpiredComposerStatus: jest.fn(),
    activateAction: jest.fn(),
    consumeTextRevealSession: jest.fn(),
    settleTextRevealSession: jest.fn(),
    ...overrides,
  };
}
