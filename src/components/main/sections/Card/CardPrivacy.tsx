import React, {
  type TeactNode,
  useEffect,
  useRef,
} from '../../../../lib/teact/teact';

import type { CardController } from '../../../../util/card/types';

import { forceMutation, suppressStrict } from '../../../../lib/fasterdom/fasterdom';
import buildClassName from '../../../../util/buildClassName';
import { createPrivacyField } from '../../../../util/card/privacy';
import { EARLY_FRAME_MARGIN_MS } from '../../../../util/card/surfaceLight';
import { captureProductionText, localPosition } from '../../../../util/card/textSnapshot';

import { getIsInBackground } from '../../../../hooks/useBackgroundMode';
import useLastCallback from '../../../../hooks/useLastCallback';

import styles from './CardPrivacy.module.scss';

const IDLE_FRAME_MS = 1000 / 30 - EARLY_FRAME_MARGIN_MS;
const ACTIVE_FRAME_MS = 1000 / 60 - EARLY_FRAME_MARGIN_MS;

interface OwnProps {
  children: TeactNode;
  isHidden: boolean;
  isDisabled: boolean;
  isBalance?: boolean;
  palette: [string, string];
  controller: CardController;
  /** Must change whenever the text colors may change. Size changes are picked up separately. */
  revision: string;
  className?: string;
  onClick?: NoneToVoidFunction;
}

function CardPrivacy({
  children,
  isHidden,
  isDisabled,
  isBalance,
  palette,
  controller,
  revision,
  className,
  onClick,
}: OwnProps) {
  const ref = useRef<HTMLSpanElement>();
  const contentRef = useRef<HTMLSpanElement>();
  const canvasRef = useRef<HTMLCanvasElement>();
  const fieldRef = useRef<ReturnType<typeof createPrivacyField>>();
  const redrawRef = useRef<NoneToVoidFunction>();
  const getState = useLastCallback(() => ({ isHidden, isDisabled, palette }));

  useEffect(() => {
    const root = ref.current!;
    const target = contentRef.current!;
    const canvas = canvasRef.current!;
    let rafId = 0;
    let previous = 0;
    let isVisible = true;
    let isCancelled = false;
    let signature = '';
    let gestureLayout: [x: number, y: number, width: number, height: number] | undefined;

    // The snapshot lays out a styled copy of the text, which cannot avoid a forced layout
    function capture(): HTMLCanvasElement {
      return suppressStrict(() => {
        const text = captureProductionText(target, { palette: getState().palette });

        return isBalance ? text : drawChangeCapsule(text, target, controller);
      });
    }

    function getIsShown() {
      return isVisible && !document.hidden && !getIsInBackground();
    }

    function draw(now: number) {
      rafId = 0;

      if (isCancelled || !getIsShown()) {
        previous = 0;
        return;
      }

      const field = fieldRef.current;
      if (!field) return;

      const { isDisabled: isFieldDisabled } = getState();
      const { motion } = controller;

      // Drifting dust looks the same at 30 fps, while transitions and finger tracking run at 60 fps like the surface
      const frameMs = field.isTransitioning || motion?.isPlaying ? ACTIVE_FRAME_MS : IDLE_FRAME_MS;

      if (previous && now - previous < frameMs) {
        rafId = requestAnimationFrame(draw);
        return;
      }

      const dt = previous ? Math.min(0.1, (now - previous) / 1000) : 1 / 60;
      previous = now;

      const card = controller.cardRef.current;
      let finger: [number, number] | undefined;

      if (card && motion?.isPlaying && motion.pointer) {
        gestureLayout ??= [...localPosition(target, card), card.clientWidth, card.clientHeight];

        const [x, y, width, height] = gestureLayout;
        finger = [((motion.pointer[0] + 1) * width) / 2 - x, ((motion.pointer[1] + 1) * height) / 2 - y];
      } else {
        gestureLayout = undefined;
      }

      forceMutation(() => {
        field.advance(dt, finger, isFieldDisabled, motion?.isHovering ? 'mouse' : 'touch');
      }, target);

      // While hidden, the dust keeps drifting until the field is off screen, the tab is hidden or the app goes
      // to the background. `start` resumes it then.
      if (field.isTransitioning || (!isFieldDisabled && field.isConcealed)) {
        rafId = requestAnimationFrame(draw);
      }
    }

    function start() {
      if (!getIsShown()) return;

      // After a pause, the first frame moves the animation by one frame, not by the whole pause.
      // A frame queued in a hidden tab runs only after the pause, so it is reset as well.
      previous = 0;
      if (!rafId) rafId = requestAnimationFrame(draw);
    }

    function layout() {
      if (isCancelled) return;

      const width = target.offsetWidth;
      const height = target.offsetHeight;
      if (!width || !height) return;

      const { isHidden: isFieldHidden, palette: fieldPalette } = getState();
      const font = getComputedStyle(target.firstElementChild ?? target);
      const dustPalette: [string, string] = isBalance ? fieldPalette : [font.color, font.color];
      const key = `${width}:${height}:${dustPalette.join(':')}`;

      if (key === signature) {
        start();
        return;
      }

      signature = key;

      const ctx = document.createElement('canvas').getContext('2d')!;
      ctx.font = `${font.fontWeight} ${font.fontSize} ${font.fontFamily}`;

      const glyph = ctx.measureText('0');
      const fieldWidth = isBalance ? Math.min(224, controller.cardRef.current!.clientWidth - 24) : 130;
      const fieldHeight = isBalance
        ? Math.min(height, glyph.actualBoundingBoxAscent + glyph.actualBoundingBoxDescent + 2)
        : 26;
      const previousField = fieldRef.current;

      forceMutation(() => {
        const field = createPrivacyField(
          canvas,
          target,
          capture,
          width,
          height,
          dustPalette,
          {
            x: (width - fieldWidth) / 2,
            y: (height - fieldHeight) / 2,
            width: fieldWidth,
            height: fieldHeight,
          },
          previousField?.time ?? 0,
          previousField?.dust,
        );
        field.toggle(isFieldHidden, [width / 2, height / 2], true);
        fieldRef.current = field;
      }, [canvas, target]);

      start();
    }

    // While a CSS color transition runs, the computed color is not final yet
    function handleTransitionEnd(e: TransitionEvent) {
      if (e.propertyName === 'color') layout();
    }

    const resizeObserver = new ResizeObserver(layout);
    resizeObserver.observe(target);
    target.addEventListener('transitionend', handleTransitionEnd);

    const intersectionObserver = new IntersectionObserver(([entry]) => {
      isVisible = entry.isIntersecting;
      start();
    });
    intersectionObserver.observe(root);
    document.addEventListener('visibilitychange', start);
    const unsubscribeFromBackground = getIsInBackground.subscribe(start);
    layout();
    redrawRef.current = start;
    void document.fonts.ready.then(layout);

    return () => {
      isCancelled = true;
      cancelAnimationFrame(rafId);
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      target.removeEventListener('transitionend', handleTransitionEnd);
      document.removeEventListener('visibilitychange', start);
      unsubscribeFromBackground();

      // Synchronous, so the removal cannot land after the next effect run has set up a new field.
      // The cleanup runs in the measure phase on a dependency change and in the mutate phase on unmount,
      // and `forceMutation` rejects the mutate phase.
      suppressStrict(() => {
        target.style.removeProperty('visibility');
      });
    };
  }, [isBalance, revision, controller, getState]);

  useEffect(() => {
    const field = fieldRef.current;
    const target = contentRef.current;
    if (!field || !target) return;

    const card = controller.cardRef.current;
    const position = card ? localPosition(target, card) : [0, 0];
    const origin: [number, number] = controller.origin
      ? [controller.origin[0] - position[0], controller.origin[1] - position[1]]
      : [target.offsetWidth / 2, target.offsetHeight / 2];

    forceMutation(() => {
      field.toggle(isHidden, origin, isDisabled);
    }, target);

    redrawRef.current?.();
  }, [isHidden, isDisabled, controller]);

  return (
    <span
      ref={ref}
      className={buildClassName(styles.root, className, isBalance && styles.balance)}
      onClick={onClick}
    >
      <span className={styles.anchor}>
        <span
          ref={contentRef}
          className={buildClassName(styles.content, isHidden && styles.concealed)}
          aria-hidden={isHidden}
        >
          {children}
        </span>
        <canvas ref={canvasRef} className={styles.dust} aria-hidden data-measure-exclude />
      </span>
    </span>
  );
}

