import { createCardMotionClock } from './cardBackgroundMotion';

it('speeds the spots up while the card is pressed and settles after release', () => {
  const idle = createCardMotionClock();
  const pressed = createCardMotionClock();
  for (let i = 0; i < 60; i++) {
    idle.advance(1 / 60, 0);
    pressed.advance(1 / 60, 1);
  }

  expect(idle.spotTime).toBeCloseTo(1);
  expect(idle.waveTime).toBeCloseTo(1.55);
  expect(idle.isBoosting).toBe(false);
  // Full boost triples the speed, minus the short ramp at the start
  expect(pressed.spotTime).toBeGreaterThan(2.5);
  expect(pressed.spotTime).toBeLessThan(3);
  expect(pressed.isBoosting).toBe(true);

  for (let i = 0; i < 60 * 5; i++) {
    pressed.advance(1 / 60, 0);
  }
  expect(pressed.isBoosting).toBe(false);
});
