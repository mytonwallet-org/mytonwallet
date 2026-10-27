import { sameBackgroundKey, surfaceBackgroundKey } from './surfaceCache';
import { restingSurfaceFrame } from './surfaceLight';
import { getCardSurfaceProfile } from './surfaceProfile';

const gram = getCardSurfaceProfile(undefined, true);
const frame = restingSurfaceFrame();
const key = (
  next = frame,
  profile = gram,
  spots = 0,
  geometry = [358, 208, 716, 416],
  revision = 1,
) => surfaceBackgroundKey(next, profile, geometry, spots, revision);

it('reuses Gram while star activity and twinkle clocks change', () => {
  expect(sameBackgroundKey(key(), key({ ...frame, time: 10, blobTime: 20, activity: 1 }))).toBe(
    true,
  );
});

it('keeps clocks that move custom artwork and color spots', () => {
  expect(
    sameBackgroundKey(
      key(frame, { ...gram, isCustom: true }),
      key({ ...frame, time: 1 }, { ...gram, isCustom: true }),
    ),
  ).toBe(false);

  expect(sameBackgroundKey(key(frame, gram, 3), key({ ...frame, blobTime: 1 }, gram, 3))).toBe(
    false,
  );
});

it('invalidates for exact light changes, dimensions, DPR, material and replacement textures', () => {
  expect(sameBackgroundKey(key(), key({ ...frame, tilt: [0.000001, 0] }))).toBe(false);
  expect(sameBackgroundKey(key(), key({ ...frame, gramRotation: 0.1 }))).toBe(false);
  expect(sameBackgroundKey(key(), key(frame, gram, 0, [358, 208, 358, 208]))).toBe(false);
  expect(sameBackgroundKey(key(), key(frame, gram, 0, [360, 209, 720, 418]))).toBe(false);
  expect(sameBackgroundKey(key(), key(frame, { ...gram, intensity: 0.1 }))).toBe(false);
  expect(sameBackgroundKey(key(), key(frame, gram, 0, undefined, 2))).toBe(false);
});
