import React, {
  memo, useEffect, useLayoutEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { AgentSpinningTopHandoff } from './helpers/agentSpinningTop';

import buildClassName from '../../util/buildClassName';
import { SWIPE_DISABLED_CLASS_NAME } from '../../util/swipeController';
import { createAgentSpinningTop } from './helpers/agentSpinningTop';
import {
  getIsAgentSpinningTopRendererAvailable,
  subscribeToAgentSpinningTopFailure,
} from './helpers/agentSpinningTopRenderer';

import AgentMark from './AgentMark';

import styles from './AgentSpinningTop.module.scss';

interface OwnProps {
  /** The top's box, as the mark's */
  className?: string;
  /** What only the flat mark takes, as its wobble */
  markClassName?: string;
  /** The flat mark's gradient lets the background show through, as in the empty chat */
  isGradientSoft?: boolean;
  /** How fast the top spins relative to its regular speed */
  speed?: number;
  /** Taps spin it up; a hold grows it threefold above everything, where a drag spins and tilts it */
  isTouchInteractive?: boolean;
  /** Shared with the top that takes this one's place, which goes on with its motion */
  handoff?: AgentSpinningTopHandoff;
}

/**
 * The Agent's spinning top in 3D, as on iOS and Android, drawn with WebGL2. Where WebGL2 is not available, it is the
 * flat mark.
 */
function AgentSpinningTop({
  className,
  markClassName,
  isGradientSoft,
  speed = 1,
  isTouchInteractive = false,
  handoff,
}: OwnProps) {
  const [isRenderedIn3d, setIsRenderedIn3d] = useState(getIsAgentSpinningTopRendererAvailable);
  const rootRef = useRef<HTMLSpanElement>();
  const canvasRef = useRef<HTMLCanvasElement>();

  useEffect(() => {
    if (!isRenderedIn3d) return undefined;

    return subscribeToAgentSpinningTopFailure(() => setIsRenderedIn3d(false));
  }, [isRenderedIn3d]);

  // The top starts as its canvas comes, so that it is drawn in the frame it shows
  useLayoutEffect(() => {
    const root = rootRef.current;
    const canvas = canvasRef.current;
    if (!isRenderedIn3d || !root || !canvas) return undefined;

    return createAgentSpinningTop(root, canvas, { speed, isTouchInteractive, handoff }).destroy;
  }, [handoff, isRenderedIn3d, isTouchInteractive, speed]);

  if (!isRenderedIn3d) {
    return (
      <AgentMark className={buildClassName(className, markClassName)} withGradient isGradientSoft={isGradientSoft} />
    );
  }

  return (
    <span
      ref={rootRef}
      className={buildClassName(
        styles.root,
        // A drag that starts on the top turns it, rather than swiping the chat away
        isTouchInteractive && buildClassName(styles.interactive, SWIPE_DISABLED_CLASS_NAME),
        className,
      )}
      aria-hidden
    >
      <canvas ref={canvasRef} className={styles.canvas} />
    </span>
  );
}

export default memo(AgentSpinningTop);
