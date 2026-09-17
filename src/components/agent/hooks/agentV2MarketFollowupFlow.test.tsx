import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import type { AgentPublicFollowUpV2 } from '../../../api/agentV2/protocol/types';
import type {
  AgentV2HostContextSnapshot,
  AgentV2RunResult,
} from '../../../api/agentV2/types';
import type { LangFn } from '../../../hooks/useLang';

import {
  cancelAgentV2ActiveRunReplays,
  publishAgentV2Update,
} from '../../../util/agentV2Updates';
import { waitFor } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { buildAgentV2HostContext } from '../../agentV2/buildHostContext';
import useAgentV2Messages, { type UseAgentV2MessagesResult } from './useAgentV2Messages';

import AgentV2IncomingMessage from '../../agentV2/AgentV2IncomingMessage';
import MessageBubble from '../MessageBubble';

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const RUN_ID = '33333333-3333-4333-8333-333333333333';
const INPUT_MESSAGE_ID = '44444444-4444-4444-8444-444444444444';
const BRIEF_MESSAGE_ID = '55555555-5555-4555-8555-555555555555';
const DETAILED_MESSAGE_ID = '66666666-6666-4666-8666-666666666666';
const FOLLOWUP_ID = 'adadadad-adad-4dad-8dad-adadadadadad';
const FOLLOWUP_PROMPT = 'Explain market analysis.';

const mockLang = Object.assign((key: string) => key, { code: 'en' as const }) as LangFn;

const mockSetAgentMeta = jest.fn();

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../../hooks/useLang', () => ({
  __esModule: true,
  default: () => mockLang,
}));
jest.mock('../../agentV2/buildHostContext', () => ({ buildAgentV2HostContext: jest.fn() }));
jest.mock('../../../global', () => ({
  ...jest.requireActual('../../../global'),
  getGlobal: () => ({}),
  getActions: () => ({
    openReceiveModal: jest.fn(),
    openTransactionInfo: jest.fn(),
    setAgentMeta: mockSetAgentMeta,
    showTokenActivity: jest.fn(),
    startTransfer: jest.fn(),
    switchToAgent: jest.fn(),
    switchToWallet: jest.fn(),
    toggleTokenVisibility: jest.fn(),
  }),
}));

const callApiMock = jest.mocked(callApi);
const buildAgentV2HostContextMock = jest.mocked(buildAgentV2HostContext);

