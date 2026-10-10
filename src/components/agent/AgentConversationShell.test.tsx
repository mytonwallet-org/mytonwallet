import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';
import { getGlobal, setGlobal } from '../../global';

import type { AgentHint, AgentMessage, AnimationLevel } from '../../global/types';
import type {
  AgentConversation,
  AgentConversationActions,
  AgentConversationComposer,
  AgentConversationComposerHeightContext,
} from './AgentConversationShell';

import { ANIMATION_LEVEL_MAX } from '../../config';
import {
  disableStrict, enableStrict, setHandler, setPhase,
} from '../../lib/fasterdom/stricterdom';
import { processDeeplink } from '../../util/deeplink';
import { openUrl } from '../../util/openUrl';
import { updateAgentV2InputBarSpacing } from '../agentV2/inputBarSpacing';

import { AgentV2AssistantText } from '../agentV2/AgentV2Conversation';
import AgentConversationShell from './AgentConversationShell';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { isRtl: false }),
}));
jest.mock('../../util/dateFormat', () => ({
  ...jest.requireActual('../../util/dateFormat'),
  formatHumanDay: () => 'DATE_SEPARATOR',
}));

jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../util/deeplink', () => ({ processDeeplink: jest.fn() }));

const mockShowToast = jest.fn();
jest.mock('../../global', () => {
  const actual = jest.requireActual('../../global');
  return { ...actual, getActions: () => ({ ...actual.getActions(), showToast: mockShowToast }) };
});

const MESSAGE: AgentMessage = {
  id: 1,
  text: 'Hello',
  isOutgoing: false,
  timestamp: Date.UTC(2026, 7, 11),
};

const SECOND_MESSAGE: AgentMessage = {
  ...MESSAGE,
  id: 2,
  text: 'Second answer',
  timestamp: MESSAGE.timestamp + 1,
};

const HINT: AgentHint = {
  id: 'hint-1',
  langCode: 'en',
  title: 'Hint title',
  subtitle: 'Hint subtitle',
  prompt: 'Hint prompt',
};
const messageRenderSpy = jest.fn();

const MemoizedTestMessage = memo(function MemoizedTestMessage({
  message,
  onEdit,
}: {
  message: AgentMessage;
  onEdit: (id: number, text: string) => void;
}) {
  messageRenderSpy(message.id);

  return (
    <button type="button" data-message-id={message.id} onClick={() => onEdit(message.id, message.text)}>
      {message.text}
    </button>
  );
});

interface RenderShellOptions {
  isActive?: boolean;
  animationLevel?: AnimationLevel;
  messages?: AgentMessage[];
  hints?: AgentHint[];
  isInitialLoadComplete?: boolean;
  isInputDisabled?: boolean;
  isRunActive?: boolean;
  textRevealPresentations?: AgentConversation['textRevealPresentations'];
  noComposer?: boolean;
  hasOlderMessages?: boolean;
  isLoadingOlderMessages?: boolean;
  historyMode?: 'continuous' | 'windowed';
  conversationSlot?: TeactNode;
  messageListFooter?: TeactNode;
  beforeComposerSlot?: TeactNode;
  bottomStickDependency?: unknown;
  loadOlderMessages?: () => void | Promise<void>;
  onBack?: NoneToVoidFunction;
  onSendMessage?: AgentConversationComposer['onSendMessage'];
  onSendHint?: AgentConversationComposer['onSendHint'];
  onClearChat?: NoneToVoidFunction;
  onReportProblem?: AgentConversationActions['onReportProblem'];
  onComposerHeightChange?: (height: number, context: AgentConversationComposerHeightContext) => void;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
  renderMessage?: AgentConversation['renderMessage'];
  renderComposer?: AgentConversationComposer['render'];
}

let nextAnimationFrameId = 0;
let pendingAnimationFrames = new Map<number, FrameRequestCallback>();

