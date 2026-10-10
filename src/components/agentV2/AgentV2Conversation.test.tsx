import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { APP_NAME } from '../../config';

import { AgentV2AssistantText, AgentV2ConsentScreen } from './AgentV2Conversation';

const mockLang = jest.fn((key: string) => key);

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => mockLang,
}));

let nextAnimationFrameId = 0;
let pendingAnimationFrames = new Map<number, FrameRequestCallback>();

describe('AgentV2AssistantText', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.useFakeTimers();
    mockLang.mockClear();
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
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await flushUi();
    root.remove();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('uses the shared V1 streaming renderer and settles its reveal session', async () => {
    const onConsumed = jest.fn();
    const onSettled = jest.fn();
    const onComplete = jest.fn();

    TeactDOM.render(
      <AgentV2AssistantText
        messageId={7}
        text="Shared response"
        isStreaming={false}
        shouldAnimate={false}
        shouldCommitMarkdownTail
        textRevealPresentation={{
          key: 'v2:7:1',
          status: 'active',
          shouldRevealFromStart: true,
        }}
        onTextRevealSessionConsumed={onConsumed}
        onTextRevealSessionSettled={onSettled}
        onRevealComplete={onComplete}
      />,
      root,
    );
    await flushUi();

    expect(root.querySelector('[data-agent-streaming-container]')?.textContent).toBe('Shared response');
    expect(onConsumed).toHaveBeenCalledWith(7, 'v2:7:1');
    expect(onSettled).toHaveBeenCalledWith(7, 'v2:7:1');
    expect(onComplete).toHaveBeenCalledTimes(1);
  });

  it.each(['active', 'settled'] as const)('renders clickable V2 Markdown with a %s reveal session', async (status) => {
    TeactDOM.render(
      <AgentV2AssistantText
        messageId={8}
        text="[Source](https://example.com) [Receive](mtw://receive)"
        isStreaming={false}
        shouldAnimate={false}
        shouldCommitMarkdownTail
        textRevealPresentation={{
          key: 'v2:8:1',
          status,
          shouldRevealFromStart: false,
        }}
      />,
      root,
    );
    await flushUi();

    expect(root.textContent).toBe('Source Receive');
    expect(root.querySelectorAll('a')).toHaveLength(1);
    expect(root.querySelector('a')?.getAttribute('href')).toBe('https://example.com');
  });

  it('renders branded consent copy and forwards the allow action', async () => {
    const onAccept = jest.fn();
    TeactDOM.render(<AgentV2ConsentScreen onAccept={onAccept} />, root);
    await flushUi();

    expect(mockLang).toHaveBeenCalledWith('$agent_consent_feature_answers', { app_name: APP_NAME });
    expect(mockLang).toHaveBeenCalledWith('$agent_consent_disclosure_text', { app_name: APP_NAME });

    const allowButton = Array.from(root.querySelectorAll('button'))
      .find((button) => button.textContent === '$agent_consent_allow_button');
    allowButton!.click();
    await flushUi();

    expect(onAccept).toHaveBeenCalledTimes(1);
  });

  it('renders settled answers fully without an expansion toggle', async () => {
    const text = 'A long settled answer '.repeat(20);
    TeactDOM.render(
      <AgentV2AssistantText
        messageId={9}
        text={text}
        isStreaming={false}
        shouldAnimate={false}
      />,
      root,
    );
    await flushUi();

    expect(root.querySelector('[data-agent-static-text]')?.textContent).toBe(text);
    expect(root.querySelector('button[aria-expanded]')).toBeNull();
  });
});

async function flushUi() {
  for (let i = 0; i < 20; i++) {
    await jest.advanceTimersByTimeAsync(20);
    const callbacks = Array.from(pendingAnimationFrames.values());
    pendingAnimationFrames.clear();
    callbacks.forEach((callback) => callback(i * 16));
    await Promise.resolve();
  }
}
