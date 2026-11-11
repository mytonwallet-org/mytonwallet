import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getGlobal } from '../../global';

import { ANIMATION_LEVEL_MIN } from '../../config';
import { createAgentFieldGlowRenderer } from './helpers/agentFieldGlowRenderer';

import { useMediaQuery } from '../../hooks/useMediaQuery';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentFieldGlow.module.scss';

interface OwnProps {
  isActive: boolean;
}

const CLOSE_DURATION = 180;

/**
 * The field's glow while its speech is recognized and its transcript comes in, drawn by the iOS shader: lights inside
 * the field and its rim giving off light. Where WebGL is not available, CSS draws it after Android's lights.
 */
function AgentFieldGlow({ isActive }: OwnProps) {
  const { ref, shouldRender } = useShowTransition<HTMLSpanElement>({
    isOpen: isActive,
    withShouldRender: true,
    closeDuration: CLOSE_DURATION,
    className: false,
  });
  const canvasRef = useRef<HTMLCanvasElement>();
  const [hasRenderer, setHasRenderer] = useState(true);
  const isReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');

  useEffect(() => {
    const root = ref.current;
    const canvas = canvasRef.current;
    if (!shouldRender || !root || !canvas) return undefined;

    const renderer = createAgentFieldGlowRenderer(canvas);
    if (!renderer) {
      setHasRenderer(false);
      return undefined;
    }

    // The lights stand still where motion is reduced, so the glow is drawn once, as it starts
    const isStill = isReducedMotion || getGlobal().settings.animationLevel === ANIMATION_LEVEL_MIN;
    const startedAt = performance.now();
    let tint: [number, number, number] = [0, 0, 0];
    let isRtl = false;
    let frame: number | undefined;
    const render = () => {
      const time = isStill ? 0 : (performance.now() - startedAt) / 1000;
      renderer.render(time, tint, isRtl);
    };
    const tick = () => {
      render();
      frame = requestAnimationFrame(tick);
    };
    const fit = () => {
      const field = root.getBoundingClientRect();
      const style = getComputedStyle(root);
      renderer.resize({
        width: field.width,
        height: field.height,
        cornerRadius: parseFloat(style.borderTopLeftRadius) || 0,
        margin: (canvas.getBoundingClientRect().width - field.width) / 2,
      });
      // The canvas takes the accent as its colour
      tint = parseRgb(getComputedStyle(canvas).color);
      isRtl = style.direction === 'rtl';
      render();
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
  }, [isReducedMotion, ref, shouldRender]);

  if (!shouldRender) return undefined;

  return (
    <span ref={ref} className={styles.root} aria-hidden>
      {hasRenderer ? (
        // A renderer releases its context as it ends, so the next one draws on a canvas of its own
        <canvas key={isReducedMotion ? 'still' : 'moving'} ref={canvasRef} className={styles.canvas} />
      ) : renderFallback()}
    </span>
  );
}

// Android's lights drift through the field, and its border gives light: a bright core and a bloom round it, with lit
// stretches running along it
function renderFallback() {
  return (
    <>
      <span className={styles.lights}>
        <span className={styles.bottomTrack}>
          <span className={styles.bottomLight} />
        </span>
        <span className={styles.driftTrack}>
          <span className={styles.driftRise}>
            <span className={styles.driftLight} />
          </span>
        </span>
        <span className={styles.sideTrack}>
          <span className={styles.sideLight} />
        </span>
      </span>
      <span className={styles.bloom}>
        <span className={styles.bloomRing}>
          <span className={styles.bloomSweep} />
        </span>
      </span>
      <span className={styles.core}>
        <span className={styles.coreSweep} />
      </span>
    </>
  );
}

// A computed colour, `rgb(r, g, b)` or `rgba(r, g, b, a)`, as RGB from 0 to 1
function parseRgb(color: string): [number, number, number] {
  const [red = 0, green = 0, blue = 0] = color.match(/[\d.]+/g)?.map(Number) ?? [];
  return [red / 255, green / 255, blue / 255];
}

export default memo(AgentFieldGlow);