describe('AgentConversationShell', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    jest.useFakeTimers();
    messageRenderSpy.mockClear();
    pendingAnimationFrames = new Map();
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      const id = ++nextAnimationFrameId;
      pendingAnimationFrames.set(id, callback);
      return id;
    });
    jest.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => {
      pendingAnimationFrames.delete(id);
    });
    root = document.createElement('div');
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(root);
    document.body.appendChild(portals);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await flushUi();
    root.remove();
    portals.remove();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('opens an Agent V2 Markdown link through the existing application navigation handler', async () => {
    jest.mocked(openUrl).mockClear();
    renderShell({
      noComposer: true,
      messages: [MESSAGE],
      renderMessage: (message) => (
        <AgentV2AssistantText
          messageId={message.id}
          text="[**Open app**](https://example.com/app?network=ton)"
          isStreaming={false}
          shouldAnimate={false}
        />
      ),
    });
    await flushUi();

    root.querySelector<HTMLElement>('a strong')!.click();
    await flushUi();

    expect(openUrl).toHaveBeenCalledTimes(1);
    expect(openUrl).toHaveBeenCalledWith('https://example.com/app?network=ton');
  });

  it('opens a link to a screen of the app with the deeplink handler', async () => {
    jest.mocked(openUrl).mockClear();
    renderShell({
      noComposer: true,
      messages: [MESSAGE],
      renderMessage: (message) => (
        <AgentV2AssistantText
          messageId={message.id}
          text="Open Explore."
          links={[{ textOffset: 5, textLength: 7, url: 'mtw://explore' }]}
          isStreaming={false}
          shouldAnimate={false}
        />
      ),
    });
    await flushUi();

    root.querySelector<HTMLElement>('a')!.click();
    await flushUi();

    expect(processDeeplink).toHaveBeenCalledWith('mtw://explore');
    expect(openUrl).not.toHaveBeenCalled();
  });

  it('preserves V1 composer, edit, send, date-separator, and clear behavior', async () => {
    const onSendMessage = jest.fn();
    const onClearChat = jest.fn();
    let messageContext: Parameters<AgentConversation['renderMessage']>[1] | undefined;

    renderShell({
      messages: [MESSAGE, SECOND_MESSAGE],
      hints: [HINT],
      onSendMessage,
      onClearChat,
      renderMessage: (message, context) => {
        messageContext = context;
        return <div key={message.id} data-message-id={message.id}>{message.text}</div>;
      },
      renderComposer: (props) => (
        <div>
          <span data-composer-value>{props.inputValue}</span>
          <button type="button" data-fill onClick={() => props.onInput('New question')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
    });
    await flushUi();

    expect(root.querySelector('[data-message-id="1"]')?.textContent).toBe('Hello');
    expect(root.textContent).toContain('DATE_SEPARATOR');
    expect(messageContext).toBeDefined();
    expect(findHintButton()).toBeUndefined();

    messageContext!.onEditMessage(1, 'Edited question');
    await flushUi();
    expect(root.querySelector('[data-composer-value]')?.textContent).toBe('Edited question');

    (root.querySelector('[data-fill]') as HTMLButtonElement).click();
    await flushUi();
    (root.querySelector('[data-send]') as HTMLButtonElement).click();
    await flushUi();
    expect(onSendMessage).toHaveBeenCalledWith('New question', 1);
    expect(root.querySelector('[data-composer-value]')?.textContent).toBe('');

    (root.querySelector('[aria-label="Open Menu"]') as HTMLButtonElement).click();
    await flushUi();
    const clearMenuItem = Array.from(document.body.querySelectorAll('button'))
      .find((button) => button.textContent?.includes('Clear Chat'));
    expect(clearMenuItem).toBeDefined();
    clearMenuItem!.click();
    await flushUi();
    (document.getElementById('agent-clear-chat-confirm') as HTMLButtonElement).click();
    await flushUi();
    expect(onClearChat).toHaveBeenCalledTimes(1);
  });

  it('shows hints only in an empty chat and sends the clicked one', async () => {
    const onSendHint = jest.fn();
    renderShell({ hints: [HINT], onSendHint });
    await flushUi();

    const hintButton = findHintButton();
    expect(hintButton).toBeDefined();
    hintButton!.click();
    await flushUi();
    expect(onSendHint).toHaveBeenCalledWith(HINT);

    renderShell({ messages: [MESSAGE], hints: [HINT], onSendHint });
    await flushUi();
    expect(findHintButton()).toBeUndefined();
  });

  it('keeps the draft editable while an answer is running but does not send it', async () => {
    const onSendMessage = jest.fn();
    renderShell({
      messages: [MESSAGE],
      isInputDisabled: true,
      onSendMessage,
      renderComposer: (props) => (
        <div>
          <span data-composer-value>{props.inputValue}</span>
          <button type="button" data-fill onClick={() => props.onInput('Draft')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
    });
    await flushUi();

    (root.querySelector('[data-fill]') as HTMLButtonElement).click();
    await flushUi();
    expect(root.querySelector('[data-composer-value]')?.textContent).toBe('Draft');

    (root.querySelector('[data-send]') as HTMLButtonElement).click();
    await flushUi();
    expect(onSendMessage).not.toHaveBeenCalled();
    expect(root.querySelector('[data-composer-value]')?.textContent).toBe('Draft');
  });

  it('moves focus to the input on Tab only while nothing has focus and the app is unlocked', async () => {
    renderShell({ messages: [MESSAGE] });
    await flushUi();

    expect(pressTab(document.body).defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(root.querySelector('textarea'));

    const button = root.querySelector('button')!;
    button.focus();
    expect(pressTab(button).defaultPrevented).toBe(false);
    button.blur();

    setGlobal({ ...getGlobal(), isAppLockActive: true });
    try {
      expect(pressTab(document.body).defaultPrevented).toBe(false);
    } finally {
      setGlobal({ ...getGlobal(), isAppLockActive: undefined });
    }
  });

  it('trims the empty live tail reserve when the user scrolls up after the answer settles', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: MESSAGE.timestamp + 2,
    };
    let requestLiveTail: NoneToVoidFunction | undefined;
    const renderMessage: AgentConversation['renderMessage'] = (message, context) => {
      requestLiveTail = context.onRequestLiveTail;
      return <div key={message.id} data-message-id={message.id}>{message.text}</div>;
    };
    const render = (messages: AgentMessage[], isRunActive: boolean) => {
      renderShell({ messages, isRunActive, renderMessage });
    };

    render([MESSAGE], true);
    await flushUi();
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 1000, clientHeight: 400 });

    requestLiveTail!();
    render([MESSAGE, question], true);
    await flushUi();

    const liveTail = root.querySelector('[data-message-id="3"]')!.parentElement!;
    Object.defineProperties(liveTail, {
      offsetHeight: { configurable: true, value: 600 },
      getBoundingClientRect: { configurable: true, value: () => ({ top: 0 }) },
    });
    Object.defineProperty(liveTail.lastElementChild!, 'getBoundingClientRect', {
      configurable: true,
      value: () => ({ bottom: 150 }),
    });

    const scrollTo = (top: number) => {
      geometry.scrollTop = top;
      messagesElement.dispatchEvent(new Event('scroll'));
    };

    scrollTo(300);
    await flushUi();
    expect(liveTail.style.minHeight).toBe('');

    render([MESSAGE, question], false);
    await flushUi();
    scrollTo(300);
    await flushUi();
    expect(liveTail.style.minHeight).toBe('300px');

    scrollTo(0);
    await flushUi();
    expect(liveTail.style.minHeight).toBe('150px');
  });

  it('keeps Clear Chat available while an answer is running', async () => {
    const onClearChat = jest.fn();
    renderShell({
      messages: [MESSAGE, { ...SECOND_MESSAGE, isStreaming: true }],
      isInputDisabled: true,
      onClearChat,
    });
    await flushUi();

    (root.querySelector('[aria-label="Open Menu"]') as HTMLButtonElement).click();
    await flushUi();
    const clearMenuItem = Array.from(document.body.querySelectorAll('button'))
      .find((button) => button.textContent?.includes('Clear Chat'));
    expect(clearMenuItem?.disabled).toBe(false);
    clearMenuItem!.click();
    await flushUi();
    (document.getElementById('agent-clear-chat-confirm') as HTMLButtonElement).click();
    await flushUi();

    expect(onClearChat).toHaveBeenCalledTimes(1);
  });

  it('reports the conversation from the menu and an answer from its message, keeping a refused form', async () => {
    const onReportProblem = jest.fn()
      .mockResolvedValueOnce('rateLimited')
      .mockResolvedValue('sent');
    let messageContext: Parameters<AgentConversation['renderMessage']>[1] | undefined;
    renderShell({
      messages: [MESSAGE],
      onReportProblem,
      renderMessage: (message, context) => {
        messageContext = context;
        return <div key={message.id}>{message.text}</div>;
      },
    });
    await flushUi();

    (root.querySelector('[aria-label="Open Menu"]') as HTMLButtonElement).click();
    await flushUi();
    Array.from(document.body.querySelectorAll('button'))
      .find((button) => button.textContent?.includes('Report a Problem'))!
      .click();
    await flushUi();
    const comment = document.getElementById('agent-report-problem-comment') as HTMLTextAreaElement;
    comment.value = '  Wrong balance  ';
    comment.dispatchEvent(new Event('input', { bubbles: true }));
    await flushUi();
    (document.getElementById('agent-report-problem-send') as HTMLButtonElement).click();
    await flushUi();

    expect(onReportProblem).toHaveBeenLastCalledWith(undefined, 'Wrong balance');
    expect(mockShowToast).toHaveBeenLastCalledWith({ message: '$agent_report_problem_rate_limited' });
    expect(document.getElementById('agent-report-problem-send')).not.toBeNull();

    (document.getElementById('agent-report-problem-send') as HTMLButtonElement).click();
    await flushUi();
    expect(mockShowToast).toHaveBeenLastCalledWith({ message: '$agent_report_problem_sent', icon: 'icon-check' });

    messageContext!.onReportMessage!(MESSAGE.id);
    await flushUi();
    (document.getElementById('agent-report-problem-send') as HTMLButtonElement).click();
    await flushUi();
    expect(onReportProblem).toHaveBeenLastCalledWith(MESSAGE.id, '');
  });

  it('offers no report while the server does not take them', async () => {
    let messageContext: Parameters<AgentConversation['renderMessage']>[1] | undefined;
    renderShell({
      messages: [MESSAGE],
      renderMessage: (message, context) => {
        messageContext = context;
        return <div key={message.id}>{message.text}</div>;
      },
    });
    await flushUi();

    (root.querySelector('[aria-label="Open Menu"]') as HTMLButtonElement).click();
    await flushUi();

    const menuTexts = Array.from(document.body.querySelectorAll('button')).map((button) => button.textContent);
    expect(menuTexts.some((text) => text?.includes('Clear Chat'))).toBe(true);
    expect(menuTexts.some((text) => text?.includes('Report a Problem'))).toBe(false);
    expect(messageContext!.onReportMessage).toBeUndefined();
  });

  it('renders extension slots and keeps continuous remote pagination', async () => {
    const loadOlderMessages = jest.fn();

    renderShell({
      messages: [MESSAGE],
      hasOlderMessages: true,
      loadOlderMessages,
      historyMode: 'continuous',
      messageListFooter: <div data-activity-slot>Working</div>,
      beforeComposerSlot: <div data-limit-slot>Limit</div>,
      renderMessage: (message) => (
        <AgentV2AssistantText
          key={message.id}
          messageId={message.id}
          text={message.text}
          isStreaming={false}
          shouldAnimate={false}
        />
      ),
      renderComposer: () => <div data-v2-composer>Composer</div>,
    });

    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    Object.defineProperties(messagesElement, {
      scrollTop: { configurable: true, value: 0 },
      scrollHeight: { configurable: true, value: 100 },
      clientHeight: { configurable: true, value: 200 },
    });
    await flushUi();

    expect(root.querySelector('[data-activity-slot]')?.textContent).toBe('Working');
    expect(root.querySelector('[data-limit-slot]')?.textContent).toBe('Limit');
    expect(root.querySelector('[data-v2-composer]')?.textContent).toBe('Composer');
    expect(loadOlderMessages).toHaveBeenCalled();
  });

  it('scrolls to reveal follow-up controls after animated text settles', async () => {
    const messages = [MESSAGE];
    const renderMessage: AgentConversation['renderMessage'] = (message, context) => (
      <div key={message.id} data-message-id={message.id}>
        {message.text}
        {context.textRevealPresentation?.status === 'settled' && (
          <div data-followups>Follow-ups</div>
        )}
      </div>
    );
    const activePresentation = {
      [MESSAGE.id]: { key: 'reveal-1', status: 'active' as const, shouldRevealFromStart: true },
    };

    renderShell({ messages, textRevealPresentations: activePresentation, noComposer: true, renderMessage });
    await flushUi();

    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    let scrollHeight = 500;
    let scrollTop = 300;
    const directScrollAssignments = jest.fn((value: number) => {
      scrollTop = value;
    });
    const scrollTo = jest.fn(({ top }: ScrollToOptions) => {
      scrollTop = top ?? scrollTop;
    });
    Object.defineProperties(messagesElement, {
      scrollTop: {
        configurable: true,
        get: () => scrollTop,
        set: directScrollAssignments,
      },
      scrollHeight: { configurable: true, get: () => scrollHeight },
      clientHeight: { configurable: true, value: 200 },
      scrollTo: { configurable: true, value: scrollTo },
    });

    scrollHeight = 550;
    renderShell({
      messages,
      textRevealPresentations: {
        [MESSAGE.id]: { ...activePresentation[MESSAGE.id], status: 'settled' },
      },
      noComposer: true,
      renderMessage,
    });
    await flushUi();

    expect(root.querySelector('[data-followups]')).not.toBeNull();
    expect(scrollTop).toBe(scrollHeight);
    expect(directScrollAssignments).not.toHaveBeenCalled();
    expect(scrollTo).toHaveBeenCalledWith({ top: scrollHeight, behavior: 'instant' });
  });

  it('does not rerender an unchanged message when another message streams', async () => {
    const renderMessage: AgentConversation['renderMessage'] = (message, context) => (
      <MemoizedTestMessage key={message.id} message={message} onEdit={context.onEditMessage} />
    );

    renderShell({ messages: [MESSAGE, SECOND_MESSAGE], noComposer: true, renderMessage });
    await flushUi();
    expect(messageRenderSpy.mock.calls).toEqual([[MESSAGE.id], [SECOND_MESSAGE.id]]);

    messageRenderSpy.mockClear();
    renderShell({
      messages: [MESSAGE, { ...SECOND_MESSAGE, text: 'Streaming update', isStreaming: true }],
      noComposer: true,
      renderMessage,
    });
    await flushUi();

    expect(messageRenderSpy.mock.calls).toEqual([[SECOND_MESSAGE.id]]);
  });

  it('keeps shared active-state ownership around a replacement body', async () => {
    renderShell({ conversationSlot: <div data-consent-slot>Consent</div> });
    await flushUi();

    expect(document.documentElement.classList.contains('is-agent-active')).toBe(true);
    expect(root.textContent).toContain('Agent');
    expect(root.querySelector('[data-consent-slot]')?.textContent).toBe('Consent');
    expect(root.querySelector('[aria-label="Open Menu"]')).toBeNull();
    expect(root.querySelector('textarea')).toBeNull();
  });

  it('opens and resizes a bottom-pinned conversation without layout violations or smooth scrolling', async () => {
    const originalScrollTo = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollTo');
    const errors: Error[] = [];
    let scrollTop = 0;
    const scrollTo = jest.fn(({ top }: ScrollToOptions) => {
      scrollTop = top ?? scrollTop;
    });

    Object.defineProperty(Element.prototype, 'scrollTo', {
      configurable: true,
      writable: true,
      value: scrollTo,
    });
    disableStrict();
    setPhase('measure');
    setHandler((error) => errors.push(error));
    enableStrict();

    try {
      setPhase('mutate');
      renderShell({ messages: [MESSAGE] });
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const directScrollAssignments = jest.fn((value: number) => {
        scrollTop = value;
      });
      Object.defineProperties(messagesElement, {
        scrollTop: {
          configurable: true,
          get: () => scrollTop,
          set: directScrollAssignments,
        },
        scrollHeight: { configurable: true, value: 500 },
      });
      await Promise.resolve();
      setPhase('measure');
      await flushUi();

      expect(errors).toEqual([]);
      expect(scrollTop).toBe(500);
      expect(directScrollAssignments).not.toHaveBeenCalled();
      expect(scrollTo).toHaveBeenCalledWith({ top: 500, behavior: 'instant' });

      scrollTo.mockClear();
      updateAgentV2InputBarSpacing(messagesElement, 132, true);
      await flushUi();

      expect(errors).toEqual([]);
      expect(messagesElement.style.getPropertyValue('--agent-input-bar-height')).toBe('132px');
      expect(scrollTo).toHaveBeenCalledTimes(2);
      expect(scrollTo).toHaveBeenLastCalledWith({ top: 500, behavior: 'instant' });
      expect(directScrollAssignments).not.toHaveBeenCalled();
    } finally {
      disableStrict();
      setHandler();
      setPhase('measure');
      restoreProperty(Element.prototype, 'scrollTo', originalScrollTo);
    }
  });

  it('pins a sent question to the top and lets its answer grow without following it', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const answer: AgentMessage = {
      id: 4, text: 'Answer', isOutgoing: false, timestamp: question.timestamp + 1,
    };
    const renderLiveTailShell = (messages: AgentMessage[]) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
      renderComposer: (props) => (
        <div>
          <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
    });

    // Animations are disabled for hidden documents, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      renderLiveTailShell([MESSAGE, SECOND_MESSAGE]);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
      await flushUi();

      const earlierMessageElement = root.querySelector('[data-message-id="1"]');

      (root.querySelector('[data-fill]') as HTMLButtonElement).click();
      await flushUi();
      (root.querySelector('[data-send]') as HTMLButtonElement).click();
      await flushUi();
      // The reserved space below the question makes the list one screen taller
      geometry.scrollHeight = 1100;
      renderLiveTailShell([MESSAGE, SECOND_MESSAGE, question]);
      await flushUi();
      await flushUi();

      expect(root.querySelector('[data-message-id="3"]')!.parentElement)
        .not.toBe(root.querySelector('[data-message-id="2"]')!.parentElement);
      expect(root.querySelector('[data-message-id="1"]')).toBe(earlierMessageElement);
      expect(geometry.scrollTop).toBe(600);
      expect(geometry.positions.some((top) => top > 0 && top < 600)).toBe(true);

      geometry.scrollHeight = 1400;
      renderLiveTailShell([MESSAGE, SECOND_MESSAGE, question, answer]);
      await flushUi();

      expect(geometry.scrollTop).toBe(600);

      messagesElement.dispatchEvent(new WheelEvent('wheel'));
      geometry.scrollHeight = 1500;
      renderLiveTailShell([MESSAGE, SECOND_MESSAGE, question, { ...answer, text: 'Longer answer' }]);
      await flushUi();

      expect(geometry.scrollTop).toBe(1000);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('stops waiting for a question that never reaches the list', async () => {
    const renderPendingShell = (messages: AgentMessage[]) => renderShell({
      messages,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
      renderComposer: (props) => (
        <div>
          <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
    });

    renderPendingShell([MESSAGE]);
    const geometry = mockScrollGeometry(
      root.querySelector('.custom-scroll') as HTMLDivElement,
      { scrollHeight: 500, clientHeight: 500 },
    );
    await flushUi();

    // The run fails to start, so the question never appears in the list
    (root.querySelector('[data-fill]') as HTMLButtonElement).click();
    await flushUi();
    (root.querySelector('[data-send]') as HTMLButtonElement).click();
    await flushUi();
    await flushUi();
    await flushUi();

    geometry.scrollHeight = 900;
    renderPendingShell([MESSAGE, SECOND_MESSAGE]);
    await flushUi();

    expect(geometry.scrollTop).toBe(400);
  });

  it('marks only messages appended after the list is shown as just added', async () => {
    const justAddedById: Record<number, boolean> = {};
    const renderMessage: AgentConversation['renderMessage'] = (message, context) => {
      justAddedById[message.id] = context.isJustAdded;
      return <div key={message.id}>{message.text}</div>;
    };

    renderShell({ messages: [MESSAGE], noComposer: true, renderMessage });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
    await flushUi();
    expect(justAddedById[MESSAGE.id]).toBe(false);

    renderShell({ messages: [MESSAGE, SECOND_MESSAGE], noComposer: true, renderMessage });
    await flushUi();

    expect(justAddedById[MESSAGE.id]).toBe(false);
    expect(justAddedById[SECOND_MESSAGE.id]).toBe(true);
  });

  it('keeps a long V1 conversation bounded while navigating earlier history', async () => {
    const messages = Array.from({ length: 100 }, (_, index): AgentMessage => ({
      ...MESSAGE,
      id: index + 1,
      text: `Message ${index + 1}`,
      timestamp: MESSAGE.timestamp + index,
    }));
    const loadOlderMessages = jest.fn();
    const renderLongConversation = (isLoadingOlderMessages: boolean) => renderShell({
      messages,
      hasOlderMessages: true,
      isLoadingOlderMessages,
      loadOlderMessages,
      noComposer: true,
      renderMessage: (message) => (
        <div key={message.id} data-message-id={message.id}>{message.text}</div>
      ),
    });

    renderLongConversation(false);
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    Object.defineProperties(messagesElement, {
      scrollTop: { configurable: true, writable: true, value: 0 },
      scrollHeight: { configurable: true, value: 500 },
      clientHeight: { configurable: true, value: 900 },
      offsetHeight: { configurable: true, value: 900 },
    });
    await flushUi();

    renderLongConversation(true);
    await flushUi();
    renderLongConversation(false);
    await flushUi();

    const renderedIds = Array.from(root.querySelectorAll<HTMLElement>('[data-message-id]'))
      .map(({ dataset }) => Number(dataset.messageId));
    expect(renderedIds).toHaveLength(60);
    expect(renderedIds.at(-1)).toBe(100);
  });

  function renderShell({
    isActive = true,
    animationLevel = 0,
    messages = [],
    hints,
    isInitialLoadComplete = true,
    isInputDisabled = false,
    isRunActive = false,
    textRevealPresentations = {},
    noComposer = false,
    hasOlderMessages = false,
    isLoadingOlderMessages = false,
    historyMode = 'windowed',
    conversationSlot,
    messageListFooter,
    beforeComposerSlot,
    bottomStickDependency,
    loadOlderMessages = jest.fn(),
    onBack = jest.fn(),
    onSendMessage = jest.fn(),
    onSendHint = jest.fn(),
    onClearChat = jest.fn(),
    onReportProblem,
    onComposerHeightChange,
    onScroll,
    renderMessage = (message) => <div key={message.id}>{message.text}</div>,
    renderComposer,
  }: RenderShellOptions = {}) {
    TeactDOM.render(
      <AgentConversationShell
        isActive={isActive}
        animationLevel={animationLevel}
        conversation={{
          messages,
          hints,
          isInitialLoadComplete,
          isRunActive,
          textRevealPresentations,
          renderMessage,
        }}
        composer={{
          isDisabled: isInputDisabled,
          shouldHide: noComposer,
          onSendMessage,
          onSendHint,
          onHeightChange: onComposerHeightChange,
          render: renderComposer,
        }}
        history={hasOlderMessages ? {
          hasOlderMessages,
          isLoading: isLoadingOlderMessages,
          mode: historyMode,
          loadOlderMessages,
        } : undefined}
        slots={{
          body: conversationSlot,
          messageListFooter,
          beforeComposer: beforeComposerSlot,
          bottomStickDependency,
        }}
        actions={{
          onBack, onClearChat, onReportProblem, onScroll,
        }}
      />,
      root,
    );
  }
});

