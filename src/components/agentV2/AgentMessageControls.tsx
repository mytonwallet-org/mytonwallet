import type { AnimationEvent } from 'react';
import type { TeactNode } from '../../lib/teact/teact';
import React, { useLayoutEffect, useRef } from '../../lib/teact/teact';

import type { AgentPublicFollowUpV2 } from '../../api/agentV2/protocol/types';

import {
  forceMeasure, getPhase, requestForcedReflow, requestMutation,
} from '../../lib/fasterdom/fasterdom';
import getCanAnimate from '../agent/helpers/getCanAnimate';

import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentV2Conversation.module.scss';

const FOLLOWUP_CLOSE_DURATION = 200;
const FOLLOWUP_GROW_DURATION = 250;
const FOLLOWUP_APPEAR_INTERVAL = 150;
const FOLLOWUP_GROW_EASING = 'cubic-bezier(0.2, 0.7, 0.2, 1)';
// Starts at rest, as the scroll to a sent question it runs alongside
const FOLLOWUP_CLOSE_EASING = 'ease-in-out';
// The widths of the placeholders that stand in for suggestions still loading, in rem
const FOLLOWUP_PLACEHOLDER_WIDTHS = [14.375, 16.875, 12.5];
const FOLLOWUP_RESIZE_DURATION = 300;
// A suggestion's text and arrow appear over the end of its pill's resize, as iOS uncovers them from 0.14 s of 0.36 s
const FOLLOWUP_CONTENT_FADE_DELAY = 120;
const FOLLOWUP_CONTENT_FADE_DURATION = 180;
// The opacity, multiplied through the ancestors, at which the last placeholder counts as fully shown
const FOLLOWUP_REVEALED_OPACITY = 0.99;
const FOLLOWUP_LABEL_SELECTOR = '[data-agent-followup-label]';

interface OwnProps {
  followups?: AgentPublicFollowUpV2[];
  isLoadingFollowups?: boolean;
  isDisabled: boolean;
  /** The suggestions keep their pressable look and tell assistive technology that they take no press */
  isInactive?: boolean;
  shouldShowFollowups?: boolean;
  /** The suggestions open their space over 250 ms rather than pushing the chat up at once */
  shouldAnimateGrowth?: boolean;
  /** Called on each frame of that growth, so that a list at its end can follow it */
  onGrowthFrame?: NoneToVoidFunction;
  onFollowup: (item: AgentPublicFollowUpV2) => void;
  children?: TeactNode;
}

