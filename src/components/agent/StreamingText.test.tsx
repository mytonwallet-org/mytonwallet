import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import {
  disableStrict, enableStrict, setHandler, setPhase,
} from '../../lib/fasterdom/stricterdom';
import { pause } from '../../util/schedulers';

import StreamingText from './StreamingText';

describe('StreamingText', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
  });

  it('renders completed text immediately without replaying it', async () => {
    await renderText({
      text: 'Completed 👨‍👩‍👧‍👦 text',
      isStreaming: false,
      shouldAnimate: true,
    });

    expect(getTextElement().textContent).toBe('Completed 👨‍👩‍👧‍👦 text');
    expect(getTextElement().getAttribute('aria-busy')).toBe('false');
  });

  it('reveals a buffered completed response from the start for a fresh turn', async () => {
    await renderText({
      text: 'Buffered completed response',
      isStreaming: false,
      shouldAnimate: true,
      revealSessionKey: 'turn-a',
      shouldRevealFromStart: true,
    });

    expect(getTextElement().textContent).not.toBe('Buffered completed response');
    expect(getTextElement().getAttribute('aria-busy')).toBe('true');

    await pause(700);

    expect(getTextElement().textContent).toBe('Buffered completed response');
    expect(getTextElement().getAttribute('aria-busy')).toBe('false');
  });

  it('paces a streaming prefix and drains it on completion', async () => {
    const onRevealProgress = jest.fn();

    await renderText({
      text: 'Streaming text',
      isStreaming: true,
      shouldAnimate: true,
      revealSessionKey: 'turn-streaming',
      shouldRevealFromStart: true,
      onRevealProgress,
    });

    expect('Streaming text'.startsWith(getTextElement().textContent!)).toBe(true);
    expect(getTextElement().textContent).not.toBe('Streaming text');
    expect(getTextElement().getAttribute('aria-busy')).toBe('true');

    await pause(100);

    const streamedPrefix = getTextElement().textContent!;
    expect(streamedPrefix.length).toBeGreaterThan(0);
    expect('Streaming text'.startsWith(streamedPrefix)).toBe(true);
    expect(onRevealProgress).toHaveBeenCalled();

    await renderText({
      text: 'Streaming text',
      isStreaming: false,
      shouldAnimate: true,
      revealSessionKey: 'turn-streaming',
      shouldRevealFromStart: true,
      onRevealProgress,
    });
    await pause(240);

    expect(getTextElement().textContent).toBe('Streaming text');
    expect(getTextElement().getAttribute('aria-busy')).toBe('false');
  });

  it('shows the current prefix immediately on a streaming remount and paces new chunks', async () => {
    await renderText({
      text: 'Current prefix',
      isStreaming: true,
      shouldAnimate: true,
    });

    expect(getTextElement().textContent).toBe('Current prefix');

    await renderText({
      text: 'Current prefix with a new chunk',
      isStreaming: true,
      shouldAnimate: true,
    });

    expect(getTextElement().textContent).toBe('Current prefix');
    expect(getTextElement().getAttribute('aria-busy')).toBe('true');

    await renderText({
      text: 'Current prefix with a new chunk',
      isStreaming: false,
      shouldAnimate: true,
    });
    await pause(500);

    expect(getTextElement().textContent).toBe('Current prefix with a new chunk');
    expect(getTextElement().getAttribute('aria-busy')).toBe('false');
  });

  it('settles a consumed completed session after remount without replaying it', async () => {
    const onRevealComplete = jest.fn();

    await renderText({
      text: 'Completed while unmounted',
      isStreaming: false,
      shouldAnimate: true,
      revealSessionKey: 'turn-remounted-complete',
      shouldRevealFromStart: false,
      onRevealComplete,
    });
    await pause(40);

    expect(getTextElement().textContent).toBe('Completed while unmounted');
    expect(getTextElement().getAttribute('aria-busy')).toBe('false');
    expect(onRevealComplete).toHaveBeenCalledTimes(1);
  });

  it('shows the authoritative text immediately when animation is disabled', async () => {
    const onRevealComplete = jest.fn();

    await renderText({
      text: 'No animation',
      isStreaming: true,
      shouldAnimate: false,
      revealSessionKey: 'turn-no-motion',
      shouldRevealFromStart: true,
      onRevealComplete,
    });

    expect(getTextElement().textContent).toBe('No animation');
    expect(getTextElement().getAttribute('aria-busy')).toBe('false');
    expect(onRevealComplete).toHaveBeenCalledTimes(1);
  });

  it('notifies once after the final visual drain completes', async () => {
    const onRevealComplete = jest.fn();

    await renderText({
      text: 'Final visual drain',
      isStreaming: true,
      shouldAnimate: true,
      revealSessionKey: 'turn-complete',
      shouldRevealFromStart: true,
      onRevealComplete,
    });
    await renderText({
      text: 'Final visual drain',
      isStreaming: false,
      shouldAnimate: true,
      revealSessionKey: 'turn-complete',
      shouldRevealFromStart: true,
      onRevealComplete,
    });
    await pause(600);

    expect(onRevealComplete).toHaveBeenCalledTimes(1);

    await renderText({
      text: 'Final visual drain',
      isStreaming: false,
      shouldAnimate: true,
      revealSessionKey: 'turn-complete',
      shouldRevealFromStart: true,
      onRevealComplete,
    });

    expect(onRevealComplete).toHaveBeenCalledTimes(1);
  });

  it('renders Markdown', async () => {
    await renderText({
      text: '**Rendered Markdown**',
      isStreaming: false,
      shouldAnimate: false,
    });

    expect(getTextElement().querySelector('strong')?.textContent).toBe('Rendered Markdown');
  });

  it('keeps completed Markdown blocks mounted while the tail changes', async () => {
    await renderText({
      text: 'Stable paragraph.\n\nMutable tail',
      isStreaming: true,
      shouldAnimate: false,
    });

    const stableBlock = root.querySelector('[data-agent-markdown-offset="0"]');
    expect(stableBlock?.textContent).toBe('Stable paragraph.');

    await renderText({
      text: 'Stable paragraph.\n\nMutable tail extended',
      isStreaming: true,
      shouldAnimate: false,
    });

    expect(root.querySelector('[data-agent-markdown-offset="0"]')).toBe(stableBlock);
    expect(getTextElement().textContent).toBe('Stable paragraph.Mutable tail extended');
    expect(getTextElement().tagName).toBe('DIV');
  });

  it('smooths the container height when a new visual line appears', async () => {
    let naturalHeight = 20;
    const originalGetBoundingClientRect = HTMLElement.prototype.getBoundingClientRect;

    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function getBoundingClientRect(
      this: HTMLElement,
    ) {
      if (this.matches('[data-agent-streaming-text]')) {
        return buildRect(naturalHeight);
      }

      return originalGetBoundingClientRect.call(this);
    });

    await renderText({
      text: 'First line',
      isStreaming: true,
      shouldAnimate: true,
    });

    const container = getTextElement().parentElement!;
    expect(container.style.height).toBe('20px');

    naturalHeight = 40;
    await renderText({
      text: 'First line followed by enough text to wrap onto another visual line',
      isStreaming: true,
      shouldAnimate: true,
    });

    const growingHeight = parseFloat(container.style.height);
    expect(growingHeight).toBeGreaterThanOrEqual(20);
    expect(growingHeight).toBeLessThan(40);

    await pause(650);

    expect(parseFloat(container.style.height)).toBeCloseTo(40, 0);
  });

  it('keeps revealing new lines when ResizeObserver does not deliver during the drain', async () => {
    const originalResizeObserver = Object.getOwnPropertyDescriptor(globalThis, 'ResizeObserver');
    const originalGetBoundingClientRect = HTMLElement.prototype.getBoundingClientRect;
    const measuredTextLengths: number[] = [];

    class MockResizeObserver {
      constructor(callback: ResizeObserverCallback) {
        void callback;
      }

      observe = jest.fn();

      unobserve = jest.fn();

      disconnect = jest.fn();
    }

    Object.defineProperty(globalThis, 'ResizeObserver', {
      configurable: true,
      value: MockResizeObserver,
    });
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function getBoundingClientRect(
      this: HTMLElement,
    ) {
      if (this.matches('[data-agent-streaming-text]')) {
        const textLength = this.textContent?.length ?? 0;
        measuredTextLengths.push(textLength);
        return buildRect(Math.max(20, Math.ceil(textLength / 14) * 20));
      }

      return originalGetBoundingClientRect.call(this);
    });

    const initialText = 'First line.';
    const finalText = `${initialText} ${'Long continuation '.repeat(5).trimEnd()}`;

    try {
      await renderText({
        text: initialText,
        isStreaming: true,
        shouldAnimate: true,
        revealSessionKey: 'turn-with-multiple-lines',
        shouldRevealFromStart: true,
      });
      await pause(300);

      const container = getTextElement().parentElement!;
      expect(getTextElement().textContent).toBe(initialText);
      expect(container.style.height).toBe('20px');

      await renderText({
        text: finalText,
        isStreaming: false,
        shouldAnimate: true,
        revealSessionKey: 'turn-with-multiple-lines',
        shouldRevealFromStart: true,
      });
      await pause(100);

      expect(getTextElement().getAttribute('aria-busy')).toBe('true');
      expect(getTextElement().textContent).not.toBe(finalText);
      expect(getTextElement().textContent!.length).toBeGreaterThan(14);
      expect(Math.max(...measuredTextLengths)).toBeGreaterThan(14);
      expect(parseFloat(container.style.height)).toBeGreaterThan(20);

      await pause(1200);

      expect(getTextElement().textContent).toBe(finalText);
      expect(getTextElement().getAttribute('aria-busy')).toBe('false');
      expect(container.style.height).toBe('');
    } finally {
      restoreProperty(globalThis, 'ResizeObserver', originalResizeObserver);
    }
  });

  it('keeps a bounded pool of grouped settling fragments for soft reveal', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const animations: Animation[] = [];
    const animate = jest.fn(() => {
      const animation = buildAnimation();
      animations.push(animation);
      return animation;
    });

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: animate,
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    mockOpaqueBackground();

    try {
      await renderText({
        text: 'Reveal edge text keeps settling '.repeat(20),
        isStreaming: true,
        shouldAnimate: true,
        revealSessionKey: 'reveal-edge-pool',
        shouldRevealFromStart: true,
      });
      await pause(650);

      const layer = root.querySelector('[data-agent-streaming-reveal-edge]')!;
      expect(animate).toHaveBeenCalledWith(
        [
          {
            offset: 0,
            opacity: 0.16,
            filter: 'blur(0.3rem)',
            transform: 'translateY(0.08rem)',
          },
          {
            offset: 0.45,
            opacity: 0.72,
            filter: 'blur(0.08rem)',
            transform: 'translateY(0.02rem)',
          },
          {
            offset: 1,
            opacity: 1,
            filter: 'blur(0)',
            transform: 'translateY(0)',
          },
        ],
        {
          duration: 200,
          easing: 'cubic-bezier(0.2, 0.7, 0.2, 1)',
          fill: 'forwards',
        },
      );
      expect(animate.mock.calls.length).toBeGreaterThan(24);
      expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-cover]')).toHaveLength(24);
      expect(layer.querySelectorAll('*')).toHaveLength(48);
      expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-text]').length).toBe(
        layer.querySelectorAll('[data-agent-streaming-reveal-edge-cover]').length,
      );
      expect(animations.some((animation) => (animation.cancel as jest.Mock).mock.calls.length > 0)).toBe(true);
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('waits for the final reveal edge group before reporting completion', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const animations: Animation[] = [];

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: jest.fn(() => {
        const animation = buildAnimation();
        animations.push(animation);
        return animation;
      }),
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    mockOpaqueBackground();

    try {
      const onRevealComplete = jest.fn();
      await renderText({
        text: 'Edge completion waits for visual settling',
        isStreaming: false,
        shouldAnimate: true,
        revealSessionKey: 'edge-complete',
        shouldRevealFromStart: true,
        onRevealComplete,
      });
      await pause(650);

      expect(animations.length).toBeGreaterThan(0);
      expect(onRevealComplete).not.toHaveBeenCalled();

      animations.forEach((animation) => animation.onfinish?.({} as AnimationPlaybackEvent));
      await pause(20);

      expect(onRevealComplete).toHaveBeenCalledTimes(1);
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('registers a short final edge before reporting completion', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const animations: Animation[] = [];

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: jest.fn(() => {
        const animation = buildAnimation();
        animations.push(animation);
        return animation;
      }),
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    mockOpaqueBackground();

    try {
      const onRevealComplete = jest.fn();
      await renderText({
        text: 'Short',
        isStreaming: false,
        shouldAnimate: true,
        revealSessionKey: 'short-edge-complete',
        shouldRevealFromStart: true,
        onRevealComplete,
      });
      await pause(360);

      expect(animations.length).toBeGreaterThan(0);
      expect(onRevealComplete).not.toHaveBeenCalled();

      animations.forEach((animation) => animation.onfinish?.({} as AnimationPlaybackEvent));
      await pause(20);

      expect(onRevealComplete).toHaveBeenCalledTimes(1);
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('uses an inherited streaming shell color for transparent edge sources', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: jest.fn(() => buildAnimation()),
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    root.style.setProperty('--agent-reveal-edge-background', 'rgb(12, 34, 56)');

    try {
      await renderText({
        text: 'Transparent shell edge',
        isStreaming: true,
        shouldAnimate: true,
        revealSessionKey: 'transparent-edge',
        shouldRevealFromStart: true,
      });
      await pause(80);

      const cover = root.querySelector('[data-agent-streaming-reveal-edge-cover]') as HTMLElement;
      expect(cover.style.backgroundColor).toBe('rgb(12, 34, 56)');
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('composites translucent inline backgrounds into an opaque edge cover', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const getComputedStyle = window.getComputedStyle.bind(window);

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: jest.fn(() => buildAnimation()),
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    jest.spyOn(window, 'getComputedStyle').mockImplementation((element, pseudoElement) => {
      const style = getComputedStyle(element, pseudoElement);
      Object.defineProperty(style, 'backgroundColor', {
        configurable: true,
        value: element instanceof HTMLElement && element.tagName === 'CODE'
          ? 'rgb(0 0 0 / 5%)'
          : 'rgba(0, 0, 0, 0)',
      });
      return style;
    });
    root.style.setProperty('--agent-reveal-edge-background', 'rgb(100 100 100)');

    try {
      await renderText({
        text: '`code`',
        isStreaming: false,
        shouldAnimate: true,
        revealSessionKey: 'inline-code-edge',
        shouldRevealFromStart: true,
      });
      await pause(240);

      const backgroundColors = Array.from(
        root.querySelectorAll<HTMLElement>('[data-agent-streaming-reveal-edge-cover]'),
        (cover) => cover.style.backgroundColor,
      );
      expect(backgroundColors).toContain('rgb(95, 95, 95)');
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('composites a fenced-code background before using the inherited shell color', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const getComputedStyle = window.getComputedStyle.bind(window);

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: jest.fn(() => buildAnimation()),
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    jest.spyOn(window, 'getComputedStyle').mockImplementation((element, pseudoElement) => {
      const style = getComputedStyle(element, pseudoElement);
      Object.defineProperty(style, 'backgroundColor', {
        configurable: true,
        value: element instanceof HTMLElement && element.tagName === 'PRE'
          ? 'rgba(0, 0, 0, 0.05)'
          : element === document.body ? 'rgb(5, 5, 5)' : 'rgba(0, 0, 0, 0)',
      });
      return style;
    });
    root.style.setProperty('--agent-reveal-edge-background', 'rgb(100, 100, 100)');

    try {
      await renderText({
        text: '```\ncode\n```',
        isStreaming: false,
        shouldAnimate: true,
        revealSessionKey: 'fenced-code-edge',
        shouldRevealFromStart: true,
      });
      await pause(240);

      const backgroundColors = Array.from(
        root.querySelectorAll<HTMLElement>('[data-agent-streaming-reveal-edge-cover]'),
        (cover) => cover.style.backgroundColor,
      );
      expect(backgroundColors).toContain('rgb(95, 95, 95)');
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('keeps paced text working when Range and WAAPI are unavailable', async () => {
    await renderText({
      text: 'Fallback text',
      isStreaming: true,
      shouldAnimate: true,
      revealSessionKey: 'fallback-edge',
      shouldRevealFromStart: true,
    });

    await pause(100);

    expect('Fallback text'.startsWith(getTextElement().textContent!)).toBe(true);
    expect(root.querySelector('[data-agent-streaming-reveal-edge]')?.children).toHaveLength(0);
  });

  it('observes natural height and disconnects the observer on unmount', async () => {
    const originalResizeObserver = Object.getOwnPropertyDescriptor(globalThis, 'ResizeObserver');
    const observe = jest.fn();
    const disconnect = jest.fn();

    class MockResizeObserver {
      constructor(callback: ResizeObserverCallback) {
        void callback;
      }

      observe = observe;

      unobserve = jest.fn();

      disconnect = disconnect;
    }

    Object.defineProperty(globalThis, 'ResizeObserver', {
      configurable: true,
      value: MockResizeObserver,
    });

    try {
      await renderText({
        text: 'Observed',
        isStreaming: true,
        shouldAnimate: true,
      });

      expect(observe).toHaveBeenCalledWith(getTextElement());

      TeactDOM.render(undefined, root);
      await pause(60);

      expect(disconnect).toHaveBeenCalled();
    } finally {
      restoreProperty(globalThis, 'ResizeObserver', originalResizeObserver);
    }
  });

  it('cancels pending RAF and edge animation on unmount', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const cancelAnimationFrameSpy = jest.spyOn(window, 'cancelAnimationFrame');
    const animation = buildAnimation();

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: jest.fn(() => animation),
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    mockOpaqueBackground();

    try {
      await renderText({
        text: 'Pending animation ',
        isStreaming: true,
        shouldAnimate: true,
        revealSessionKey: 'pending-unmount',
        shouldRevealFromStart: true,
      });
      await pause(60);

      TeactDOM.render(undefined, root);
      await pause(60);

      expect(cancelAnimationFrameSpy).toHaveBeenCalled();
      expect(animation.cancel).toHaveBeenCalled();
    } finally {
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  it('keeps reveal measurements and mutations in their stricterdom phases', async () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const errors: Error[] = [];
    const animations: Animation[] = [];

    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: jest.fn(() => {
        const animation = buildAnimation();
        animations.push(animation);
        return animation;
      }),
    });
    jest.spyOn(document, 'createRange').mockImplementation(buildRange);
    mockOpaqueBackground();
    disableStrict();
    setPhase('measure');
    setHandler((error) => errors.push(error));
    enableStrict();

    try {
      setPhase('mutate');
      TeactDOM.render(
        <StreamingText
          text="Strict streaming edge lifecycle"
          isStreaming
          shouldAnimate
          revealSessionKey="strict-edge"
          shouldRevealFromStart
        />,
        root,
      );
      await Promise.resolve();
      setPhase('measure');
      await pause(120);

      animations.forEach((animation) => animation.onfinish?.({} as AnimationPlaybackEvent));
      await pause(60);
      setPhase('mutate');
      TeactDOM.render(undefined, root);
      await Promise.resolve();
      setPhase('measure');
      await pause(60);

      expect(errors).toEqual([]);
    } finally {
      disableStrict();
      setHandler();
      setPhase('measure');
      restoreProperty(Element.prototype, 'animate', originalAnimate);
    }
  });

  async function renderText(props: React.ComponentProps<typeof StreamingText>) {
    TeactDOM.render(<StreamingText {...props} />, root);
    await pause(20);
  }

  function getTextElement() {
    return root.querySelector('[data-agent-streaming-text]') as HTMLElement;
  }
});

function buildRect(height: number): DOMRect {
  return {
    x: 0,
    y: 0,
    top: 0,
    right: 100,
    bottom: height,
    left: 0,
    width: 100,
    height,
    toJSON: () => ({}),
  };
}

function buildRange() {
  return {
    setStart: jest.fn(),
    setEnd: jest.fn(),
    getClientRects: () => [buildRect(20)],
  } as unknown as Range;
}

function buildAnimation() {
  return {
    cancel: jest.fn(),
    effect: {
      getComputedTiming: () => ({ progress: 0.4 }),
    },
    playState: 'running',
  } as unknown as Animation;
}

function mockOpaqueBackground() {
  const getComputedStyle = window.getComputedStyle.bind(window);

  jest.spyOn(window, 'getComputedStyle').mockImplementation((element, pseudoElement) => {
    const style = getComputedStyle(element, pseudoElement);

    Object.defineProperty(style, 'backgroundColor', {
      configurable: true,
      value: 'rgb(30, 30, 30)',
    });

    return style;
  });
}

function restoreProperty(
  object: object,
  property: string,
  descriptor?: PropertyDescriptor,
) {
  if (descriptor) {
    Object.defineProperty(object, property, descriptor);
  } else {
    Reflect.deleteProperty(object, property);
  }
}
