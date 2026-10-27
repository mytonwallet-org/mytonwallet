import { lerp } from '../math';
import { smooth } from './surfaceMotion';

/** Coordinates are normalized */
interface SurfaceLight {
  tilt: readonly number[];
  touch: readonly number[];
  /** Rotation of the Gram light in radians */
  gramRotation: number;
  activity: number;
  press?: number;
  isTouchActive?: boolean;
  touchExtent?: number;
}

export interface SurfaceFrame extends SurfaceLight {
  time: number;
  blobTime: number;
}

const CARD_LIGHT_RESUME_DURATION = 0.28;
export const CARD_LIGHT_INTERACTIVE_TAIL = 0.4;

// Animation frames can arrive slightly early, so a frame rate limit accepts a frame this much before its interval ends
export const EARLY_FRAME_MARGIN_MS = 4;

export const lightFrameRate = (now: number, interactiveUntil: number, isResuming: boolean) =>
  isResuming || now < interactiveUntil ? 60 : 30;

export const resumeProgress = (elapsed: number) => smooth(elapsed / CARD_LIGHT_RESUME_DURATION);
const shortAngle = (delta: number) => Math.atan2(Math.sin(delta), Math.cos(delta));

export function restingSurfaceFrame(): SurfaceFrame {
  return {
    time: 0,
    blobTime: 0,
    tilt: [0, 0],
    touch: [0, 0, 0],
    isTouchActive: false,
    gramRotation: 0,
    activity: 0,
    press: 0,
  };
}

/** Compares with the last drawn frame rather than the previous input, so slow movement still adds up to a redraw */
export function visuallyMatches(a: SurfaceLight, b: SurfaceLight) {
  return (
    isClose(a.tilt[0], b.tilt[0], 0.00015)
    && isClose(a.tilt[1], b.tilt[1], 0.00015)
    && isClose(a.touch[0], b.touch[0], 0.00015)
    && isClose(a.touch[1], b.touch[1], 0.00015)
    && isClose(a.touch[2], b.touch[2], 0.0005)
    && a.isTouchActive === b.isTouchActive
    && isClose(a.activity, b.activity, 0.0005)
    && isClose(a.press, b.press, 0.0005)
    && isClose(a.touchExtent, b.touchExtent, 0.00015)
    && Math.abs(shortAngle(a.gramRotation - b.gramRotation)) <= 0.0002
  );
}

export function blendLight<T extends SurfaceLight>(from: T, to: T, elapsed: number): T {
  const t = resumeProgress(elapsed);

  if (t === 0) {
    return from;
  }

  if (t === 1) {
    return to;
  }

  const vector = (a: readonly number[], b: readonly number[]) => b.map((v, i) => lerp(a[i] ?? v, v, t));
  const scalar = (a: number | undefined, b: number | undefined, fallback: number) =>
    a === undefined && b === undefined ? undefined : lerp(a ?? fallback, b ?? fallback, t);

  return {
    ...to,
    tilt: vector(from.tilt, to.tilt),
    touch: vector(from.touch, to.touch),
    gramRotation: from.gramRotation + shortAngle(to.gramRotation - from.gramRotation) * t,
    activity: lerp(from.activity, to.activity, t),
    press: scalar(from.press, to.press, 0),
    isTouchActive: from.isTouchActive || to.isTouchActive,
    touchExtent: scalar(from.touchExtent, to.touchExtent, 0),
  };
}

export function createSurfaceResume() {
  let isActive = false;
  let last: SurfaceFrame | undefined;
  let from: SurfaceFrame | undefined;
  let startedAt: number | undefined;

  return {
    get last() {
      return last;
    },
    get isResuming() {
      return Boolean(from);
    },
    seed(frame: SurfaceFrame) {
      last = frame;
    },
    suspend() {
      isActive = false;
      from = undefined;
      startedAt = undefined;
    },
    activate(isInstant = false) {
      if (isActive) {
        return;
      }

      isActive = true;
      from = isInstant ? undefined : last;
      startedAt = undefined;
    },
    frame(target: SurfaceFrame, now: number): SurfaceFrame {
      if (!from) {
        return target;
      }

      const light = blendLight(
        from,
        target,
        startedAt === undefined ? 0 : Math.max(0, now - startedAt),
      );

      // Until the blend starts, the frame keeps the old wave and spot time along with the old light
      return {
        ...light,
        time: startedAt === undefined ? from.time : target.time,
        blobTime: startedAt === undefined ? from.blobTime : target.blobTime,
      };
    },
    presented(frame: SurfaceFrame, now: number) {
      last = frame;

      if (!from) {
        return;
      }

      startedAt ??= now;

      if (now - startedAt >= CARD_LIGHT_RESUME_DURATION) {
        from = undefined;
        startedAt = undefined;
      }
    },
  };
}

function isClose(x: number | undefined, y: number | undefined, epsilon: number) {
  return x === undefined || y === undefined ? x === y : Math.abs(x - y) <= epsilon;
}
