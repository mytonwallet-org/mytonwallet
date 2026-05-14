import type React from '../../../../../lib/teact/teact';
import { useRef, useState } from '../../../../../lib/teact/teact';

import { requestMutation } from '../../../../../lib/fasterdom/fasterdom';
import { vibrate } from '../../../../../util/haptics';
import { REM } from '../../../../../util/windowEnvironment';

import useEffectOnce from '../../../../../hooks/useEffectOnce';
import useLastCallback from '../../../../../hooks/useLastCallback';

const CAPSULE_PADDING_PX = 0.25 * REM;
const DRAG_THRESHOLD_PX = 5;

interface DragState {
  pointerId: number;
  startX: number;
  fromIndex: number;
  isDragStarted: boolean;
}

export default function useDraggablePill({
  tabCount,
  activeIndex,
  onCommit,
}: {
  tabCount: number;
  activeIndex: number;
  onCommit: (index: number) => void;
}) {
  const capsuleRef = useRef<HTMLDivElement>();
  const dragStateRef = useRef<DragState | undefined>(undefined);
  const previewIndexRef = useRef<number | undefined>(undefined);
  // Holds the cleanup for window-level `pointerup`/`pointercancel` listeners attached
  // in `handlePointerDown`. Until the drag threshold is crossed, `setPointerCapture` is
  // not yet called, so a release outside the capsule would not bubble to capsule's
  // `onPointerUp` and would leak `dragStateRef`. The window listeners are the fallback.
  const detachAbortRef = useRef<NoneToVoidFunction | undefined>(undefined);
  const [previewIndex, setPreviewIndex] = useState<number | undefined>(undefined);
  const [isDragging, setIsDragging] = useState(false);

  useEffectOnce(() => () => detachAbortRef.current?.());

  const handlePointerDown = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    if (!capsuleRef.current) return;
    if (dragStateRef.current) return;

    const rect = capsuleRef.current.getBoundingClientRect();
    const tabWidth = (rect.width - CAPSULE_PADDING_PX * 2) / tabCount;
    const pillLeft = rect.left + CAPSULE_PADDING_PX + activeIndex * tabWidth;
    const pillRight = pillLeft + tabWidth;
    if (e.clientX < pillLeft || e.clientX > pillRight) return;

    const { pointerId } = e;
    dragStateRef.current = {
      pointerId,
      startX: e.clientX,
      fromIndex: activeIndex,
      isDragStarted: false,
    };

    const abort = (event: PointerEvent) => {
      if (event.pointerId !== pointerId) return;

      detachAbortRef.current?.();

      if (dragStateRef.current?.pointerId === pointerId && !dragStateRef.current.isDragStarted) {
        dragStateRef.current = undefined;
      }
    };

    window.addEventListener('pointerup', abort);
    window.addEventListener('pointercancel', abort);
    detachAbortRef.current = () => {
      window.removeEventListener('pointerup', abort);
      window.removeEventListener('pointercancel', abort);

      detachAbortRef.current = undefined;
    };
  });

  const handlePointerMove = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    const state = dragStateRef.current;
    if (!state || state.pointerId !== e.pointerId || !capsuleRef.current) return;

    const delta = e.clientX - state.startX;
    if (!state.isDragStarted) {
      if (Math.abs(delta) < DRAG_THRESHOLD_PX) return;

      state.isDragStarted = true;
      detachAbortRef.current?.();
      void vibrate();
      setIsDragging(true);
      try {
        capsuleRef.current.setPointerCapture(e.pointerId);
      } catch {
        // ignore
      }
    }

    const rect = capsuleRef.current.getBoundingClientRect();
    const tabWidth = (rect.width - CAPSULE_PADDING_PX * 2) / tabCount;
    const minOffset = -state.fromIndex * tabWidth;
    const maxOffset = (tabCount - 1 - state.fromIndex) * tabWidth;
    const constrained = Math.max(minOffset, Math.min(maxOffset, delta));
    const capsule = capsuleRef.current;
    requestMutation(() => {
      capsule.style.setProperty('--drag-offset-px', `${constrained}px`);
    });

    const center = state.fromIndex + constrained / tabWidth;
    const idx = Math.max(0, Math.min(tabCount - 1, Math.round(center)));
    if (idx !== previewIndexRef.current) {
      previewIndexRef.current = idx;
      setPreviewIndex(idx);
    }
  });

  const handlePointerUp = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    const state = dragStateRef.current;
    if (!state || state.pointerId !== e.pointerId) return;

    const target = previewIndexRef.current ?? state.fromIndex;
    handleDragEnd(state, e.pointerId);

    if (state.isDragStarted && target !== state.fromIndex) {
      onCommit(target);
    }
  });

  const handlePointerCancel = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    const state = dragStateRef.current;
    if (!state || state.pointerId !== e.pointerId) return;

    handleDragEnd(state, e.pointerId);
  });

  function handleDragEnd(state: DragState, pointerId: number) {
    detachAbortRef.current?.();
    dragStateRef.current = undefined;
    previewIndexRef.current = undefined;

    if (state.isDragStarted) {
      try {
        capsuleRef.current?.releasePointerCapture(pointerId);
      } catch {
        // ignore
      }
    }

    requestMutation(() => {
      capsuleRef.current?.style.removeProperty('--drag-offset-px');
    });
    setIsDragging(false);
    setPreviewIndex(undefined);
  }

  return {
    capsuleRef,
    isDragging,
    previewIndex,
    pointerHandlers: {
      onPointerDown: handlePointerDown,
      onPointerMove: handlePointerMove,
      onPointerUp: handlePointerUp,
      onPointerCancel: handlePointerCancel,
    },
  };
}
