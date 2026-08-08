import {
  useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../../lib/teact/teact';

import type {
  TextRevealController } from '../../../util/agent/TextRevealController';

import {
  buildRevealTarget,
  type TextRevealPhase,
  type TextRevealTarget,
} from '../../../util/agent/TextRevealController';
import segmentGraphemes from '../../../util/segmentGraphemes';
import {
  createTextRevealController,
  getNowInSeconds,
  updateTextRevealController,
} from '../helpers/streamingTextController';
import { measureStreamingTextDom, mutateStreamingTextDom } from '../helpers/streamingTextDom';
import {
  applyHeightAnimationTarget,
  commitHeightAnimationFrame,
  getHeightAnimationFrame,
  getIsHeightAnimationActive,
  type HeightAnimationState,
  resetHeightAnimation,
} from '../helpers/streamingTextHeight';
import {
  animateRevealEdges,
  clearRevealEdges,
  type RevealEdgeGroupState,
} from '../helpers/streamingTextRevealEdge';

import useLastCallback from '../../../hooks/useLastCallback';
import useThrottledCallback from '../../../hooks/useThrottledCallback';

interface UseStreamingTextOptions {
  text: string;
  isStreaming: boolean;
  shouldAnimate: boolean;
  revealSessionKey?: string;
  shouldRevealFromStart: boolean;
  onRevealStart?: NoneToVoidFunction;
  onRevealProgress?: NoneToVoidFunction;
  onRevealComplete?: NoneToVoidFunction;
}

interface TextModel {
  graphemes: string[];
  target: TextRevealTarget;
}

export default function useStreamingText({
  text,
  isStreaming,
  shouldAnimate,
  revealSessionKey,
  shouldRevealFromStart,
  onRevealStart,
  onRevealProgress,
  onRevealComplete,
}: UseStreamingTextOptions) {
  const textModel = useMemo((): TextModel => {
    const graphemes = segmentGraphemes(text);

    return {
      graphemes,
      target: buildRevealTarget(text, graphemes),
    };
  }, [text]);
  const { graphemes, target } = textModel;
  const controllerRef = useRef<TextRevealController>();
  const previousGraphemesRef = useRef(graphemes);
  const shouldAnimateOnPreviousRenderRef = useRef(shouldAnimate);
  const frameRef = useRef<number>();
  const containerRef = useRef<HTMLDivElement>();
  const contentRef = useRef<HTMLDivElement>();
  const revealEdgeLayerRef = useRef<HTMLSpanElement>();
  const revealEdgeGroupsRef = useRef<RevealEdgeGroupState[]>([]);
  const heightAnimationRef = useRef<HeightAnimationState>();
  const lifecycleGenerationRef = useRef(0);
  const heightMutationRevisionRef = useRef(0);
  const pendingHeightMutationRevisionRef = useRef<number>();
  const resizeObserverRef = useRef<ResizeObserver>();
  const phaseRef = useRef<TextRevealPhase>('streaming');
  const shouldAnimateRef = useRef(shouldAnimate);
  const appliedRevealSessionKeyRef = useRef(revealSessionKey);
  const hasActiveRevealRef = useRef(Boolean(isStreaming || revealSessionKey));
  const hasNotifiedRevealStartRef = useRef(false);
  const hasNotifiedRevealCompleteRef = useRef(false);

  if (!controllerRef.current) {
    controllerRef.current = createTextRevealController(
      target,
      isStreaming && shouldAnimate,
      getNowInSeconds(),
      shouldAnimate && shouldRevealFromStart,
    );
  }

  const [revealState, setRevealState] = useState(controllerRef.current.getSnapshot());
  const revealStateRef = useRef(revealState);
  const previousRenderedCountRef = useRef(revealState.revealedGraphemeCount);
  const previousTextContentRef = useRef('');
  const visibleGraphemeCount = shouldAnimate
    ? revealState.revealedGraphemeCount
    : target.graphemeCount;
  const visualPhase = shouldAnimate ? revealState.phase : 'complete';
  const visibleText = useMemo(
    () => graphemes.slice(0, visibleGraphemeCount).join(''),
    [graphemes, visibleGraphemeCount],
  );

  phaseRef.current = visualPhase;
  shouldAnimateRef.current = shouldAnimate;

  const notifyRevealProgress = useLastCallback(() => {
    onRevealProgress?.();
  });

  const notifyRevealStart = useLastCallback(() => {
    onRevealStart?.();
  });

  const notifyRevealComplete = useLastCallback(() => {
    onRevealComplete?.();
  });

  const tryNotifyRevealComplete = useLastCallback(() => {
    if (
      phaseRef.current !== 'complete'
      || !hasActiveRevealRef.current
      || hasNotifiedRevealCompleteRef.current
      || revealEdgeGroupsRef.current.length > 0
      || pendingHeightMutationRevisionRef.current !== undefined
      || getIsHeightAnimationActive(heightAnimationRef.current)
    ) {
      return;
    }

    hasNotifiedRevealCompleteRef.current = true;
    notifyRevealComplete();
  });

  const commitSnapshot = useLastCallback((snapshot: ReturnType<TextRevealController['getSnapshot']>) => {
    const previousSnapshot = revealStateRef.current;
    if (
      snapshot.revealedGraphemeCount > 0
      && hasActiveRevealRef.current
      && !hasNotifiedRevealStartRef.current
    ) {
      hasNotifiedRevealStartRef.current = true;
      notifyRevealStart();
    }

    if (
      snapshot.revealedGraphemeCount === previousSnapshot.revealedGraphemeCount
      && snapshot.phase === previousSnapshot.phase
    ) {
      return;
    }

    revealStateRef.current = snapshot;
    setRevealState(snapshot);
  });

  const cancelRevealFrame = useLastCallback(() => {
    if (frameRef.current === undefined) return;

    cancelAnimationFrame(frameRef.current);
    frameRef.current = undefined;
  });

  const scheduleRevealFrame = useLastCallback(() => {
    if (frameRef.current !== undefined) return;

    frameRef.current = requestAnimationFrame(function advanceReveal(timestamp) {
      frameRef.current = undefined;
      const controller = controllerRef.current!;
      const snapshot = controller.tick(timestamp / 1000);

      commitSnapshot(snapshot);

      const container = containerRef.current;
      const heightFrame = getHeightAnimationFrame(heightAnimationRef, timestamp / 1000);
      if (container && heightFrame) {
        const lifecycleGeneration = lifecycleGenerationRef.current;
        mutateStreamingTextDom(() => {
          if (
            lifecycleGenerationRef.current !== lifecycleGeneration
            || containerRef.current !== container
          ) {
            return;
          }

          const hasCommittedHeightFrame = commitHeightAnimationFrame(container, heightAnimationRef, heightFrame);
          if (hasCommittedHeightFrame && heightFrame.hasHeightChanged) {
            notifyRevealProgress();
          }
          tryNotifyRevealComplete();
        });
      }

      if (controller.shouldTick || getIsHeightAnimationActive(heightAnimationRef.current)) {
        frameRef.current = requestAnimationFrame(advanceReveal);
      }
    });
  });

  const updateContentHeight = useLastCallback(() => {
    const container = containerRef.current;
    const content = contentRef.current;
    if (!container || !content) return;

    const targetHeight = measureStreamingTextDom(() => Math.ceil(content.getBoundingClientRect().height));
    const lifecycleGeneration = lifecycleGenerationRef.current;
    const mutationRevision = ++heightMutationRevisionRef.current;
    pendingHeightMutationRevisionRef.current = mutationRevision;
    mutateStreamingTextDom(() => {
      if (
        lifecycleGenerationRef.current !== lifecycleGeneration
        || heightMutationRevisionRef.current !== mutationRevision
        || containerRef.current !== container
        || contentRef.current !== content
      ) {
        if (pendingHeightMutationRevisionRef.current === mutationRevision) {
          pendingHeightMutationRevisionRef.current = undefined;
        }
        return;
      }

      pendingHeightMutationRevisionRef.current = undefined;
      const shouldScheduleFrame = applyHeightAnimationTarget(
        container,
        targetHeight,
        shouldAnimateRef.current,
        phaseRef.current,
        heightAnimationRef,
      );
      if (shouldScheduleFrame) {
        scheduleRevealFrame();
      }
      tryNotifyRevealComplete();
    });
  });

  const scheduleContentHeightUpdate = useThrottledCallback(() => {
    updateContentHeight();
  }, [updateContentHeight], requestAnimationFrame);

  useEffect(() => {
    const now = getNowInSeconds();
    const previousGraphemes = previousGraphemesRef.current;
    let controller = controllerRef.current!;
    const controllerPhase = controller.getSnapshot().phase;
    const shouldStartNewReveal = Boolean(
      revealSessionKey
      && revealSessionKey !== appliedRevealSessionKeyRef.current,
    );

    if (!shouldAnimate) {
      controller = createTextRevealController(target, false, now);
    } else if (shouldStartNewReveal) {
      controller = createTextRevealController(target, isStreaming, now, shouldRevealFromStart);
    } else if (!shouldAnimateOnPreviousRenderRef.current) {
      controller = createTextRevealController(target, isStreaming, now);
    } else if (!isStreaming && controllerPhase === 'complete') {
      controller = createTextRevealController(target, false, now);
    } else {
      if (isStreaming && (controllerPhase === 'draining' || controllerPhase === 'complete')) {
        const previousText = previousGraphemes.join('');
        const previousTarget = buildRevealTarget(previousText, previousGraphemes);

        controller = createTextRevealController(previousTarget, true, now);
      }

      updateTextRevealController(controller, previousGraphemes, graphemes, target, now);

      if (!isStreaming) {
        controller.finalize(target, now);
      }
    }

    controllerRef.current = controller;
    if (isStreaming || revealSessionKey) {
      hasActiveRevealRef.current = true;
      if (shouldStartNewReveal) {
        hasNotifiedRevealStartRef.current = false;
      }
      hasNotifiedRevealCompleteRef.current = false;
    }
    previousGraphemesRef.current = graphemes;
    appliedRevealSessionKeyRef.current = revealSessionKey;
    shouldAnimateOnPreviousRenderRef.current = shouldAnimate;
    commitSnapshot(controller.getSnapshot());

    if (controller.shouldTick || getIsHeightAnimationActive(heightAnimationRef.current)) {
      scheduleRevealFrame();
    } else {
      cancelRevealFrame();
    }
  }, [
    graphemes, isStreaming, revealSessionKey, shouldAnimate, shouldRevealFromStart, target,
    cancelRevealFrame, commitSnapshot, scheduleRevealFrame,
  ]);

  useEffect(tryNotifyRevealComplete, [tryNotifyRevealComplete, visualPhase]);

  useLayoutEffect(() => {
    const previousCount = previousRenderedCountRef.current;
    const currentCount = visibleGraphemeCount;
    const content = contentRef.current;
    const currentTextContent = content?.textContent ?? '';

    previousRenderedCountRef.current = currentCount;
    if (previousCount !== currentCount) {
      notifyRevealProgress();
      scheduleContentHeightUpdate();
    }

    if (
      !content
      || !shouldAnimate
      || currentCount <= previousCount
    ) {
      if (!shouldAnimate || currentCount < previousCount) {
        clearRevealEdges(revealEdgeGroupsRef);
      }
    } else {
      animateRevealEdges(
        containerRef.current,
        content,
        revealEdgeLayerRef.current,
        previousTextContentRef.current,
        currentTextContent,
        revealEdgeGroupsRef,
        lifecycleGenerationRef,
        tryNotifyRevealComplete,
      );
    }

    previousTextContentRef.current = currentTextContent;

    if (
      !shouldAnimate
      || visualPhase === 'complete'
      || typeof ResizeObserver === 'undefined'
    ) {
      updateContentHeight();
    }
  }, [
    notifyRevealProgress,
    scheduleContentHeightUpdate,
    shouldAnimate,
    updateContentHeight,
    visibleGraphemeCount,
    visualPhase,
    tryNotifyRevealComplete,
  ]);

  useEffect(() => {
    const content = contentRef.current;
    if (!content || typeof ResizeObserver === 'undefined') return undefined;

    const observer = new ResizeObserver(scheduleContentHeightUpdate);
    resizeObserverRef.current = observer;
    observer.observe(content);
    updateContentHeight();

    return () => {
      observer.disconnect();
      if (resizeObserverRef.current === observer) {
        resizeObserverRef.current = undefined;
      }
    };
  }, [scheduleContentHeightUpdate, updateContentHeight]);

  useEffect(() => {
    const container = containerRef.current;

    return () => {
      lifecycleGenerationRef.current += 1;
      heightMutationRevisionRef.current += 1;
      pendingHeightMutationRevisionRef.current = undefined;
      cancelRevealFrame();
      resizeObserverRef.current?.disconnect();
      clearRevealEdges(revealEdgeGroupsRef);
      if (container) {
        mutateStreamingTextDom(() => {
          resetHeightAnimation(container, heightAnimationRef);
        });
      }
    };
  }, [cancelRevealFrame]);

  return {
    containerRef,
    contentRef,
    revealEdgeLayerRef,
    visibleText,
    visualPhase,
  };
}
