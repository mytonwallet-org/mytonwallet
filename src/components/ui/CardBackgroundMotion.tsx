import type { ElementRef } from '../../lib/teact/teact';
import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import type { CardArtworkLayers } from '../../util/cardSvgLayers';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import {
  CARD_MOTION_BOOST_FPS, CARD_MOTION_FPS, createCardMotionClock, createCardMotionRenderer, getCardMotionSeed,
} from '../../util/cardBackgroundMotion';
import { loadCardArtworkLayers } from '../../util/cardSvgLayers';

import { useMediaQuery } from '../../hooks/useMediaQuery';

import styles from './CardBackgroundMotion.module.scss';

interface OwnProps {
  imageRef: ElementRef<HTMLImageElement>;
  /** The artwork source, split into separately animated layers when it is the generator's SVG */
  imageUrl: string;
  /** The NFT address determines where the wave starts in its cycle */
  motionKey: string;
  isDisabled?: boolean;
  className?: string;
}

/**
 * Animation frames can arrive slightly early, so the 4 ms margin keeps the rate near the target
 */
const FRAME_MARGIN_MS = 4;
const IDLE_FRAME_INTERVAL_MS = (1000 / CARD_MOTION_FPS) - FRAME_MARGIN_MS;
const BOOST_FRAME_INTERVAL_MS = (1000 / CARD_MOTION_BOOST_FPS) - FRAME_MARGIN_MS;

/**
 * The canvas animates a copy of the NFT image over the original.
 * The original image remains visible if WebGL cannot render the canvas.
 */
function CardBackgroundMotion({
  imageRef,
  imageUrl,
  motionKey,
  isDisabled,
  className,
}: OwnProps) {
  const canvasRef = useRef<HTMLCanvasElement>();
  const hasReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  const isMotionDisabled = isDisabled || hasReducedMotion;

  useEffect(() => {
    const canvas = canvasRef.current;
    const image = imageRef.current;
    if (isMotionDisabled || !canvas || !image?.naturalWidth) {
      return undefined;
    }

    let isCancelled = false;
    let stopMotion: NoneToVoidFunction | undefined;

    // Artwork that cannot be split animates as one layer
    void loadCardArtworkLayers(imageUrl).catch(() => undefined).then((layers) => {
      if (isCancelled) return;

      stopMotion = startMotion(canvas, layers ?? {
        base: image, spots: [], contrastColor: -1, contrastOpacity: 0,
      }, getCardMotionSeed(motionKey));
    });

    return () => {
      isCancelled = true;
      stopMotion?.();
    };
  }, [imageRef, imageUrl, isMotionDisabled, motionKey]);

  if (isMotionDisabled) {
    return undefined;
  }

  return <canvas ref={canvasRef} className={buildClassName(styles.canvas, className)} />;
}

export default memo(CardBackgroundMotion);

function startMotion(canvas: HTMLCanvasElement, layers: CardArtworkLayers, seed: number) {
  let renderer: ReturnType<typeof createCardMotionRenderer>;
  try {
    renderer = createCardMotionRenderer(canvas, layers, seed);
  } catch {
    // Cross-origin images without CORS access cannot become WebGL textures, so the original remains visible
    renderer = undefined;
  }

  if (!renderer) return undefined;

  const clock = createCardMotionClock();
  let isCancelled = false;
  let isOnScreen = true;
  let rafId: number | undefined;
  let lastFrameAt = 0;
  let press = 0;

  function drawFrame(now: number) {
    if (isCancelled) return;

    rafId = requestAnimationFrame(drawFrame);

    // The interval follows the last drawn frame's press, so a new press is noticed at most one idle frame late
    const frameInterval = press > 0 || clock.isBoosting ? BOOST_FRAME_INTERVAL_MS : IDLE_FRAME_INTERVAL_MS;
    if (now - lastFrameAt < frameInterval) return;

    // `CardTilt` reports a held or hovered card through this property; the clock speeds the spots up
    press = parseFloat(getComputedStyle(canvas).getPropertyValue('--card-press')) || 0;
    if (lastFrameAt) clock.advance((now - lastFrameAt) / 1000, press);
    lastFrameAt = now;
    renderer!.draw(clock.waveTime, clock.spotTime);
  }

  function start() {
    if (rafId !== undefined || !isOnScreen || document.visibilityState !== 'visible') return;

    // Resume the wave where it stopped, ignoring the time spent paused
    lastFrameAt = 0;
    rafId = requestAnimationFrame(drawFrame);
  }

  function stop() {
    if (rafId === undefined) return;

    cancelAnimationFrame(rafId);
    rafId = undefined;
  }

  let appliedSize = '';

  // `fasterdom` requires the size read and drawing-buffer write in separate phases.
  // Changing the canvas size can trigger `ResizeObserver`, so unchanged sizes are skipped to avoid a loop.
  function syncSize(onDone?: NoneToVoidFunction) {
    requestMeasure(() => {
      if (isCancelled) return;

      const size = renderer!.measure();
      const key = size ? `${size.cssWidth}x${size.cssHeight}` : '';
      if (size && key === appliedSize) {
        onDone?.();
        return;
      }

      requestMutation(() => {
        if (isCancelled) return;

        if (size) {
          appliedSize = key;
          renderer!.applySize(size);
        }
        onDone?.();
      });
    });
  }

  const visibilityObserver = new IntersectionObserver(([entry]) => {
    isOnScreen = entry.isIntersecting;
    if (isOnScreen) start();
    else stop();
  });
  visibilityObserver.observe(canvas);

  const resizeObserver = new ResizeObserver(() => syncSize());
  resizeObserver.observe(canvas);

  function handleTabVisibility() {
    if (document.visibilityState === 'visible') start();
    else stop();
  }

  document.addEventListener('visibilitychange', handleTabVisibility);
  syncSize(start);

  return () => {
    isCancelled = true;
    stop();
    visibilityObserver.disconnect();
    resizeObserver.disconnect();
    document.removeEventListener('visibilitychange', handleTabVisibility);
    renderer.destroy();
  };
}
