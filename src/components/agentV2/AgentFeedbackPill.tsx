import React, { memo, useEffect, useLayoutEffect } from '../../lib/teact/teact';
import { setExtraStyles } from '../../lib/teact/teact-dom';

import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';
import type { AgentIconName } from '../agent/AgentIcon';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';
import { REM } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import AgentIcon from '../agent/AgentIcon';
import Portal from '../ui/Portal';

import styles from './AgentFeedbackPill.module.scss';

interface OwnProps {
  /** Shown with the answer's menu */
  isOpen: boolean;
  feedback?: AgentAnswerFeedbackV2;
  /** The answer's bubble, whose top trailing corner the pill sits on */
  getAnchorElement: () => HTMLElement | undefined;
  onChange: (feedback?: AgentAnswerFeedbackV2) => void;
  /** Closes the menu the pill comes with */
  onClose: NoneToVoidFunction;
}

const OPTIONS: { value: AgentAnswerFeedbackV2; label: string; icon: AgentIconName }[] = [
  { value: 'like', label: 'Like', icon: 'like' },
  { value: 'dislike', label: 'Dislike', icon: 'dislike' },
];

// The pill's body overlaps the bubble's top by 0.75rem and reaches 1.25rem past its trailing edge, as on mobile
const BODY_HEIGHT_REM = 3.5;
const WIDTH_REM = 6.75;
const OVERLAP_REM = 0.75;
const OVERHANG_REM = 1.25;
const SCREEN_MARGIN_REM = 0.5;

/** Like and Dislike over an answer while its menu is open, as a thought bubble pointing at it */
function AgentFeedbackPill({
  isOpen, feedback, getAnchorElement, onChange, onClose,
}: OwnProps) {
  const lang = useLang();
  const { ref, shouldRender } = useShowTransition<HTMLDivElement>({
    isOpen,
    withShouldRender: true,
    className: false,
  });

  useLayoutEffect(() => {
    if (!isOpen) return;

    requestMeasure(() => {
      const anchor = getAnchorElement();
      const pill = ref.current;
      if (!anchor || !pill) return;

      const { top, left, right } = anchor.getBoundingClientRect();
      const width = WIDTH_REM * REM;
      const margin = SCREEN_MARGIN_REM * REM;
      const pillLeft = lang.isRtl ? left - OVERHANG_REM * REM : right + OVERHANG_REM * REM - width;
      const maxLeft = document.documentElement.clientWidth - width - margin;

      requestMutation(() => {
        setExtraStyles(pill, {
          top: `${Math.max(margin, top - (BODY_HEIGHT_REM - OVERLAP_REM) * REM)}px`,
          left: `${Math.min(Math.max(margin, pillLeft), maxLeft)}px`,
        });
      });
    });
  }, [getAnchorElement, isOpen, lang.isRtl, ref]);

  // A press here is not a press outside the menu, which would close it before the click lands
  useEffect(() => {
    const pill = ref.current;
    if (!pill) return undefined;

    function stopPress(e: Event) {
      e.stopPropagation();
    }

    pill.addEventListener('mousedown', stopPress);
    return () => pill.removeEventListener('mousedown', stopPress);
  }, [ref, shouldRender]);

  const handleClick = useLastCallback((value: AgentAnswerFeedbackV2) => {
    vibrate(true);
    // A second press on the chosen rating withdraws it
    onChange(feedback === value ? undefined : value);
    onClose();
  });

  if (!shouldRender) return undefined;

  return (
    <Portal>
      <div ref={ref} className={styles.root}>
        <div className={styles.body}>
          {OPTIONS.map(({ value, label, icon }) => {
            const isSelected = feedback === value;

            return (
              <button
                key={value}
                type="button"
                className={buildClassName(styles.button, isSelected && styles.selected)}
                aria-label={lang(label)}
                aria-pressed={isSelected}
                title={lang(label)}
                onClick={() => handleClick(value)}
              >
                <AgentIcon name={icon} className={styles.icon} />
              </button>
            );
          })}
        </div>
        <span className={styles.bump} aria-hidden />
        <span className={styles.dot} aria-hidden />
      </div>
    </Portal>
  );
}

export default memo(AgentFeedbackPill);
