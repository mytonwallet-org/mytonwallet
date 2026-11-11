import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { Point } from './agentFeedback';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate } from '../../util/animation';
import buildStyle from '../../util/buildStyle';

import AnimatedSticker from '../ui/AnimatedSticker';

import styles from './AgentFeedbackPill.module.scss';

interface OwnProps {
  tgsUrl: string;
  /** Names the animation and its size, so that its frames are shared while it plays */
  renderId: string;
  size: number;
  /** The point the animation is centred on, measured on every frame so that it follows the answer */
  getCenter: () => Point | undefined;
  onEnded: NoneToVoidFunction;
}

// An effect whose animation never ends, as when it fails to load, goes after this long
const MAX_DURATION = 5000;

/**
 * Telegram's effect of a reaction, played once over everything at a point of the chat: drawn on top of the window, so
 * that neither the bubble nor the list clips it
 */
function AgentFeedbackEffect({
  tgsUrl, renderId, size, getCenter, onEnded,
}: OwnProps) {
  const ref = useRef<HTMLDivElement>();

  useLayoutEffect(() => {
    let isActive = true;
    animate(() => {
      const element = ref.current;
      if (!isActive || !element) return false;

      const center = getCenter();
      requestMutation(() => {
        element.style.visibility = center ? '' : 'hidden';
        if (center) {
          element.style.transform = `translate3d(${center.x - size / 2}px, ${center.y - size / 2}px, 0)`;
        }
      });

      return true;
    }, requestMeasure);

    return () => {
      isActive = false;
    };
  }, [getCenter, ref, size]);

  return (
    <div
      ref={ref}
      className={styles.effect}
      style={buildStyle(`width: ${size}px`, `height: ${size}px`)}
      data-agent-feedback-effect={renderId}
      aria-hidden
    >
      <AnimatedSticker
        renderId={renderId}
        tgsUrl={tgsUrl}
        size={size}
        play
        noLoop
        forceOnHeavyAnimation
        onEnded={onEnded}
      />
    </div>
  );
}

const MemoizedAgentFeedbackEffect = memo(AgentFeedbackEffect);

/** Plays an effect once over the window, and removes it when it ends */
export function playAgentFeedbackEffect(props: Omit<OwnProps, 'onEnded'>) {
  const container = document.createElement('div');
  document.body.appendChild(container);

  let isRemoved = false;
  const timeout = window.setTimeout(remove, MAX_DURATION);

  function remove() {
    if (isRemoved) return;

    isRemoved = true;
    window.clearTimeout(timeout);
    TeactDOM.render(undefined, container);
    container.remove();
  }

  function handleEnded() {
    // The animation reports its end from inside its own frame, which unmounting it there would cut short
    requestMutation(remove);
  }

  TeactDOM.render(<MemoizedAgentFeedbackEffect {...props} onEnded={handleEnded} />, container);
}
