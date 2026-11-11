import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentConversationComposerProps } from '../agent/AgentConversationShell';

import { getAgentV2LocalState, resetAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import { startOpeningTextFlight } from './agentOpeningQuestion';

import { PORTRAIT_SCREEN_QUERY } from '../../hooks/useDeviceScreen';

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

let mockComposer: AgentConversationComposerProps;
jest.mock('./AgentV2Composer', () => ({
  __esModule: true,
  default: (props: AgentConversationComposerProps) => {
    mockComposer = props;
    return undefined;
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
    if (action.endsWith('send')) expect(onStartChat).toHaveBeenCalledWith('A question', false);

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
  expect(onStartChat).toHaveBeenCalledWith(question, false);
});

function renderList() {
  TeactDOM.render(
    <AgentThreadList
      isActive
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
