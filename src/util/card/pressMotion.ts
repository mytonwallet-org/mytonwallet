import { clamp } from '../math';

/** Press settings of the iOS home card (PR #13087, fc251ae9). Angles are in degrees, time in seconds. */
const ANGLE = 12 * Math.PI / 180;
const DEPTH = 12 / 8;
const RELEASE_FREQUENCY = 13.9529;
const MINIMUM_PRESS_SECONDS = 0.07;

type CardPressValue = readonly [number, number, number];

export function createCardPressMotion() {
  let value = [0, 0, 0];
  let velocity = [0, 0, 0];
  let target = [0, 0, 0];

  function isSettled() {
    return value.every((v, i) => Math.abs(v - target[i]) < 0.00015)
      && velocity.every((v) => Math.abs(v) < 0.002);
  }

  return {
    get value(): CardPressValue { return value as [number, number, number]; },
    get isSettled() { return isSettled(); },
    press(x: number, y: number) {
      x = clamp(x, -1, 1);
      y = clamp(y, -1, 1);

      const length = Math.max(1, Math.hypot(x, y));
      target = [x / length, y / length, 1];
    },
    release() { target = [0, 0, 0]; },
    reset() {
      value = [0, 0, 0];
      velocity = [0, 0, 0];
      target = [0, 0, 0];
    },
    advance(dt: number) {
      if (dt <= 0 || !Number.isFinite(dt)) return;

      const frequency = target[2] > 0 ? 28 : RELEASE_FREQUENCY;

      // Exact step of a critically damped spring, so the frame rate does not change the path
      const decay = Math.exp(-frequency * dt);

      value = value.map((v, i) => {
        const offset = v - target[i];
        const term = velocity[i] + offset * frequency;
        velocity[i] = (velocity[i] - term * frequency * dt) * decay;

        return target[i] + (offset + term * dt) * decay;
      });

      if (isSettled()) {
        value = [...target];
        velocity = [0, 0, 0];
      }
    },
  };
}

export function getCardPressMatrix([x, y, engagement]: CardPressValue, width: number): number[] {
  if (x === 0 && y === 0 && engagement === 0) {
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  }

  const ax = -y * ANGLE;
  const ay = x * ANGLE;
  const sx = Math.sin(ax);
  const cx = Math.cos(ax);
  const sy = Math.sin(ay);
  const cy = Math.cos(ay);
  const distance = Math.max(650, width * 2.5);
  const push = engagement * DEPTH;
  const scale = 1 - 0.01 * push;

  // `matrix3d` of perspective * translate * rotateX * rotateY * scale, checked against the iOS matrix
  return [
    cy * scale, sx * sy * scale, -cx * sy * scale, cx * sy * scale / distance,
    0, cx * scale, sx * scale, -sx * scale / distance,
    sy, -sx * cy, cx * cy, -cx * cy / distance,
    0, 0, -4 * push, 1 + 4 * push / distance,
  ];
}

export function createCardPressTimeline() {
  const motion = createCardPressMotion();
  let minimumRemaining = 0;
  let releaseRemaining: number | undefined;

  return {
    get value() { return motion.value; },
    get isSettled() { return releaseRemaining === undefined && motion.isSettled; },
    press(x: number, y: number, isBegin: boolean) {
      releaseRemaining = undefined;
      if (isBegin) minimumRemaining = MINIMUM_PRESS_SECONDS;
      motion.press(x, y);
    },
    releaseImmediately() {
      minimumRemaining = 0;
      releaseRemaining = undefined;
      motion.release();
    },
    release() {
      // Even a tap that starts and ends within one frame keeps the card pressed for at least 70 ms
      if (minimumRemaining > 0) releaseRemaining = minimumRemaining;
      else motion.release();
    },
    advance(dt: number) {
      minimumRemaining = Math.max(0, minimumRemaining - dt);

      if (releaseRemaining !== undefined) {
        if (releaseRemaining <= dt) {
          releaseRemaining = undefined;
          motion.release();
        } else {
          releaseRemaining -= dt;
        }
      }

      motion.advance(dt);
    },
    reset() {
      minimumRemaining = 0;
      releaseRemaining = undefined;
      motion.reset();
    },
  };
}
