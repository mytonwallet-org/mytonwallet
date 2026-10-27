import type { CardSurfaceProfile, SurfaceFrame } from './surfaceRenderer';
import type { CardArtworkLayers } from './svgLayers';
import type { CardController } from './types';

import { forceMutation } from '../../lib/fasterdom/fasterdom';
import { logDebugError } from '../logs';
import {
  CARD_LIGHT_INTERACTIVE_TAIL,
  createSurfaceResume,
  EARLY_FRAME_MARGIN_MS,
  lightFrameRate,
  restingSurfaceFrame,
  visuallyMatches,
} from './surfaceLight';
import { createCardMotionClock, createLightActivity, createSurfaceLight, getGramLightRotation } from './surfaceMotion';
import { surfaceRenderer } from './surfaceRenderer';
import { getCardTouchGlowExtent } from './touchGlowTexture';

import { getIsInBackground } from '../../hooks/useBackgroundMode';

const FRAME_MS = 1000 / 60;

interface Options {
  canvas: HTMLCanvasElement;
  card: HTMLElement;
  profile: CardSurfaceProfile;
  layers: Promise<CardArtworkLayers>;
  controller: CardController;
  getIsDisabled: () => boolean;
  onPresent: (tilt: readonly number[], width: number, height: number) => void;
  onReadyChange: (isReady: boolean) => void;
}

export type CardSurfaceLoop = ReturnType<typeof startCardSurface>;

/**
 * Runs the frame loop of the card surface: decides when a new frame is needed and draws it with the renderer.
 * The loop stops while the card is off screen or the tab is hidden. In the background, the card keeps a still frame.
 */
