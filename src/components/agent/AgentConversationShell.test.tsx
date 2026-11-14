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
  AgentConversationComposerProps,
  AgentConversationSession,
  AgentConversationSessionStore,
  AgentConversationSlots,
} from './AgentConversationShell';

import { ANIMATION_LEVEL_MAX } from '../../config';
import { requestMutation } from '../../lib/fasterdom/fasterdom';
import {
  disableStrict, enableStrict, getPhase, setHandler, setPhase,
} from '../../lib/fasterdom/stricterdom';
import { processDeeplink } from '../../util/deeplink';
import { openUrl } from '../../util/openUrl';
import { updateAgentV2InputBarSpacing } from '../agentV2/inputBarSpacing';
import { getSnapEffectLayer } from './helpers/snapEffect';

import { PORTRAIT_SCREEN_QUERY } from '../../hooks/useDeviceScreen';
import useAgentV2Dictation from './hooks/useAgentV2Dictation';

import AgentV2Composer from '../agentV2/AgentV2Composer';
import { AgentV2AssistantText } from '../agentV2/AgentV2Conversation';
import AgentConversationShell from './AgentConversationShell';
import { MESSAGE_LIST_ITEM_SELECTOR } from './MessageBubble';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { isRtl: false }),
}));
jest.mock('./helpers/formatAgentChatDate', () => ({
  __esModule: true,
  default: () => ({ day: 'DATE_SEPARATOR', time: '' }),
}));

jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('./hooks/useAgentV2Dictation', () => {
  const actual = jest.requireActual('./hooks/useAgentV2Dictation');
  return { ...actual, __esModule: true, default: jest.fn(actual.default) };
});
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

// The class of a message's row, by which the list keeps its scroll position
const MESSAGE_ROW_CLASS_NAME = MESSAGE_LIST_ITEM_SELECTOR.slice(1);

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

// A starter hint of the pool, which has a title alone and is sent as it
const HINT: AgentHint = {
  id: 'market.today',
  langCode: 'en',
  title: 'Hint title',
  subtitle: '',
  prompt: 'Hint title',
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
  hasOpeningQuestion?: boolean;
  isInputDisabled?: boolean;
  isQueueing?: boolean;
  canStop?: boolean;
  onStop?: NoneToVoidFunction;
  sentQueuedMessage?: { id: number };
  isRunActive?: boolean;
  queuedMessageCount?: number;
  textRevealPresentations?: AgentConversation['textRevealPresentations'];
  unreadMessageId?: number;
  hasDailyDateLines?: boolean;
  loadFailure?: AgentConversation['loadFailure'];
  emptyText?: string;
  noComposer?: boolean;
  withoutComposer?: boolean;
  hasOlderMessages?: boolean;
  isLoadingOlderMessages?: boolean;
  noLoadingIndicator?: boolean;
  historyMode?: 'continuous' | 'windowed';
  conversationSlot?: TeactNode;
  headerAccessory?: AgentConversationSlots['headerAccessory'];
  messageListFooter?: TeactNode;
  runActivity?: TeactNode;
  beforeComposerSlot?: TeactNode;
  bottomStickDependency?: unknown;
  loadOlderMessages?: () => void | Promise<void>;
  onBack?: NoneToVoidFunction;
  onSendMessage?: AgentConversationComposer['onSendMessage'];
  onSendHint?: AgentConversationComposer['onSendHint'];
  hasMenu?: boolean;
  onDelete?: NoneToVoidFunction;
  onRequestSupport?: AgentConversationActions['onRequestSupport'];
  onReportProblem?: AgentConversationActions['onReportProblem'];
  onComposerHeightChange?: (height: number, context: AgentConversationComposerHeightContext) => void;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
  onMessageVisible?: AgentConversationActions['onMessageVisible'];
  renderMessage?: AgentConversation['renderMessage'];
  renderComposer?: AgentConversationComposer['render'];
  onRequestConsent?: AgentConversationComposer['onRequestConsent'];
  dissolvingMessageIds?: AgentConversation['dissolvingMessageIds'];
  isFooterDissolving?: boolean;
  onDissolveStart?: NoneToVoidFunction;
  session?: AgentConversationSessionStore;
  noLiveTail?: boolean;
}

let nextAnimationFrameId = 0;
let pendingAnimationFrames = new Map<number, FrameRequestCallback>();