function AgentMessageControls({
  followups,
  isLoadingFollowups = false,
  isDisabled,
  isInactive = false,
  shouldShowFollowups = false,
  shouldAnimateGrowth = false,
  onGrowthFrame,
  onFollowup,
  children,
}: OwnProps) {
  const hasFollowupRow = Boolean(followups?.length) || isLoadingFollowups;
  const isFollowupRowOpen = hasFollowupRow && shouldShowFollowups;

  // Once a newer message arrives, the row fades out and leaves the DOM instead of staying under an old answer
  const { ref: followupRowRef, shouldRender: shouldRenderFollowupRow } = useShowTransition<HTMLDivElement>({
    isOpen: isFollowupRowOpen,
    withShouldRender: true,
    className: false,
    closeDuration: FOLLOWUP_CLOSE_DURATION,
    // Without motion the row has no fade to wait for, so it leaves at once rather than collapsing
    noCloseTransition: !getCanAnimate(),
  });
  const wasFollowupRowOpenRef = useRef(isFollowupRowOpen);
  const collapseRef = useRef<Animation>();
  const loadingFramesRef = useRef<DOMRect[]>();
  const hasRevealedLoadingRef = useRef(false);

  const handleLoadingRevealEnd = useLastCallback((event: AnimationEvent<HTMLDivElement>) => {
    if (!isLoadingFollowups || !event.animationName.includes('followup-appear')) return;
    let opacity = 1;
    for (let element = event.target as HTMLElement | null; element; element = element.parentElement) {
      opacity *= Number(getComputedStyle(element).opacity);
    }
    hasRevealedLoadingRef.current = opacity > FOLLOWUP_REVEALED_OPACITY;
  });

  const handleGrowthFrame = useLastCallback(() => onGrowthFrame?.());

  // Each placeholder turns into its suggestion: the pill keeps its fill and its ring and takes the suggestion's size,
  // which moves the pills under it along, and only the text and the arrow appear in it. Placeholders still coming in
  // turn into suggestions that come in with their own entrance, one by one, as the placeholders did.
  useLayoutEffect(() => {
    const row = followupRowRef.current;
    if (!row) return undefined;

    if (isLoadingFollowups) {
      hasRevealedLoadingRef.current = false;
      requestForcedReflow(() => {
        loadingFramesRef.current = Array.from(row.children, (child) => child.getBoundingClientRect());
      });
      return undefined;
    }

    const previous = loadingFramesRef.current;
    const shouldMorphTogether = hasRevealedLoadingRef.current;
    loadingFramesRef.current = undefined;
    hasRevealedLoadingRef.current = false;
    if (!previous || !getCanAnimate()) return undefined;

    let frame: number | undefined;
    requestForcedReflow(() => {
      const morphs = Array.from(row.children).flatMap((child, index) => {
        const from = previous[index];
        if (!(child instanceof HTMLElement) || !from || !child.animate) return [];

        const to = child.getBoundingClientRect();
        const label = child.querySelector<HTMLElement>(FOLLOWUP_LABEL_SELECTOR);
        return to.width && to.height ? [{
          element: child, index, from, to, label, labelWidth: label?.getBoundingClientRect().width,
        }] : [];
      });

      return () => {
        const resizes = morphs.map(({
          element, index, from, to, label, labelWidth,
        }) => {
          const delay = shouldMorphTogether ? 0 : index * FOLLOWUP_APPEAR_INTERVAL;
          const timing: KeyframeAnimationOptions = {
            duration: FOLLOWUP_RESIZE_DURATION, delay, easing: FOLLOWUP_GROW_EASING, fill: 'backwards',
          };
          // The text keeps the lines it ends up with while the pill around it changes its size
          label?.animate([{ minWidth: `${labelWidth}px` }, { minWidth: `${labelWidth}px` }], timing);
          if (shouldMorphTogether) {
            element.getAnimations().forEach((animation) => animation.cancel());
            Array.from(element.children).forEach((part) => {
              part.animate([{ opacity: 0 }, { opacity: 1 }], {
                duration: FOLLOWUP_CONTENT_FADE_DURATION,
                delay: FOLLOWUP_CONTENT_FADE_DELAY,
                easing: 'ease-out',
                fill: 'backwards',
              });
            });
          }

          return element.animate([
            { width: `${from.width}px`, height: `${from.height}px`, overflow: 'hidden' },
            { width: `${to.width}px`, height: `${to.height}px`, overflow: 'hidden' },
          ], timing);
        });

        // A list at its end follows the pills as they change their height
        function follow() {
          handleGrowthFrame();
          if (resizes.some(({ playState }) => playState === 'running')) frame = requestAnimationFrame(follow);
        }
        frame = requestAnimationFrame(follow);
      };
    });

    return () => {
      if (frame) cancelAnimationFrame(frame);
    };
  }, [followupRowRef, handleGrowthFrame, isLoadingFollowups, shouldRenderFollowupRow]);

  // A suggestion that wraps is as wide as its longest line, as on iOS, rather than as wide as the row lets it be. The
  // labels are fitted before the morph out of the placeholders measures where the suggestions end.
  useLayoutEffect(() => {
    const row = followupRowRef.current;
    if (!row || isLoadingFollowups) return undefined;

    fitFollowupLabels(row);
    return observeFollowupRowWidth(row);
  }, [followupRowRef, followups, isLoadingFollowups, shouldRenderFollowupRow]);

  // The row grows once, when it appears
  useLayoutEffect(() => {
    const row = followupRowRef.current;
    if (!shouldRenderFollowupRow || !shouldAnimateGrowth || !row?.animate) return undefined;

    let frame: number | undefined;
    requestForcedReflow(() => {
      const height = row.offsetHeight;
      const { marginTop } = getComputedStyle(row);

      return () => {
        const animation = row.animate([
          { height: '0px', marginTop: '0px', overflow: 'hidden' },
          { height: `${height}px`, marginTop, overflow: 'hidden' },
        ], { duration: FOLLOWUP_GROW_DURATION, easing: FOLLOWUP_GROW_EASING });
        function follow() {
          handleGrowthFrame();
          if (animation.playState !== 'finished') frame = requestAnimationFrame(follow);
        }
        frame = requestAnimationFrame(follow);
      };
    });

    return () => {
      if (frame) cancelAnimationFrame(frame);
    };
  }, [followupRowRef, handleGrowthFrame, shouldAnimateGrowth, shouldRenderFollowupRow]);

  // As it fades, the row gives its space back over the same time, so that what comes after it, as the question just
  // sent, moves up with it rather than jumping when it leaves
  useLayoutEffect(() => {
    const wasOpen = wasFollowupRowOpenRef.current;
    wasFollowupRowOpenRef.current = isFollowupRowOpen;
    // A row that opens again while it closes takes its space back at once
    if (isFollowupRowOpen) {
      collapseRef.current?.cancel();
      collapseRef.current = undefined;
    }
    const row = followupRowRef.current;
    if (!wasOpen || isFollowupRowOpen || !row?.animate) return undefined;

    let frame: number | undefined;
    requestForcedReflow(() => {
      const height = row.offsetHeight;
      const { marginTop } = getComputedStyle(row);

      return () => {
        const animation = row.animate([
          { height: `${height}px`, marginTop, overflow: 'hidden' },
          { height: '0px', marginTop: '0px', overflow: 'hidden' },
        ], { duration: FOLLOWUP_CLOSE_DURATION, easing: FOLLOWUP_CLOSE_EASING, fill: 'forwards' });
        collapseRef.current = animation;
        function follow() {
          handleGrowthFrame();
          if (animation.playState !== 'finished') frame = requestAnimationFrame(follow);
        }
        frame = requestAnimationFrame(follow);
      };
    });

    return () => {
      if (frame) cancelAnimationFrame(frame);
    };
  }, [followupRowRef, handleGrowthFrame, isFollowupRowOpen]);

  if (!shouldRenderFollowupRow && !children) {
    return undefined;
  }

  return (
    <div className={styles.richContent}>
      {children}
      {shouldRenderFollowupRow && (
        <div ref={followupRowRef} className={styles.followupRow} data-agent-followup-row>
          {isLoadingFollowups && FOLLOWUP_PLACEHOLDER_WIDTHS.map((width, index) => (
            <div
              key={index}
              data-agent-followup-placeholder
              className={styles.followupSkeleton}
              style={`width: ${width}rem; --followup-delay: ${index * FOLLOWUP_APPEAR_INTERVAL}ms`}
              onAnimationEnd={index === FOLLOWUP_PLACEHOLDER_WIDTHS.length - 1 ? handleLoadingRevealEnd : undefined}
              aria-hidden
            />
          ))}
          {!isLoadingFollowups && followups?.map((item, index) => (
            <button
              key={item.id}
              type="button"
              data-agent-followup-id={item.id}
              className={styles.followupButton}
              style={`--followup-delay: ${index * FOLLOWUP_APPEAR_INTERVAL}ms`}
              disabled={isDisabled}
              aria-disabled={isInactive || undefined}
              onClick={() => onFollowup(item)}
            >
              <span className={styles.followupArrowIcon} aria-hidden />
              <span className={styles.followupLabel} data-agent-followup-label>
                {/* Inline, so that each of its lines has a box of its own to measure */}
                <span>{item.text}</span>
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export default AgentMessageControls;

/** Narrows each label in `container` that wraps to its longest line. Runs where the DOM may be changed. */
function fitFollowupLabels(container: HTMLElement) {
  const labels = Array.from(container.querySelectorAll<HTMLElement>(FOLLOWUP_LABEL_SELECTOR));
  if (!labels.length) return;

  labels.forEach((label) => label.style.removeProperty('width'));
  const widths = measureAfterMutation(() => labels.map(getLongestLineWidth));
  labels.forEach((label, index) => {
    const width = widths[index];
    if (width) label.style.width = `${width}px`;
  });
}

/** The width of the longest line of a label's text, or nothing for a label on one line */
function getLongestLineWidth(label: HTMLElement) {
  const text = label.firstElementChild;
  if (!text) return undefined;

  const lines = new Map<number, { left: number; right: number }>();
  Array.from(text.getClientRects()).forEach(({
    top, left, right, width, height,
  }) => {
    if (!width || !height) return;

    const key = Math.round(top);
    const line = lines.get(key);
    lines.set(key, line
      ? { left: Math.min(line.left, left), right: Math.max(line.right, right) }
      : { left, right });
  });
  if (lines.size < 2) return undefined;

  return Math.ceil(Math.max(...Array.from(lines.values(), ({ left, right }) => right - left)));
}

// A layout effect runs in the mutation phase, where the layout is read through `forceMeasure`
function measureAfterMutation<T>(measure: () => T): T {
  return getPhase() === 'mutate' ? forceMeasure(measure) : measure();
}

/** Fits the labels again once the row's width changes */
function observeFollowupRowWidth(row: HTMLElement) {
  let width: number | undefined;
  const observer = new ResizeObserver(([entry]) => {
    const previousWidth = width;
    width = entry.contentRect.width;
    if (previousWidth === undefined || previousWidth === width) return;

    requestMutation(() => fitFollowupLabels(row));
  });
  observer.observe(row);

  return () => observer.disconnect();
}