export function startCardSurface({
  canvas,
  card,
  profile,
  layers,
  controller,
  getIsDisabled,
  onPresent,
  onReadyChange,
}: Options) {
  const light = createSurfaceLight();
  const clock = createCardMotionClock();
  const gpu = createSurfaceResume();
  const content = createSurfaceResume();
  // NFT and Gram artwork moves on its own, so these cards keep drawing at rest
  const hasIdleMotion = profile.isCustom || profile.isGram;
  let activity = createLightActivity();
  let renderer: ReturnType<typeof surfaceRenderer> | undefined;
  let published: SurfaceFrame | undefined;
  let presentedClock: ReturnType<typeof clock.snapshot> | undefined;
  let interactiveUntil = 0;
  let isStopped = false;
  let isActive = false;
  let isVisible = true;
  let isPresented = false;
  let shouldDrawGpu = true;
  let shouldPublishContent = true;
  let rafId = 0;
  let lastAt = 0;
  let previous = 0;
  let lastTickAt = 0;
  let clockAt = 0;
  let width = card.clientWidth;
  let height = card.clientHeight;
  let cornerRadius = parseFloat(getComputedStyle(card).borderTopLeftRadius) || 0;
  let pixelRatio = devicePixelRatio;
  let touchExtent = getCardTouchGlowExtent(width);

  const restFrame = () => ({ ...restingSurfaceFrame(), touchExtent });

  content.seed(restFrame());

  function getIsShown() {
    return isVisible && !document.hidden;
  }

  function setPresented(value: boolean) {
    if (isPresented === value) return;

    isPresented = value;
    onReadyChange(value);
  }

  function dropRenderer() {
    cancelAnimationFrame(rafId);
    rafId = 0;
    renderer = undefined;
    shouldDrawGpu = true;
    setPresented(false);
  }

  function present(frame: SurfaceFrame) {
    let isDrawn: boolean;

    try {
      // Resizing the canvas does not change the layout, since its CSS size is fixed
      isDrawn = forceMutation(() => renderer!.draw(frame, width, height, cornerRadius), canvas);
    } catch (error) {
      logDebugError('CardSurface draw failed', error);
      renderer!.destroy();
      dropRenderer();

      return false;
    }

    // `draw` returns false while the WebGL context is lost
    if (!isDrawn) return false;

    onPresent(frame.tilt, width, height);
    setPresented(true);

    return true;
  }

  function updateActivation(isInstant = false) {
    const shouldBeActive = !getIsDisabled() && getIsShown() && !getIsInBackground();
    if (shouldBeActive === isActive) return;

    isActive = shouldBeActive;
    previous = 0;
    lastTickAt = 0;
    clockAt = 0;

    if (isActive) {
      content.activate();
      gpu.activate(isInstant);
      shouldDrawGpu = true;
      shouldPublishContent = true;
      return;
    }

    // The canvas keeps showing its last frame, and the light later blends from it. The motion starts over from rest.
    gpu.suspend();
    if (presentedClock) clock.restore(presentedClock);
    content.suspend();

    const rest = restFrame();
    content.seed(rest);
    published = rest;
    light.reset();
    activity = createLightActivity();
  }

  function schedule() {
    rafId = requestAnimationFrame(tick);
  }

  function tick(now: number) {
    rafId = 0;

    if (isStopped || !renderer) return;

    updateActivation();

    if (!getIsShown() || width <= 0 || height <= 0) return;

    // While disabled or in the background, the card shows a still frame. It is drawn once, so a card that starts
    // in an unfocused window still gets its surface, and is redrawn only after a size change.
    if (!isActive) {
      if (shouldDrawGpu) {
        const rest = restFrame();

        if (present(rest)) {
          gpu.seed(rest);
          shouldDrawGpu = false;
        } else if (renderer) {
          schedule();
        }
      }
      return;
    }

    // The light and the finger glow update at 60 fps even when the background moves at a lower rate
    if (lastTickAt && now - lastTickAt < FRAME_MS - EARLY_FRAME_MARGIN_MS) {
      schedule();
      return;
    }

    lastTickAt = lastTickAt ? now - ((now - lastTickAt) % FRAME_MS) : now;

    const dt = previous ? Math.min(0.1, (now - previous) / 1000) : 0;
    previous = now;

    const seconds = now / 1000;
    const { motion } = controller;
    const press = motion?.press[2] ?? 0;
    light.advance(dt, motion?.pointer);
    activity.advance(press, dt);

    const frame = content.frame({
      time: clock.waveTime,
      blobTime: clock.spotTime,
      tilt: [...light.tilt],
      touch: [motion?.light.x ?? 0, motion?.light.y ?? 0, motion?.light.opacity ?? 0],
      touchExtent,
      isTouchActive: Boolean(motion?.pointer || (motion?.light.opacity ?? 0) > 0),
      gramRotation: getGramLightRotation(motion?.press ?? [0, 0, 0], height / width),
      activity: profile.isGram ? activity.value : 0,
      press,
    }, seconds);
    const isLightChanged = !published || !visuallyMatches(frame, published);

    if (shouldPublishContent || isLightChanged) {
      published = frame;
      if (isLightChanged) interactiveUntil = seconds + CARD_LIGHT_INTERACTIVE_TAIL;
      shouldPublishContent = false;
    }

    content.presented(frame, seconds);

    if (hasIdleMotion && press > 0) {
      interactiveUntil = seconds + CARD_LIGHT_INTERACTIVE_TAIL;
    }

    const interval = 1000 / lightFrameRate(seconds, interactiveUntil, gpu.isResuming || content.isResuming);
    const isChanged = !gpu.last || !visuallyMatches(frame, gpu.last);
    const shouldDrawGpuFrame = shouldDrawGpu || hasIdleMotion || isChanged || gpu.isResuming;

    if (shouldDrawGpuFrame && (shouldDrawGpu || interval === FRAME_MS || now - lastAt >= interval - 1)) {
      const elapsed = clockAt ? Math.min(0.1, (now - clockAt) / 1000) : 0;

      if (hasIdleMotion) {
        clock.advance(elapsed, Math.max(published!.press ?? 0, published!.activity));
      }

      const gpuFrame = gpu.frame({ ...published!, time: clock.waveTime, blobTime: clock.spotTime }, seconds);

      if (present(gpuFrame)) {
        // The blend from the old frame starts counting only once this frame is actually drawn
        gpu.presented(gpuFrame, seconds);
        presentedClock = clock.snapshot();
        lastAt = !lastAt || shouldDrawGpu ? now : now - ((now - lastAt) % interval);
        clockAt = now;
        shouldDrawGpu = false;
      } else {
        shouldDrawGpu = true;
        if (presentedClock) clock.restore(presentedClock);
      }
    }

    if (!renderer) return;

    if (hasIdleMotion || shouldDrawGpu || gpu.isResuming || content.isResuming
      || isLightChanged || seconds < interactiveUntil) {
      schedule();
    } else {
      previous = 0;
    }
  }

  function start() {
    if (isStopped || rafId || !renderer || !getIsShown()) return;

    previous ||= performance.now() - FRAME_MS;
    schedule();
  }

  function refresh() {
    updateActivation();
    shouldDrawGpu ||= getIsDisabled();
    shouldPublishContent = true;
    start();
  }

  function wake() {
    if (isActive) start();
  }

  function updateGeometry() {
    const radius = parseFloat(getComputedStyle(card).borderTopLeftRadius) || 0;
    if (width === card.clientWidth && height === card.clientHeight
      && cornerRadius === radius && pixelRatio === devicePixelRatio) return;

    pixelRatio = devicePixelRatio;
    width = card.clientWidth;
    height = card.clientHeight;
    cornerRadius = radius;
    touchExtent = getCardTouchGlowExtent(width);
    shouldDrawGpu = true;
    shouldPublishContent = true;
    start();
  }

  function handleContextLost(e: Event) {
    // Without `preventDefault` the browser never restores the context
    e.preventDefault();
    dropRenderer();
  }

  function createRenderer() {
    void layers
      .then((artwork) => {
        if (isStopped) return;

        renderer = surfaceRenderer(canvas, profile, artwork, width);
        updateActivation(true);
        shouldDrawGpu = true;
        start();
      })
      .catch((error: unknown) => {
        if (!isStopped) logDebugError('CardSurface initialization failed', error);
      });
  }

  const resizeObserver = new ResizeObserver(updateGeometry);
  resizeObserver.observe(canvas);

  const intersectionObserver = new IntersectionObserver(([entry]) => {
    isVisible = entry.isIntersecting;
    updateActivation();
    start();
  });
  intersectionObserver.observe(canvas);
  window.addEventListener('resize', updateGeometry);
  document.addEventListener('visibilitychange', refresh);
  const unsubscribeFromBackground = getIsInBackground.subscribe(refresh);
  canvas.addEventListener('webglcontextlost', handleContextLost);
  canvas.addEventListener('webglcontextrestored', createRenderer);
  createRenderer();

  return {
    get isPresented() {
      return isPresented;
    },
    refresh,
    wake,
    stop() {
      isStopped = true;
      cancelAnimationFrame(rafId);
      renderer?.destroy();
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      window.removeEventListener('resize', updateGeometry);
      document.removeEventListener('visibilitychange', refresh);
      unsubscribeFromBackground();
      canvas.removeEventListener('webglcontextlost', handleContextLost);
      canvas.removeEventListener('webglcontextrestored', createRenderer);
    },
  };
}
