import {
  advanceDriftParticle, advanceDriftParticleStream, createDriftParticle, createDriftParticleStream, setupDriftParticles,
} from './driftParticles';

const CONFIG = { particles: [[27, 65, 10, 0.3]] as const, path: 'M0 0L10 0L5 10Z', pathSize: 10 };

function dispatchPointerEvent(target: EventTarget, type: string, buttons = 0) {
  const event = new MouseEvent(type, { bubbles: true, button: 0, buttons });
  Object.defineProperties(event, { pointerId: { value: 1 }, pointerType: { value: 'mouse' } });
  target.dispatchEvent(event);
}

describe('shared fixed-particle mode', () => {
  let cleanups: (() => void)[];
  let originalPath: typeof Path2D;

  beforeEach(() => {
    jest.useFakeTimers();
    cleanups = [];
    originalPath = window.Path2D;
    window.Path2D = jest.fn() as unknown as typeof Path2D;
  });

  afterEach(() => {
    cleanups.forEach((cleanup) => cleanup());
    window.Path2D = originalPath;
    jest.restoreAllMocks();
    jest.useRealTimers();
  });

  function setup(isStatic = false) {
    const canvas = document.createElement('canvas');
    const target = document.createElement('div');
    document.body.appendChild(target);
    const alphas: number[] = [];
    const context = {
      setTransform: jest.fn(), clearRect: jest.fn(), save: jest.fn(), restore: jest.fn(),
      translate: jest.fn(), scale: jest.fn(), globalAlpha: 1,
      fill: jest.fn(),
    };
    context.fill.mockImplementation(() => {
      alphas.push(context.globalAlpha);
    });
    jest.spyOn(canvas, 'getContext').mockReturnValue(context as unknown as CanvasRenderingContext2D);
    const destroy = setupDriftParticles(canvas, CONFIG, 322, 204, [0.2, 0.6, 1], [0, 8], { target, isStatic });
    cleanups.push(() => {
      destroy();
      target.remove();
    });
    return { target, context, alphas, destroy };
  }

  it('accelerates movement on hover without changing the fade clock', () => {
    const idle = setup();
    const hovered = setup();
    dispatchPointerEvent(hovered.target, 'pointerenter');
    jest.advanceTimersByTime(1000);
    expect(hovered.context.scale.mock.calls).not.toEqual(idle.context.scale.mock.calls);
    expect(hovered.alphas).toEqual(idle.alphas);
  });

  it.each(['pointerup', 'pointercancel', 'lostpointercapture'])('releases a held boost on %s', (event) => {
    const released = setup();
    const held = setup();
    dispatchPointerEvent(released.target, 'pointerdown', 1);
    dispatchPointerEvent(held.target, 'pointerdown', 1);
    jest.advanceTimersByTime(1000);
    dispatchPointerEvent(event === 'lostpointercapture' ? released.target : document.body, event);
    // Window events release all matching pointer IDs, including the control
    dispatchPointerEvent(held.target, 'pointerdown', 1);
    jest.advanceTimersByTime(2000);
    expect(released.context.scale.mock.calls.at(-1)).not.toEqual(held.context.scale.mock.calls.at(-1));
  });

  it('pauses on blur, resumes on focus, and cancels all work on cleanup', () => {
    const { context, target, destroy } = setup();
    dispatchPointerEvent(target, 'pointerdown', 1);
    jest.advanceTimersByTime(1000);
    window.dispatchEvent(new Event('blur'));
    const before = context.fill.mock.calls.length;
    jest.advanceTimersByTime(1000);
    expect(context.fill).toHaveBeenCalledTimes(before);
    window.dispatchEvent(new Event('focus'));
    jest.advanceTimersByTime(1000);
    expect(context.fill.mock.calls.length).toBeGreaterThan(before);
    destroy();
    const after = context.fill.mock.calls.length;
    jest.advanceTimersByTime(1000);
    expect(context.fill).toHaveBeenCalledTimes(after);
  });

  it('renders one still with no interaction or animation loop when motion is disabled', () => {
    const { target, context } = setup(true);
    dispatchPointerEvent(target, 'pointerenter');
    dispatchPointerEvent(target, 'pointerdown', 1);
    jest.advanceTimersByTime(5000);
    expect(context.fill).toHaveBeenCalledTimes(1);
    expect(context.globalAlpha).toBe(0.3);
  });

  it.each([1, 2, 3, 6])('only moves outward and resets while invisible at speed %s', (speed) => {
    const state = createDriftParticle(0);
    let resets = 0;
    for (let frame = 0; frame < 1200; frame++) {
      const before = state.progress;
      advanceDriftParticle(state, 1 / 60, speed);
      if (state.progress < before) {
        expect(state.opacity).toBe(0);
        resets++;
      }
    }
    expect(resets).toBeGreaterThan(2);
  });

  it('keeps the fade duration unchanged when movement accelerates', () => {
    const idle = createDriftParticle(2.6);
    const boosted = createDriftParticle(2.6);
    advanceDriftParticle(idle, 0, 1);
    advanceDriftParticle(boosted, 0, 3);
    for (let frame = 0; frame < 20; frame++) {
      advanceDriftParticle(idle, 1 / 60, 1);
      advanceDriftParticle(boosted, 1 / 60, 3);
      expect(boosted.opacity).toBeCloseTo(idle.opacity, 8);
    }
    expect(boosted.progress).toBeGreaterThan(idle.progress);
  });

  it.each([1, 3, 6])('emits a steady stream instead of cohorts at speed %s', (speed) => {
    const stream = createDriftParticleStream(18);
    const births: number[] = [];
    for (let frame = 0; frame < 1800; frame++) {
      const before = stream.particles.map((particle) => particle.opacity);
      advanceDriftParticleStream(stream, 1 / 60, speed);
      const born = stream.particles.filter((particle, index) => particle.opacity > 0 && before[index] === 0);
      expect(born.length).toBeLessThanOrEqual(1);
      expect(stream.particles.filter((particle) => particle.opacity > 0.1).length).toBeGreaterThan(5);
      if (frame > 600 && born.length) births.push(frame / 60);
    }
    const gaps = births.slice(1).map((time, index) => time - births[index]);
    expect(gaps.length).toBeGreaterThan(30);
    expect(Math.min(...gaps)).toBeGreaterThan(0.08);
    expect(Math.max(...gaps) - Math.min(...gaps)).toBeLessThan(0.04);
  });

  it.each([false, true])('keeps particles visible through acceleration and release (scatter=%s)', (shouldScatter) => {
    const stream = createDriftParticleStream(18, undefined, shouldScatter);
    for (let frame = 0; frame < 2400; frame++) {
      const before = stream.particles.map((particle) => particle.progress);
      const speed = [1, 3, 6, 3, 1][Math.floor(frame / 120) % 5];
      advanceDriftParticleStream(stream, 1 / 60, speed, { shouldScatter });
      stream.particles.forEach((particle, index) => {
        if (particle.progress < before[index]) expect(particle.opacity).toBe(0);
      });
      expect(stream.particles.filter((particle) => particle.opacity > 0.1).length).toBeGreaterThan(5);
    }
  });

  it.each([[3, 2], [6, 3]])('returns the boosted particle pool %s/%s to baseline', (speed, density) => {
    const stream = createDriftParticleStream(18);
    for (let frame = 0; frame < 1800; frame++) {
      advanceDriftParticleStream(stream, 1 / 60, speed, {}, density);
    }
    expect(stream.particles.length).toBe(18 * density);
    expect(stream.particles.filter((particle) => !particle.isWaiting).length).toBeGreaterThan(18 * density - 2);
    for (let frame = 0; frame < 600; frame++) {
      advanceDriftParticleStream(stream, 1 / 60, 1);
    }
    expect(stream.particles.filter((particle) => !particle.isWaiting).length).toBeLessThanOrEqual(18);
  });
});
