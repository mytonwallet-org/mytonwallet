import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentMessage } from '../../global/types';
import type { AgentConversation, AgentConversationShellProps } from '../agent/AgentConversationShell';
import type { UseAgentV2MessagesResult } from '../agent/hooks/useAgentV2Messages';

import { pause } from '../../util/schedulers';

import useAgentV2Messages from '../agent/hooks/useAgentV2Messages';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentInputBar from '../agent/AgentInputBar';
import { AgentV2Classic } from './AgentV2Classic';
import AgentV2IncomingMessage from './AgentV2IncomingMessage';

const mockSwitchToWallet = jest.fn();

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  AGENT_V2_QUOTA_STATUS_ENABLED: true,
}));
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
jest.mock('../agent/AgentConversationShell', () => ({
  __esModule: true,
  default: jest.fn((props: AgentConversationShellProps) => props.composer.render?.({
    inputRef: { current: undefined },
    inputValue: '',
    isDisabled: false,
    onInput: jest.fn(),
    onKeyDown: jest.fn(),
    onSend: jest.fn(),
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

const USER_QUOTA = {
  limit: 1_000,
  used: 4,
  remaining: 996,
  resetAt: '2026-08-16T00:00:00.000Z',
};

const useAgentV2MessagesMock = jest.mocked(useAgentV2Messages);
const AgentConversationShellMock = jest.mocked(AgentConversationShell);
const AgentInputBarMock = jest.mocked(AgentInputBar);
const AgentV2IncomingMessageMock = jest.mocked(AgentV2IncomingMessage);

describe('AgentV2Classic', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    useAgentV2MessagesMock.mockReturnValue(buildMessagesResult());
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.clearAllMocks();
  });

  it('renders provider capacity inside the measured input bar without hiding the quota button', async () => {
    TeactDOM.render(<AgentV2Classic isActive animationLevel={0} />, root);
    await pause(20);

    const inputBarProps = AgentInputBarMock.mock.calls.at(-1)![0];
    expect(inputBarProps.userQuota).toBe(USER_QUOTA);
    expect(inputBarProps.quotaStatus).toBeDefined();
    expect(inputBarProps.statusNotice).toBeDefined();

    const shellProps = AgentConversationShellMock.mock.calls.at(-1)![0];
    expect(shellProps.slots?.beforeComposer).toBeUndefined();
    expect(shellProps.history).toMatchObject({
      hasOlderMessages: false,
      isLoading: false,
      mode: 'continuous',
    });
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

    const inputBarProps = AgentInputBarMock.mock.calls.at(-1)![0];
    expect(inputBarProps.statusNotice).toBeDefined();
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
});

function buildMessagesResult(overrides: Partial<UseAgentV2MessagesResult> = {}): UseAgentV2MessagesResult {
  return {
    messages: [],
    isInitialLoadComplete: true,
    isInputDisabled: false,
    isRunActive: false,
    textRevealPresentations: {},
    hasOlderMessages: false,
    isLoadingOlderMessages: false,
    isConsentAccepted: true,
    composerStatus: { kind: 'capacity', mode: 'degraded' },
    userQuota: USER_QUOTA,
    loadOlderMessages: jest.fn(() => Promise.resolve()),
    sendMessage: jest.fn(),
    sendHint: jest.fn(),
    sendFollowup: jest.fn(),
    clearChat: jest.fn(),
    reportProblem: jest.fn(() => Promise.resolve('sent' as const)),
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
