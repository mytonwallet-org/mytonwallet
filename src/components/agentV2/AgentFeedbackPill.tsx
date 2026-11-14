import React, {
  memo, useEffect, useLayoutEffect, useRef, useState,
} from '../../lib/teact/teact';
import { addExtraClass, removeExtraClass, setExtraStyles } from '../../lib/teact/teact-dom';
import { getActions } from '../../global';

import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';
import type { AgentFeedbackFlightStop } from './agentFeedbackFlight';

import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import generateUniqueId from '../../util/generateUniqueId';
import { vibrate } from '../../util/haptics';
import { throttleWith } from '../../util/schedulers';
import windowSize from '../../util/windowSize';
import getCanAnimate from '../agent/helpers/getCanAnimate';
import {
  AGENT_FEEDBACK_ANIMATIONS,
  AGENT_FEEDBACK_LARGE_DOT_RADIUS,
  AGENT_FEEDBACK_SMALL_DOT_RADIUS,
  getAgentFeedbackCloudLayout,
} from './agentFeedback';
import { startAgentFeedbackFlight, waitForAgentFeedbackFlight } from './agentFeedbackFlight';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Portal from '../ui/Portal';
import AgentFeedbackCloudIcon from './AgentFeedbackCloudIcon';

import styles from './AgentFeedbackPill.module.scss';

interface OwnProps {
  /** Shown with the answer's menu */
  isOpen: boolean;
  messageId: number;
  feedback?: AgentAnswerFeedbackV2;
  isOperator?: boolean;
  /** The answer's bubble, whose top trailing corner the cloud points at, and to whose bottom one a reaction flies */
  getAnchorElement: () => HTMLElement | undefined;
  /** The bottom of the answer with what hangs from its bubble, which the cloud hangs under without room above */
  getMessageBottom: () => number | undefined;
  onChange: (feedback?: AgentAnswerFeedbackV2) => Promise<(() => boolean) | undefined>;
  /** Closes the menu the cloud comes with */
  onClose: NoneToVoidFunction;
}

/** A reaction chosen in the cloud, or none for a withdrawn one */
interface Choice {
  value?: AgentAnswerFeedbackV2;
  confirmation: Promise<(() => boolean) | undefined>;
}

const OPTIONS: { value: AgentAnswerFeedbackV2; label: string; className: string }[] = [
  { value: 'like', label: 'Like', className: styles.like },
  { value: 'dislike', label: 'Dislike', className: styles.dislike },
];

// The cloud shrinks back to its tail as fast as the menu fades
const CLOSE_DURATION = 200;
// Scrolls of every element, which do not bubble, reach the document's capturing listener
const FOLLOW_LISTENER_OPTIONS: AddEventListenerOptions = { capture: true, passive: true };
// Each icon appears as the growing capsule reaches its place, the one nearer the tail first. Its place in the cloud
// fades in with it, after the same delay.
const APPEAR_DELAYS: Record<AgentAnswerFeedbackV2, number> = {
  like: 220,
  dislike: 180,
};
const APPEAR_DELAY_STYLES: Record<AgentAnswerFeedbackV2, string> = {
  like: `--cloud-icon-delay: ${APPEAR_DELAYS.like}ms`,
  dislike: `--cloud-icon-delay: ${APPEAR_DELAYS.dislike}ms`,
};

/**
 * The reactions over an answer while its menu is open, as iMessage's tapbacks: a cloud with Telegram's animated heart
 * and broken heart, which grows out of a thought tail at the bubble's top corner, the current rating with its circle.
 *
 * As in Telegram, the answer keeps its emoji at its bottom corner while the cloud is open. A chosen reaction's emoji
 * flies from the cloud to the corner as the cloud closes into its tail.
 */
