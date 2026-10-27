import reference from '../../../tests/fixtures/cardPressMotion.json';
import { createCardPressMotion, createCardPressTimeline, getCardPressMatrix } from './pressMotion';

// Expected values come from the iOS code (`CardPressMotion.swift` with Core Animation), not from this one.
// iOS PR #13087, angle 12, depth 1.5, release frequency 13.9529.
it('matches native poses and all 16 matrix entries through press, movement and release', () => {
  for (const point of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]]) {
    for (const width of [320, 358, 450]) {
      const frames = reference.filter((r) => r.width === width && r.point.join() === point.join());
      if (!frames.length) continue;

      const motion = createCardPressMotion();
      motion.press(point[0], point[1]);

      for (let frame = 1; frame <= 120; frame++) {
        if (frame === 31) motion.press(-point[0] * 0.4, -point[1] * 0.4);
        if (frame === 61) motion.release();
        motion.advance(1 / 60);

        const expected = frames.find((r) => r.frame === frame);
        if (!expected) continue;

        motion.value.forEach((v, i) => expect(v).toBeCloseTo(expected.value[i], 12));
        getCardPressMatrix(motion.value, width).forEach((v, i) => expect(v).toBeCloseTo(expected.matrix[i], 12));
      }
    }
  }
});

it('keeps the same physics at 30, 60 and 120 Hz', () => {
  const results = [30, 60, 120].map((hz) => {
    const motion = createCardPressMotion();
    motion.press(0.8, -0.6);
    for (let i = 0; i < hz / 5; i++) motion.advance(1 / hz);

    const pressed = [...motion.value];
    motion.release();
    for (let i = 0; i < hz / 5; i++) motion.advance(1 / hz);

    return [...pressed, ...motion.value];
  });
  results.slice(1).forEach((r) => r.forEach((v, i) => expect(v).toBeCloseTo(results[0][i], 12)));
});

it.each([[1, 1], [-1, 1], [1, -1], [-1, -1]])('pushes the touched corner away: %s,%s', (x, y) => {
  const motion = createCardPressMotion();
  motion.press(x, y);
  motion.advance(1);
  expect(Math.hypot(motion.value[0], motion.value[1])).toBeCloseTo(1, 12);

  const matrix = getCardPressMatrix(motion.value, 358);
  const z = x * 179 * matrix[2] + y * 104 * matrix[6] + matrix[14];
  expect(z).toBeLessThan(0);
  expect(matrix[14]).toBe(-6);
});

it('has a monotonic release after a held press and settles to exact identity', () => {
  const motion = createCardPressMotion();
  motion.press(1, 0);
  motion.advance(1);
  motion.release();

  let engagement = 1;

  for (let i = 0; i < 180; i++) {
    motion.advance(1 / 60);
    expect(motion.value[2]).toBeGreaterThanOrEqual(0);
    expect(motion.value[2]).toBeLessThanOrEqual(engagement);
    engagement = motion.value[2];
  }

  expect(motion.isSettled).toBe(true);
  expect(getCardPressMatrix(motion.value, 358)).toEqual([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
});

it('preserves a down/up in one frame and clears it on reset', () => {
  const motion = createCardPressTimeline();
  motion.press(1, -1, true);
  motion.release();
  for (let i = 0; i < 4; i++) motion.advance(1 / 60);
  expect(motion.value[2]).toBeGreaterThan(0.5);
  motion.reset();
  expect(motion.value).toEqual([0, 0, 0]);
  expect(motion.isSettled).toBe(true);
});
