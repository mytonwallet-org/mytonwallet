import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getGlobal } from '../../global';

import { ANIMATION_LEVEL_MIN } from '../../config';
import buildClassName from '../../util/buildClassName';
import { createAgentEdgeGlowRenderer } from './helpers/agentEdgeGlowRenderer';

import { useMediaQuery } from '../../hooks/useMediaQuery';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentEdgeGlow.module.scss';

interface OwnProps {
  isActive: boolean;
}

const CLOSE_DURATION = 400;

/**
 * The glow running along the chat's edges while the Agent thinks, drawn by the iOS shader, or by a conic gradient
 * where WebGL is not available
 */
function AgentEdgeGlow({ isActive }: OwnProps) {
  const { ref, shouldRender } = useShowTransition({
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

    const renderer = createAgentEdgeGlowRenderer(canvas);
    if (!renderer) {
      setHasRenderer(false);
      return undefined;
    }

    // The lights stand still where motion is reduced, so the glow is drawn once, at the start of its loop
    const isStill = isReducedMotion || getGlobal().settings.animationLevel === ANIMATION_LEVEL_MIN;
    const startedAt = performance.now();
    let frame: number | undefined;
    const render = () => {
      const time = isStill ? 0 : (performance.now() - startedAt) / 1000;
      renderer.render(time, document.documentElement.classList.contains('theme-dark'));
    };
    const tick = () => {
      render();
      frame = requestAnimationFrame(tick);
    };
    const fit = () => {
      const { width, height } = root.getBoundingClientRect();
      renderer.resize(width, height, parseFloat(getComputedStyle(root).borderTopLeftRadius) || 0);
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
    <div ref={ref} className={buildClassName(styles.root, !hasRenderer && styles.fallback)} aria-hidden>
      {hasRenderer ? (
        // A renderer releases its context as it ends, so the next one draws on a canvas of its own
        <canvas key={isReducedMotion ? 'still' : 'moving'} ref={canvasRef} className={styles.canvas} />
      ) : <div className={styles.lights} />}
    </div>
  );
}

export default memo(AgentEdgeGlow);
