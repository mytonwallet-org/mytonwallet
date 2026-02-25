import type { TeactNode } from '../../lib/teact/teact';
import React, {
  type ElementRef,
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { clamp } from '../../util/math';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import styles from './Draggable.module.scss';

type TPoint = {
  x: number;
  y: number;
};

type Offset = {
  top?: number;
  bottom?: number;
  left?: number;
  right?: number;
};

type DraggableState = {
  isDragging: boolean;
  scrollTop: number;
  origin: TPoint;
  translation: TPoint;
  width?: number;
  height?: number;
};

type OwnProps = {
  children: TeactNode;
  onDrag: (translation: TPoint, id: number | string) => void;
  onDragEnd: NoneToVoidFunction;
  id: number | string;
  style?: string;
  knobStyle?: string;
  isDisabled?: boolean;
  offset?: Offset;
  parentRef?: ElementRef<HTMLDivElement>;
  scrollRef?: ElementRef<HTMLDivElement>;
  className?: string;
  onClick: (e: React.MouseEvent | React.TouchEvent) => void;
};

const ZERO_POINT: TPoint = { x: 0, y: 0 };

const DEFAULT_OFFSET: Offset = {
  top: 0,
  bottom: 0,
  left: 0,
  right: 0,
};

const EDGE_THRESHOLD = 150;

function Draggable({
  children,
  id,
  onDrag,
  onDragEnd,
  style: externalStyle,
  knobStyle,
  isDisabled,
  offset = DEFAULT_OFFSET,
  parentRef,
  scrollRef,
  className,
  onClick,
}: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();
  const buttonRef = useRef<HTMLDivElement>();
  const scrollIntervalId = useRef<number>();

  const [state, setState] = useState<DraggableState>({
    isDragging: false,
    scrollTop: 0,
    origin: ZERO_POINT,
    translation: ZERO_POINT,
  });

  const lastMousePosition = useRef<TPoint>({ x: 0, y: 0 });

  const updateDraggablePosition = () => {
    if (!state.isDragging || !ref.current || !parentRef?.current || !scrollRef?.current) return;

    const translation = calculateConstrainedTranslation(
      state,
      lastMousePosition.current,
      scrollRef.current.scrollTop,
      ref.current,
      parentRef.current,
      offset,
    );

    setState((current) => ({
      ...current,
      translation,
    }));

    onDrag(translation, id);
  };

  const stopContinuousScroll = () => {
    if (scrollIntervalId.current !== undefined) {
      cancelAnimationFrame(scrollIntervalId.current);
      scrollIntervalId.current = undefined;
    }
  };

  const startContinuousScroll = (scrollContainer: HTMLElement, speed: number) => {
    const animateScroll = () => {
      scrollContainer.scrollBy(0, speed);
      updateDraggablePosition();
      scrollIntervalId.current = requestAnimationFrame(animateScroll);
    };

    stopContinuousScroll();
    animateScroll();
  };

  const setInitialState = (e: React.MouseEvent | TouchEvent) => {
    const origin = getClientCoordinate(e);
    const scrollTop = scrollRef?.current?.scrollTop ?? 0;

    setState({
      ...state,
      isDragging: true,
      origin,
      scrollTop,
      width: ref.current?.offsetWidth,
      height: ref.current?.offsetHeight,
    });
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    setInitialState(e);
  };

  const handleTouchStart = useLastCallback((e: TouchEvent) => {
    e.stopPropagation();
    e.preventDefault();
    setInitialState(e);
  });

  const handleMouseMove = useLastCallback((e: MouseEvent | TouchEvent) => {
    if (!ref.current || !parentRef?.current || !scrollRef?.current) return;

    const { x, y } = getClientCoordinate(e);
    lastMousePosition.current = { x, y };

    const translation = calculateConstrainedTranslation(
      state,
      lastMousePosition.current,
      scrollRef.current.scrollTop,
      ref.current,
      parentRef.current,
      offset,
    );

    const scrollRect = scrollRef.current.getBoundingClientRect();
    const distanceFromTop = y - scrollRect.top;
    const distanceFromBottom = scrollRect.bottom - y;

    if (distanceFromTop < EDGE_THRESHOLD) {
      startContinuousScroll(
        scrollRef.current,
        -scaledEase((EDGE_THRESHOLD - distanceFromTop) / EDGE_THRESHOLD),
      );
    } else if (distanceFromBottom < EDGE_THRESHOLD) {
      startContinuousScroll(
        scrollRef.current,
        scaledEase((EDGE_THRESHOLD - distanceFromBottom) / EDGE_THRESHOLD),
      );
    } else {
      stopContinuousScroll();
    }

    setState((current) => ({
      ...current,
      translation,
    }));

    onDrag(translation, id);
  });

  const handleMouseUp = useLastCallback(() => {
    setState((current) => ({
      ...current,
      isDragging: false,
      width: undefined,
      height: undefined,
    }));

    onDragEnd();
  });

  const handleClick = useLastCallback((e: React.MouseEvent | React.TouchEvent) => {
    if (state.isDragging) {
      return;
    }

    onClick(e);
  });

  useEffect(() => {
    const dragButtonRef = buttonRef.current;

    if (dragButtonRef) {
      dragButtonRef.addEventListener('touchstart', handleTouchStart, { passive: false });
    }

    if (state.isDragging) {
      window.addEventListener('touchmove', handleMouseMove);
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('touchend', handleMouseUp);
      window.addEventListener('touchcancel', handleMouseUp);
      window.addEventListener('mouseup', handleMouseUp);
    } else {
      stopContinuousScroll();
      window.removeEventListener('touchmove', handleMouseMove);
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('touchend', handleMouseUp);
      window.removeEventListener('touchcancel', handleMouseUp);
      window.removeEventListener('mouseup', handleMouseUp);

      setState((current) => ({
        ...current,
        translation: ZERO_POINT,
      }));
    }

    return () => {
      if (state.isDragging) {
        stopContinuousScroll();
        window.removeEventListener('touchmove', handleMouseMove);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('touchend', handleMouseUp);
        window.removeEventListener('touchcancel', handleMouseUp);
        window.removeEventListener('mouseup', handleMouseUp);

        if (dragButtonRef) {
          dragButtonRef.removeEventListener('touchstart', handleTouchStart);
        }
      }
    };
  }, [handleMouseMove, handleMouseUp, handleTouchStart, state.isDragging, buttonRef, isDisabled]);

  const fullClassName = buildClassName(styles.container, className, state.isDragging && styles.isDragging);

  const cssStyles = useMemo(() => {
    return buildStyle(
      state.isDragging && `transform: translate(${state.translation.x}px, ${state.translation.y}px)`,
      state.width ? `width: ${state.width}px` : undefined,
      state.height ? `height: ${state.height}px` : undefined,
      externalStyle,
    );
  }, [externalStyle, state.height, state.isDragging, state.translation.x, state.translation.y, state.width]);

  return (
    <div style={cssStyles} className={fullClassName} ref={ref} onClick={handleClick}>
      {!isDisabled && (
        <div
          ref={buttonRef}
          aria-label={lang('i18n_dragToSort')}
          tabIndex={0}
          role="button"
          className={buildClassName(styles.knob, 'div-button', 'draggable-knob')}
          onMouseDown={handleMouseDown}
          style={knobStyle}
        >
          <i className="icon icon-sort" aria-hidden />
        </div>
      )}
      {children}
    </div>
  );
}

export default memo(Draggable);

function getClientCoordinate(e: MouseEvent | TouchEvent | React.MouseEvent | React.TouchEvent) {
  let x;
  let y;

  if ('touches' in e) {
    x = e.touches[0].clientX;
    y = e.touches[0].clientY;
  } else {
    x = e.clientX;
    y = e.clientY;
  }

  return { x, y };
}

function scaledEase(n: number) {
  return 5 * (n ** 3) + 1;
}

function calculateConstrainedTranslation(
  state: DraggableState,
  lastMousePosition: TPoint,
  lastScrollTop: number,
  draggableElement: HTMLDivElement,
  parentElement: HTMLDivElement,
  offset: Offset,
) {
  const translation = {
    x: lastMousePosition.x - state.origin.x,
    y: lastMousePosition.y - state.origin.y + lastScrollTop - state.scrollTop,
  };

  const {
    top = 0, right = 0, bottom = 0, left = 0,
  } = offset;

  const parentRect = parentElement.getBoundingClientRect();
  const draggableRect = draggableElement.getBoundingClientRect();

  const minX = -draggableElement.offsetLeft + left;
  const maxX = parentRect.width - draggableRect.width - draggableElement.offsetLeft + right;
  const minY = -draggableElement.offsetTop + top;
  const maxY = parentRect.height - draggableRect.height - draggableElement.offsetTop + bottom;

  return {
    x: clamp(translation.x, minX, maxX),
    y: clamp(translation.y, minY, maxY),
  };
}