describe('AgentConversationShell', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    jest.useFakeTimers();
    // eslint-disable-next-line no-null/no-null
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);
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

  it('reports intersecting messages only after the active list is placed and disconnects off screen', async () => {
    const onMessageVisible = jest.fn();
    const observe = jest.fn();
    const disconnect = jest.fn();
    let reportIntersection: (target: Element, isIntersecting: boolean) => void;
    const observerMock = jest.spyOn(window, 'IntersectionObserver').mockImplementation((callback, options) => {
      const observer: IntersectionObserver = {
        root: options!.root!, rootMargin: options!.rootMargin!, thresholds: [0],
        observe, unobserve: jest.fn(), disconnect, takeRecords: () => [],
      };
      reportIntersection = (target, isIntersecting) => {
        const rect = new DOMRect(0, 0, 100, 100);
        callback([{
          target, isIntersecting, intersectionRatio: isIntersecting ? 1 : 0,
          time: 0, boundingClientRect: rect, intersectionRect: rect, rootBounds: rect,
        }], observer);
      };
      return observer;
    });
    const options = {
      messages: [MESSAGE], renderMessage: renderDissolvingMessage, onMessageVisible,
    };
    renderShell({ ...options, isActive: false });
    await flushUi();
    expect(observerMock).not.toHaveBeenCalled();
    mockScrollGeometry(root.querySelector<HTMLElement>('.custom-scroll')!, { scrollHeight: 100, clientHeight: 100 });

    renderShell(options);
    await flushUi();
    const message = root.querySelector<HTMLElement>('[data-agent-v2-message-id="1"]')!;
    expect(observe).toHaveBeenCalledWith(message);
    expect(observerMock.mock.calls.at(-1)![1]!.root).toBe(message.closest('.custom-scroll'));
    reportIntersection!(message, false);
    expect(onMessageVisible).not.toHaveBeenCalled();
    reportIntersection!(message, true);
    expect(onMessageVisible.mock.calls).toEqual([[1]]);

    renderShell({ ...options, isActive: false });
    await flushUi();
    expect(disconnect).toHaveBeenCalledTimes(1);
    reportIntersection!(message, true);
    expect(onMessageVisible.mock.calls).toEqual([[1]]);
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

  it.each(['typing', 'dictation', 'edit', 'clear', 'send', 'immediate send'] as const)(
    'hands off the latest %s before the pending render', async (action) => {
      const question = { ...MESSAGE, id: 3, text: 'First question', isOutgoing: true };
      const save = jest.fn();
      const onSendMessage = jest.fn();
      let composerProps: AgentConversationComposerProps;
      let editMessage: Parameters<AgentConversation['renderMessage']>[1]['onEditMessage'];
      const renderComposer: AgentConversationComposer['render'] = (props) => {
        composerProps = props;
        return <span data-composer-value>{props.inputValue}</span>;
      };
      const renderMessage: AgentConversation['renderMessage'] = (message, context) => {
        editMessage = context.onEditMessage;
        return <div key={message.id}>{message.text}</div>;
      };
      renderShell({ messages: [question, MESSAGE], renderMessage, renderComposer, onSendMessage, session: { save } });
      await flushUi();

      if (action === 'edit') {
        editMessage!(question.id, 'Edited question');
      } else {
        composerProps!.onInput('A follow-up');
        if (action === 'dictation') composerProps!.onInput('A follow-up in progress');
        if (action === 'immediate send') composerProps!.onSend();
        if (action === 'clear' || action === 'send') {
          await flushUi();
          if (action === 'clear') composerProps!.onInput('');
          else composerProps!.onSend();
        }
      }
      switchLayout();
      const saved: AgentConversationSession = save.mock.lastCall![0];
      const expectedDraft = action === 'edit' ? 'Edited question'
        : action === 'dictation' ? 'A follow-up in progress'
          : action === 'typing' ? 'A follow-up' : '';
      expect(saved.draft).toBe(expectedDraft);
      expect(saved.editedMessage).toEqual(action === 'edit'
        ? { indexFromEnd: 1, text: 'First question' } : undefined);
      if (action.endsWith('send')) expect(onSendMessage).toHaveBeenCalledWith('A follow-up', undefined);

      TeactDOM.render(undefined, root);
      renderShell({ messages: [question, MESSAGE], renderMessage, renderComposer, session: { initial: saved, save } });
      await flushUi();
      expect(root.querySelector('[data-composer-value]')?.textContent).toBe(expectedDraft);
    },
  );

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

  it('shows no hints in an empty chat whose hints did not load, and keeps its Contact Support', async () => {
    const onRequestSupport = jest.fn();
    renderShell({ hasMenu: true, onRequestSupport });
    await flushUi();

    expect(root.querySelector('[data-agent-hints]')).toBeNull();
    const supportButton = root.querySelector<HTMLButtonElement>('button[aria-label="$agent_support_contact"]');
    expect(supportButton?.disabled).toBe(false);
    supportButton!.click();
    expect(onRequestSupport).toHaveBeenCalledWith('header');
  });

  for (const isHintTapped of [false, true]) {
    const name = isHintTapped
      ? 'lets an empty chat\'s hints leave where they stand as a tapped hint becomes its first question'
      : 'lets an empty chat\'s hints leave where they stand as its first question goes from the field';
    it(name, async () => {
      const question: AgentMessage = {
        id: 3, text: 'Question', isOutgoing: true, timestamp: MESSAGE.timestamp,
      };
      const onSendHint = jest.fn();
      const renderEmptyShell = (messages: AgentMessage[]) => renderShell({
        animationLevel: ANIMATION_LEVEL_MAX,
        messages,
        hints: [HINT],
        onSendHint,
        renderMessage: (message) => <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>,
        renderComposer: (props) => (
          <div>
            <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
            <button type="button" data-send onClick={props.onSend}>Send</button>
          </div>
        ),
      });
      const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
      Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

      try {
        renderEmptyShell([]);
        const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
        mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
        await flushUi();
        // The spacer pushes the hints down over the field
        const spacer = messagesElement.firstElementChild as HTMLElement;
        const hints = root.querySelector<HTMLElement>('[data-agent-hints]')!;
        Object.defineProperty(spacer, 'offsetHeight', { configurable: true, value: 240 });
        Object.defineProperties(hints, {
          offsetTop: { configurable: true, value: 260 },
          offsetLeft: { configurable: true, value: 8 },
          offsetWidth: { configurable: true, value: 384 },
        });

        if (isHintTapped) {
          findHintButton()!.click();
          await flushUi(1);
          expect(onSendHint).toHaveBeenCalledWith(HINT);
        } else {
          (root.querySelector('[data-fill]') as HTMLButtonElement).click();
          await flushUi();
          (root.querySelector('[data-send]') as HTMLButtonElement).click();
          await flushUi(1);
        }
        renderEmptyShell([question]);
        await flushUi(2);

        // The question stands at the top at once, with no space kept over it, and the hints fade where they stood,
        // out of its way, rather than being pushed under it
        expect(spacer.style.minHeight).toBe('');
        expect(hints.isConnected).toBe(true);
        expect([hints.style.top, hints.style.left, hints.style.width]).toEqual(['260px', '8px', '384px']);

        await flushUi();
        expect(root.querySelector('[data-agent-hints]')).toBeNull();
      } finally {
        restoreProperty(document, 'hidden', originalHidden);
      }
    });
  }

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

  it('keeps an edit begun before an answer, with its send dimmed, and sends it once the answer has ended', async () => {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const onSendMessage = jest.fn();
    let messageContext: Parameters<AgentConversation['renderMessage']>[1] | undefined;
    const renderEditingShell = (isQueueing: boolean) => renderShell({
      messages: [question, SECOND_MESSAGE],
      isQueueing,
      onSendMessage,
      renderMessage: (message, context) => {
        messageContext = context;
        return <div key={message.id}>{message.text}</div>;
      },
      renderComposer: (props) => (
        <div>
          <span data-composer-value>{props.inputValue}</span>
          <button type="button" data-send data-is-disabled={String(props.isDisabled)} onClick={props.onSend}>
            Send
          </button>
        </div>
      ),
    });
    renderEditingShell(false);
    await flushUi();
    messageContext!.onEditMessage(question.id, 'Edited question');
    await flushUi();

    // An answer starts, as from a suggestion, while the edit is open, and the edit waits for it with its send dimmed,
    // as on iOS
    renderEditingShell(true);
    await flushUi();
    const findSend = () => root.querySelector<HTMLButtonElement>('[data-send]')!;
    expect(findSend().dataset.isDisabled).toBe('true');
    findSend().click();
    await flushUi();
    expect(onSendMessage).not.toHaveBeenCalled();
    expect(root.querySelector('[data-composer-value]')?.textContent).toBe('Edited question');

    renderEditingShell(false);
    await flushUi();
    expect(findSend().dataset.isDisabled).toBe('false');
    findSend().click();
    await flushUi();
    expect(onSendMessage).toHaveBeenCalledWith('Edited question', question.id);
  });

  it('sends on Return and starts a new line on Return with Option, Command or Ctrl', async () => {
    const onSendMessage = jest.fn();
    renderShell({ messages: [MESSAGE], onSendMessage });
    await flushUi();
    const input = root.querySelector('textarea')!;
    input.value = 'First line';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    await flushUi();

    for (const modifier of ['altKey', 'metaKey', 'ctrlKey'] as const) {
      input.setSelectionRange(input.value.length, input.value.length);
      input.dispatchEvent(new KeyboardEvent('keydown', {
        key: 'Enter', bubbles: true, cancelable: true, [modifier]: true,
      }));
      await flushUi();
    }
    expect(onSendMessage).not.toHaveBeenCalled();
    expect(input.value).toBe('First line\n\n\n');

    input.value = 'First line\nSecond line';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    await flushUi();
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await flushUi();
    expect(onSendMessage).toHaveBeenCalledWith('First line\nSecond line', undefined);
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

    // The reserve starts 400 px down the list's content and ends the list 600 px further down, unless it is trimmed
    const reserve = root.querySelector<HTMLElement>('[data-agent-live-tail-reserve]')!;
    const getReserveHeight = () => Number.parseFloat(reserve.style.height) || 600;
    Object.defineProperties(reserve, {
      offsetHeight: { configurable: true, get: getReserveHeight },
      getBoundingClientRect: {
        configurable: true,
        value: () => ({ bottom: 400 + getReserveHeight() - geometry.scrollTop }),
      },
    });
    mockRect(messagesElement, { top: 0, bottom: 400 });

    const scrollTo = (top: number) => {
      geometry.scrollTop = top;
      messagesElement.dispatchEvent(new Event('scroll'));
    };

    scrollTo(300);
    await flushUi();
    expect(reserve.style.height).toBe('');

    render([MESSAGE, question], false);
    await flushUi();
    scrollTo(300);
    await flushUi();
    expect(reserve.style.height).toBe('300px');

    // Wholly below the screen, the reserve goes
    scrollTo(0);
    await flushUi();
    expect(reserve.style.height).toBe('0px');
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

  it('shows the chat menu button only once the menu has an item', async () => {
    renderShell({ messages: [MESSAGE], hasMenu: true });
    await flushUi();

    expect(root.querySelector('[aria-label="Open Menu"]')).toBeNull();

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

  it('draws the composer again with the consent request as it comes and goes', async () => {
    const renderComposer = jest.fn(() => <div data-v2-composer>Composer</div>);
    const onRequestConsent = jest.fn();
    renderShell({ messages: [MESSAGE], renderComposer, onRequestConsent });
    await flushUi();
    expect(renderComposer).toHaveBeenLastCalledWith(expect.objectContaining({ onRequestConsent }));

    renderShell({ messages: [MESSAGE], renderComposer });
    await flushUi();
    expect(renderComposer).toHaveBeenLastCalledWith(expect.objectContaining({ onRequestConsent: undefined }));
  });

  it('offers a report of the conversation before its messages have come', async () => {
    renderShell({ messages: [], hasMenu: true, onReportProblem: jest.fn() });
    await flushUi();

    (root.querySelector('[aria-label="Open Menu"]') as HTMLButtonElement).click();
    await flushUi();

    const menuTexts = Array.from(document.body.querySelectorAll('button')).map((button) => button.textContent);
    expect(menuTexts.some((text) => text?.includes('Report a Problem'))).toBe(true);
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

  it('attaches the accessory under the header at its height, also over a list with nothing to show', async () => {
    const headerAccessory = { content: <div data-accessory>Switch</div>, height: 2.875 };
    renderShell({ messages: [MESSAGE], headerAccessory });
    await flushUi();

    const conversation = root.querySelector<HTMLElement>('[data-agent-conversation]')!;
    expect(conversation.style.getPropertyValue('--agent-header-accessory-height')).toBe('2.875rem');
    expect(root.querySelector('[data-accessory]')?.textContent).toBe('Switch');

    renderShell({ messages: [], emptyText: 'Nothing yet', headerAccessory: { ...headerAccessory, height: 6 } });
    await flushUi();

    expect(root.textContent).toContain('Nothing yet');
    expect(root.querySelector('[data-accessory]')?.textContent).toBe('Switch');
    expect((root.firstElementChild as HTMLElement).style.getPropertyValue('--agent-header-accessory-height'))
      .toBe('6rem');
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

  it('pins at once a question sent while the ended answer\'s run settles, as it goes next', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const onSendMessage = jest.fn();
    // The answer has ended and can no longer be stopped, while its run settles
    const renderSettlingShell = (messages: AgentMessage[]) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages,
      isQueueing: true,
      canStop: false,
      onSendMessage,
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
      renderSettlingShell([MESSAGE, SECOND_MESSAGE]);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
      await flushUi();

      (root.querySelector('[data-fill]') as HTMLButtonElement).click();
      await flushUi();
      (root.querySelector('[data-send]') as HTMLButtonElement).click();
      await flushUi();
      expect(onSendMessage).toHaveBeenCalledWith('Question', undefined);
      // The queued question shows at once, and the list carries it to the top as it does a fresh send
      geometry.scrollHeight = 1100;
      renderSettlingShell([MESSAGE, SECOND_MESSAGE, question]);
      await flushUi();
      await flushUi();

      expect(geometry.scrollTop).toBe(600);
      expect(geometry.positions.some((top) => top > 0 && top < 600)).toBe(true);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('flies a question sent from the field into its bubble in place before the list takes it up', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const answer: AgentMessage = {
      id: 4, text: 'Answer', isOutgoing: false, timestamp: question.timestamp + 1,
    };
    let onTextRevealProgress: NoneToVoidFunction | undefined;
    const renderFlightShell = (messages: AgentMessage[]) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages,
      renderMessage: (message, context) => {
        onTextRevealProgress = context.onTextRevealProgress;
        return (
          <div key={message.id} data-agent-v2-message-id={message.id}>
            {message.isOutgoing ? (
              <div data-question-bubble>
                <span data-agent-question-text>{message.text}</span>
              </div>
            ) : message.text}
          </div>
        );
      },
      renderComposer: (props) => (
        <div>
          <textarea ref={props.inputRef} value={props.inputValue} />
          <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
    });
    const animations: { element: Element; keyframes: Keyframe[]; options: KeyframeAnimationOptions }[] = [];
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value(this: Element, keyframes: Keyframe[], options: KeyframeAnimationOptions) {
        animations.push({ element: this, keyframes, options });
        return { onfinish: undefined, cancel: jest.fn() } as unknown as Animation;
      },
    });
    // The question lands under the answers on screen, and the field's text stands at the bottom
    jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
      const element = this as HTMLElement;
      let rect = {
        left: 0, top: 0, width: 400, height: 800,
      };
      if (element.matches('textarea')) {
        rect = {
          left: 20, top: 740, width: 300, height: 42,
        };
      } else if (element.matches('[data-agent-question-text]')) {
        rect = {
          left: 232, top: 408, width: 120, height: 20,
        };
      } else if (element.matches('[data-question-bubble]')) {
        rect = {
          left: 220, top: 400, width: 160, height: 40,
        };
      } else if (element.matches('span') && element.textContent === 'Question') {
        rect = {
          left: 20, top: 750, width: 60, height: 22,
        };
      } else if (element.querySelector('[data-agent-v2-message-id="2"]')
        && !element.querySelector('[data-agent-v2-message-id="3"]')) {
        rect = {
          left: 0, top: 300, width: 400, height: 80,
        };
      }
      const {
        left, top, width, height,
      } = rect;
      return {
        left, top, width, height, right: left + width, bottom: top + height, x: left, y: top, toJSON: () => undefined,
      };
    });
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      renderFlightShell([MESSAGE, SECOND_MESSAGE]);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
      await flushUi();
      const input = root.querySelector('textarea')!;
      Object.defineProperties(input, {
        clientWidth: { configurable: true, value: 300 },
        clientHeight: { configurable: true, value: 42 },
      });

      (root.querySelector('[data-fill]') as HTMLButtonElement).click();
      await flushUi();
      (root.querySelector('[data-send]') as HTMLButtonElement).click();
      await flushUi(1);
      geometry.scrollHeight = 1100;
      renderFlightShell([MESSAGE, SECOND_MESSAGE, question]);
      await flushUi(4);

      // The field's text flies into the bubble, which stays out of sight meanwhile, its own appearance not playing
      const bubble = root.querySelector<HTMLElement>('[data-question-bubble]')!;
      const fieldText = findFieldTextPicture();
      expect(bubble.style.opacity).toBe('0');
      expect(fieldText?.style.transform).toMatch(/^translate\(/);
      expect(animations.some(({ element }) => element === bubble)).toBe(false);
      // The bubble takes the flight's place as it lands
      await flushUi();
      expect(bubble.style.opacity).toBe('');
      expect(findFieldTextPicture()).toBeUndefined();
      // The list stands still while the question lands, and as its answer comes, and takes it up a moment after
      expect(geometry.scrollTop).toBe(0);
      renderFlightShell([MESSAGE, SECOND_MESSAGE, question, answer]);
      await flushUi();
      await flushUi();
      await flushUi();
      expect(geometry.scrollTop).toBe(600);

      // The answer came into view as the list took the question up, so a later change under the list, as the field
      // growing, leaves the list where it is
      geometry.scrollTop = 300;
      onTextRevealProgress!();
      await flushUi();
      expect(geometry.scrollTop).toBe(300);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('keeps the list off its end as the field shrinks back before the list has placed a sent question', async () => {
    const onComposerHeightChange = jest.fn();
    let onHeightChange: ((height: number) => void) | undefined;
    renderShell({
      messages: [MESSAGE, SECOND_MESSAGE],
      onComposerHeightChange,
      renderComposer: (props) => {
        onHeightChange = props.onHeightChange;
        return (
          <div>
            <textarea ref={props.inputRef} value={props.inputValue} />
            <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
            <button type="button" data-send onClick={props.onSend}>Send</button>
          </div>
        );
      },
    });
    await flushUi();
    (root.querySelector('[data-fill]') as HTMLButtonElement).click();
    await flushUi();
    onHeightChange!(104);
    expect(onComposerHeightChange.mock.lastCall![1].getIsAtBottom()).toBe(true);

    // On a slow device the field shrinks back before the question reaches the list
    (root.querySelector('[data-send]') as HTMLButtonElement).click();
    await flushUi(1);
    onHeightChange!(44);

    expect(onComposerHeightChange.mock.lastCall![1].getIsAtBottom()).toBe(false);
  });

  it('does not fly a question with secret words out of the field, as its bubble shows it without them', async () => {
    const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
    const onSendMessage = jest.fn();
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      renderShell({
        animationLevel: ANIMATION_LEVEL_MAX,
        messages: [MESSAGE, SECOND_MESSAGE],
        onSendMessage,
        renderComposer: (props) => (
          <div>
            <textarea ref={props.inputRef} value={props.inputValue} />
            <button type="button" data-fill onClick={() => props.onInput(phrase)}>Fill</button>
            <button type="button" data-send onClick={props.onSend}>Send</button>
          </div>
        ),
      });
      await flushUi();
      Object.defineProperties(root.querySelector('textarea')!, {
        clientWidth: { configurable: true, value: 300 },
        clientHeight: { configurable: true, value: 42 },
      });

      (root.querySelector('[data-fill]') as HTMLButtonElement).click();
      await flushUi();
      (root.querySelector('[data-send]') as HTMLButtonElement).click();
      await flushUi(1);

      expect(onSendMessage).toHaveBeenCalledWith(phrase, undefined);
      expect(Array.from(document.querySelectorAll('span')).some((span) => span.textContent === phrase)).toBe(false);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  for (const isMessenger of [false, true]) {
    const name = isMessenger
      ? 'flies a question sent from the field into its bubble at the end of a list that scrolls as a messenger'
      : 'flies a question sent from the field into its bubble as the list takes it up from under the field';
    it(name, async () => {
      const question: AgentMessage = {
        id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
      };
      const justAddedById: Record<number, boolean> = {};
      const renderFlightShell = (messages: AgentMessage[]) => renderShell({
        animationLevel: ANIMATION_LEVEL_MAX,
        messages,
        noLiveTail: isMessenger,
        renderMessage: (message, context) => {
          justAddedById[message.id] ??= context.isJustAdded;
          return (
            <div key={message.id} data-agent-v2-message-id={message.id}>
              {message.isOutgoing ? (
                <div data-question-bubble>
                  <span data-agent-question-text>{message.text}</span>
                </div>
              ) : message.text}
            </div>
          );
        },
        renderComposer: (props) => (
          <div>
            <textarea ref={props.inputRef} value={props.inputValue} />
            <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
            <button type="button" data-send onClick={props.onSend}>Send</button>
          </div>
        ),
      });
      // The question lands under the field, out of sight, and the field's text stands at the bottom
      jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
        const element = this as HTMLElement;
        let rect = {
          left: 0, top: 0, width: 400, height: 800,
        };
        if (element.matches('textarea')) {
          rect = {
            left: 20, top: 740, width: 300, height: 42,
          };
        } else if (element.matches('[data-agent-question-text]')) {
          rect = {
            left: 232, top: 908, width: 120, height: 20,
          };
        } else if (element.matches('[data-question-bubble]')) {
          rect = {
            left: 220, top: 900, width: 160, height: 40,
          };
        } else if (element.matches('span') && element.textContent === 'Question') {
          rect = {
            left: 20, top: 750, width: 60, height: 22,
          };
        }
        const {
          left, top, width, height,
        } = rect;
        return {
          left, top, width, height, right: left + width, bottom: top + height, x: left, y: top, toJSON: () => undefined,
        };
      });
      const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
      Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

      try {
        renderFlightShell([MESSAGE, SECOND_MESSAGE]);
        const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
        const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
        await flushUi();
        const input = root.querySelector('textarea')!;
        Object.defineProperties(input, {
          clientWidth: { configurable: true, value: 300 },
          clientHeight: { configurable: true, value: 42 },
        });

        (root.querySelector('[data-fill]') as HTMLButtonElement).click();
        await flushUi();
        (root.querySelector('[data-send]') as HTMLButtonElement).click();
        await flushUi(1);
        geometry.scrollHeight = isMessenger ? 600 : 1100;
        renderFlightShell([MESSAGE, SECOND_MESSAGE, question]);
        await flushUi(4);

        // The field's text flies into the bubble as the list brings it up, the bubble out of sight meanwhile and its
        // own appearance not playing
        const bubble = root.querySelector<HTMLElement>('[data-question-bubble]')!;
        expect(justAddedById[question.id]).toBe(false);
        expect(bubble.style.opacity).toBe('0');
        expect(findFieldTextPicture()?.style.transform).toMatch(/^translate\(/);

        await flushUi();
        expect(bubble.style.opacity).toBe('');
        expect(findFieldTextPicture()).toBeUndefined();
        await flushUi();
        expect(geometry.scrollTop).toBe(isMessenger ? 100 : 600);
      } finally {
        restoreProperty(document, 'hidden', originalHidden);
      }
    });
  }

  it('flies a question queued behind the answer from the field into its bubble at the end of the list', async () => {
    const question: AgentMessage = { ...MESSAGE, text: 'Asked question', isOutgoing: true };
    const answer: AgentMessage = { ...SECOND_MESSAGE, text: 'Answer being written', isStreaming: true };
    const queued: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const onSendMessage = jest.fn();
    const justAddedById: Record<number, boolean> = {};
    const session = { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
    const renderQueueShell = (messages: AgentMessage[], queuedMessageCount: number) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages,
      queuedMessageCount,
      isRunActive: true,
      isQueueing: true,
      canStop: true,
      onSendMessage,
      renderMessage: (message, context) => {
        justAddedById[message.id] ??= context.isJustAdded;
        return (
          <div key={message.id} data-agent-v2-message-id={message.id}>
            {message.isOutgoing ? (
              <div data-question-bubble>
                <span data-agent-question-text>{message.text}</span>
              </div>
            ) : message.text}
          </div>
        );
      },
      renderComposer: (props) => (
        <div>
          <textarea ref={props.inputRef} value={props.inputValue} />
          <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
      session,
    });
    // The queued question shows under the answer, above the field, and the field's text stands at the bottom
    jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
      const element = this as HTMLElement;
      let rect = {
        left: 0, top: 0, width: 400, height: 800,
      };
      if (element.matches('textarea')) {
        rect = {
          left: 20, top: 740, width: 300, height: 42,
        };
      } else if (element.matches('[data-agent-question-text]')) {
        rect = {
          left: 232, top: 608, width: 120, height: 20,
        };
      } else if (element.matches('[data-question-bubble]')) {
        rect = {
          left: 220, top: 600, width: 160, height: 40,
        };
      } else if (element.matches('span') && element.textContent === 'Question') {
        rect = {
          left: 20, top: 750, width: 60, height: 22,
        };
      }
      const {
        left, top, width, height,
      } = rect;
      return {
        left, top, width, height, right: left + width, bottom: top + height, x: left, y: top, toJSON: () => undefined,
      };
    });
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      renderQueueShell([question, answer], 0);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 1100, clientHeight: 500 });
      await flushUi();
      const input = root.querySelector('textarea')!;
      Object.defineProperties(input, {
        clientWidth: { configurable: true, value: 300 },
        clientHeight: { configurable: true, value: 42 },
      });
      const pinnedScrollTop = geometry.scrollTop;

      (root.querySelector('[data-fill]') as HTMLButtonElement).click();
      await flushUi();
      (root.querySelector('[data-send]') as HTMLButtonElement).click();
      await flushUi(1);
      expect(onSendMessage).toHaveBeenCalledWith('Question', undefined);
      renderQueueShell([question, answer, queued], 1);
      await flushUi(4);

      // The field's text flies into the bubble, which stays out of sight meanwhile, its own appearance not playing
      const bubble = root.querySelector<HTMLElement>('[data-agent-v2-message-id="3"] [data-question-bubble]')!;
      expect(justAddedById[queued.id]).toBe(false);
      expect(bubble.style.opacity).toBe('0');
      expect(findFieldTextPicture()?.style.transform).toMatch(/^translate\(/);

      await flushUi();
      expect(bubble.style.opacity).toBe('');
      expect(findFieldTextPicture()).toBeUndefined();
      // The list stays at the question being answered, which the queued one waits under
      expect(geometry.scrollTop).toBe(pinnedScrollTop);
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
    // The question's turn ends with its answer, and its reserve 500 px below the turn's top
    Object.defineProperty(liveTail, 'getBoundingClientRect', {
      configurable: true,
      value: () => ({ top: 700, bottom: 900 }),
    });
    Object.defineProperty(liveTail.querySelector('[data-agent-live-tail-reserve]')!, 'getBoundingClientRect', {
      configurable: true,
      value: () => ({ top: 716, bottom: 1200 }),
    });
    await flushUi();

    // At the end of the reserve rather than of the list, which ends 200 px further down
    expect(geometry.scrollTop).toBe(700);

    geometry.scrollHeight = 1600;
    renderPinnedShell([MESSAGE, SECOND_MESSAGE, question, { ...answer, text: 'Longer answer' }]);
    await flushUi();

    expect(geometry.scrollTop).toBe(700);
  });

  it('pins the question a new chat opens with under the header, its answer coming under it', async () => {
    const question: AgentMessage = { id: 1, text: 'Question', isOutgoing: true, timestamp: MESSAGE.timestamp };
    const answer: AgentMessage = { id: 2, text: 'Answer', isOutgoing: false, timestamp: question.timestamp + 1 };
    // The chat tells of its opening question until the question has been sent
    const renderNewChat = (messages: AgentMessage[]) => renderShell({
      messages,
      hasOpeningQuestion: messages.length === 1,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
    });

    renderNewChat([question]);
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 700, clientHeight: 500 });
    const liveTail = root.querySelector('[data-message-id="1"]')!.parentElement!;
    // The question's turn starts 100 px down the list and holds the reserve for its answer, 500 px from its top
    Object.defineProperties(liveTail, {
      offsetHeight: { configurable: true, value: 500 },
      getBoundingClientRect: {
        configurable: true,
        value: () => ({ top: 100 - geometry.scrollTop, bottom: 600 - geometry.scrollTop }),
      },
    });
    Object.defineProperty(liveTail.lastElementChild!, 'getBoundingClientRect', {
      configurable: true,
      value: () => ({ bottom: 200 - geometry.scrollTop }),
    });
    await flushUi();

    // At the end of the reserve rather than of the list, which ends 100 px further down
    expect(geometry.scrollTop).toBe(100);

    geometry.scrollHeight = 900;
    renderNewChat([question, answer]);
    await flushUi();

    expect(geometry.scrollTop).toBe(100);
  });

  it('puts a sent message at the end without a reserve and follows new messages only from the end', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const reply: AgentMessage = {
      id: 4, text: 'Reply', isOutgoing: false, timestamp: question.timestamp + 1,
    };
    const laterReply: AgentMessage = { ...reply, id: 5, timestamp: reply.timestamp + 1 };
    const renderMessengerShell = (messages: AgentMessage[]) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages,
      noLiveTail: true,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
      renderComposer: (props) => (
        <div>
          <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
    });
    const findScrollButton = () => root.querySelector('button[aria-label="Scroll To Bottom"]');

    renderMessengerShell([MESSAGE, SECOND_MESSAGE]);
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
    await flushUi();

    (root.querySelector('[data-fill]') as HTMLButtonElement).click();
    await flushUi();
    (root.querySelector('[data-send]') as HTMLButtonElement).click();
    await flushUi();
    geometry.scrollHeight = 600;
    renderMessengerShell([MESSAGE, SECOND_MESSAGE, question]);
    await flushUi();

    expect(geometry.scrollTop).toBe(100);

    geometry.scrollHeight = 800;
    renderMessengerShell([MESSAGE, SECOND_MESSAGE, question, reply]);
    await flushUi();

    expect(geometry.scrollTop).toBe(300);

    // The event of the list's own scroll comes first
    messagesElement.dispatchEvent(new Event('scroll'));
    messagesElement.dispatchEvent(new WheelEvent('wheel'));
    messagesElement.scrollTop = 100;
    messagesElement.dispatchEvent(new Event('scroll'));
    await flushUi();
    geometry.scrollHeight = 1000;
    renderMessengerShell([MESSAGE, SECOND_MESSAGE, question, reply, laterReply]);
    await flushUi();

    expect(geometry.scrollTop).toBe(100);
    expect(findScrollButton()).not.toBeNull();
  });

  it('keeps a question pinned before messenger scrolling in place and drops its reserve on the next send', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const answer: AgentMessage = {
      id: 4, text: 'Answer', isOutgoing: false, timestamp: question.timestamp + 1,
    };
    const reply: AgentMessage = { ...answer, id: 5, timestamp: answer.timestamp + 1 };
    const nextQuestion: AgentMessage = { ...question, id: 6, timestamp: reply.timestamp + 1 };
    const renderTransitionShell = (messages: AgentMessage[], noLiveTail?: boolean) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages,
      noLiveTail,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
      renderComposer: (props) => (
        <div>
          <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
          <button type="button" data-send onClick={props.onSend}>Send</button>
        </div>
      ),
    });
    const send = async () => {
      (root.querySelector('[data-fill]') as HTMLButtonElement).click();
      await flushUi();
      (root.querySelector('[data-send]') as HTMLButtonElement).click();
      await flushUi();
    };

    // Animations are disabled for hidden documents, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      renderTransitionShell([MESSAGE, SECOND_MESSAGE]);
      const geometry = mockScrollGeometry(
        root.querySelector('.custom-scroll') as HTMLDivElement,
        { scrollHeight: 500, clientHeight: 500 },
      );
      await flushUi();

      await send();
      geometry.scrollHeight = 1100;
      renderTransitionShell([MESSAGE, SECOND_MESSAGE, question]);
      await flushUi();
      await flushUi();
      // The answer grows into the reserve
      renderTransitionShell([MESSAGE, SECOND_MESSAGE, question, answer]);
      await flushUi();

      expect(geometry.scrollTop).toBe(600);

      renderTransitionShell([MESSAGE, SECOND_MESSAGE, question, answer], true);
      await flushUi();

      expect(geometry.scrollTop).toBe(600);

      geometry.scrollHeight = 1500;
      renderTransitionShell([MESSAGE, SECOND_MESSAGE, question, answer, reply], true);
      await flushUi();

      expect(geometry.scrollTop).toBe(1000);

      // The reserve goes with the question pinned before
      expect(root.querySelector('[data-agent-live-tail-reserve]')).not.toBeNull();
      await send();

      expect(root.querySelector('[data-agent-live-tail-reserve]')).toBeNull();

      geometry.scrollHeight = 1100;
      renderTransitionShell([MESSAGE, SECOND_MESSAGE, question, answer, reply, nextQuestion], true);
      await flushUi();

      expect(geometry.scrollTop).toBe(600);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('keeps a pinned question in place as an answer taller than its reserve comes with the switch', async () => {
    const question: AgentMessage = {
      id: 3, text: 'Question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const answer: AgentMessage = {
      id: 4, text: 'Long answer', isOutgoing: false, timestamp: question.timestamp + 1,
    };
    const supportLine: AgentMessage = {
      ...answer, id: 5, text: 'Support requested', timestamp: answer.timestamp + 1,
    };
    const reply: AgentMessage = { ...answer, id: 6, text: 'Reply', timestamp: supportLine.timestamp + 1 };
    const renderSwitchShell = (messages: AgentMessage[], noLiveTail?: boolean) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages,
      noLiveTail,
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
      renderSwitchShell([MESSAGE, SECOND_MESSAGE]);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
      await flushUi();

      (root.querySelector('[data-fill]') as HTMLButtonElement).click();
      await flushUi();
      (root.querySelector('[data-send]') as HTMLButtonElement).click();
      await flushUi();
      geometry.scrollHeight = 1100;
      renderSwitchShell([MESSAGE, SECOND_MESSAGE, question]);
      await flushUi();
      await flushUi();

      expect(geometry.scrollTop).toBe(600);

      // One update hands the chat to support and brings the answer with the support line, taller than the reserve
      geometry.scrollHeight = 1800;
      renderSwitchShell([MESSAGE, SECOND_MESSAGE, question, answer, supportLine], true);
      await flushUi();

      expect(geometry.scrollTop).toBe(600);

      // The event of the list's own scroll comes first
      messagesElement.dispatchEvent(new Event('scroll'));
      messagesElement.scrollTop = 1300;
      messagesElement.dispatchEvent(new Event('scroll'));
      await flushUi();
      geometry.scrollHeight = 1900;
      renderSwitchShell([MESSAGE, SECOND_MESSAGE, question, answer, supportLine, reply], true);
      await flushUi();

      expect(geometry.scrollTop).toBe(1400);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('opens at its end rather than at a question pinned in its last mount when it scrolls as a messenger', async () => {
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
      noLiveTail: true,
      renderMessage: (message) => <div key={message.id} data-message-id={message.id}>{message.text}</div>,
      session,
    });

    renderPinnedShell([], false);
    await flushUi();
    const geometry = mockScrollGeometry(
      root.querySelector('.custom-scroll') as HTMLDivElement,
      { scrollHeight: 1400, clientHeight: 500 },
    );

    renderPinnedShell([MESSAGE, SECOND_MESSAGE, question, answer]);
    const liveTail = root.querySelector('[data-message-id="3"]')!.parentElement!;
    Object.defineProperty(liveTail, 'getBoundingClientRect', {
      configurable: true,
      value: () => ({ top: 700, bottom: 1200 }),
    });
    await flushUi();

    expect(geometry.scrollTop).toBe(900);

    geometry.scrollHeight = 1600;
    renderPinnedShell([MESSAGE, SECOND_MESSAGE, question, { ...answer, text: 'Longer answer' }]);
    await flushUi();

    expect(geometry.scrollTop).toBe(1100);
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
    const layer = getSnapEffectLayer();
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

    const layer = getSnapEffectLayer();
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

  it('shows the activity of the answer being produced under its question, above the questions that wait', async () => {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const waiting: AgentMessage = { ...SECOND_MESSAGE, text: 'Waiting question', isOutgoing: true };
    const activity = <div key="activity" data-agent-run-activity>Analyzing</div>;
    const renderMessage: AgentConversation['renderMessage'] = (message) => (
      <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
    );
    renderShell({
      messages: [question, waiting], queuedMessageCount: 1, isRunActive: true, runActivity: activity, renderMessage,
    });
    await flushUi();

    const activityRow = root.querySelector<HTMLElement>('[data-agent-run-activity]')!;
    const questionRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="1"]')!;
    const waitingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="2"]')!;
    expect(activityRow.parentElement).toBe(questionRow.parentElement);
    expect(activityRow.previousElementSibling).toBe(questionRow);
    expect(waitingRow.parentElement).not.toBe(questionRow.parentElement);

    // Once the waiting question goes, the activity follows it
    renderShell({
      messages: [question, waiting], isRunActive: true, runActivity: activity, renderMessage,
    });
    await flushUi();
    expect(root.querySelector<HTMLElement>('[data-agent-run-activity]')!.previousElementSibling).toBe(waitingRow);
  });

  it('pins a queued question as it goes, while another still waits after it', async () => {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const going: AgentMessage = {
      ...SECOND_MESSAGE, text: 'Going question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const waiting: AgentMessage = {
      ...SECOND_MESSAGE, id: 3, text: 'Waiting question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 2,
    };
    // The question being answered is pinned, as after its send
    const session = { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
    const renderQueueShell = (queuedMessageCount: number, sentQueuedMessage?: { id: number }) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages: [question, going, waiting],
      queuedMessageCount,
      sentQueuedMessage,
      isRunActive: true,
      isQueueing: true,
      canStop: true,
      session,
    });
    // Animations are disabled for hidden documents, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      renderQueueShell(2);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
      await flushUi();

      // The question that goes is carried to the top as a fresh send, whatever waits after it
      geometry.scrollHeight = 1100;
      renderQueueShell(1, { id: going.id });
      await flushUi();
      await flushUi();

      expect(geometry.scrollTop).toBe(600);
      expect(geometry.positions.some((top) => top > 0 && top < 600)).toBe(true);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('pins a queued question as it goes from the end of the list', async () => {
    // Animations are disabled for hidden documents, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      // The list is held at its end, with no question pinned and no scroll button
      const render = renderGoingQueue();
      render(2);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
      await flushUi();
      expect(findScrollToBottomButton()).toBeNull();

      // The question that goes is pinned as a fresh send, with its reserve under it
      const sentQueuedMessage = { id: 2 };
      geometry.scrollHeight = 1100;
      render(1, sentQueuedMessage);
      await flushUi();
      await flushUi();

      expect(geometry.scrollTop).toBe(600);
      expect(root.querySelector('[data-agent-live-tail-reserve]')!.parentElement)
        .toBe(root.querySelector('[data-agent-v2-message-id="2"]')!.parentElement);

      // Its answer grows into the reserve without the list following it
      geometry.scrollHeight = 1400;
      render(1, sentQueuedMessage, true);
      await flushUi();

      expect(geometry.scrollTop).toBe(600);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('pins a queued question as it goes after a small scroll up that leaves the last row in sight', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      // The question being answered is pinned at the list's end, with the reserve under the questions that wait
      const render = renderGoingQueue({ initial: { draft: '', isQuestionPinned: true }, save: jest.fn() });
      render(2);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 1100, clientHeight: 500 });
      await flushUi();
      expect(geometry.scrollTop).toBe(600);

      // The user scrolls up 100 px, farther than the button's distance from the list's end, while the question that
      // waits last stays in sight, so no scroll button shows
      mockRect(messagesElement, { top: 0, bottom: 500 });
      mockRect(root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!, { top: 300, bottom: 340 });
      messagesElement.dispatchEvent(new WheelEvent('wheel'));
      messagesElement.scrollTop = 500;
      messagesElement.dispatchEvent(new Event('scroll'));
      await flushUi();
      expect(findScrollToBottomButton()).toBeNull();

      // The question that goes is pinned as a fresh send, with the top space and the reserve
      geometry.scrollHeight = 1200;
      render(1, { id: 2 });
      await flushUi();
      await flushUi();

      const goingTurn = root.querySelector('[data-agent-v2-message-id="2"]')!.parentElement;
      expect(geometry.scrollTop).toBe(700);
      expect(root.querySelector('[data-agent-live-tail-reserve]')!.parentElement).toBe(goingTurn);
      expect(findLiveTailSpaceTurn()).toBe(goingTurn);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('leaves a list scrolled up where it is as a queued question goes, its scroll button taking it down', async () => {
    // Animations are disabled for hidden documents, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      // The question being answered is pinned, as after its send
      const render = renderGoingQueue({ initial: { draft: '', isQuestionPinned: true }, save: jest.fn() });
      render(2);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 1100, clientHeight: 500 });
      await flushUi();

      // The user scrolls up to read the pinned question's turn, which takes the question that waits last out of sight,
      // and the scroll button shows
      const pinnedTurn = root.querySelector<HTMLElement>('[data-agent-v2-message-id="1"]')!.parentElement!;
      const goingTurn = root.querySelector<HTMLElement>('[data-agent-v2-message-id="2"]')!.parentElement!;
      mockRect(messagesElement, { top: 0, bottom: 500 });
      mockRect(pinnedTurn, { top: 100, bottom: 250 });
      mockRect(goingTurn, { top: 300, bottom: 400 });
      mockRect(root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!, { top: 560, bottom: 600 });
      messagesElement.dispatchEvent(new WheelEvent('wheel'));
      messagesElement.scrollTop = 200;
      messagesElement.dispatchEvent(new Event('scroll'));
      await flushUi();
      expect(findScrollToBottomButton()).not.toBeNull();
      expect(findLiveTailSpaceTurn()).toBe(pinnedTurn);

      // The question goes with its reserve, and its answer comes under it, while the list stays where the user took it
      // and the pinned question's turn keeps its top space
      const writeCount = geometry.positions.length;
      const sentQueuedMessage = { id: 2 };
      geometry.scrollHeight = 1200;
      render(1, sentQueuedMessage);
      expect(findLiveTailSpaceTurn()).toBe(pinnedTurn);
      await flushUi();
      geometry.scrollHeight = 1500;
      render(1, sentQueuedMessage, true);
      await flushUi();

      expect(geometry.positions.slice(writeCount).every((top) => top === 200)).toBe(true);
      expect(geometry.scrollTop).toBe(200);
      expect(root.querySelector('[data-agent-live-tail-reserve]')!.parentElement).toBe(goingTurn);
      expect(findLiveTailSpaceTurn()).toBe(pinnedTurn);
      expect(findScrollToBottomButton()).not.toBeNull();

      // The space goes to the question that went once the user has scrolled the rows it moves out of sight
      mockRect(goingTurn, { top: -10, bottom: 90 });
      messagesElement.scrollTop = 410;
      messagesElement.dispatchEvent(new Event('scroll'));
      await flushUi();

      expect(findLiveTailSpaceTurn()).toBe(goingTurn);
      expect(geometry.scrollTop).toBe(410);

      // The scroll button takes the user down to the end, where the reserve holds the question that went
      findScrollToBottomButton()!.click();
      await flushUi(60);

      expect(geometry.scrollTop).toBe(1000);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('leaves the user reading a pinned question whose answer runs past the screen as the next one goes', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      const render = renderGoingQueue({ initial: { draft: '', isQuestionPinned: true }, save: jest.fn() });
      render(2);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 1100, clientHeight: 500 });
      // The pinned question starts 200 px into the list's content, and its answer runs past the screen with the
      // question that waits under it
      const liveTail = root.querySelector('[data-agent-v2-message-id="1"]')!.parentElement!;
      Object.defineProperty(liveTail, 'getBoundingClientRect', {
        configurable: true,
        value: () => ({ top: -400, bottom: 100 }),
      });
      mockRect(messagesElement, { top: 0, bottom: 500 });
      mockRect(root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!, { top: 700, bottom: 740 });
      await flushUi();

      expect(geometry.scrollTop).toBe(200);
      expect(findScrollToBottomButton()).not.toBeNull();

      // The question goes, and its answer comes under it, while the user keeps reading where they were
      const writeCount = geometry.positions.length;
      const sentQueuedMessage = { id: 2 };
      geometry.scrollHeight = 1200;
      render(1, sentQueuedMessage);
      await flushUi();
      geometry.scrollHeight = 1500;
      render(1, sentQueuedMessage, true);
      await flushUi();

      expect(geometry.positions.slice(writeCount).every((top) => top === 200)).toBe(true);
      expect(geometry.scrollTop).toBe(200);
      expect(findScrollToBottomButton()).not.toBeNull();
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('gives the top space to a queued question pinned as it goes in the same frame', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      // The question being answered is pinned, with no scroll button
      const render = renderGoingQueue({ initial: { draft: '', isQuestionPinned: true }, save: jest.fn() });
      render(2);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
      await flushUi();
      const goingTurn = root.querySelector('[data-agent-v2-message-id="2"]')!.parentElement;
      expect(findLiveTailSpaceTurn()).toBe(root.querySelector('[data-agent-v2-message-id="1"]')!.parentElement);

      geometry.scrollHeight = 1100;
      render(1, { id: 2 });
      expect(findLiveTailSpaceTurn()).toBe(goingTurn);
      await flushUi();
      await flushUi();

      expect(geometry.scrollTop).toBe(600);
      expect(findLiveTailSpaceTurn()).toBe(goingTurn);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it.each(['the first question of a chat', 'a question pinned before the chat mounted again'] as const)(
    'shows the scroll button as the answer to %s runs past the screen, keeping the reader as a queued one goes',
    async (pinnedQuestion) => {
      const isFirstQuestion = pinnedQuestion === 'the first question of a chat';
      const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
      const answer: AgentMessage = { ...SECOND_MESSAGE, text: 'Answer' };
      const longAnswer: AgentMessage = { ...answer, text: 'Long answer' };
      const queued: AgentMessage = {
        ...SECOND_MESSAGE, id: 3, text: 'Queued question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
      };
      const session = isFirstQuestion ? undefined : { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
      let reportRevealProgress: NoneToVoidFunction | undefined;
      const render = (messages: AgentMessage[], queuedMessageCount = 0, sentQueuedMessage?: { id: number }) => {
        const isRunning = messages.length > 0;
        renderShell({
          animationLevel: ANIMATION_LEVEL_MAX,
          messages,
          queuedMessageCount,
          sentQueuedMessage,
          isRunActive: isRunning,
          isQueueing: isRunning,
          canStop: isRunning,
          renderMessage: (message, context) => {
            reportRevealProgress = context.onTextRevealProgress;
            return <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>;
          },
          renderComposer: (props) => (
            <div>
              <button type="button" data-fill onClick={() => props.onInput('Question')}>Fill</button>
              <button type="button" data-send onClick={props.onSend}>Send</button>
            </div>
          ),
          session,
        });
      };
      const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
      Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

      try {
        render(isFirstQuestion ? [] : [question, answer]);
        const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
        const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 500, clientHeight: 500 });
        await flushUi();

        if (isFirstQuestion) {
          // The question is pinned at the top, where the list already stands at its end
          (root.querySelector('[data-fill]') as HTMLButtonElement).click();
          await flushUi();
          (root.querySelector('[data-send]') as HTMLButtonElement).click();
          await flushUi();
          render([question]);
          await flushUi();
          render([question, answer]);
          await flushUi();
          reportRevealProgress!();
          await flushUi();
        }
        expect(geometry.scrollTop).toBe(0);
        expect(findScrollToBottomButton()).toBeNull();

        // The answer runs 400 px past the screen, and the scroll button shows
        geometry.scrollHeight = 900;
        render([question, longAnswer]);
        mockRect(messagesElement, { top: 0, bottom: 500 });
        const answerRow = root.querySelector<HTMLElement>(`[data-agent-v2-message-id="${answer.id}"]`)!;
        mockRect(answerRow, { top: 100, bottom: 900 });
        await flushUi();
        reportRevealProgress!();
        await flushUi();
        expect(findScrollToBottomButton()).not.toBeNull();

        // A question queued meanwhile goes, and the list stays where the user reads
        render([question, longAnswer, queued], 1);
        await flushUi();
        const writeCount = geometry.positions.length;
        geometry.scrollHeight = 1000;
        render([question, longAnswer, queued], 0, { id: queued.id });
        await flushUi();
        await flushUi();

        expect(geometry.positions.slice(writeCount).every((top) => top === 0)).toBe(true);
        expect(geometry.scrollTop).toBe(0);
        expect(findScrollToBottomButton()).not.toBeNull();
      } finally {
        restoreProperty(document, 'hidden', originalHidden);
      }
    },
  );

  it('glides the questions that wait up into the place of a stopped activity, and down from the next', async () => {
    // Motion runs only while the page is visible, and jsdom reports the document as hidden
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      const tops = mockListRects({
        1: 50, activity: 100, 3: 150, 4: 200, end: 240,
      });
      const { render, onStop } = await stopOverQueuedQuestions(ANIMATION_LEVEL_MAX, 2);
      expect(onStop).toHaveBeenCalledTimes(1);
      const questionRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="1"]')!;
      const goingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="3"]')!;
      const waitingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!;

      // The stopped activity goes, and the questions that wait start from where they stood, 50 px lower
      render({ queuedMessageCount: 2 });
      Object.assign(tops, { 3: 100, 4: 150, end: 190 });
      await flushFrame();
      expect(getTranslateY(goingRow)).toBe(50);
      expect(getTranslateY(waitingRow)).toBe(50);
      expect(getTranslateY(questionRow)).toBe(0);

      // They ease into their places together on Telegram's list curve, as on iOS
      const offsets: number[] = [];
      for (let frame = 0; frame < 10; frame++) {
        await flushFrame();
        offsets.push(getTranslateY(goingRow));
        expect(getTranslateY(waitingRow)).toBe(offsets[frame]);
      }
      offsets.forEach((offset, index) => {
        expect(offset).toBeGreaterThan(0);
        expect(offset).toBeLessThan(index ? offsets[index - 1] : 50);
      });
      await flushUi(40);
      expect(getTranslateY(goingRow)).toBe(0);
      expect(goingRow.style.translate || '').toBe('');

      // The next question goes, and the activity that comes in under it moves the question still waiting down
      Object.assign(tops, { activity: 150, 4: 200, end: 240 });
      render({ queuedMessageCount: 1, sentQueuedMessage: { id: 3 }, hasActivity: true });
      await flushFrame();
      const activityRow = root.querySelector<HTMLElement>('[data-agent-run-activity]')!;
      expect(activityRow.previousElementSibling).toBe(goingRow);
      expect(getTranslateY(waitingRow)).toBe(-50);
      expect(getTranslateY(activityRow)).toBe(0);
      expect(getTranslateY(goingRow)).toBe(0);
      expect(getTranslateY(questionRow)).toBe(0);

      await flushUi(45);
      expect(getTranslateY(waitingRow)).toBe(0);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('glides the questions that wait from where a list held at its end showed them', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      const tops = mockListRects({
        1: 50, activity: 100, 3: 150, 4: 200, end: 280,
      });
      const { render } = await stopOverQueuedQuestions(ANIMATION_LEVEL_MAX, 2, true);
      const waitingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!;

      // The content under the questions gets 40 px shorter as the list renders, and the list, held at its end, shows
      // them 40 px lower, so they start 40 px above their places
      tops.end = 240;
      render({ queuedMessageCount: 2, hasActivity: true });
      await flushFrame();
      expect(getTranslateY(waitingRow)).toBe(-40);

      await flushUi(45);
      expect(getTranslateY(waitingRow)).toBe(0);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('lets a growing answer push the questions that wait, and glides them as the next activity comes', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
      const answer: AgentMessage = {
        ...MESSAGE, id: 2, text: 'Answer', isStreaming: true, timestamp: MESSAGE.timestamp + 1,
      };
      const going: AgentMessage = {
        ...MESSAGE, id: 3, text: 'Going question', isOutgoing: true, timestamp: MESSAGE.timestamp + 2,
      };
      const waiting: AgentMessage = {
        ...MESSAGE, id: 4, text: 'Waiting question', isOutgoing: true, timestamp: MESSAGE.timestamp + 3,
      };
      const tops = mockListRects({
        1: 50, 2: 100, 3: 150, 4: 200, end: 240,
      });
      const session = { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
      let reportRevealProgress: NoneToVoidFunction | undefined;
      const renderChat = (
        shownAnswer: AgentMessage, queuedMessageCount: number, sentQueuedMessage?: { id: number },
      ) => (
        renderShell({
          animationLevel: ANIMATION_LEVEL_MAX,
          messages: [question, shownAnswer, going, waiting],
          queuedMessageCount,
          sentQueuedMessage,
          isRunActive: true,
          isQueueing: true,
          canStop: true,
          runActivity: sentQueuedMessage ? <div key="activity" data-agent-run-activity>Analyzing</div> : undefined,
          renderMessage: (message, context) => {
            reportRevealProgress = context.onTextRevealProgress;
            return <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>;
          },
          session,
        })
      );
      renderChat(answer, 2);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      mockScrollGeometry(messagesElement, { scrollHeight: 600, clientHeight: 600 });
      await flushUi();
      const goingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="3"]')!;
      const waitingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!;

      // The answer's text pushes them down as it comes, as it does any message
      Object.assign(tops, { 3: 180, 4: 230, end: 270 });
      reportRevealProgress!();
      await flushFrame();
      expect(getTranslateY(goingRow)).toBe(0);
      expect(getTranslateY(waitingRow)).toBe(0);

      // The answer ends and the next question goes, and the activity that comes in under it moves the question still
      // waiting down
      Object.assign(tops, { activity: 220, 4: 270, end: 310 });
      renderChat({ ...answer, isStreaming: undefined }, 1, { id: going.id });
      await flushFrame();
      expect(getTranslateY(waitingRow)).toBe(-40);
      expect(getTranslateY(goingRow)).toBe(0);

      await flushUi(45);
      expect(getTranslateY(waitingRow)).toBe(0);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('lets the questions that wait ride with the list when the whole list moves', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
      const going: AgentMessage = {
        ...MESSAGE, id: 3, text: 'Going question', isOutgoing: true, timestamp: MESSAGE.timestamp + 2,
      };
      const waiting: AgentMessage = {
        ...MESSAGE, id: 4, text: 'Waiting question', isOutgoing: true, timestamp: MESSAGE.timestamp + 3,
      };
      const tops = mockListRects({
        1: 50, activity: 100, 3: 150, 4: 200, end: 240,
      });
      const session = { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
      const render = () => renderShell({
        animationLevel: ANIMATION_LEVEL_MAX,
        messages: [question, going, waiting],
        queuedMessageCount: 2,
        isRunActive: true,
        isQueueing: true,
        canStop: true,
        runActivity: <div key="activity" data-agent-run-activity>Analyzing</div>,
        renderMessage: (message) => <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>,
        session,
      });
      render();
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      mockScrollGeometry(messagesElement, { scrollHeight: 600, clientHeight: 600 });
      await flushUi();
      const goingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="3"]')!;
      const waitingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!;

      // Everything in the list moves 120 px down as it renders, as when the space above the first message grows, and
      // the rows under the answer go along with the rows above them
      tops.shift = 120;
      render();
      await flushFrame();
      await flushFrame();
      expect(getTranslateY(goingRow)).toBe(0);
      expect(getTranslateY(waitingRow)).toBe(0);

      // A row above them that changes still moves them from where they stood
      Object.assign(tops, { 3: 190, 4: 240, end: 280 });
      render();
      await flushFrame();
      expect(getTranslateY(goingRow)).toBe(-40);
      expect(getTranslateY(waitingRow)).toBe(-40);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('rests while the questions that wait stand still, and forgets their places while the list is hidden', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
      const going: AgentMessage = {
        ...MESSAGE, id: 3, text: 'Going question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
      };
      const waiting: AgentMessage = {
        ...MESSAGE, id: 4, text: 'Waiting question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 2,
      };
      const tops = mockListRects({
        1: 50, activity: 100, 3: 150, 4: 200, end: 240,
      });
      const session = { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
      const render = (isActive: boolean) => renderShell({
        isActive,
        animationLevel: ANIMATION_LEVEL_MAX,
        messages: [question, going, waiting],
        queuedMessageCount: 2,
        isRunActive: true,
        isQueueing: true,
        canStop: true,
        runActivity: <div key="activity" data-agent-run-activity>Analyzing</div>,
        renderMessage: (message) => <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>,
        session,
      });
      render(true);
      const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
      mockScrollGeometry(messagesElement, { scrollHeight: 600, clientHeight: 600 });
      await flushUi();
      const goingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="3"]')!;
      const waitingRow = root.querySelector<HTMLElement>('[data-agent-v2-message-id="4"]')!;

      // While nothing moves, the list measures nothing
      const { calls: rectReads } = jest.mocked(Element.prototype.getBoundingClientRect).mock;
      const settledReadCount = rectReads.length;
      await flushUi();
      expect(rectReads.length).toBe(settledReadCount);

      // Another screen of the app takes the Agent's place and keeps the list without a box
      tops.hidden = 1;
      Object.defineProperty(messagesElement, 'clientHeight', { configurable: true, value: 0 });
      render(false);
      await flushUi();

      // The Agent shows again, and the questions that wait stand where they are
      delete tops.hidden;
      Object.defineProperty(messagesElement, 'clientHeight', { configurable: true, value: 600 });
      render(true);
      await flushFrame();
      expect(getTranslateY(goingRow)).toBe(0);
      expect(getTranslateY(waitingRow)).toBe(0);

      // A row above them that changes moves them from there again
      Object.assign(tops, { activity: 140, 3: 190, 4: 240, end: 280 });
      render(true);
      await flushFrame();
      expect(getTranslateY(goingRow)).toBe(-40);
      expect(getTranslateY(waitingRow)).toBe(-40);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('moves the questions that wait at once where motion is reduced or none waits', async () => {
    const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    try {
      const tops = mockListRects({
        1: 50, activity: 100, 3: 150, 4: 200, end: 240,
      });
      const reduced = await stopOverQueuedQuestions(0, 2);
      reduced.render({ queuedMessageCount: 2 });
      Object.assign(tops, { 3: 100, 4: 150, end: 190 });
      await flushUi(3);
      expect(reduced.onStop).toHaveBeenCalledTimes(1);
      expect(getTranslateY(root.querySelector<HTMLElement>('[data-agent-v2-message-id="3"]')!)).toBe(0);

      TeactDOM.render(undefined, root);
      await flushUi();

      Object.assign(tops, { 3: 150, 4: 200, end: 240 });
      const unqueued = await stopOverQueuedQuestions(ANIMATION_LEVEL_MAX, 0);
      unqueued.render({ queuedMessageCount: 0 });
      Object.assign(tops, { 3: 100, 4: 150, end: 190 });
      await flushUi(3);
      expect(unqueued.onStop).toHaveBeenCalledTimes(1);
      expect(getTranslateY(root.querySelector<HTMLElement>('[data-agent-v2-message-id="3"]')!)).toBe(0);
    } finally {
      restoreProperty(document, 'hidden', originalHidden);
    }
  });

  it('closes the gap in the new last turn when a question comes in as the dust settles', async () => {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const answer: AgentMessage = { ...SECOND_MESSAGE, text: 'Answer to regenerate' };
    const nextQuestion: AgentMessage = { ...MESSAGE, id: 3, text: 'Next question', isOutgoing: true };
    const renderMessage = renderDissolvingMessage;
    await dissolveAnswer(question, answer);
    const firstGap = findDissolveGap()!;

    renderShell({ animationLevel: ANIMATION_LEVEL_MAX, messages: [question, nextQuestion], renderMessage });
    await flushUi(3);
    const gap = findDissolveGap()!;
    expect(gap).not.toBe(firstGap);

    await flushUi(30);
    expect(gap.style.height).toBe('0px');
  });

  it('starts what the closed gap moved where it stood, leaving out what stays out of sight', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const animate = jest.fn();
    Object.defineProperty(Element.prototype, 'animate', { configurable: true, value: animate });

    try {
      const messagesElement = await dissolveAnswer(
        { ...MESSAGE, text: 'Question', isOutgoing: true },
        { ...SECOND_MESSAGE, text: 'Answer to regenerate' },
      );
      const gap = findDissolveGap()!;
      const turn = gap.parentElement!;
      const spacer = messagesElement.firstElementChild as HTMLElement;
      mockRect(spacer, { top: -900, bottom: -800 });
      // The list stands at its end, so the closed gap brings the turn down
      turn.getBoundingClientRect = () => {
        const top = gap.style.height === '0px' ? 150 : 50;
        return {
          top, bottom: top + 150, left: 0, right: 300, x: 0, y: top, width: 300, height: 150, toJSON: () => undefined,
        };
      };

      await flushUi(30);

      expect(animate.mock.contexts).toEqual([turn]);
      expect(animate).toHaveBeenCalledWith(
        [{ transform: 'translate(0px, -100px)' }, { transform: 'none' }],
        { duration: 400, easing: 'ease', composite: 'add' },
      );
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
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

  it.each(['pinned', 'read above'] as const)(
    'keeps the rows in sight in place as an answer comes above the questions that wait in a long chat (%s)',
    async (place) => {
      // The chat has more messages than the list renders at once, so the answer takes older ones into the list too
      const history = buildMessages(32);
      const timestamp = MESSAGE.timestamp + history.length;
      const question: AgentMessage = { ...MESSAGE, id: 33, text: 'Question', isOutgoing: true, timestamp };
      const answer: AgentMessage = { ...MESSAGE, id: 36, text: 'Answer', timestamp: timestamp + 1 };
      const going: AgentMessage = {
        ...MESSAGE, id: 34, text: 'Going question', isOutgoing: true, timestamp: timestamp + 2,
      };
      const waiting: AgentMessage = {
        ...MESSAGE, id: 35, text: 'Waiting question', isOutgoing: true, timestamp: timestamp + 3,
      };
      const renderChat = (messages: AgentMessage[]) => renderShell({
        messages,
        queuedMessageCount: 2,
        isRunActive: true,
        isQueueing: true,
        canStop: true,
        hasOlderMessages: true,
        historyMode: 'continuous',
        renderMessage: (message) => (
          <div key={message.id} className={MESSAGE_ROW_CLASS_NAME} data-agent-v2-message-id={message.id}>
            {message.text}
          </div>
        ),
        session: place === 'pinned' ? { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() } : undefined,
      });
      // As in a browser, a laid-out row has an `offsetParent`, so the list keeps its scroll anchor on the row it last
      // scrolled to
      const originalOffsetParent = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'offsetParent');
      Object.defineProperty(HTMLElement.prototype, 'offsetParent', {
        configurable: true,
        get(this: HTMLElement) {
          return this.parentElement;
        },
      });

      try {
        renderChat([...history, question, going, waiting]);
        const messagesElement = root.querySelector<HTMLDivElement>('.custom-scroll')!;
        const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 3100, clientHeight: 500 });
        mockRenderedRowRects(geometry);
        await flushUi();

        // The list scrolls down to its end, as it does to pin a question, and a reader then scrolls back up
        for (const top of place === 'pinned' ? [2500, 2600] : [2500, 2600, 2000]) {
          messagesElement.scrollTop = top;
          messagesElement.dispatchEvent(new Event('scroll'));
          await flushUi();
        }
        const shownRow = root.querySelector<HTMLElement>(
          `[data-agent-v2-message-id="${place === 'pinned' ? question.id : 26}"]`,
        )!;
        const shownTop = shownRow.getBoundingClientRect().top;
        expect(root.querySelector('[data-agent-v2-message-id="1"]')).toBeNull();

        geometry.scrollHeight = 3800;
        renderChat([...history, question, answer, going, waiting]);
        await flushUi();

        expect(root.querySelector('[data-agent-v2-message-id="1"]')).not.toBeNull();
        expect(shownRow.getBoundingClientRect().top).toBe(shownTop);
      } finally {
        restoreProperty(HTMLElement.prototype, 'offsetParent', originalOffsetParent);
      }
    },
  );

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

  it('shows the text of an empty list centered without Retry, and the messages once they come', async () => {
    renderShell({ emptyText: 'Nothing yet', withoutComposer: true });
    await flushUi();

    expect(root.querySelector('.custom-scroll')).toBeNull();
    expect(root.textContent).toContain('Nothing yet');
    expect(root.querySelector('[role="alert"]')).toBeNull();
    expect(Array.from(root.querySelectorAll('button')).some((button) => button.textContent === 'Retry')).toBe(false);

    renderShell({ emptyText: 'Nothing yet', loadFailure: { text: 'Load failed', onRetry: jest.fn() } });
    await flushUi();

    expect(root.textContent).not.toContain('Nothing yet');
    expect(root.querySelector('[role="alert"]')?.textContent).toContain('Load failed');

    renderShell({ messages: [MESSAGE], emptyText: 'Nothing yet' });
    await flushUi();

    expect(root.querySelector('.custom-scroll')?.textContent).toContain('Hello');
    expect(root.textContent).not.toContain('Nothing yet');
  });

  it('puts each day of the news under its date line in an element of its own, which the line stays over', async () => {
    const firstDay = new Date(2026, 9, 20, 9).getTime();
    const secondDay = new Date(2026, 9, 21, 9).getTime();
    renderShell({
      withoutComposer: true,
      hasDailyDateLines: true,
      messages: [
        { ...MESSAGE, id: 1, timestamp: firstDay },
        { ...MESSAGE, id: 2, timestamp: firstDay + 1000 },
        { ...MESSAGE, id: 3, timestamp: secondDay },
      ],
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
    });
    await flushUi();

    const [first, second, third] = [1, 2, 3].map((id) => root.querySelector(`[data-agent-v2-message-id="${id}"]`)!);
    expect(first.parentElement).toBe(second.parentElement);
    expect(third.parentElement).not.toBe(first.parentElement);
    expect(first.parentElement!.firstElementChild!.textContent).toBe('DATE_SEPARATOR');
    expect(third.parentElement!.firstElementChild!.textContent).toBe('DATE_SEPARATOR');
  });

  it('shows the spinner under the header while older messages load', async () => {
    renderShell({ messages: [MESSAGE], hasOlderMessages: true, isLoadingOlderMessages: true });
    await flushUi();
    expect(root.querySelector('[aria-label="Loading..."]')).not.toBeNull();

    renderShell({ messages: [MESSAGE], hasOlderMessages: true });
    await flushUi();
    expect(root.querySelector('[aria-label="Loading..."]')).toBeNull();
  });

  it('shows no spinner while the news feed loads older posts', async () => {
    renderShell({
      messages: [MESSAGE], hasOlderMessages: true, isLoadingOlderMessages: true, noLoadingIndicator: true,
    });
    await flushUi();

    expect(root.querySelector('[aria-label="Loading..."]')).toBeNull();
    expect(root.textContent).toContain('Hello');
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

  it('restores a chat by its position from the end when a remount reassigns message ids', async () => {
    let messages = buildMessages(30);
    let savedSession: AgentConversationSession | undefined;
    const { messagesElement } = renderChat();
    await flushUi();
    messagesElement.scrollTop = 1250;
    messagesElement.dispatchEvent(new Event('scroll'));
    await flushUi();
    switchLayout();

    TeactDOM.render(undefined, root);
    await flushUi();
    messages = messages.map((message) => ({ ...message, id: message.id + 10 }));

    const { geometry } = renderChat(savedSession);
    await flushUi();
    expect(geometry.scrollTop).toBe(1250);
    const openingMessage = root.querySelector<HTMLElement>('[data-agent-v2-message-id="22"]')!;
    expect(openingMessage.textContent).toBe('Message 12');
    expect(openingMessage.getBoundingClientRect().top).toBe(-50);

    function renderChat(initial?: AgentConversationSession) {
      renderShell({
        messages,
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
      const element = root.querySelector<HTMLDivElement>('.custom-scroll')!;
      const geometry = mockScrollGeometry(element, { scrollHeight: 3000, clientHeight: 500 });
      mockMessageRects(geometry, messages);
      return { messagesElement: element, geometry };
    }
  });

  it('keeps its place as it is about to give way to another list', async () => {
    const messages = buildMessages(30);
    let savedSession: AgentConversationSession | undefined;
    let leave: NoneToVoidFunction | undefined;
    renderShell({
      messages,
      withoutComposer: true,
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
      session: {
        save: (session) => {
          savedSession = session;
        },
        shouldKeepPlaceOffScreen: true,
        subscribeToLeave: (onLeave) => {
          leave = onLeave;
          return () => {
            leave = undefined;
          };
        },
      },
    });
    const messagesElement = root.querySelector<HTMLDivElement>('.custom-scroll')!;
    const geometry = mockScrollGeometry(messagesElement, { scrollHeight: 4000, clientHeight: 500 });
    mockMessageRects(geometry, messages);
    await flushUi();
    messagesElement.scrollTop = 1250;
    messagesElement.dispatchEvent(new Event('scroll'));
    await flushUi();

    leave!();
    expect(savedSession).toEqual(expect.objectContaining({
      isPlaced: true, scrollAnchor: { messageId: 12, indexFromEnd: 18, offset: -50 },
    }));
    TeactDOM.render(undefined, root);
    await flushUi();
    expect(leave).toBeUndefined();
  });

  it.each(['unchanged', 'appended', 'reposted', 'removed'])('restores its place on remount (%s)', async (change) => {
    let messages = buildMessages(30);
    let savedSession: AgentConversationSession | undefined;
    const renderList = (isActive: boolean, initial?: AgentConversationSession) => renderShell({
      isActive,
      messages,
      withoutComposer: true,
      renderMessage: (message) => (
        <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>
      ),
      session: {
        initial,
        save: (session) => {
          savedSession = session;
        },
        shouldKeepPlaceOffScreen: true,
      },
    });
    const mockGeometry = () => {
      const geometry = mockScrollGeometry(
        root.querySelector<HTMLDivElement>('.custom-scroll')!, {
          scrollHeight: messages.length * 100 + 1000, clientHeight: 500,
        },
      );
      mockMessageRects(geometry, messages);
      return geometry;
    };

    renderList(true);
    mockGeometry();
    await flushUi();
    const messagesElement = root.querySelector<HTMLDivElement>('.custom-scroll')!;
    messagesElement.scrollTop = 1250;
    messagesElement.dispatchEvent(new Event('scroll'));
    await flushUi();

    // A discussion opens over the list
    renderList(false);
    await flushUi();
    expect(savedSession).toEqual(expect.objectContaining({
      isPlaced: true, scrollAnchor: { messageId: 12, indexFromEnd: 18, offset: -50 },
    }));

    TeactDOM.render(undefined, root);
    await flushUi();
    if (change === 'appended') messages = buildMessages(60);
    if (change === 'reposted') messages = [...messages.filter(({ id }) => id !== 12), messages[11]];
    if (change === 'removed') messages = messages.filter(({ id }) => id !== 12);

    renderList(true, savedSession);
    const geometry = mockGeometry();
    await flushUi();
    const openingMessageId = change === 'removed' ? 11 : 12;
    const openingMessage = root.querySelector<HTMLElement>(`[data-agent-v2-message-id="${openingMessageId}"]`)!;
    expect(openingMessage).not.toBeNull();
    expect(openingMessage.getBoundingClientRect().top).toBe(-50);
    expect(geometry.scrollTop).toBe(change === 'reposted' ? 3050 : change === 'removed' ? 1150 : 1250);
  });

  it('keeps the whole transcript being written as the layouts switch', async () => {
    let savedSession: AgentConversationSession | undefined;
    const renderChat = (initial?: AgentConversationSession) => renderShell({
      renderComposer: (props) => <AgentV2Composer {...props} isActive />,
      session: {
        initial,
        save: (session) => {
          savedSession = session;
        },
      },
    });
    renderChat();
    await flushUi();

    jest.mocked(useAgentV2Dictation).mock.lastCall![0].onTranscript('one two three');
    switchLayout();
    expect(savedSession?.draft).toBe('one two three');

    TeactDOM.render(undefined, root);
    await flushUi();
    expect(savedSession?.draft).toBe('one two three');
    renderChat(savedSession);
    await flushUi();
    expect(root.querySelector('textarea')!.value).toBe('one two three');
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

  // Returns the render of a question whose answer is being produced, with two questions waiting after it, of which
  // the first goes with `sentQueuedMessage` and gets its answer with `hasGoingAnswer`
  function renderGoingQueue(session?: AgentConversationSessionStore) {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const going: AgentMessage = {
      ...SECOND_MESSAGE, text: 'Going question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const goingAnswer: AgentMessage = {
      ...SECOND_MESSAGE, id: 3, text: 'Answer', timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const waiting: AgentMessage = {
      ...SECOND_MESSAGE, id: 4, text: 'Waiting question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 2,
    };

    return (queuedMessageCount: number, sentQueuedMessage?: { id: number }, hasGoingAnswer = false) => renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages: hasGoingAnswer ? [question, going, goingAnswer, waiting] : [question, going, waiting],
      queuedMessageCount,
      sentQueuedMessage,
      isRunActive: true,
      isQueueing: true,
      canStop: true,
      renderMessage: (message) => <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>,
      session,
    });
  }

  // Renders a question whose answer is being produced, with its activity under it and two questions waiting after
  // them, and presses Stop once the rows have their places. The question is pinned unless the list is held at its end.
  // `render` draws the chat as the stop changes it.
  async function stopOverQueuedQuestions(
    animationLevel: AnimationLevel, queuedMessageCount: number, isHeldAtEnd = false,
  ) {
    const question: AgentMessage = { ...MESSAGE, text: 'Question', isOutgoing: true };
    const going: AgentMessage = {
      ...MESSAGE, id: 3, text: 'Going question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 1,
    };
    const waiting: AgentMessage = {
      ...MESSAGE, id: 4, text: 'Waiting question', isOutgoing: true, timestamp: SECOND_MESSAGE.timestamp + 2,
    };
    const onStop = jest.fn();
    const session = isHeldAtEnd ? undefined : { initial: { draft: '', isQuestionPinned: true }, save: jest.fn() };
    const render = ({ queuedMessageCount: count, sentQueuedMessage, hasActivity = false }: {
      queuedMessageCount: number;
      sentQueuedMessage?: { id: number };
      hasActivity?: boolean;
    }) => renderShell({
      animationLevel,
      messages: [question, going, waiting],
      queuedMessageCount: count,
      isRunActive: true,
      isQueueing: true,
      canStop: true,
      sentQueuedMessage,
      onStop,
      runActivity: hasActivity ? <div key="activity" data-agent-run-activity>Analyzing</div> : undefined,
      renderMessage: (message) => <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>,
      renderComposer: (props) => <button type="button" data-stop onClick={props.onStop}>Stop</button>,
      session,
    });
    render({ queuedMessageCount, hasActivity: true });
    const messagesElement = root.querySelector('.custom-scroll') as HTMLDivElement;
    mockScrollGeometry(messagesElement, { scrollHeight: 600, clientHeight: 600 });
    await flushUi();

    root.querySelector<HTMLButtonElement>('[data-stop]')!.click();
    // The rows are measured where they stand before the stop changes them
    await flushFrame();

    return { render, onStop };
  }

  // The answer turns to dust, and the gap holds its place until the dust settles
  async function dissolveAnswer(question: AgentMessage, answer: AgentMessage) {
    const renderMessage = renderDissolvingMessage;
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
    mockRect(root.querySelector<HTMLElement>(`[data-agent-v2-message-id="${question.id}"]`)!, { top: 50, bottom: 90 });
    mockRect(root.querySelector<HTMLElement>(`[data-agent-v2-message-id="${answer.id}"]`)!, { top: 100, bottom: 200 });

    renderShell({
      animationLevel: ANIMATION_LEVEL_MAX,
      messages: [question, answer],
      dissolvingMessageIds: [answer.id],
      renderMessage,
    });
    await flushUi(3);

    renderShell({ animationLevel: ANIMATION_LEVEL_MAX, messages: [question], renderMessage });
    await flushUi(3);

    return messagesElement;
  }

  function renderShell({
    isActive = true,
    animationLevel = 0,
    messages = [],
    hints,
    isInitialLoadComplete = true,
    hasOpeningQuestion,
    isInputDisabled = false,
    isQueueing,
    canStop,
    onStop,
    sentQueuedMessage,
    isRunActive = false,
    queuedMessageCount,
    textRevealPresentations = {},
    unreadMessageId,
    hasDailyDateLines,
    loadFailure,
    emptyText,
    noComposer = false,
    withoutComposer = false,
    hasOlderMessages = false,
    isLoadingOlderMessages = false,
    noLoadingIndicator,
    historyMode = 'windowed',
    conversationSlot,
    headerAccessory,
    messageListFooter,
    runActivity,
    beforeComposerSlot,
    bottomStickDependency,
    loadOlderMessages = jest.fn(),
    onBack = jest.fn(),
    onSendMessage = jest.fn(),
    onSendHint = jest.fn(),
    hasMenu = false,
    onDelete,
    onRequestSupport,
    onReportProblem,
    onComposerHeightChange,
    onScroll,
    onMessageVisible,
    renderMessage = (message) => <div key={message.id}>{message.text}</div>,
    renderComposer,
    onRequestConsent,
    dissolvingMessageIds,
    isFooterDissolving,
    onDissolveStart,
    session,
    noLiveTail,
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
            hasOpeningQuestion,
            isRunActive,
            queuedMessageCount,
            textRevealPresentations,
            unreadMessageId,
            hasDailyDateLines,
            loadFailure,
            emptyText,
            dissolvingMessageIds,
            isFooterDissolving,
            onDissolveStart,
            renderMessage,
          }}
          composer={withoutComposer ? undefined : {
            isDisabled: isInputDisabled,
            isQueueing,
            canStop,
            onStop,
            sentQueuedMessage,
            shouldHide: noComposer,
            onSendMessage,
            onSendHint,
            onHeightChange: onComposerHeightChange,
            onRequestConsent,
            render: renderComposer,
          }}
          history={hasOlderMessages ? {
            hasOlderMessages,
            isLoading: isLoadingOlderMessages,
            noLoadingIndicator,
            mode: historyMode,
            loadOlderMessages,
          } : undefined}
          slots={{
            body: conversationSlot,
            headerAccessory,
            messageListFooter,
            runActivity,
            beforeComposer: beforeComposerSlot,
            bottomStickDependency,
          }}
          header={hasMenu ? { hasMenu, canRequestSupport: Boolean(onRequestSupport) } : undefined}
          actions={{
            onBack, onDelete, onRequestSupport, onReportProblem, onScroll, onMessageVisible,
          }}
          session={session}
          noLiveTail={noLiveTail}
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

// Each message stands 100 px below the one before it, in list order when given or in `id` order
function mockMessageRects(geometry: { scrollTop: number }, messages?: AgentMessage[]) {
  jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
    const id = (this as HTMLElement).dataset?.agentV2MessageId;
    const position = messages ? messages.findIndex((message) => String(message.id) === id) + 1 : Number(id);
    const top = id ? position * 100 - geometry.scrollTop : 0;
    return {
      top, bottom: top + 100, left: 0, right: 300, x: 0, y: top, width: 300, height: 100, toJSON: () => undefined,
    };
  });
}

/**
 * Places each rendered message 100 px below the one rendered before it, as the list lays out the messages it renders.
 * The list's own box starts at 0.
 */
function mockRenderedRowRects(geometry: { scrollTop: number }) {
  jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
    const element = this as HTMLElement;
    if (element.classList.contains('custom-scroll')) {
      return {
        top: 0, bottom: element.clientHeight, left: 0, right: 300, x: 0, y: 0, width: 300, height: element.clientHeight,
        toJSON: () => undefined,
      };
    }

    const rows = Array.from(document.querySelectorAll('[data-agent-v2-message-id]'));
    const index = rows.indexOf(element);
    const top = index < 0 ? 0 : index * 100 - geometry.scrollTop;
    const height = index < 0 ? 0 : 100;
    return {
      top, bottom: top + height, left: 0, right: 300, x: 0, y: top, width: 300, height, toJSON: () => undefined,
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

function findScrollToBottomButton() {
  return document.querySelector<HTMLButtonElement>('button[aria-label="Scroll To Bottom"]');
}

// The turn with the live tail's top space
function findLiveTailSpaceTurn() {
  return document.querySelector('[data-agent-live-tail-space]');
}

// The picture of the field's text, which flies over the list into the question's bubble
function findFieldTextPicture() {
  const text = Array.from(document.querySelectorAll('span'))
    .find((span) => span.textContent === 'Question' && !span.closest('[data-agent-v2-message-id]'));
  return text?.parentElement?.parentElement ?? undefined;
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

// Runs one frame and the work it leaves for later in that frame
async function flushFrame() {
  await flushUi(1);
  await jest.advanceTimersByTimeAsync(0);
}

/**
 * Places the rows of the list at the tops `tops` gives, by message id and `activity`, each 40 px tall and moved by the
 * offset it is drawn at. The turn of the last message ends at `end`, the other turns start at 0, and everything in the
 * list is `shift` lower. The list's own box starts at 0 and is as tall as the list. With `hidden`, nothing has a box.
 */
function mockListRects(tops: Record<string, number>) {
  jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
    const element = this as HTMLElement;
    if (tops.hidden) {
      return {
        top: 0, bottom: 0, left: 0, right: 0, x: 0, y: 0, width: 0, height: 0, toJSON: () => undefined,
      };
    }

    if (element.classList.contains('custom-scroll')) {
      return {
        top: 0, bottom: element.clientHeight, left: 0, right: 300, x: 0, y: 0, width: 300, height: element.clientHeight,
        toJSON: () => undefined,
      };
    }

    const key = element.dataset?.agentV2MessageId
      ?? (element.hasAttribute('data-agent-run-activity') ? 'activity' : undefined);
    const isLastTurn = !key && Boolean(element.querySelector(':scope > [data-agent-v2-message-id="4"]'));
    const shift = tops.shift ?? 0;
    const top = shift + (key !== undefined ? tops[key] + getTranslateY(element) : isLastTurn ? tops.end - 40 : 0);
    return {
      top, bottom: top + 40, left: 0, right: 300, x: 0, y: top, width: 300, height: 40, toJSON: () => undefined,
    };
  });

  return tops;
}

// The list draws a row moved by `0 ${offset}px`, which jsdom keeps as it is set
function getTranslateY(element: HTMLElement) {
  return Number.parseFloat((element.style.translate || '').split(' ')[1]) || 0;
}

function renderDissolvingMessage(message: AgentMessage) {
  return <div key={message.id} data-agent-v2-message-id={message.id}>{message.text}</div>;
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
