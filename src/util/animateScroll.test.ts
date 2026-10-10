import {
  disableStrict, enableStrict, requestMutation, setHandler,
} from '../lib/fasterdom/fasterdom';
import animateScroll, { isAnimatingScroll, restartScrollAnimation } from './animateScroll';

const FRAME_DURATION = 16;

let pendingAnimationFrames: FrameRequestCallback[] = [];

describe('animateScroll', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    pendingAnimationFrames = [];
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      pendingAnimationFrames.push(callback);
      return pendingAnimationFrames.length;
    });
  });

  afterEach(async () => {
    await runFrames(100);
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('eases towards the target within a distance-based duration', async () => {
    const container = createContainer({ scrollHeight: 700, clientHeight: 500 });
    const onEnd = jest.fn();

    requestMutation(animateScroll(container, getBottomScrollTop, { onEnd }));
    await runFrames(12);

    expect(container.scrollTop).toBeGreaterThan(0);
    expect(container.scrollTop).toBeLessThan(200);
    expect(isAnimatingScroll(container)).toBe(true);
    expect(container.style.scrollBehavior).toBe('auto');
    expect(onEnd).not.toHaveBeenCalled();

    // A 200 px path takes 375 ms
    await runFrames(12);

    expect(container.scrollTop).toBe(200);
    expect(isAnimatingScroll(container)).toBe(false);
    expect(container.style.scrollBehavior).toBe('');
    expect(onEnd).toHaveBeenCalledTimes(1);
  });

  it('jumps over the part of a long path that exceeds the maximum distance', async () => {
    const container = createContainer({ scrollHeight: 3000, clientHeight: 500 });

    requestMutation(animateScroll(container, getBottomScrollTop, { maxDistance: 800 }));
    await runFrames(1);

    expect(container.scrollTop).toBe(1700);
  });

  it('scrolls instantly when the duration is forced to zero', async () => {
    const container = createContainer({ scrollHeight: 3000, clientHeight: 500 });
    const onEnd = jest.fn();

    requestMutation(animateScroll(container, getBottomScrollTop, { forceDuration: 0, onEnd }));
    await runFrames(1);

    expect(container.scrollTop).toBe(2500);
    expect(isAnimatingScroll(container)).toBe(false);
    expect(onEnd).toHaveBeenCalledTimes(1);
  });

  it('retargets a running animation after the content grows', async () => {
    const container = createContainer({ scrollHeight: 700, clientHeight: 500 });
    const onEnd = jest.fn();

    requestMutation(animateScroll(container, getBottomScrollTop, { onEnd }));
    await runFrames(5);
    Object.defineProperty(container, 'scrollHeight', { configurable: true, value: 900 });
    restartScrollAnimation();
    await runFrames(40);

    expect(container.scrollTop).toBe(400);
    expect(onEnd).toHaveBeenCalledTimes(1);
  });

  it('ends on time even when the target keeps moving', async () => {
    const container = createContainer({ scrollHeight: 700, clientHeight: 500 });
    const onEnd = jest.fn();

    // A 200 px path takes 375 ms, so 30 frames are more than enough for it to finish
    requestMutation(animateScroll(container, getBottomScrollTop, { onEnd }));
    for (let i = 0; i < 30; i++) {
      Object.defineProperty(container, 'scrollHeight', { configurable: true, value: 700 + i * 50 });
      restartScrollAnimation();

      await runFrames(1);
    }

    expect(isAnimatingScroll(container)).toBe(false);
    expect(onEnd).toHaveBeenCalledTimes(1);
    // The target moved away from its initial 200 px while the animation was running
    expect(container.scrollTop).toBeGreaterThan(200);
  });

  it('reads the layout only in measure phases', async () => {
    const errors: Error[] = [];
    const geometryByElement = new WeakMap<Element, { scrollTop: number; scrollHeight: number; clientHeight: number }>();
    const originalDescriptors = GEOMETRY_PROPS.map((prop) => (
      [prop, Object.getOwnPropertyDescriptor(Element.prototype, prop)] as const
    ));
    // `stricterdom` instruments the prototype getters, so the geometry must be mocked there
    GEOMETRY_PROPS.forEach((prop) => {
      Object.defineProperty(Element.prototype, prop, {
        configurable: true,
        get(this: Element) {
          return geometryByElement.get(this)?.[prop] ?? 0;
        },
        set(this: Element, value: number) {
          const geometry = geometryByElement.get(this);
          if (geometry) geometry[prop] = value;
        },
      });
    });
    const container = document.createElement('div');
    document.body.appendChild(container);
    geometryByElement.set(container, { scrollTop: 0, scrollHeight: 700, clientHeight: 500 });
    setHandler((error) => errors.push(error));
    enableStrict();

    try {
      requestMutation(animateScroll(container, getBottomScrollTop));
      await runFrames(30);

      expect(errors).toEqual([]);
      expect(geometryByElement.get(container)!.scrollTop).toBe(200);
    } finally {
      disableStrict();
      setHandler();
      container.remove();
      originalDescriptors.forEach(([prop, descriptor]) => {
        Object.defineProperty(Element.prototype, prop, descriptor!);
      });
    }
  });
});

const GEOMETRY_PROPS = ['scrollTop', 'scrollHeight', 'clientHeight'] as const;

function createContainer({ scrollHeight, clientHeight }: { scrollHeight: number; clientHeight: number }) {
  const container = document.createElement('div');
  let scrollTop = 0;

  Object.defineProperties(container, {
    scrollHeight: { configurable: true, value: scrollHeight },
    clientHeight: { configurable: true, value: clientHeight },
    scrollTop: {
      configurable: true,
      get: () => scrollTop,
      set: (value: number) => {
        scrollTop = value;
      },
    },
  });

  return container;
}

function getBottomScrollTop(container: HTMLElement) {
  return container.scrollHeight - container.clientHeight;
}

async function runFrames(count: number) {
  for (let i = 0; i < count; i++) {
    jest.advanceTimersByTime(FRAME_DURATION);
    const callbacks = pendingAnimationFrames;
    pendingAnimationFrames = [];
    callbacks.forEach((callback) => callback(Date.now()));

    // `fasterdom` runs its mutation phases in a promise chain after the measure phase
    for (let j = 0; j < 5; j++) {
      await Promise.resolve();
    }
  }
}
