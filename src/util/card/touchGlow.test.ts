import reference from '../../../tests/fixtures/cardTouchGlow.json';
import { createCardTouchGlow } from './touchGlow';

it.each(['hold', 'short', 'earlyRelease', 'retouch'])('matches Swift CardTouchSpotMotion: %s', (scenario) => {
  const glow = createCardTouchGlow();
  glow.press(0.7, -0.6, true);

  for (let frame = 1; frame <= 180; frame++) {
    if (scenario === 'short' && frame === 7) glow.release();
    if (['earlyRelease', 'retouch'].includes(scenario) && frame === 25) glow.release();
    if (scenario === 'retouch' && frame === 37) glow.press(-0.7, 0.3, true);
    if (scenario === 'hold' && frame === 31) glow.press(0.4, 0.7);
    if (scenario === 'hold' && frame === 73) glow.release();
    if (scenario === 'retouch' && frame === 91) glow.release();

    glow.advance(1 / 60);

    const native = reference.find((r) => r.scenario === scenario && r.frame === frame);
    if (!native) continue;

    const { x, y, opacity } = glow.light;
    [x, y, opacity].forEach((v, i) => expect(v).toBeCloseTo(native.light[i], 12));
  }
});

it('uses a fixed 60 Hz accumulator at 30, 60 and 120 Hz', () => {
  const samples = [30, 60, 120].map((hz) => {
    const glow = createCardTouchGlow();
    glow.press(0.7, -0.6, true);
    for (let i = 0; i < hz / 2; i++) glow.advance(1 / hz);

    const pressed = glow.light;
    glow.release();
    for (let i = 0; i < hz / 2; i++) glow.advance(1 / hz);

    return [pressed, glow.light];
  });

  expect(samples[1]).toEqual(samples[0]);
  expect(samples[2]).toEqual(samples[0]);
});

it('starts after 150 ms, becomes full after the 670 ms ramp and resets on a new down', () => {
  const glow = createCardTouchGlow();
  glow.press(1, -1, true);
  for (let i = 0; i < 9; i++) glow.advance(1 / 60);
  expect(glow.light.opacity).toBeLessThan(1e-12);
  glow.advance(1 / 60);
  expect(glow.light.opacity).toBeGreaterThan(0);
  for (let i = 0; i < 40; i++) glow.advance(1 / 60);
  expect(glow.light.opacity).toBe(1);
  glow.release();
  glow.press(-1, 1, true);
  expect(glow.light.opacity).toBe(0);
});

it('never grows appearance after an early release or catches up time spent inactive', () => {
  const glow = createCardTouchGlow();
  glow.press(0.5, 0.5, true);
  for (let i = 0; i < 24; i++) glow.advance(1 / 60);

  const opacity = glow.light.opacity;
  glow.release();

  for (let i = 0; i < 180; i++) {
    glow.advance(1 / 60);
    expect(glow.light.opacity).toBeLessThanOrEqual(opacity + 1e-12);
  }

  glow.reset();
  glow.press(0.5, 0.5, true);
  glow.advance(5);
  expect(glow.light.opacity).toBe(0);
});
