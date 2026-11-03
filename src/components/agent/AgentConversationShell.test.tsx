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
  AgentConversationSession,
  AgentConversationSessionStore,
} from './AgentConversationShell';

import { ANIMATION_LEVEL_MAX } from '../../config';
import { requestMutation } from '../../lib/fasterdom/fasterdom';
import {
  disableStrict, enableStrict, getPhase, setHandler, setPhase,
} from '../../lib/fasterdom/stricterdom';
import { processDeeplink } from '../../util/deeplink';
import { openUrl } from '../../util/openUrl';
import { updateAgentV2InputBarSpacing } from '../agentV2/inputBarSpacing';

import { PORTRAIT_SCREEN_QUERY } from '../../hooks/useDeviceScreen';

import { AgentV2AssistantText } from '../agentV2/AgentV2Conversation';
import AgentConversationShell from './AgentConversationShell';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { isRtl: false }),
}));
jest.mock('./helpers/formatAgentChatDate', () => ({
  __esModule: true,
  default: () => ({ day: 'DATE_SEPARATOR', time: '' }),
}));

jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../util/deeplink', () => ({ processDeeplink: jest.fn() }));

// Stands in for the rendered window of a long list, which `resetScroll` moves to its end
let mockViewport: { ids: string[] } | undefined;
jest.mock('../../hooks/useInfiniteScroll', () => {
  const actual = jest.requireActual('../../hooks/useInfiniteScroll');
  return {
    ...actual,
    __esModule: true,
    default: (options: { listIds?: string[] }) => (mockViewport ? [
      mockViewport.ids,
      jest.fn(),
      () => {
        mockViewport!.ids = options.listIds!.slice(-30);
      },
    ] : actual.default(options)),
  };
});

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
  unreadMessageId?: number;
  initialMessageId?: number;
  loadFailure?: AgentConversation['loadFailure'];
  noComposer?: boolean;
  withoutComposer?: boolean;
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
  hasMenu?: boolean;
  onDelete?: NoneToVoidFunction;
  onReportProblem?: AgentConversationActions['onReportProblem'];
  onComposerHeightChange?: (height: number, context: AgentConversationComposerHeightContext) => void;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
  renderMessage?: AgentConversation['renderMessage'];
  renderComposer?: AgentConversationComposer['render'];
  dissolvingMessageIds?: AgentConversation['dissolvingMessageIds'];
  isFooterDissolving?: boolean;
  onDissolveStart?: NoneToVoidFunction;
  session?: AgentConversationSessionStore;
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

  it('preserves V1 composer, edit, send, date-separator, and delete behavior', async () => {
    const onSendMessage = jest.fn();
    const onDelete = jest.fn();
    let messageContext: Parameters<AgentConversation['renderMessage']>[1] | undefined;

    renderShell({
      messages: [MESSAGE, SECOND_MESSAGE],
      hints: [HINT],
      hasMenu: true,
      onSendMessage,
      onDelete,
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
    const deleteMenuItem = findMenuItem('Delete Chat');
    expect(deleteMenuItem).toBeDefined();
    deleteMenuItem!.click();
    await flushUi();
    expect(onDelete).toHaveBeenCalledTimes(1);
  });

  it('keeps the draft and the question in edit for the next mount of the chat', async () => {
    const QUESTION: AgentMessage = {
      ...MESSAGE, id: 3, text: 'First question', isOutgoing: true,
    };
    const onSendMessage = jest.fn();
    let messageContext: Parameters<AgentConversation['renderMessage']>[1] | undefined;
    const save = jest.fn();
    const renderComposer: AgentConversationComposer['render'] = (props) => (
      <div>
        <span data-composer-value>{props.inputValue}</span>
        <button type="button" data-send onClick={props.onSend}>Send</button>
      </div>
    );
    const renderMessage: AgentConversation['renderMessage'] = (message, context) => {
      messageContext = context;
      return <div key={message.id}>{message.text}</div>;
    };

    renderShell({
      messages: [QUESTION, MESSAGE], renderMessage, renderComposer, session: { save },
    });
    await flushUi();
    messageContext!.onEditMessage(QUESTION.id, 'First question, edited');
    await flushUi();
    expect(save).toHaveBeenLastCalledWith({
      draft: 'First question, edited',
      editedMessage: { indexFromEnd: 1, text: 'First question' },
    });

    // The next mount numbers the same messages afresh
    TeactDOM.render(undefined, root);
    renderShell({
      messages: [{ ...QUESTION, id: 13 }, { ...MESSAGE, id: 14 }],
      renderMessage,
      renderComposer,
      onSendMessage,
      session: { initial: save.mock.lastCall![0], save },
    });
    await flushUi();
    expect(root.querySelector('[data-composer-value]')?.textContent).toBe('First question, edited');

    (root.querySelector('[data-send]') as HTMLButtonElement).click();
    await flushUi();
    expect(onSendMessage).toHaveBeenCalledWith('First question, edited', 13);
    expect(save).toHaveBeenLastCalledWith({ draft: '', editedMessage: undefined });
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

  it('opens with the input focused on a pointer device, unless the lock screen covers the Agent', async () => {
    renderShell({ messages: [MESSAGE] });
    await flushUi();
    expect(document.activeElement).toBe(root.querySelector('textarea'));

    TeactDOM.render(undefined, root);
    (document.activeElement as HTMLElement | null)?.blur();
    setGlobal({ ...getGlobal(), isAppLockActive: true });
    try {
      renderShell({ messages: [MESSAGE] });
      await flushUi();
      expect(document.activeElement).not.toBe(root.querySelector('textarea'));
    } finally {
      setGlobal({ ...getGlobal(), isAppLockActive: undefined });
    }
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

  it('keeps Delete Chat available while an answer is running', async () => {
    const onDelete = jest.fn();
    renderShell({
      messages: [MESSAGE, { ...SECOND_MESSAGE, isStreaming: true }],
      isInputDisabled: true,
      hasMenu: true,
      onDelete,
    });
    await flushUi();

    (root.querySelector('[aria-label="Open Menu"]') as HTMLButtonElement).click();
    await flushUi();
    const deleteMenuItem = findMenuItem('Delete Chat');
    expect(deleteMenuItem?.disabled).toBe(false);
    deleteMenuItem!.click();
    await flushUi();

    expect(onDelete).toHaveBeenCalledTimes(1);
  });

  it('hangs the chat menu 12 px in from the header end, over the header bottom', async () => {
    renderShell({ messages: [MESSAGE], hasMenu: true, onDelete: jest.fn() });
    await flushUi();

    const menuButton = root.querySelector<HTMLButtonElement>('[aria-label="Open Menu"]')!;
    const header = menuButton.parentElement!.parentElement!;
    header.getBoundingClientRect = () => ({
      top: 0, bottom: 48, left: 0, right: 402, x: 0, y: 0, width: 402, height: 48, toJSON: () => undefined,
    });
    menuButton.click();
    await flushUi();

    const menuItem = findMenuItem('Delete Chat')!;
    const placed = Array.from(document.body.querySelectorAll<HTMLElement>('[style]'))
      .find((element) => element.contains(menuItem) && element.style.left);
    expect(placed?.style.left).toBe('390px');
    expect(placed?.style.top).toBe('38px');
  });

  it('dims the chat menu until it has an item', async () => {
    renderShell({ messages: [MESSAGE], hasMenu: true });
    await flushUi();

    expect(root.querySelector<HTMLButtonElement>('[aria-label="Open Menu"]')?.disabled).toBe(true);

    renderShell({ messages: [MESSAGE], hasMenu: true, onDelete: jest.fn() });
    await flushUi();

    expect(root.querySelector<HTMLButtonElement>('[aria-label="Open Menu"]')?.disabled).toBe(false);
  });

  it('reports the conversation from the menu and an answer from its message, keeping a refused form', async () => {
    const onReportProblem = jest.fn()
      .mockResolvedValueOnce('rateLimited')
      .mockResolvedValue('sent');
    let messageContext: Parameters<AgentConversation['renderMessage']>[1] | undefined;
    renderShell({
      messages: [MESSAGE],
      hasMenu: true,
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
      hasMenu: true,
      onDelete: jest.fn(),
      renderMessage: (message, context) => {
        messageContext = context;
        return <div key={message.id}>{message.text}</div>;
      },
    });
    await flushUi();

    (root.querySelector('[aria-label="Open Menu"]') as HTMLButtonElement).click();
    await flushUi();

    const menuTexts = Array.from(document.body.querySelectorAll('button')).map((button) => button.textContent);
    expect(menuTexts.some((text) => text?.includes('Delete Chat'))).toBe(true);
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

  it('requests an underfilled history only once when loading fails without new messages', async () => {
    const messages = [MESSAGE];
    let loadTimer: number | undefined;
    const loadOlderMessages = jest.fn(() => {
      renderList(true);
      loadTimer = window.setTimeout(() => renderList(false), 20);
    });
    function renderList(isLoadingOlderMessages = false) {
      renderShell({
        messages,
        withoutComposer: true,
        hasOlderMessages: true,
        historyMode: 'continuous',
        isLoadingOlderMessages,
        loadOlderMessages,
      });
    }

    renderList();
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    mockScrollGeometry(messagesElement, { scrollHeight: 100, clientHeight: 500 });

    try {
      await flushUi(60);
      expect(loadOlderMessages).toHaveBeenCalledTimes(1);
    } finally {
      window.clearTimeout(loadTimer);
    }
  });

  it('requests the next page when newly loaded messages still leave the history underfilled', async () => {
    const messages = buildMessages(4);
    let currentMessages = messages.slice(2);
    const loadOlderMessages = jest.fn(() => renderList(true));
    function renderList(isLoadingOlderMessages = false) {
      renderShell({
        messages: currentMessages,
        withoutComposer: true,
        hasOlderMessages: true,
        historyMode: 'continuous',
        isLoadingOlderMessages,
        loadOlderMessages,
      });
    }

    renderList();
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 100, clientHeight: 500 });
    await flushUi();
    expect(loadOlderMessages).toHaveBeenCalledTimes(1);

    currentMessages = messages;
    geometry.scrollHeight = 200;
    renderList();
    await flushUi();

    expect(loadOlderMessages).toHaveBeenCalledTimes(2);
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

  it('heads a replacement body with the plain header', async () => {
    renderShell({ conversationSlot: <div data-consent-slot>Consent</div>, hasMenu: true });
    await flushUi();

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

  it('pins the last question again in the next mount of a chat that had it pinned', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const answer: AgentMessage = {
      id: 4, text: 'Answer', isOutgoing: false, timestamp: question.timestamp + 1,
    };
    const session: AgentConversationSessionStore = { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
    const renderPinnedShell = (messages: AgentMessage[], isInitialLoadComplete = true) => renderShell({
      messages,
      isInitialLoadComplete,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
      session,
    });

    renderPinnedShell([], false);
    await flushUi();
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 1400, clientHeight: 500 });

    renderPinnedShell([MESSAGE, SECOND_MESSAGE, question, answer]);
    const liveTail = root.querySelector('[data-message-id="3"]')!.parentElement!;
    // The question's turn ends with the reserve under its answer, 500 px below the turn's top
    Object.defineProperties(liveTail, {
      offsetHeight: { configurable: true, value: 500 },
      getBoundingClientRect: { configurable: true, value: () => ({ top: 700, bottom: 1200 }) },
    });
    Object.defineProperty(liveTail.lastElementChild!, 'getBoundingClientRect', {
      configurable: true,
      value: () => ({ bottom: 900 }),
    });
    await flushUi();

    // At the end of the reserve rather than of the list, which ends 200 px further down
    expect(geometry.scrollTop).toBe(700);

    geometry.scrollHeight = 1600;
    renderPinnedShell([MESSAGE, SECOND_MESSAGE, question, { ...answer, text: 'Longer answer' }]);
    await flushUi();

    expect(geometry.scrollTop).toBe(700);
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

  it('turns messages to dust where they stand and closes the space they leave', async () => {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const answer: AgentMessage = { ...SECOND_MESSAGE, text: 'Answer to regenerate' };
    const renderMessage: AgentConversation['renderMessage'] = (message) => (
      <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
    );
    const onDissolveStart = jest.fn();
    renderShell({ animationLevel: ANIMATION_LEVEL_MAX, messages: [question, answer], renderMessage });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    mockScrollGeometry(messagesElement, { scrollHeight: 600, clientHeight: 600 });
    await flushUi();

    // Dust is drawn only while the page is visible, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
    document.dispatchEvent(new Event('visibilitychange'));
    await flushUi(3);
    restoreProperty(document, 'hidden', originalHidden);

    mockRect(messagesElement, { top: 0, bottom: 600 });
    mockRect(root.querySelector<HTMLElement>('[data-agent-v2-message-id="1"]')!, { top: 50, bottom: 90 });
    mockRect(root.querySelector<HTMLElement>('[data-agent-v2-message-id="2"]')!, { top: 100, bottom: 200 });

    renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages: [question, answer],
      dissolvingMessageIds: [answer.id],
      onDissolveStart,
      renderMessage,
    });
    await flushUi(3);

    // A ghost of the answer turns to dust over the list
    const layer = messagesElement.nextElementSibling!;
    expect(onDissolveStart).toHaveBeenCalledTimes(1);
    expect(layer.textContent).toBe(answer.text);
    expect(layer.querySelector('svg')).not.toBeNull();

    renderShell({ animationLevel: ANIMATION_LEVEL_MAX, messages: [question], renderMessage });
    await flushUi(3);

    // The space ends where the answer ended until the dust settles
    expect(findDissolveGap()!.style.height).toBe('200px');

    // The space closes, and the ghost goes once its dust has settled
    await flushUi(80);
    expect(findDissolveGap()).toBeUndefined();
    expect(layer.childElementCount).toBe(0);
    expect(root.querySelector('[data-agent-v2-message-id="2"]')).toBeNull();
  });

  it('turns the footer to dust where it stands and hands over the next one', async () => {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const renderMessage: AgentConversation['renderMessage'] = (message) => (
      <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
    );
    const failure = <p key="status" data-agent-list-footer>Limit failure</p>;
    const onDissolveStart = jest.fn();
    renderShell({
      animationLevel: ANIMATION_LEVEL_MAX, messages: [question], renderMessage, messageListFooter: failure,
    });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    mockScrollGeometry(messagesElement, { scrollHeight: 600, clientHeight: 600 });
    await flushUi();

    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
    document.dispatchEvent(new Event('visibilitychange'));
    await flushUi(3);
    restoreProperty(document, 'hidden', originalHidden);

    mockRect(messagesElement, { top: 0, bottom: 600 });
    mockRect(root.querySelector<HTMLElement>('[data-agent-v2-message-id="1"]')!, { top: 50, bottom: 90 });
    mockRect(root.querySelector<HTMLElement>('[data-agent-list-footer]')!, { top: 96, bottom: 124 });

    renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages: [question],
      renderMessage,
      messageListFooter: failure,
      isFooterDissolving: true,
      onDissolveStart,
    });
    await flushUi(3);

    const layer = messagesElement.nextElementSibling!;
    expect(onDissolveStart).toHaveBeenCalledTimes(1);
    expect(layer.textContent).toBe('Limit failure');

    renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages: [question],
      renderMessage,
      messageListFooter: <p key="next">Next</p>,
    });
    await flushUi(3);

    expect(findDissolveGap()!.style.height).toBe('124px');
    // The ghost in the layer is all that is left of it
    expect(messagesElement.querySelector('[data-agent-list-footer]')).toBeNull();
    await flushUi(80);
    expect(findDissolveGap()).toBeUndefined();
    expect(layer.childElementCount).toBe(0);
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

  it('scrolls to the latest messages out of the rendered window as smoothly as to rendered ones', async () => {
    const messages = Array.from({ length: 50 }, (_, index): AgentMessage => ({
      ...MESSAGE,
      id: index + 1,
      text: `Message ${index + 1}`,
      timestamp: MESSAGE.timestamp + index,
    }));
    mockViewport = { ids: ['date:1', ...messages.slice(0, 29).map(({ id }) => String(id))] };
    // Animations are disabled for hidden documents, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      renderShell({
        animationLevel: ANIMATION_LEVEL_MAX,
        messages,
        noComposer: true,
        renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
      });
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 5000, clientHeight: 500 });
      await flushUi();

      // The user scrolls up to the first rendered messages
      messagesElement.scrollTop = 0;
      messagesElement.dispatchEvent(new Event('scroll'));
      await flushUi();
      geometry.positions.length = 0;
      root.querySelector<HTMLButtonElement>('[aria-label="Scroll To Bottom"]')!.click();
      await flushUi(60);

      const renderedIds = Array.from(root.querySelectorAll<HTMLElement>('[data-message-id]'))
        .map(({ dataset }) => Number(dataset.messageId));
      expect(renderedIds.at(-1)).toBe(50);
      // As within the window, the list comes to the last screens and scrolls through them to its end
      const path = geometry.positions.filter((top) => top > 0);
      expect(path[0]).toBeGreaterThanOrEqual(3700);
      expect(path[0]).toBeLessThan(4000);
      expect(new Set(path).size).toBeGreaterThan(2);
      expect(path.at(-1)).toBe(4500);
    } finally {
      mockViewport = undefined;
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('stays where the user scrolls down to as the latest messages come into the rendered window', async () => {
    const messages = Array.from({ length: 50 }, (_, index): AgentMessage => ({
      ...MESSAGE,
      id: index + 1,
      text: `Message ${index + 1}`,
      timestamp: MESSAGE.timestamp + index,
    }));
    const renderLongConversation = () => renderShell({
      messages: [...messages],
      noComposer: true,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
    });
    mockViewport = { ids: ['date:1', ...messages.slice(0, 29).map(({ id }) => String(id))] };

    try {
      renderLongConversation();
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 5000, clientHeight: 500 });
      await flushUi();

      // The user scrolls down through older messages, and the latest ones render below them
      messagesElement.scrollTop = 3000;
      messagesElement.dispatchEvent(new Event('scroll'));
      await flushUi();
      mockViewport.ids = messages.slice(-30).map(({ id }) => String(id));
      renderLongConversation();
      await flushUi();

      expect(root.querySelector('[data-message-id="50"]')).not.toBeNull();
      expect(geometry.scrollTop).toBe(3000);
    } finally {
      mockViewport = undefined;
    }
  });

  it('shows a failed load centered with Retry while nothing shows, and as the last line otherwise', async () => {
    const onRetry = jest.fn();
    renderShell({
      loadFailure: { text: 'Load failed', onRetry }, hints: [HINT], hasMenu: true, onDelete: jest.fn(),
    });
    await flushUi();

    expect(root.querySelector('.custom-scroll')).toBeNull();
    expect(root.querySelector('[role="alert"]')?.textContent).toContain('Load failed');
    expect(findHintButton()).toBeUndefined();
    expect(root.querySelector<HTMLButtonElement>('[aria-label="Open Menu"]')?.disabled).toBe(false);
    Array.from(root.querySelectorAll('button')).find((button) => button.textContent === 'Retry')!.click();
    expect(onRetry).toHaveBeenCalledTimes(1);

    renderShell({ messages: [MESSAGE], loadFailure: { text: 'Load failed', onRetry } });
    await flushUi();

    expect(root.querySelector('[role="alert"]')).toBeNull();
    const list = root.querySelector('.custom-scroll')!;
    expect(list.textContent).toContain('Hello');
    expect(list.textContent!.indexOf('Load failed')).toBeGreaterThan(list.textContent!.indexOf('Hello'));
    root.querySelector<HTMLButtonElement>('[aria-label="$agent_retry_request"]')!.click();
    expect(onRetry).toHaveBeenCalledTimes(2);
  });

  it('shows the spinner under the header while older messages load', async () => {
    renderShell({ messages: [MESSAGE], hasOlderMessages: true, isLoadingOlderMessages: true });
    await flushUi();
    expect(root.querySelector('[aria-label="Loading..."]')).not.toBeNull();

    renderShell({ messages: [MESSAGE], hasOlderMessages: true });
    await flushUi();
    expect(root.querySelector('[aria-label="Loading..."]')).toBeNull();
  });

  it('opens at the first unread message after retrying an empty failed history load', async () => {
    renderShell({
      loadFailure: { text: 'Load failed', onRetry: jest.fn() },
      withoutComposer: true,
    });
    await flushUi();
    expect(root.querySelector('.custom-scroll')).toBeNull();

    renderShell({
      messages: buildMessages(10),
      unreadMessageId: 7,
      withoutComposer: true,
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
    });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 3000, clientHeight: 500 });
    mockMessageRects(geometry);
    await flushUi();

    expect(geometry.scrollTop).toBe(700);
  });

  it('opens at the first unread message after a "New" line rather than at its end', async () => {
    const messages = buildMessages(10);
    renderShell({
      messages,
      unreadMessageId: 7,
      withoutComposer: true,
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
    });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 3000, clientHeight: 500 });
    mockMessageRects(geometry);
    await flushUi();

    expect(root.textContent).toContain('$agent_news_new');
    expect(root.textContent!.indexOf('$agent_news_new')).toBe(root.textContent!.indexOf('Message 7') - 15);
    expect(root.querySelector('textarea')).toBeNull();
    expect(geometry.scrollTop).toBe(700);

    // The list stays where it opened as more messages come
    renderShell({
      messages: [...messages, ...buildMessages(11).slice(10)],
      unreadMessageId: 7,
      withoutComposer: true,
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
    });
    await flushUi();
    expect(geometry.scrollTop).toBe(700);
  });

  it('opens at the first unread message when it renders in the middle of a frame\'s update', async () => {
    const messages = buildMessages(10);
    let geometry: ReturnType<typeof mockScrollGeometry> | undefined;
    // The app renders in a frame's mutation phase, after which the frame's forced reflows run and its measures wait
    requestMutation(() => {
      renderShell({
        messages,
        unreadMessageId: 7,
        withoutComposer: true,
        renderMessage: (message) => (
          <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
        ),
      });
      geometry = mockScrollGeometry(root.querySelector('.custom-scroll') as HTMLDivElement, {
        scrollHeight: 3000, clientHeight: 500,
      });
      mockMessageRects(geometry);
    });
    await flushUi();

    expect(geometry!.scrollTop).toBe(700);
    expect(root.querySelector('[aria-label="Scroll To Bottom"]')).not.toBeNull();
  });

  it('opens again at its end where a layout switch left it, rather than at its first unread message', async () => {
    const messages = buildMessages(10);
    let savedSession: AgentConversationSession | undefined;
    const renderList = (initial?: AgentConversationSession) => {
      renderShell({
        messages,
        unreadMessageId: 7,
        withoutComposer: true,
        renderMessage: (message) => (
          <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
        ),
        session: {
          initial,
          save: (session) => {
            savedSession = session;
          },
        },
      });
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 3000, clientHeight: 500 });
      mockMessageRects(geometry);
      return { messagesElement, geometry };
    };

    const { messagesElement, geometry } = renderList();
    await flushUi();
    expect(geometry.scrollTop).toBe(700);

    // The user scrolls to the end, and the app switches layouts
    messagesElement.scrollTop = 2500;
    messagesElement.dispatchEvent(new Event('scroll'));
    await flushUi();
    switchLayout();
    expect(savedSession).toEqual(expect.objectContaining({ isPlaced: true, scrollAnchor: undefined }));

    TeactDOM.render(undefined, root);
    await flushUi();
    const { geometry: nextGeometry } = renderList(savedSession);
    await flushUi();

    expect(root.textContent).toContain('$agent_news_new');
    expect(nextGeometry.scrollTop).toBe(2500);
  });

  it('restores a saved scroll anchor beyond the initial rendered window', async () => {
    const messages = buildMessages(60);
    renderShell({
      messages,
      withoutComposer: true,
      session: {
        initial: { draft: '', isPlaced: true, scrollAnchor: { indexFromEnd: 55, offset: -25 } },
        save: jest.fn(),
      },
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
    });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 7000, clientHeight: 500 });
    mockMessageRects(geometry);
    await flushUi();

    expect(root.querySelector('[data-agent-v2-message-id="5"]')).not.toBeNull();
    expect(geometry.scrollTop).toBe(525);
  });

  it('opens at the message it is given beyond the rendered window', async () => {
    const messages = buildMessages(60);
    renderShell({
      messages,
      initialMessageId: 5,
      unreadMessageId: 40,
      withoutComposer: true,
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
    });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 7000, clientHeight: 500 });
    mockMessageRects(geometry);
    await flushUi();

    expect(root.querySelector('[data-agent-v2-message-id="5"]')).not.toBeNull();
    expect(geometry.scrollTop).toBe(500);
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
    unreadMessageId,
    initialMessageId,
    loadFailure,
    noComposer = false,
    withoutComposer = false,
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
    hasMenu = false,
    onDelete,
    onReportProblem,
    onComposerHeightChange,
    onScroll,
    renderMessage = (message) => <div key={message.id}>{message.text}</div>,
    renderComposer,
    dissolvingMessageIds,
    isFooterDissolving,
    onDissolveStart,
    session,
  }: RenderShellOptions = {}) {
    // The app renders inside the mutate phase, where layout effects may use `forceMeasure`
    const previousPhase = getPhase();
    setPhase('mutate');

    try {
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
            unreadMessageId,
            initialMessageId,
            loadFailure,
            dissolvingMessageIds,
            isFooterDissolving,
            onDissolveStart,
            renderMessage,
          }}
          composer={withoutComposer ? undefined : {
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
          header={hasMenu ? { hasMenu } : undefined}
          actions={{
            onBack, onDelete, onReportProblem, onScroll,
          }}
          session={session}
        />,
        root,
      );
    } finally {
      setPhase(previousPhase);
    }
  }
});