describe('Agent V2 market analysis follow-up flow', () => {
  let root: HTMLDivElement;
  let result: UseAgentV2MessagesResult | undefined;
  let pendingRun: ReturnType<typeof createDeferred<AgentV2RunResult | undefined>>;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    result = undefined;
    pendingRun = createDeferred<AgentV2RunResult | undefined>();
    mockSetAgentMeta.mockReset();
    buildAgentV2HostContextMock.mockReset();
    buildAgentV2HostContextMock.mockReturnValue(hostContext());
    callApiMock.mockReset();
    callApiMock.mockImplementation((...args) => {
      switch (args[0]) {
        case 'getAgentV2Consent':
          return Promise.resolve(true);
        case 'getAgentV2DefaultThread':
          return Promise.resolve({
            protocolVersion: 2,
            thread: threadSummary(5),
            created: false,
          });
        case 'getAgentV2Messages':
          return Promise.resolve({
            ok: true,
            value: {
              thread: threadSummary(5),
              messages: [],
            },
          });
        case 'getAgentV2Hints':
        case 'getAgentV2Availability':
        case 'getAgentV2UserQuota':
          return Promise.resolve(undefined);
        case 'updateAgentV2HostContext':
          return Promise.resolve({
            ok: true,
            value: { authorityChanged: false, generation: 1 },
          }) as never;
        case 'startAgentV2Run':
          return pendingRun.promise as never;
        default:
          return Promise.resolve(undefined);
      }
    });
    cancelAgentV2ActiveRunReplays();
  });

  afterEach(() => {
    pendingRun.resolve(undefined);
    TeactDOM.render(undefined, root);
    root.remove();
    cancelAgentV2ActiveRunReplays();
  });

  it('reveals the suggested prompt after brief Markdown and starts its run', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);

    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: BRIEF_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: BRIEF_MESSAGE_ID,
      delta: '**TON:** current price. The main risk is weak demand.',
    });
    publishAgentV2Update({
      kind: 'messageContentEnded',
      ...routing(),
      messageId: BRIEF_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'followupsAvailable',
      ...routing(),
      messageId: BRIEF_MESSAGE_ID,
      items: [marketDetailFollowup()],
    });
    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: BRIEF_MESSAGE_ID,
      finishReason: 'complete',
    });
    expect(await waitFor(() => Boolean(result?.messages[0]?.text.includes('main risk')), 10, 20)).toBe(true);

    const briefMessage = result!.messages[0];
    const revealPresentation = result!.textRevealPresentations[briefMessage.id];
    expect(revealPresentation).toMatchObject({ status: 'active' });
    expect(getButton(FOLLOWUP_PROMPT)).toBeUndefined();

    result!.settleTextRevealSession(briefMessage.id, revealPresentation.key);
    expect(await waitFor(() => Boolean(getButton(FOLLOWUP_PROMPT)), 10, 20)).toBe(true);

    getButton(FOLLOWUP_PROMPT)!.click();
    expect(await waitFor(() => (
      callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run')
    ), 10, 20)).toBe(true);
    expect(await waitFor(() => result?.messages.at(-1)?.text === FOLLOWUP_PROMPT, 10, 20)).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      threadId: THREAD_ID,
      expectedThreadRevision: 5,
      input: { kind: 'append', text: FOLLOWUP_PROMPT },
      followupOf: { messageId: BRIEF_MESSAGE_ID, followupId: FOLLOWUP_ID },
    }));

    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: DETAILED_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: DETAILED_MESSAGE_ID,
      delta: '**Timeframes**\n\nDaily evidence is balanced. The main risk remains weak demand.',
    });
    expect(await waitFor(
      () => Boolean(result?.messages.at(-1)?.text.includes('Daily evidence')),
      10,
      20,
    )).toBe(true);
    expect(result!.messages.at(-1)).toMatchObject({ isStreaming: true });
  });

  function Harness() {
    result = useAgentV2Messages({ isActive: true, lang: mockLang });
    return (
      <div>
        {result.messages.map((message) => (
          <MessageBubble
            key={message.id}
            message={message}
            areLinksEnabled={false}
            isDisabled={result!.isInputDisabled}
            incomingMessageComponent={AgentV2IncomingMessage}
            shouldRenderStreamingText
            shouldAnimateTextStreaming={false}
            textRevealPresentation={result!.textRevealPresentations[message.id]}
            onFollowup={result!.sendFollowup}
          />
        ))}
      </div>
    );
  }

  function getButton(label: string) {
    return Array.from(root.querySelectorAll('button')).find((button) => button.textContent === label);
  }
});

function marketDetailFollowup(): AgentPublicFollowUpV2 {
  return {
    id: FOLLOWUP_ID,
    kind: 'suggested_prompt',
    text: FOLLOWUP_PROMPT,
  };
}

function threadSummary(revision: number) {
  return {
    id: THREAD_ID,
    revision,
    metadataRevision: 1 as const,
    titleSource: 'none' as const,
    isPinned: false as const,
    isDefault: true as const,
    createdAt: '2026-08-15T10:00:00.000Z',
    updatedAt: '2026-08-15T10:00:00.000Z',
    lastActivityAt: '2026-08-15T10:00:00.000Z',
    messageCount: 0,
  };
}

function routing() {
  return {
    clientRunId: CLIENT_RUN_ID,
    runId: RUN_ID,
    threadId: THREAD_ID,
  };
}

function hostContext(): AgentV2HostContextSnapshot {
  return {
    platform: 'classic',
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    activeAccountId: 'account-one',
    activeNetwork: 'ton',
    accounts: [],
    savedAddresses: [],
  };
}

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}
