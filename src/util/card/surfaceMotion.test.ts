import { createCardMotionClock } from './surfaceMotion';

it('speeds the spots up while the card is pressed and settles after release', () => {
  const idle = createCardMotionClock();
  const pressed = createCardMotionClock();

  for (let i = 0; i < 60; i++) {
    idle.advance(1 / 60, 0);
    pressed.advance(1 / 60, 1);
  }

  expect(idle.spotTime).toBeCloseTo(1);
  expect(idle.waveTime).toBeCloseTo(1.55);

  // Full boost triples the speed, minus the short ramp at the start
  expect(pressed.spotTime).toBeGreaterThan(2.5);
  expect(pressed.spotTime).toBeLessThan(3);

  for (let i = 0; i < 60 * 5; i++) {
    pressed.advance(1 / 60, 0);
  }

  const settled = pressed.spotTime;
  pressed.advance(1, 0);
  expect(pressed.spotTime - settled).toBeCloseTo(1);
});

it('freezes the actually presented artwork phase, including the boost state', () => {
  const clock = createCardMotionClock();
  clock.advance(1, 0.8);

  const presented = clock.snapshot();
  clock.advance(1 / 60, 1);
  clock.restore(presented);
  expect(clock.snapshot()).toEqual(presented);
  clock.advance(0, 0);
  expect(clock.snapshot()).toEqual(presented);
});
