import React, { memo, useRef } from '../../lib/teact/teact';

import type { AgentHint } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useHorizontalScroll from '../../hooks/useHorizontalScroll';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentHints.module.scss';

interface OwnProps {
  isOpen: boolean;
  hints?: AgentHint[];
  onHintClick: (prompt: string) => void;
}

const CLOSE_ANIMATION_DURATION_MS = 250;

function AgentHints({ isOpen, hints, onHintClick }: OwnProps) {
  const containerRef = useRef<HTMLDivElement>();

  const { ref, shouldRender } = useShowTransition<HTMLDivElement>({
    isOpen: isOpen && Boolean(hints?.length),
    withShouldRender: true,
    className: false,
    closeDuration: CLOSE_ANIMATION_DURATION_MS,
  });

  useHorizontalScroll({ containerRef, isDisabled: !shouldRender || !isOpen });

  if (!shouldRender) return undefined;

  return (
    <div ref={ref} className={buildClassName(styles.wrapper)}>
      <div ref={containerRef} className={styles.panel}>
        {hints!.map((hint, index) => (
          <button
            key={hint.id}
            type="button"
            className={styles.hint}
            style={`--hint-index: ${index}`}
            onClick={() => onHintClick(hint.prompt)}
          >
            <span className={styles.inner}>
              <span className={styles.title}>{hint.title}</span>
              <span className={styles.subtitle}>{hint.subtitle}</span>
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}

export default memo(AgentHints);