export default CardPrivacy;

/**
 * Hiding the change hides its whole capsule, so the snapshot draws the capsule too, and it dissolves with the text.
 * The glass gradient and the rim of `.change` are too faint to see on the flying fragments and are left out.
 */
function drawChangeCapsule(text: HTMLCanvasElement, target: HTMLElement, controller: CardController) {
  const result = document.createElement('canvas');
  result.width = text.width;
  result.height = text.height;

  const ctx = result.getContext('2d')!;
  const width = text.width / 2;
  const height = text.height / 2;
  ctx.scale(2, 2);

  // Two arcs instead of `roundRect`, which Chrome supports only from version 99
  ctx.beginPath();
  ctx.arc(height / 2, height / 2, height / 2, Math.PI / 2, Math.PI * 1.5);
  ctx.arc(width - height / 2, height / 2, height / 2, Math.PI * 1.5, Math.PI / 2);
  ctx.closePath();
  ctx.clip();

  const card = controller.cardRef.current;
  const backdrop = controller.getBackdrop?.();

  if (card && backdrop) {
    const [x, y] = localPosition(target, card);
    ctx.filter = 'blur(12px)';
    ctx.drawImage(backdrop, -x, -y, card.clientWidth, card.clientHeight);
    ctx.filter = 'none';
  }

  ctx.fillStyle = getComputedStyle(target.firstElementChild!).backgroundColor;
  ctx.fillRect(0, 0, width, height);
  ctx.drawImage(text, 0, 0, width, height);

  return result;
}
