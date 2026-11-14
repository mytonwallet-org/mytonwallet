import { createCarouselIdle, createCarouselSnap } from './carouselMotion';

it.each([[-126, 0], [126, 0], [210, 336], [462, 336]])(
  'settles monotonically from %s to %s without overshooting', (from, target) => {
    const motion = createCarouselSnap(from, target, Math.sign(target - from) * 3000);
    let previous = from;

    for (let i = 0; i < 120; i++) {
      const value = motion.advance(1 / 120);

      expect(Math.abs(target - value)).toBeLessThanOrEqual(Math.abs(target - previous));
      expect(value).toBeGreaterThanOrEqual(Math.min(from, target));
      expect(value).toBeLessThanOrEqual(Math.max(from, target));
      previous = value;
    }

    expect(motion.isSettled).toBe(true);
  },
);

it('has the same trajectory at 60 Hz and 120 Hz', () => {
  const at60Hz = createCarouselSnap(210, 336, 250);
  const at120Hz = createCarouselSnap(210, 336, 250);

  for (let i = 0; i < 30; i++) {
    at60Hz.advance(1 / 60);
    at120Hz.advance(1 / 120);
    at120Hz.advance(1 / 120);
  }

  expect(at60Hz.position).toBeCloseTo(at120Hz.position, 9);
  expect(at60Hz.velocity).toBeCloseTo(at120Hz.velocity, 9);
});

it('retargets a forward swipe without resetting position or velocity', () => {
  const first = createCarouselSnap(0, 336);

  first.advance(0.12);

  const next = createCarouselSnap(first.position, 672, first.velocity);

  expect(next.position).toBe(first.position);
  expect(next.velocity).toBe(first.velocity);
  expect(next.advance(1 / 120) - first.position).toBeLessThan(20);
});

it('eases into a snap after a stationary release', () => {
  const motion = createCarouselSnap(210, 336);

  expect(motion.advance(1 / 120) - 210).toBeLessThan(6);
});

it('finishes a full-card snap within 240 ms, without a long invisible tail', () => {
  const motion = createCarouselSnap(0, 336);

  for (let i = 0; i < 28; i++) motion.advance(1 / 120);

  expect(motion.isSettled).toBe(true);
});

describe('native scroll handoff', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it('does not start a snap in the gap between 60 Hz input packets', () => {
    const start = jest.fn();
    const idle = createCarouselIdle(start);

    for (let packet = 0; packet < 12; packet++) {
      idle.schedule();
      jest.advanceTimersByTime(17);
    }

    expect(start).not.toHaveBeenCalled();
    jest.advanceTimersByTime(32);
    expect(start).toHaveBeenCalledTimes(1);
  });

  it('cancels a queued frame when a new gesture starts', () => {
    const start = jest.fn();
    const idle = createCarouselIdle(start);

    idle.schedule();
    jest.advanceTimersByTime(16);
    idle.cancel();
    jest.runAllTimers();
    expect(start).not.toHaveBeenCalled();
  });

  it('does not take over native touch momentum when Safari delivers sparse scroll events', () => {
    const settle = jest.fn();
    const idle = createCarouselIdle(settle, 120);

    for (let packet = 0; packet < 8; packet++) {
      idle.schedule();
      jest.advanceTimersByTime(80);
    }

    expect(settle).not.toHaveBeenCalled();
    jest.advanceTimersByTime(80);
    expect(settle).toHaveBeenCalledTimes(1);
  });
});