function AgentFeedbackPill({
  isOpen, messageId, feedback, isOperator = false, getAnchorElement, getMessageBottom, onChange, onClose,
}: OwnProps) {
  const lang = useLang();
  const { ref, shouldRender } = useShowTransition<HTMLDivElement>({
    isOpen,
    withShouldRender: true,
    className: false,
    closeDuration: CLOSE_DURATION,
  });
  // The chosen reaction's flight to the answer's corner
  const stopFlightRef = useRef<AgentFeedbackFlightStop>();
  // The reaction chosen in the cloud, which flies to the corner as the cloud closes
  const choiceRef = useRef<Choice>();
  const hasChosenRef = useRef(false);
  const [selectKeys, setSelectKeys] = useState<Partial<Record<AgentAnswerFeedbackV2, string>>>({});
  // The reaction a press started on, which chooses it as the press ends there, and the click that follows such a press
  const pressedValueRef = useRef<AgentAnswerFeedbackV2>();
  const isClickSuppressedRef = useRef(false);

  // The cloud decides as it opens whether its icons have motion
  const isPreviouslyOpenRef = useRef(false);
  const canAnimateRef = useRef(false);
  if (isOpen && !isPreviouslyOpenRef.current) {
    canAnimateRef.current = getCanAnimate();
  }
  isPreviouslyOpenRef.current = isOpen;

  const getOption = useLastCallback((value: AgentAnswerFeedbackV2) => (
    ref.current?.querySelector<HTMLElement>(`[data-agent-feedback-option="${value}"]`) ?? undefined
  ));
  const getOptionIcon = useLastCallback((value: AgentAnswerFeedbackV2) => (
    getOption(value)?.querySelector<HTMLElement>(`.${styles.icon}`) ?? undefined
  ));
  // A cloud opened again starts afresh, and a reaction still flying to the corner lands there at once
  const resetCloud = useLastCallback(() => {
    stopFlightRef.current?.();
    stopFlightRef.current = undefined;
    choiceRef.current = undefined;
    hasChosenRef.current = false;
    pressedValueRef.current = undefined;
    isClickSuppressedRef.current = false;
    OPTIONS.forEach(({ value }) => {
      const icon = getOptionIcon(value);
      if (icon) removeExtraClass(icon, styles.iconFlown);
    });
  });

  // The chosen reaction's emoji leaves its place for the answer's corner while the cloud closes into its tail. A
  // withdrawn reaction leaves the cloud to close alone. The first like and the first dislike explain themselves in a
  // toast once they reach the answer and are saved, which plays the emoji's `center` once more in its icon's place.
  const startFlight = useLastCallback(() => {
    pressedValueRef.current = undefined;
    const choice = choiceRef.current;
    choiceRef.current = undefined;
    if (!choice?.value) return;

    const reaction = choice.value;
    const { center, rest, centerSize } = AGENT_FEEDBACK_ANIMATIONS[reaction];
    const toast = {
      feedback: reaction, isOperator, animatedIcon: { tgsUrl: center, previewUrl: rest, size: centerSize },
    };

    function showToast() {
      void choice!.confirmation.then((getIsCurrentFeedback) => {
        if (getIsCurrentFeedback?.()) getActions().showAgentFeedbackToast(toast);
      });
    }

    if (!getCanAnimate()) {
      showToast();
      return;
    }

    const icon = getOptionIcon(reaction);
    if (icon) addExtraClass(icon, styles.iconFlown);
    stopFlightRef.current = startAgentFeedbackFlight(messageId, {
      reaction,
      getCloudIcon: () => getOptionIcon(reaction),
      getBubbleElement: getAnchorElement,
      isRtl: Boolean(lang.isRtl),
    });
    waitForAgentFeedbackFlight(messageId, showToast);
  });

  useLayoutEffect(() => {
    if (isOpen) {
      resetCloud();
    } else {
      startFlight();
    }
  }, [isOpen, resetCloud, startFlight]);

  useLayoutEffect(() => {
    if (!isOpen) return undefined;

    function measurePlace() {
      const anchor = getAnchorElement();
      const cloud = ref.current;
      if (!anchor || !cloud) return undefined;

      const bubbleRect = anchor.getBoundingClientRect();
      const layout = getAgentFeedbackCloudLayout(
        bubbleRect, getMessageBottom() ?? bubbleRect.bottom, windowSize.get(), Boolean(lang.isRtl),
      );

      return () => {
        setExtraStyles(cloud, {
          '--cloud-left': `${layout.left}px`,
          '--cloud-top': `${layout.top}px`,
          transformOrigin: `${layout.largeDotX}px ${layout.largeDotY}px`,
          '--large-dot-left': `${layout.largeDotX - AGENT_FEEDBACK_LARGE_DOT_RADIUS}px`,
          '--large-dot-top': `${layout.largeDotY - AGENT_FEEDBACK_LARGE_DOT_RADIUS}px`,
          '--small-dot-left': `${layout.smallDotX - AGENT_FEEDBACK_SMALL_DOT_RADIUS}px`,
          '--small-dot-top': `${layout.smallDotY - AGENT_FEEDBACK_SMALL_DOT_RADIUS}px`,
        });
      };
    }

    const place = throttleWith(requestMeasure, () => {
      const applyPlace = measurePlace();
      if (applyPlace) requestMutation(applyPlace);
    });

    // The cloud takes its place before its first frame
    requestForcedReflow(measurePlace);
    // The menu holds the chat still, but the list can still move the answer under it, as when it keeps its end while
    // the answer grows. The cloud follows on every scroll frame, without motion of its own, and stays at the top of the
    // screen over an answer whose top is out of sight.
    document.addEventListener('scroll', place, FOLLOW_LISTENER_OPTIONS);
    return () => document.removeEventListener('scroll', place, FOLLOW_LISTENER_OPTIONS);
  }, [getAnchorElement, getMessageBottom, isOpen, lang.isRtl, ref]);

  // A press here is not a press outside the menu, which would close it before the click lands
  useEffect(() => {
    const cloud = ref.current;
    if (!cloud) return undefined;

    function stopPress(e: Event) {
      e.stopPropagation();
    }

    cloud.addEventListener('mousedown', stopPress);
    return () => cloud.removeEventListener('mousedown', stopPress);
  }, [ref, shouldRender]);

  // A second press on the chosen reaction withdraws it
  const choose = useLastCallback((value: AgentAnswerFeedbackV2) => {
    if (!isOpen || hasChosenRef.current) return;

    hasChosenRef.current = true;
    const nextFeedback = feedback === value ? undefined : value;
    vibrate(true);
    choiceRef.current = { value: nextFeedback, confirmation: onChange(nextFeedback) };
    onClose();
  });

  const handleClick = useLastCallback((value: AgentAnswerFeedbackV2) => {
    if (isClickSuppressedRef.current) {
      isClickSuppressedRef.current = false;
      return;
    }

    choose(value);
  });

  const playSelect = useLastCallback((value: AgentAnswerFeedbackV2) => {
    setSelectKeys((keys) => ({ ...keys, [value]: generateUniqueId() }));
  });

  const handlePointerDown = useLastCallback((
    e: React.PointerEvent<HTMLButtonElement>, value: AgentAnswerFeedbackV2,
  ) => {
    // A pointer that hovers has played `select` already
    if (e.pointerType !== 'mouse') playSelect(value);
    isClickSuppressedRef.current = false;
    pressedValueRef.current = e.button === 0 ? value : undefined;
    // Touch keeps its pointer on the button it pressed, which would take the release from elsewhere
    if (e.currentTarget.hasPointerCapture?.(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
  });

  // A press chooses the reaction it ends on, however long it was held, as a click does. A long touch makes no click,
  // and the click that follows a shorter press is the same press.
  const handlePointerUp = useLastCallback((value: AgentAnswerFeedbackV2) => {
    if (pressedValueRef.current !== value) return;

    pressedValueRef.current = undefined;
    isClickSuppressedRef.current = true;
    choose(value);
  });

  const handlePointerCancel = useLastCallback(() => {
    pressedValueRef.current = undefined;
  });

  // A long touch does not open the browser's menu over the cloud
  const handleContextMenu = useLastCallback((e: React.MouseEvent) => {
    e.preventDefault();
  });

  if (!shouldRender) return undefined;

  return (
    <Portal>
      <div ref={ref} className={styles.root} data-agent-feedback-cloud>
        <span className={buildClassName(styles.dot, styles.smallDot)} aria-hidden />
        <span className={buildClassName(styles.dot, styles.largeDot)} aria-hidden />
        <div className={styles.capsule} aria-hidden />
        {OPTIONS.map(({ value, label, className }) => {
          const isSelected = feedback === value;
          const title = lang(label);

          return (
            <button
              key={value}
              type="button"
              className={buildClassName(styles.button, className, isSelected && styles.selected)}
              style={APPEAR_DELAY_STYLES[value]}
              data-agent-feedback-option={value}
              aria-label={title}
              aria-pressed={isSelected}
              title={title}
              onClick={() => handleClick(value)}
              onMouseEnter={() => playSelect(value)}
              onPointerDown={(e) => handlePointerDown(e, value)}
              onPointerUp={() => handlePointerUp(value)}
              onPointerCancel={handlePointerCancel}
              onContextMenu={handleContextMenu}
            >
              <AgentFeedbackCloudIcon
                reaction={value}
                noAnimation={!canAnimateRef.current}
                appearDelay={APPEAR_DELAYS[value]}
                selectKey={selectKeys[value]}
              />
            </button>
          );
        })}
      </div>
    </Portal>
  );
}

export default memo(AgentFeedbackPill);
