import {
  blendLight,
  createSurfaceResume,
  lightFrameRate,
  restingSurfaceFrame,
  resumeProgress,
  visuallyMatches,
} from './surfaceLight';

const old = {
  ...restingSurfaceFrame(),
  time: 9,
  blobTime: 4,
  tilt: [0.7, -0.4],
  gramRotation: (179 * Math.PI) / 180,
  touch: [0.3, 0.2, 0.8],
  isTouchActive: true,
  touchExtent: 120,
  activity: 0.8,
};
const target = {
  ...restingSurfaceFrame(),
  time: 10,
  blobTime: 5,
  tilt: [-0.6, 0.3],
  gramRotation: (-179 * Math.PI) / 180,
  touchExtent: 160,
};

it('uses the native 280 ms smoothstep curve in seconds', () => {
  expect(resumeProgress(-1)).toBe(0);
  expect(resumeProgress(0.07)).toBe(0.15625);
  expect(resumeProgress(0.14)).toBe(0.5);
  expect(resumeProgress(0.28)).toBe(1);
  expect(resumeProgress(1)).toBe(1);
});

it.each([30, 60, 120])('starts at the frozen frame and reaches live input at %i fps', (fps) => {
  const resume = createSurfaceResume();
  resume.seed(old);
  resume.suspend();
  resume.activate();

  const first = resume.frame(target, 100);
  expect(first).toEqual(old);

  // Frames that are requested but not drawn yet don't use up the blend
  expect(resume.frame(target, 200)).toEqual(old);
  resume.presented(first, 200);

  for (let i = 1; i <= Math.ceil(fps * 0.28); i++) {
    const now = 200 + i / fps;
    const frame = resume.frame(target, now);
    resume.presented(frame, now);
  }

  expect(resume.last).toEqual(target);
  expect(resume.isResuming).toBe(false);
});

it('continues an interrupted transition from the actual intermediate frame and keeps its phase', () => {
  const resume = createSurfaceResume();
  resume.seed(old);
  resume.activate();
  resume.presented(resume.frame(target, 1), 1);

  const middle = resume.frame(target, 1.12);
  resume.presented(middle, 1.12);
  expect(middle.tilt).not.toEqual(old.tilt);
  resume.suspend();
  resume.activate();
  expect(resume.frame({ ...target, time: 100, blobTime: 100 }, 50)).toEqual(middle);
});

it('keeps live input and does not restart on a repeated activation/configuration update', () => {
  const resume = createSurfaceResume();
  resume.seed(old);
  resume.activate();
  resume.presented(resume.frame(target, 0), 0);
  resume.activate();
  resume.activate();

  const moved = { ...target, tilt: [0.1, 0.9] };
  expect(resume.frame(moved, 0.28)).toEqual(moved);
});

it('uses a short arc for the Gram angle and interpolates light channels', () => {
  const half = blendLight(old, target, 0.14);
  expect(half.gramRotation).toBeCloseTo(Math.PI);
  expect(half.touchExtent).toBe(140);
});

it('filters noise against the last publication while accumulating slow movement', () => {
  let published = restingSurfaceFrame();
  let count = 0;

  for (let i = 1; i <= 100; i++) {
    const candidate = { ...published, tilt: [i * 0.00001, 0], gramRotation: i * 0.00001 };

    if (!visuallyMatches(candidate, published)) {
      published = candidate;
      count++;
    }
  }

  expect(count).toBeGreaterThan(0);
  expect(count).toBeLessThan(10);
  expect(published.tilt[0]).toBeGreaterThan(0.0008);

  expect(visuallyMatches({ ...published, isTouchActive: true, touch: [0, 0, 0] }, published)).toBe(
    false,
  );
});

it('compares Gram across its angle seam without treating a full turn as new light', () => {
  expect(visuallyMatches({ ...old, gramRotation: old.gramRotation + 2 * Math.PI }, old)).toBe(
    true,
  );
});

it('separates content reset from the retained GPU light', () => {
  const gpu = createSurfaceResume();
  const content = createSurfaceResume();
  gpu.seed(old);
  content.seed(old);
  gpu.suspend();
  content.suspend();
  content.seed(restingSurfaceFrame());
  gpu.activate();
  content.activate();
  expect(gpu.frame(target, 0)).toEqual(old);
  expect(content.frame(target, 0)).toEqual(restingSurfaceFrame());
});

it('keeps 60 fps for the 400 ms interactive tail and for resume, then returns to 30 fps', () => {
  expect(lightFrameRate(1.39, 1.4, false)).toBe(60);
  expect(lightFrameRate(1.4, 1.4, false)).toBe(30);
  expect(lightFrameRate(5, 1.4, true)).toBe(60);
});
