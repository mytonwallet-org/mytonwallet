import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentMessage } from '../../global/types';
import type { TextRevealPresentation } from './hooks/useAgentMessages';

import { pause } from '../../util/schedulers';

import MessageBubble from './MessageBubble';

const STREAMING_SHELL_ANIMATION_NAME = 'expand-incoming-streaming-shell';

describe('MessageBubble streaming text', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('renders hydrated Markdown immediately without replaying it', async () => {
    renderBubble(buildMessage('Hydrated **Markdown** response'), {
      shouldAnimateTextStreaming: true,
    });
    await pause(20);

    const text = getStaticText();
    expect(text.textContent).toBe('Hydrated Markdown response');
    expect(text.querySelector('strong')?.textContent).toBe('Markdown');
    expect(root.querySelector('[data-agent-streaming-container]')).toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell]')).toBeNull();
  });

  it('reveals a live response and reports completion for its session', async () => {
    const message = buildMessage('Streaming **Markdown** response', true);
    const onTextRevealProgress = jest.fn();
    const onTextRevealComplete = jest.fn();

    renderBubble(message, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:1', true),
      onTextRevealProgress,
      onTextRevealComplete,
    });
    await pause(220);

    expect(getStreamingText().textContent).toMatch(/^Streaming/);
    expect(getStreamingText().textContent).not.toBe('Streaming Markdown response');
    expect(onTextRevealProgress).toHaveBeenCalled();

    renderBubble({ ...message, isStreaming: undefined }, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:1', false),
      onTextRevealProgress,
      onTextRevealComplete,
    });
    await pause(650);

    expect(getStreamingText().textContent).toBe('Streaming Markdown response');
    expect(getStreamingText().querySelector('strong')?.textContent).toBe('Markdown');
    expect(onTextRevealComplete).toHaveBeenCalledTimes(1);

    renderBubble({ ...message, isStreaming: undefined }, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:1', false, 'settled'),
      onTextRevealProgress,
      onTextRevealComplete,
    });
    await pause(20);

    expect(root.querySelector('[data-agent-streaming-shell]')).not.toBeNull();
    const animatedShell = root.querySelector('[data-agent-streaming-shell-animated]')!;
    expect(animatedShell).not.toBeNull();

    getStaticText().dispatchEvent(buildAnimationEndEvent(STREAMING_SHELL_ANIMATION_NAME));
    await pause(20);
    expect(root.querySelector('[data-agent-streaming-shell-animated]')).not.toBeNull();

    animatedShell.dispatchEvent(buildAnimationEndEvent(STREAMING_SHELL_ANIMATION_NAME));
    await pause(20);

    expect(root.querySelector('[data-agent-streaming-shell]')).not.toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell-animated]')).toBeNull();
  });

  it('keeps the loader until the first text chunk arrives', async () => {
    const onTextRevealSessionConsumed = jest.fn();

    renderBubble({
      ...buildMessage('', true),
      isTyping: true,
    }, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:1', true),
      onTextRevealSessionConsumed,
    });
    await pause(20);

    expect(onTextRevealSessionConsumed).toHaveBeenCalledWith(1, '0:1:1');
    expect(root.querySelector('[data-agent-streaming-text]')).toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell]')).toBeNull();

    renderBubble(buildMessage('First text chunk', true), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:1', false),
      onTextRevealSessionConsumed,
    });
    await pause(20);

    expect(getStreamingText().textContent).not.toBe('First text chunk');
  });

  it('keeps the compact loader while the initial text seed is buffering', async () => {
    renderBubble(buildMessage('A', true), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:buffering', true),
    });
    await pause(100);

    expect(root.querySelector('[data-agent-streaming-waiting]')).not.toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell]')).toBeNull();
    expect(root.querySelector('[role="status"]')?.getAttribute('aria-label')).toBe('Loading...');

    await pause(260);

    expect(root.querySelector('[data-agent-streaming-waiting]')).toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell]')).not.toBeNull();
    expect(getStreamingText().textContent).toBe('A');
  });

  it('keeps streamed action buttons unavailable until the final visual drain', async () => {
    const message = buildMessage('[Open Agent](mtw://agent)', true);

    renderBubble(message, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:button-buffering', true),
    });
    await pause(100);

    expect(root.querySelector('button')).toBeNull();
    expect(root.querySelector('[data-agent-streaming-waiting]')).not.toBeNull();

    await pause(260);

    expect(root.querySelector('button')).toBeNull();
    expect(root.querySelector('[data-agent-streaming-waiting]')).toBeNull();

    renderBubble({ ...message, isStreaming: undefined }, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:button-buffering', false),
    });
    await pause(500);

    expect(root.querySelector('button')?.textContent).toBe('Open Agent');
  });

  it('hides mixed action markup and its button until reveal completion', async () => {
    const message = buildMessage('Done.\n\n[Open Agent](mtw://agent)', true);

    renderBubble(message, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:mixed-action', true),
    });
    await pause(220);

    expect(getStreamingText().textContent).not.toContain('[');
    expect(getStreamingText().textContent).not.toContain('mtw://');
    expect(root.querySelector('button')).toBeNull();

    renderBubble({ ...message, isStreaming: undefined }, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:mixed-action', false),
    });
    await pause(500);

    expect(getStreamingText().textContent).toBe('Done.');
    expect(root.querySelector('button')?.textContent).toBe('Open Agent');
  });

  it('buffers incomplete streamed action markup', async () => {
    renderBubble(buildMessage('Done.\n\n[Open Agent](mtw://ag', true), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:incomplete-action', true),
    });
    await pause(500);

    expect(getStreamingText().textContent).toBe('Done.');
    expect(root.querySelector('button')).toBeNull();
  });

  it('uses the action fallback for a button-only incomplete stream', async () => {
    renderBubble(buildMessage('[Open Agent](mtw://ag', true), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:incomplete-button-only', true),
    });
    await pause(500);

    expect(getStreamingText().textContent).toBe('👇');
    expect(root.querySelector('button')).toBeNull();
  });

  it('shows the current streaming prefix immediately after remount', async () => {
    const message = buildMessage('Authoritative streamed prefix', true);

    renderBubble(message, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:first-mount', true),
    });
    await pause(100);
    expect(getStreamingText().textContent).not.toBe(message.text);

    TeactDOM.render(undefined, root);
    renderBubble(message, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:first-mount', false),
    });
    await pause(20);

    expect(getStreamingText().textContent).toBe(message.text);
  });

  it('switches a partial stream error to compact static text immediately', async () => {
    renderBubble(buildMessage('Partial answer', true), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:error', true),
    });
    await pause(100);

    renderBubble(buildMessage('Localized error'), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:error', false, 'error'),
    });
    await pause(20);

    expect(getStaticText().textContent).toBe('Localized error');
    expect(root.querySelector('[data-agent-streaming-container]')).toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell]')).toBeNull();
  });

  it('does not create a ResizeObserver for hydrated or settled text', async () => {
    const resizeObserver = jest.fn();
    const originalResizeObserver = Object.getOwnPropertyDescriptor(globalThis, 'ResizeObserver');

    Object.defineProperty(globalThis, 'ResizeObserver', {
      configurable: true,
      value: resizeObserver,
    });

    try {
      renderBubble(buildMessage('Hydrated response'), {
        shouldAnimateTextStreaming: true,
      });
      await pause(20);
      expect(resizeObserver).not.toHaveBeenCalled();

      renderBubble(buildMessage('Settled response'), {
        shouldAnimateTextStreaming: true,
        textRevealPresentation: buildPresentation('0:1:settled', false, 'settled'),
      });
      await pause(20);

      expect(resizeObserver).not.toHaveBeenCalled();
      expect(root.querySelector('[data-agent-streaming-shell]')).not.toBeNull();
    } finally {
      restoreProperty(globalThis, 'ResizeObserver', originalResizeObserver);
    }
  });

  it('keeps a hydrated history on the lightweight static path', async () => {
    const resizeObserver = jest.fn();
    const originalResizeObserver = Object.getOwnPropertyDescriptor(globalThis, 'ResizeObserver');

    Object.defineProperty(globalThis, 'ResizeObserver', {
      configurable: true,
      value: resizeObserver,
    });

    try {
      TeactDOM.render(
        <div>
          {Array.from({ length: 30 }, (_, index) => (
            <MessageBubble
              key={index}
              message={{
                ...buildMessage(`Hydrated response ${index}`),
                id: index,
              }}
              shouldAnimateTextStreaming
            />
          ))}
        </div>,
        root,
      );
      await pause(20);

      expect(root.querySelectorAll('[data-agent-static-text]')).toHaveLength(30);
      expect(root.querySelectorAll('[data-agent-streaming-container]')).toHaveLength(0);
      expect(resizeObserver).not.toHaveBeenCalled();
    } finally {
      restoreProperty(globalThis, 'ResizeObserver', originalResizeObserver);
    }
  });

  it('shows hydrated and non-animated action buttons immediately', async () => {
    const message = buildMessage('[Open Agent](mtw://agent)');

    renderBubble(message, {
      shouldAnimateTextStreaming: true,
    });
    await pause(20);
    expect(root.querySelector('button')?.textContent).toBe('Open Agent');

    renderBubble(buildMessage('[Swap](mtw://swap)', true), {
      shouldAnimateTextStreaming: false,
      textRevealPresentation: buildPresentation('0:1:no-motion-action', true),
    });
    await pause(20);
    expect(root.querySelector('button')?.textContent).toBe('Swap');
  });

  it('resets the expanded shell for an edited response session', async () => {
    renderBubble(buildMessage('First animated response', true), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:1', true),
    });
    await pause(60);

    expect(root.querySelector('[data-agent-streaming-shell]')).not.toBeNull();

    renderBubble({
      ...buildMessage('', true),
      isTyping: true,
    }, {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:2', true),
    });
    await pause(20);

    expect(root.querySelector('[data-agent-streaming-shell]')).toBeNull();

    renderBubble(buildMessage('Edited animated response', true), {
      shouldAnimateTextStreaming: true,
      textRevealPresentation: buildPresentation('0:1:2', true),
    });
    await pause(60);

    expect(root.querySelector('[data-agent-streaming-shell]')).not.toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell-animated]')).not.toBeNull();
  });

  it('uses the final expanded shell without decorative motion when animation is disabled', async () => {
    renderBubble(buildMessage('Immediate local response', true), {
      shouldAnimateTextStreaming: false,
      textRevealPresentation: buildPresentation('0:1:no-motion', true),
    });
    await pause(20);

    expect(root.querySelector('[data-agent-streaming-shell]')).not.toBeNull();
    expect(root.querySelector('[data-agent-streaming-shell-animated]')).toBeNull();
  });

  function renderBubble(
    message: AgentMessage,
    props: Partial<React.ComponentProps<typeof MessageBubble>>,
  ) {
    TeactDOM.render(<MessageBubble message={message} {...props} />, root);
  }

  function getStreamingText() {
    return root.querySelector('[data-agent-streaming-text]') as HTMLElement;
  }

  function getStaticText() {
    return root.querySelector('[data-agent-static-text]') as HTMLElement;
  }
});

function buildMessage(text: string, isStreaming = false): AgentMessage {
  return {
    id: 1,
    text,
    isOutgoing: false,
    isStreaming: isStreaming || undefined,
    timestamp: 1,
  };
}

function buildPresentation(
  key: string,
  shouldRevealFromStart: boolean,
  status: TextRevealPresentation['status'] = 'active',
): TextRevealPresentation {
  return {
    key,
    status,
    shouldRevealFromStart,
  };
}

function buildAnimationEndEvent(animationName: string) {
  const event = new Event('animationend', { bubbles: true });
  Object.defineProperty(event, 'animationName', { value: animationName });
  return event;
}

function restoreProperty(target: object, property: PropertyKey, descriptor?: PropertyDescriptor) {
  if (descriptor) {
    Object.defineProperty(target, property, descriptor);
  } else {
    Reflect.deleteProperty(target, property);
  }
}