function findHintButton() {
  return Array.from(document.body.querySelectorAll('button'))
    .find((button) => button.textContent?.includes(HINT.title));
}

async function flushUi() {
  for (let i = 0; i < 20; i++) {
    await jest.advanceTimersByTimeAsync(20);
    const callbacks = Array.from(pendingAnimationFrames.values());
    pendingAnimationFrames.clear();
    callbacks.forEach((callback) => callback(i * 16));
    await Promise.resolve();
  }
}

function pressTab(target: HTMLElement) {
  const event = new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
  target.dispatchEvent(event);
  return event;
}

function mockScrollGeometry(
  element: HTMLElement,
  { scrollHeight, clientHeight }: { scrollHeight: number; clientHeight: number },
) {
  const geometry = {
    scrollTop: 0,
    scrollHeight,
    positions: [] as number[],
  };

  function setScrollTop(value: number) {
    geometry.scrollTop = Math.min(Math.max(value, 0), geometry.scrollHeight - clientHeight);
    geometry.positions.push(geometry.scrollTop);
  }

  Object.defineProperties(element, {
    scrollTop: { configurable: true, get: () => geometry.scrollTop, set: setScrollTop },
    scrollHeight: { configurable: true, get: () => geometry.scrollHeight },
    clientHeight: { configurable: true, value: clientHeight },
    scrollTo: {
      configurable: true,
      value: ({ top }: ScrollToOptions) => setScrollTop(top ?? geometry.scrollTop),
    },
  });

  return geometry;
}

function restoreProperty(target: object, key: PropertyKey, descriptor?: PropertyDescriptor) {
  if (descriptor) {
    Object.defineProperty(target, key, descriptor);
  } else {
    Reflect.deleteProperty(target, key);
  }
}
