import { clamp } from '../math';
import { smooth } from './surfaceMotion';

/** Finger glow timing of iOS `CardTouchSpotMotion` (PR #13087, fc251ae9). Time is in seconds. */
const STEP = 1 / 60;
const DELAY = 0.15;
const DURATION = 0.67;
const REST = 0.0002;

export function createCardTouchGlow() {
  let value = [0.5, 0.5, 0];
  let target = [...value];
  let velocity = [0, 0, 0];
  let remainder = 0;
  let heldTime = 0;
  let appearance = 0;
  let isFollowing = false;

  function isSettled() {
    return !(isFollowing && appearance < 1) && value.every((v, i) => Math.abs(v - target[i]) <= REST)
      && velocity.every((v) => Math.abs(v) <= REST);
  }

  return {
    get light() {
      return {
        x: clamp((value[0] - 0.5) * 2 * 1.15, -1, 1),
        y: clamp((value[1] - 0.5) * 2 * 1.15, -1, 1),
        opacity: clamp(value[2], 0, 1) * appearance,
      };
    },
    get isSettled() { return isSettled(); },
    press(x: number, y: number, isBegin = false) {
      if (isBegin || !isFollowing) {
        heldTime = 0;
        appearance = 0;
        value[2] = 0;
        velocity[2] = 0;
      }

      isFollowing = true;
      target = [(clamp(x, -1, 1) + 1) / 2, (clamp(y, -1, 1) + 1) / 2, 1];
    },
    release() {
      isFollowing = false;
      target = [0.5, 0.5, 0];
    },
    reset() {
      value = [0.5, 0.5, 0];
      target = [...value];
      velocity = [0, 0, 0];
      remainder = 0;
      heldTime = 0;
      appearance = 0;
      isFollowing = false;
    },
    advance(dt: number) {
      if (dt <= 0 || !Number.isFinite(dt)) return;

      remainder += Math.min(dt, 0.1);

      while (remainder + 1e-12 >= STEP) {
        remainder = Math.max(0, remainder - STEP);

        if (isFollowing) {
          heldTime += STEP;
          appearance = smooth((heldTime - DELAY) / DURATION);
        }

        const stiffness = isFollowing ? 0.066 : 0.01;
        const damping = isFollowing ? 0.25 : 0.06;

        value = value.map((v, i) => {
          velocity[i] = (velocity[i] + (target[i] - v) * stiffness) * (1 - damping);

          return v + velocity[i];
        });
      }

      if (isSettled()) {
        value = [...target];
        velocity = [0, 0, 0];
      }
    },
  };
}