function buildMessages(count: number) {
  return Array.from({ length: count }, (_, index): AgentMessage => ({
    ...MESSAGE,
    id: index + 1,
    text: `Message ${index + 1}`,
    timestamp: MESSAGE.timestamp + index,
  }));
}

// Each message stands 100 px below the one before it, as many pixels from the content's top as its id says
function mockMessageRects(geometry: { scrollTop: number }) {
  jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
    const id = (this as HTMLElement).dataset?.agentV2MessageId;
    const top = id ? Number(id) * 100 - geometry.scrollTop : 0;
    return {
      top, bottom: top + 100, left: 0, right: 300, x: 0, y: top, width: 300, height: 100, toJSON: () => undefined,
    };
  });
}

// Calls the listeners of the layouts' media query, as the app switches between them
function switchLayout() {
  jest.mocked(window.matchMedia).mock.results.forEach(({ type: resultType, value }) => {
    if (resultType !== 'return' || value.media !== PORTRAIT_SCREEN_QUERY) return;

    const removedListeners = jest.mocked(value.removeEventListener).mock.calls.map(([, listener]) => listener);
    jest.mocked(value.addEventListener).mock.calls.forEach(([type, listener]) => {
      if (type === 'change' && !removedListeners.includes(listener)) (listener as EventListener)(new Event('change'));
    });
  });
}

function findMenuItem(text: string) {
  return Array.from(document.body.querySelectorAll('button')).find((button) => button.textContent?.includes(text));
}

function findHintButton() {
  return Array.from(document.body.querySelectorAll('button'))
    .find((button) => button.textContent?.includes(HINT.title));
}

async function flushUi(frameCount = 20) {
  for (let i = 0; i < frameCount; i++) {
    await jest.advanceTimersByTimeAsync(20);
    const callbacks = Array.from(pendingAnimationFrames.values());
    pendingAnimationFrames.clear();
    callbacks.forEach((callback) => callback(i * 16));
    await Promise.resolve();
  }
}

function findDissolveGap() {
  return Array.from(document.querySelectorAll<HTMLElement>('div[aria-hidden]')).find(({ style }) => style.height);
}

function mockRect(element: HTMLElement, { top, bottom }: { top: number; bottom: number }) {
  element.getBoundingClientRect = () => ({
    top, bottom, left: 0, right: 300, x: 0, y: top, width: 300, height: bottom - top, toJSON: () => undefined,
  });
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
