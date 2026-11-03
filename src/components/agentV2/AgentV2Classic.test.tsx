import React, { type VirtualElementComponent } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentPublicFollowUpV2 } from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import type { AgentConversation, AgentConversationShellProps } from '../agent/AgentConversationShell';
import type { UseAgentV2MessagesResult } from '../agent/hooks/useAgentV2Messages';

import { openUrl } from '../../util/openUrl';
import { pause, waitFor } from '../../util/schedulers';
import { shareUrl } from '../../util/share';

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
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../agent/hooks/useAgentV2Messages', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../util/share', () => ({ shareUrl: jest.fn() }));
jest.mock('../agent/AgentConversationShell', () => ({
  __esModule: true,
  default: jest.fn((props: AgentConversationShellProps) => props.composer!.render?.({
    inputRef: { current: undefined },
    inputValue: '',
    isDisabled: false,
    onInput: jest.fn(),
    onKeyDown: jest.fn(),
    onSend: jest.fn(),
    onInsertText: jest.fn(),
  })),
}));
jest.mock('../agent/AgentInputBar', () => ({
  __esModule: true,
  default: jest.fn(() => undefined),
}));
jest.mock('./AgentV2Conversation', () => ({
  AgentV2ConsentScreen: jest.fn(() => undefined),
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

  it('does not offer deletion for an untouched composer without a target or thread', async () => {
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ messages: [], thread: undefined }));
    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} onDelete={jest.fn()} />, root);
    await pause(20);
    const { header, actions } = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(header).toBeUndefined();
    expect(actions?.onDelete).toBeUndefined();
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

  it('opens at the first answer the user has not seen and tells where it stands', async () => {
    const question: AgentMessage = { id: 10, text: 'Question', isOutgoing: true, timestamp: 1 };
    const answer: AgentMessage = { id: 11, text: 'Answer', isOutgoing: false, timestamp: 2 };
    const timestamp = '2026-10-21T12:00:00.000Z';
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      messages: [question, answer],
      thread: {
        id: 'thread',
        revision: 1,
        messageCount: 4,
        createdAt: timestamp,
        updatedAt: timestamp,
        lastActivityAt: timestamp,
      },
    }));
    const onUnreadStartResolved = jest.fn();
    TeactDOM.render(
      <AgentV2Classic
        isActive
        chatKey={3}
        animationLevel={0}
        unreadStart="latestAnswer"
        onUnreadStartResolved={onUnreadStartResolved}
      />,
      root,
    );
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

  it('wires message retry only when the normalized message grants it', async () => {
    const retryMessage = jest.fn();
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({ retryMessage }));

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

    providerFailure.props.onRetry?.(1);
    expect(retryMessage).toHaveBeenCalledWith(1);
  });

  it('renders a news post without message controls or an opening question', async () => {
    const news = NEWS;
    const message = NEWS_POST;
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult({
      news,
      messages: [message],
      isOpeningNews: true,
      isInitialLoadComplete: false,
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

  it('shows news followups through the shared controls and hides them during a run and after an answer', async () => {
    const message = { ...NEWS_POST, followups: [NEWS_FOLLOWUP] };
    const sendFollowup = jest.fn();
    const onRequestLiveTail = jest.fn();
    const result = buildMessagesResult({
      news: NEWS, messages: [message], sendFollowup, composerStatus: undefined,
    });
    const messagesRoot = document.createElement('div');
    document.body.appendChild(messagesRoot);
    const renderPost = async (overrides: Partial<UseAgentV2MessagesResult> = {}) => {
      useAgentV2MessagesMock.mockReturnValue({ ...result, ...overrides });
      TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
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
      expect(onRequestLiveTail).toHaveBeenCalledTimes(1);
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

  it.each([
    { url: 'https://example.com/news', canOpenSource: true },
    { url: 'javascript:alert(1)', canOpenSource: false },
  ])('shares a news post with source $url', async ({ url, canOpenSource }) => {
    const news = {
      eventId: 5,
      headline: 'News headline',
      body: 'Complete **news** body',
      publishedAt: '2026-10-21T09:00:00.000Z',
      sources: [{ name: 'Source', url }],
    };
    const handleParentClick = jest.fn();
    TeactDOM.render(
      <div onClick={handleParentClick}>
        <AgentNewsPost news={news} message={NEWS_POST} isDisabled={false} shouldShowFollowups={false} />
      </div>, root,
    );
    await pause(20);

    if (canOpenSource) {
      root.querySelector('a')!.click();
      expect(handleParentClick).not.toHaveBeenCalled();
      expect(openUrl).toHaveBeenCalledTimes(1);
      expect(openUrl).toHaveBeenCalledWith(url);
    }
    root.querySelector('h3')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2 }));
    await pause(20);

    const buttons = Array.from(document.body.querySelectorAll('button'));
    expect(buttons.map(({ textContent }) => textContent)).toEqual([
      ...(canOpenSource ? ['$agent_news_open_source'] : []),
      'Copy',
      'Share',
    ]);
    buttons.find(({ textContent }) => textContent === 'Share')!.click();
    expect(shareUrl).toHaveBeenCalledWith(
      canOpenSource ? url : undefined,
      news.headline,
      canOpenSource ? undefined : `News headline\n\nComplete news body\n\n${url}`,
    );
  });
});

function buildMessagesResult(overrides: Partial<UseAgentV2MessagesResult> = {}): UseAgentV2MessagesResult {
  return {
    messages: [],
    isOpeningNews: false,
    isInitialLoadComplete: true,
    hasPendingQuestion: false,
    isInputDisabled: false,
    isMessageRegenerable: () => false,
    isRunActive: false,
    textRevealPresentations: {},
    hasOlderMessages: false,
    isLoadingOlderMessages: false,
    isConsentAccepted: true,
    composerStatus: { kind: 'capacity', mode: 'degraded' },
    loadOlderMessages: jest.fn(() => Promise.resolve()),
    retryHistory: jest.fn(),
    sendMessage: jest.fn(),
    sendHint: jest.fn(),
    sendFollowup: jest.fn(),
    clearChat: jest.fn(),
    cancelPendingRequests: jest.fn(() => Promise.resolve(undefined)),
    reportProblem: jest.fn(() => Promise.resolve('sent' as const)),
    rateMessage: jest.fn(),
    acceptConsent: jest.fn(),
    retryMessage: jest.fn(),
    retryAdmission: jest.fn(),
    refreshExpiredComposerStatus: jest.fn(),
    activateAction: jest.fn(),
    consumeTextRevealSession: jest.fn(),
    settleTextRevealSession: jest.fn(),
    ...overrides,
  };
}
