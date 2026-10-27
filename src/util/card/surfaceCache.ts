import type { SurfaceFrame } from './surfaceLight';
import type { CardSurfaceProfile } from './surfaceRenderer';

/** Leaves out `activity` and the clocks used only by the Gram stars, which are drawn over the cached background */
export function surfaceBackgroundKey(
  frame: SurfaceFrame,
  profile: CardSurfaceProfile,
  geometry: readonly number[],
  spotCount: number,
  textureRevision: number,
) {
  return [
    ...geometry,
    textureRevision,
    spotCount,
    Number(profile.isCustom),
    Number(profile.isGram),
    profile.seed,
    profile.material,
    profile.intensity,
    profile.shineOpacity,
    profile.gramWidth,
    profile.gramBlur,
    profile.isCustom ? frame.time : 0,
    spotCount ? frame.blobTime : 0,
    ...frame.tilt,
    ...frame.touch,
    frame.gramRotation,
    frame.touchExtent ?? 0,
  ];
}

export function sameBackgroundKey(a: readonly number[] | undefined, b: readonly number[]) {
  return Boolean(a && a.length === b.length && a.every((v, i) => v === b[i]));
}
