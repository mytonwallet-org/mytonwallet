import type { Point } from './surfaceMotion';

import { clamp } from '../math';
import { spring } from './surfaceMotion';

const MAX_ROTATION_DEGREES = 15;
const ROTATION_PER_CARD_OFFSET = 1.7;
const PERSPECTIVE_PER_WIDTH = 150 / 84;
const PIVOT_PER_WIDTH = 0.6;
const SNAP_FREQUENCY = 40;
const SNAP_SETTLED_DISTANCE_PX = 0.5;
const SNAP_SETTLED_VELOCITY_PX_PER_S = 12;
const DEFAULT_IDLE_DELAY_MS = 16;

/** Native cover flow `P * T(pivot) * Ry * T(-pivot)`, including projected inner-edge correction */
export function getCarouselPose(cardOffset: number, width: number) {
  const angle = (-clamp(cardOffset * ROTATION_PER_CARD_OFFSET, -1, 1) * MAX_ROTATION_DEGREES * Math.PI) / 180;
  const perspective = PERSPECTIVE_PER_WIDTH * width;
  const pivot = PIVOT_PER_WIDTH * width * (cardOffset > 0 ? 1 : -1);
  const cos = Math.cos(angle);
  const sin = Math.sin(angle);
  const translateX = pivot * (1 - cos);
  const translateZ = pivot * sin;
  const innerEdge = cardOffset > 0 ? -width / 2 : width / 2;
  const projectedInnerEdge = (innerEdge * cos + translateX)
    / ((innerEdge * sin) / perspective + 1 - translateZ / perspective);

  return {
    matrix: [
      cos, 0, -sin, sin / perspective,
      0, 1, 0, 0,
      sin, 0, cos, -cos / perspective,
      translateX, 0, translateZ, 1 - translateZ / perspective,
    ],
    edgeCorrection: (innerEdge - projectedInnerEdge) * Math.min(1, Math.abs(cardOffset)),
  };
}

/** Critically damped snapping with velocity continuity across interrupted selections */
export function createCarouselSnap(initialPosition: number, target: number, initialVelocity = 0) {
  const distance = target - initialPosition;
  const position: Point = [initialPosition, 0];
  const targetPoint: Point = [target, 0];

  // The limits keep a fast fling from reversing away from the selected card or overshooting it
  const velocity: Point = [
    Math.sign(distance) * Math.min(
      Math.max(0, initialVelocity * Math.sign(distance)),
      Math.abs(distance) * SNAP_FREQUENCY,
    ),
    0,
  ];

  return {
    get position() {
      return position[0];
    },
    get velocity() {
      return velocity[0];
    },
    get isSettled() {
      return Math.abs(target - position[0]) < SNAP_SETTLED_DISTANCE_PX
        && Math.abs(velocity[0]) < SNAP_SETTLED_VELOCITY_PX_PER_S;
    },
    advance(elapsedSeconds: number) {
      spring(position, velocity, targetPoint, SNAP_FREQUENCY, Math.max(0, elapsedSeconds));

      return position[0];
    },
  };
}

/** Waits briefly, then lets the input and scroll events of the next frame cancel the callback */
export function createCarouselIdle(onIdle: NoneToVoidFunction, delayMs = DEFAULT_IDLE_DELAY_MS) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let frame = 0;

  function cancel() {
    clearTimeout(timer);
    cancelAnimationFrame(frame);
    frame = 0;
  }

  return {
    cancel,
    schedule() {
      cancel();

      timer = setTimeout(() => {
        frame = requestAnimationFrame(() => {
          frame = 0;
          onIdle();
        });
      }, delayMs);
    },
  };
}
