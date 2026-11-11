import {
  disableStrict, enableStrict, requestMutation, setHandler,
} from '../lib/fasterdom/fasterdom';
import animateScroll, {
  cancelScrollAnimation, isAnimatingScroll, restartScrollAnimation, trackWheelInertia,
} from './animateScroll';

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

  it('lets go of a jump that waits for momentum when nothing moves the container', async () => {
    const container = createContainer({ scrollHeight: 3000, clientHeight: 500 });

    requestMutation(animateScroll(container, getBottomScrollTop, { forceDuration: 0, shouldWaitForMomentum: true }));
    await runFrames(1);

    expect(container.scrollTop).toBe(2500);
    expect(isAnimatingScroll(container)).toBe(true);
    await runFrames(10);
    expect(isAnimatingScroll(container)).toBe(false);
    expect(container.scrollTop).toBe(2500);
  });

  it('holds an instant jump against a fling or a trackpad\'s inertia from before it', async () => {
    const container = createContainer({ scrollHeight: 3000, clientHeight: 500 });
    const onEnd = jest.fn();
    const wheel = (deltaY: number) => {
      jest.advanceTimersByTime(FRAME_DURATION);
      const event = new WheelEvent('wheel', { deltaY });
      Object.defineProperty(event, 'timeStamp', { value: Date.now() });
      return trackWheelInertia(container, event);
    };
    wheel(-30);
    wheel(-28);

    requestMutation(animateScroll(container, getBottomScrollTop, {
      forceDuration: 0, shouldWaitForMomentum: true, onEnd,
    }));
    await runFrames(1);
    expect(container.scrollTop).toBe(2500);
    // The inertia of the swipe carries on after the jump
    expect(wheel(-26)).toBe(true);

    for (let i = 0; i < 15; i++) {
      moveOnItsOwn(container, -6);
      await runFrames(1);
      expect(container.scrollTop).toBe(2500);
    }
    expect(isAnimatingScroll(container)).toBe(true);

    const onScroll = jest.fn();
    container.addEventListener('scroll', onScroll);
    await runFrames(20);
    expect(isAnimatingScroll(container)).toBe(false);
    expect(container.scrollTop).toBe(2500);
    expect(onScroll).toHaveBeenCalledTimes(1);
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

  it('stays at the target while a fling from before goes on moving the container, and lets go once it rests',
    async () => {
      const container = createContainer({ scrollHeight: 700, clientHeight: 500 });
      const onEnd = jest.fn();

      requestMutation(animateScroll(container, getBottomScrollTop, { onEnd }));
      // The fling pulls the container back up by a few pixels between the animation's frames
      for (let i = 0; i < 40; i++) {
        await runFrames(1);
        moveOnItsOwn(container, -4);
      }

      expect(onEnd).toHaveBeenCalledTimes(1);
      expect(isAnimatingScroll(container)).toBe(true);
      await runFrames(1);
      expect(container.scrollTop).toBe(200);

      // At rest, the container is let go and stays at the target, and its listeners learn where it rests
      const onScroll = jest.fn();
      container.addEventListener('scroll', onScroll);
      await runFrames(20);
      expect(isAnimatingScroll(container)).toBe(false);
      expect(container.scrollTop).toBe(200);
      expect(onEnd).toHaveBeenCalledTimes(1);
      expect(onScroll).toHaveBeenCalledTimes(1);
    });

  it('lets go of the target at once when the scroll is cancelled', async () => {
    const container = createContainer({ scrollHeight: 700, clientHeight: 500 });

    requestMutation(animateScroll(container, getBottomScrollTop));
    for (let i = 0; i < 30; i++) {
      await runFrames(1);
      moveOnItsOwn(container, -4);
    }
    expect(isAnimatingScroll(container)).toBe(true);

    cancelScrollAnimation();
    moveOnItsOwn(container, -50);
    await runFrames(2);

    expect(isAnimatingScroll(container)).toBe(false);
    expect(container.scrollTop).toBe(146);
  });

  // A touch or a wheel cancels the scroll from an event handler, outside the mutation phase
  it('gives the container its scroll behavior back in a mutation once the scroll is cancelled', async () => {
    const container = createContainer({ scrollHeight: 700, clientHeight: 500 });
    requestMutation(animateScroll(container, getBottomScrollTop));
    await runFrames(3);

    cancelScrollAnimation();

    expect(container.style.scrollBehavior).toBe('auto');
    await runFrames(1);
    expect(container.style.scrollBehavior).toBe('');
  });

  it('keeps the scroll behavior of an animation that starts before the cancelled one gives it back', async () => {
    const container = createContainer({ scrollHeight: 700, clientHeight: 500 });
    requestMutation(animateScroll(container, getBottomScrollTop));
    await runFrames(3);

    // The next animation is already on its way to the mutation phase as the user cancels the running one
    requestMutation(animateScroll(container, () => 0));
    cancelScrollAnimation();
    await runFrames(1);

    expect(isAnimatingScroll(container)).toBe(true);
    expect(container.style.scrollBehavior).toBe('auto');
  });

  it('tells the inertia of a swipe from before the animation from a new swipe', async () => {
    const container = createContainer({ scrollHeight: 3000, clientHeight: 500 });
    const wheel = (deltaY: number, delay = FRAME_DURATION) => {
      jest.advanceTimersByTime(delay);
      // The event's own time is when the trackpad made it, which jsdom does not take from the fake clock
      const event = new WheelEvent('wheel', { deltaY });
      Object.defineProperty(event, 'timeStamp', { value: Date.now() });
      return trackWheelInertia(container, event);
    };

    // A swipe up whose inertia dies down: nothing is animated yet, so none of it is left over
    expect([-30, -40, -38, -35].map((deltaY) => wheel(deltaY))).toEqual([false, false, false, false]);

    requestMutation(animateScroll(container, getBottomScrollTop));
    await runFrames(1);

    // The inertia carries on after the scroll button is pressed
    expect([-33, -30, -30, -26].map((deltaY) => wheel(deltaY))).toEqual([true, true, true, true]);
    // A swipe that speeds up, one the other way and one after a pause are new
    expect(wheel(-60)).toBe(false);
    expect(wheel(20)).toBe(false);
    expect(wheel(-10, 150)).toBe(false);
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

// A fling or a trackpad's inertia scrolls the container by itself, which the container reports with a scroll event
function moveOnItsOwn(container: HTMLElement, distance: number) {
  container.scrollTop += distance;
  container.dispatchEvent(new Event('scroll'));
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
