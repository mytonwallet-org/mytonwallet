import React, {
  memo, useEffect, useLayoutEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { AgentSpinningTopHandoff, AgentSpinningTopState } from './helpers/agentSpinningTop';

import buildClassName from '../../util/buildClassName';
import { SWIPE_DISABLED_CLASS_NAME } from '../../util/swipeController';
import { createAgentSpinningTop } from './helpers/agentSpinningTop';
import {
  getIsAgentSpinningTopRendererAvailable,
  subscribeToAgentSpinningTopFailure,
} from './helpers/agentSpinningTopRenderer';

import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import { useStateRef } from '../../hooks/useStateRef';

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
  /** A large top, as the empty chat's, stands on the ground, with a shadow or a glow under it and its reflection */
  shouldShowGround?: boolean;
  /** Thinking spins the top up; a Stop grows it and knocks it over a little, and it rights itself */
  agentState?: AgentSpinningTopState;
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
  shouldShowGround = false,
  agentState = 'idle',
  handoff,
}: OwnProps) {
  const [isRenderedIn3d, setIsRenderedIn3d] = useState(getIsAgentSpinningTopRendererAvailable);
  const rootRef = useRef<HTMLSpanElement>();
  const canvasRef = useRef<HTMLCanvasElement>();
  const controllerRef = useRef<ReturnType<typeof createAgentSpinningTop>>();
  const agentStateRef = useStateRef(agentState);

  useEffect(() => {
    if (!isRenderedIn3d) return undefined;

    return subscribeToAgentSpinningTopFailure(() => setIsRenderedIn3d(false));
  }, [isRenderedIn3d]);

  // The top starts as its canvas comes, so that it is drawn in the frame it shows
  useLayoutEffect(() => {
    const root = rootRef.current;
    const canvas = canvasRef.current;
    if (!isRenderedIn3d || !root || !canvas) return undefined;

    const controller = createAgentSpinningTop(root, canvas, { speed, isTouchInteractive, shouldShowGround, handoff });
    // A new top starts in the state it shows. A top that comes with a Stop, as the chat's end takes the indicator from
    // the answer the Stop removes, shows the Stop.
    const initialState = agentStateRef.current;
    if (initialState !== 'idle') controller.setState(initialState);
    controllerRef.current = controller;
    return () => {
      controllerRef.current = undefined;
      controller.destroy();
    };
  }, [agentStateRef, handoff, isRenderedIn3d, isTouchInteractive, shouldShowGround, speed]);

  useEffectWithPrevDeps(([prevAgentState]) => {
    if (prevAgentState !== undefined) controllerRef.current?.setState(agentState);
  }, [agentState]);

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
