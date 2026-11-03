import type { AnimationEvent } from 'react';
import type { TeactNode } from '../../lib/teact/teact';
import React, { useLayoutEffect, useRef } from '../../lib/teact/teact';

import type { AgentPublicFollowUpV2 } from '../../api/agentV2/protocol/types';

import { requestForcedReflow } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
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
const FOLLOWUP_MORPH_DURATION = 300;
// Placeholders that were fully shown turn into the suggestions from this opacity rather than from nothing
const FOLLOWUP_MORPH_START_OPACITY = 0.45;
// The opacity, multiplied through the ancestors, at which the last placeholder counts as fully shown
const FOLLOWUP_REVEALED_OPACITY = 0.99;

interface OwnProps {
  followups?: AgentPublicFollowUpV2[];
  isLoadingFollowups?: boolean;
  isDisabled: boolean;
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

  useLayoutEffect(() => {
    const row = followupRowRef.current;
    if (!row) return;

    if (isLoadingFollowups) {
      hasRevealedLoadingRef.current = false;
      requestForcedReflow(() => {
        loadingFramesRef.current = Array.from(row.children, (child) => child.getBoundingClientRect());
      });
      return;
    }

    const previous = loadingFramesRef.current;
    const shouldMorphTogether = hasRevealedLoadingRef.current;
    loadingFramesRef.current = undefined;
    hasRevealedLoadingRef.current = false;
    if (!previous || !getCanAnimate()) return;

    requestForcedReflow(() => {
      const morphs = Array.from(row.children).flatMap((child, index) => {
        const from = previous[index];
        if (!(child instanceof HTMLElement) || !from || !child.animate) return [];

        const to = child.getBoundingClientRect();
        return to.width && to.height ? [{ element: child, index, from, to }] : [];
      });

      return () => {
        morphs.forEach(({ element, index, from, to }) => {
          element.getAnimations().forEach((animation) => animation.cancel());
          element.animate([
            {
              transform: `translate(${from.left - to.left}px, ${from.top - to.top}px) `
                + `scale(${from.width / to.width}, ${from.height / to.height})`,
              opacity: shouldMorphTogether ? FOLLOWUP_MORPH_START_OPACITY : 0,
            },
            { transform: 'none', opacity: 1 },
          ], {
            duration: FOLLOWUP_MORPH_DURATION,
            delay: shouldMorphTogether ? 0 : index * FOLLOWUP_APPEAR_INTERVAL,
            easing: FOLLOWUP_GROW_EASING,
            fill: 'backwards',
          });
        });
      };
    });
  }, [followupRowRef, isLoadingFollowups, shouldRenderFollowupRow]);

  const handleGrowthFrame = useLastCallback(() => onGrowthFrame?.());

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
        <div ref={followupRowRef} className={styles.followupRow}>
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
              className={buildClassName(styles.followupButton, styles.followupArrow)}
              style={`--followup-delay: ${index * FOLLOWUP_APPEAR_INTERVAL}ms`}
              disabled={isDisabled}
              onClick={() => onFollowup(item)}
            >
              <span className={styles.followupLabel}>{item.text}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export default AgentMessageControls;
