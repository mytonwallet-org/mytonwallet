import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentConversationComposerProps } from '../agent/AgentConversationShell';

import { getAgentV2LocalState, resetAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import { startOpeningTextFlight } from './agentOpeningQuestion';

import { PORTRAIT_SCREEN_QUERY } from '../../hooks/useDeviceScreen';

import { getIsAnyModalOpen } from '../ui/Modal';
import AgentThreadList from './AgentThreadList';

jest.mock('../../api', () => ({ callApi: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en', isRtl: false }),
}));

jest.mock('./agentOpeningQuestion', () => ({
  startOpeningSuggestionMorph: jest.fn(),
  startOpeningTextFlight: jest.fn(),
}));

jest.mock('../ui/Modal', () => ({
  ...jest.requireActual('../ui/Modal'),
  getIsAnyModalOpen: jest.fn(() => false),
}));

let mockComposer: AgentConversationComposerProps;
jest.mock('./AgentV2Composer', () => ({
  __esModule: true,
  default: (props: AgentConversationComposerProps & { onFocus: NoneToVoidFunction }) => {
    mockComposer = props;
    return <textarea ref={props.inputRef} onFocus={props.onFocus} />;
  },
}));

let root: HTMLDivElement;
let nextFrameId = 0;
const frames = new Map<number, FrameRequestCallback>();
const onStartChat = jest.fn();

beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  resetAgentV2LocalState();
  frames.clear();
  // eslint-disable-next-line no-null/no-null
  jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);
  jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
    const id = ++nextFrameId;
    frames.set(id, callback);
    return id;
  });
  jest.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => frames.delete(id));
  root = document.createElement('div');
  document.body.appendChild(root);
});

afterEach(async () => {
  TeactDOM.render(undefined, root);
  await flushUi();
  root.remove();
  jest.useRealTimers();
  jest.restoreAllMocks();
});

it.each(['typing', 'dictation', 'clear', 'send', 'immediate send'] as const)(
  'hands off the list draft after %s before the pending render', async (action) => {
    renderList();
    await flushUi();
    mockComposer.onInput('A question');
    if (action === 'dictation') mockComposer.onInput('A question in progress');
    if (action === 'immediate send') mockComposer.onSend();
    if (action === 'clear' || action === 'send') {
      await flushUi();
      if (action === 'clear') mockComposer.onInput('');
      else mockComposer.onSend();
    }

    switchLayout();
    const expected = action === 'typing' ? 'A question' : action === 'dictation' ? 'A question in progress' : '';
    expect(getAgentV2LocalState().draftOnMount).toBe(expected);
    if (action.endsWith('send')) expect(onStartChat).toHaveBeenCalledWith('A question', false, undefined);

    TeactDOM.render(undefined, root);
    renderList();
    await flushUi();
    expect(mockComposer.inputValue).toBe(expected);
  },
);

it.each([
  ['flies a question into the new chat\'s bubble', 'A question', true],
  // Its bubble shows it without the secret words the field holds
  [
    'does not fly a question with secret words',
    'Hi! abandon ability able about above absent absorb abstract absurd abuse access accident',
    false,
  ],
] as const)('%s', async (_, question, isFlying) => {
  jest.mocked(startOpeningTextFlight).mockClear();
  renderList();
  await flushUi();
  const input = document.createElement('textarea');
  mockComposer.inputRef.current = input;
  mockComposer.onInput(question);
  await flushUi();
  mockComposer.onSend();

  if (isFlying) {
    expect(startOpeningTextFlight).toHaveBeenCalledWith(input, question);
  } else {
    expect(startOpeningTextFlight).not.toHaveBeenCalled();
  }
  expect(onStartChat).toHaveBeenCalledWith(question, false, undefined);
});

describe('field focus', () => {
  beforeEach(() => {
    jest.mocked(getIsAnyModalOpen).mockReturnValue(false);
  });

  it('focuses the field as the Agent opens on the list, but not under a chat, a modal or on coming back', async () => {
    renderList();
    await flushUi();
    expect(document.activeElement).toBe(getField());
    expect(getIsComposing()).toBe(false);

    TeactDOM.render(undefined, root);
    getField()?.blur();
    jest.mocked(getIsAnyModalOpen).mockReturnValue(true);
    renderList();
    await flushUi();
    expect(document.activeElement).toBe(document.body);
    jest.mocked(getIsAnyModalOpen).mockReturnValue(false);

    // The Agent opens on a chat, and Back leaves the focus to the chats' stack
    TeactDOM.render(undefined, root);
    renderList({ isActive: false });
    await flushUi();
    renderList();
    await flushUi();
    expect(document.activeElement).toBe(document.body);

    // The Agent opens again on the list
    renderList({ isActive: false, isAgentActive: false });
    await flushUi();
    renderList();
    await flushUi();
    expect(document.activeElement).toBe(getField());
  });

  it('moves the focus to the field on Tab only while nothing has focus', async () => {
    renderList({ isAgentActive: false });
    await flushUi();
    expect(document.activeElement).toBe(document.body);

    expect(pressTab(document.body).defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(getField());
    expect(getIsComposing()).toBe(false);

    const button = document.createElement('button');
    root.appendChild(button);
    button.focus();
    expect(pressTab(button).defaultPrevented).toBe(false);
    expect(document.activeElement).toBe(button);
  });

  it.each(['click', 'input'] as const)('starts composing on a %s into the focused field', async (type) => {
    renderList();
    await flushUi();
    expect(document.activeElement).toBe(getField());
    expect(getIsComposing()).toBe(false);

    getField()!.dispatchEvent(new Event(type, { bubbles: true }));
    await flushUi();
    expect(getIsComposing()).toBe(true);
  });
});

function renderList({ isActive = true, isAgentActive = true } = {}) {
  TeactDOM.render(
    <AgentThreadList
      isActive={isActive}
      isAgentActive={isAgentActive}
      hasMore={false}
      isRetrying={false}
      newsUnreadCount={0}
      activityLangKeys={{}}
      onSelect={jest.fn()}
      onOpenNews={jest.fn()}
      onStartChat={onStartChat}
      onRequestConsent={jest.fn()}
      onLoadMore={jest.fn()}
      onRetry={jest.fn()}
      onRename={jest.fn()}
      onTogglePin={jest.fn()}
      onDelete={jest.fn()}
    />,
    root,
  );
}

function getField() {
  return root.querySelector('textarea');
}

function getIsComposing() {
  return root.textContent!.includes('New Chat');
}

function pressTab(target: HTMLElement) {
  const event = new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
  target.dispatchEvent(event);
  return event;
}

function switchLayout() {
  jest.mocked(window.matchMedia).mock.results.forEach(({ type: resultType, value }) => {
    if (resultType !== 'return' || value.media !== PORTRAIT_SCREEN_QUERY) return;
    const removed = jest.mocked(value.removeEventListener).mock.calls.map(([, listener]) => listener);
    jest.mocked(value.addEventListener).mock.calls.forEach(([type, listener]) => {
      if (type === 'change' && !removed.includes(listener)) (listener as EventListener)(new Event('change'));
    });
  });
}

async function flushUi() {
  for (let i = 0; i < 20; i++) {
    await jest.advanceTimersByTimeAsync(20);
    const callbacks = Array.from(frames.values());
    frames.clear();
    callbacks.forEach((callback) => callback(i * 16));
    await Promise.resolve();
  }
}
