import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { AnimationLevel } from '../../global/types';

import { ANIMATION_LEVEL_MIN } from '../../config';
import { forceMutation } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import { createAgentEdgeGlowRenderer } from './helpers/agentEdgeGlowRenderer';
import { getIsDarkTheme } from './helpers/agentGlowPalette';

import { useMediaQuery } from '../../hooks/useMediaQuery';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentEdgeGlow.module.scss';

interface OwnProps {
  isActive: boolean;
  animationLevel: AnimationLevel;
}

const CLOSE_DURATION = 400;
// The glow draws at most 60 frames a second, as on iOS. A frame due a little early still draws, so a 60 Hz display
// gets every one.
const MINIMUM_FRAME_INTERVAL_MS = 1000 / 60 - 2;

/**
 * The glow of the chat's edges while the Agent thinks, drawn by the iOS shader: a thin, almost white core line along
 * the edges giving off a bloom and a haze inward, blue and purple stretches running along it at their own speeds, and
 * faint lights drifting behind the composer. Where WebGL is not available, CSS draws it as near as it can.
 */
function AgentEdgeGlow({ isActive, animationLevel }: OwnProps) {
  const { ref, shouldRender } = useShowTransition({
    isOpen: isActive,
    withShouldRender: true,
    closeDuration: CLOSE_DURATION,
    className: false,
  });
  const canvasRef = useRef<HTMLCanvasElement>();
  const [hasRenderer, setHasRenderer] = useState(true);
  const isReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  // The lights stand still where motion is off, so the glow is drawn once, at the start of its loop
  const isStill = isReducedMotion || animationLevel === ANIMATION_LEVEL_MIN;

  useEffect(() => {
    const root = ref.current;
    const canvas = canvasRef.current;
    if (!shouldRender || !root || !canvas) return undefined;

    const renderer = createAgentEdgeGlowRenderer(canvas);
    if (!renderer) {
      setHasRenderer(false);
      return undefined;
    }

    const startedAt = performance.now();
    let frame: number | undefined;
    let lastFrameAt = 0;
    const render = (now: number) => {
      lastFrameAt = now;
      renderer.render(isStill ? 0 : (now - startedAt) / 1000, getIsDarkTheme());
    };
    const tick = (now: number) => {
      if (now - lastFrameAt >= MINIMUM_FRAME_INTERVAL_MS) render(now);
      frame = requestAnimationFrame(tick);
    };
    // It runs in the measure phase, from the effect and the observer. The canvas takes its size in the same frame, so
    // the glow is never drawn stretched from the size it had.
    const fit = () => {
      const { width, height } = root.getBoundingClientRect();
      const radius = parseFloat(getComputedStyle(root).borderTopLeftRadius) || 0;
      forceMutation(() => {
        renderer.resize(width, height, radius);
        render(performance.now());
      }, canvas);
    };
    const resizeObserver = new ResizeObserver(fit);
    resizeObserver.observe(root);
    fit();
    if (!isStill) frame = requestAnimationFrame(tick);

    const handleContextLost = () => {
      if (frame !== undefined) cancelAnimationFrame(frame);
      frame = undefined;
      setHasRenderer(false);
    };
    canvas.addEventListener('webglcontextlost', handleContextLost);

    return () => {
      if (frame !== undefined) cancelAnimationFrame(frame);
      resizeObserver.disconnect();
      canvas.removeEventListener('webglcontextlost', handleContextLost);
      renderer.destroy();
    };
  }, [isStill, ref, shouldRender]);

  if (!shouldRender) return undefined;

  return (
    <div ref={ref} className={buildClassName(styles.root, !hasRenderer && styles.fallback)} aria-hidden>
      {hasRenderer ? (
        // A renderer releases its context as it ends, so the next one draws on a canvas of its own
        <canvas key={isStill ? 'still' : 'moving'} ref={canvasRef} className={styles.canvas} />
      ) : renderFallback()}
    </div>
  );
}

// The stretches turn along the edges under a mask that gives them the bloom's and the haze's falloff, the core line
// lies over them, and two faint lights sway near the bottom
function renderFallback() {
  return (
    <>
      <div className={styles.stretches}>
        <div className={styles.blueStretches} />
        <div className={styles.purpleStretches} />
      </div>
      <div className={styles.core} />
      <div className={styles.lights} />
    </>
  );
}

export default memo(AgentEdgeGlow);
