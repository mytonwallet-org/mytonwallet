import { clamp } from '../math';

const CARD_MOTION_SPEED = 1.55;
const BOOST_ATTACK_SECONDS = 0.12;
const BOOST_DECAY_SECONDS = 0.65;

export const smooth = (v: number) => {
  const t = clamp(v, 0, 1);

  return t * t * (3 - 2 * t);
};

export const quintic = (v: number) => {
  const t = clamp(v, 0, 1);

  return t * t * t * (t * (t * 6 - 15) + 10);
};

export type Point = [number, number];

interface CardMotionClockSnapshot { waveTime: number; spotTime: number; boost: number }

export function createCardMotionClock() {
  let waveTime = 0;
  let spotTime = 0;
  let boost = 0;

  return {
    snapshot(): CardMotionClockSnapshot { return { waveTime, spotTime, boost }; },
    restore(snapshot: CardMotionClockSnapshot) {
      waveTime = snapshot.waveTime;
      spotTime = snapshot.spotTime;
      boost = snapshot.boost;
    },
    get waveTime() {
      return waveTime;
    },
    get spotTime() {
      return spotTime;
    },
    advance(elapsedSeconds: number, press: number) {
      const target = clamp(press, 0, 1);
      const response = target > boost ? BOOST_ATTACK_SECONDS : BOOST_DECAY_SECONDS;
      const decay = Math.exp(-elapsedSeconds / response);

      // The spot time is accumulated from the current speed, so a press speeds the spots up without making them jump
      const integratedBoost = target * elapsedSeconds + (boost - target) * response * (1 - decay);
      waveTime += elapsedSeconds * CARD_MOTION_SPEED;
      spotTime += elapsedSeconds + 2 * integratedBoost;
      boost = target + (boost - target) * decay;
    },
  };
}

export function createLightActivity() {
  let value = 0;
  let holdRemaining = 0;
  let fadeElapsed = 0;
  let fadeStart = 0;

  return {
    get value() {
      return value;
    },
    advance(press: number, dt: number) {
      if (dt <= 0) return;

      const target = clamp(press, 0, 1);

      if (target > 0) {
        holdRemaining = 1;
        fadeElapsed = 0;
        if (target > value) value += (target - value) * (1 - Math.exp(-dt / 0.08));
      } else if (value > 0) {
        const fadingTime = Math.max(0, dt - holdRemaining);
        holdRemaining = Math.max(0, holdRemaining - dt);

        if (fadingTime <= 0) return;

        if (fadeElapsed === 0) fadeStart = value;
        fadeElapsed = Math.min(2, fadeElapsed + fadingTime);
        value = fadeStart * (1 - smooth(fadeElapsed / 2));
      }
    },
  };
}

export function spring(value: Point, velocity: Point, target: Point, rate: number, dt: number) {
  // Exact step of a critically damped spring, so the frame rate does not change the path
  const decay = Math.exp(-rate * dt);

  for (let i = 0; i < 2; i++) {
    const offset = value[i] - target[i];
    const term = velocity[i] + rate * offset;
    value[i] = target[i] + (offset + term * dt) * decay;
    velocity[i] = (velocity[i] - rate * term * dt) * decay;
  }
}

/** The light tilt follows the pointer and returns to the center without it */
export function createSurfaceLight() {
  const tilt: Point = [0, 0];

  return {
    tilt,
    reset() { tilt.fill(0); },
    advance(dt: number, pointer?: readonly number[]) {
      const amount = 1 - Math.exp(-dt / 0.12);
      for (let i = 0; i < 2; i++) tilt[i] += ((pointer?.[i] ?? 0) - tilt[i]) * amount;
    },
  };
}

/** Rotation of the Gram light in radians, turned by pressing the card off its center */
export function getGramLightRotation(press: readonly number[], aspect: number) {
  const turn = ((-aspect * press[0] + press[1]) * Math.PI) / 3;

  return Math.PI * Math.tanh(turn / Math.PI);
}

/** Mulberry32: a deterministic `[0, 1)` sequence, so the same field always gets the same dust */
export function randomSequence(seed: number) {
  return () => {
    seed = (seed + 0x6D2B79F5) | 0;

    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;

    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
