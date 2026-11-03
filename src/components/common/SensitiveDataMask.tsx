import type { RefObject } from 'react';
import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { Theme } from '../../global/types';

import { requestMutation } from '../../lib/fasterdom/fasterdom';
import { animateInstantly } from '../../util/animation';
import { getIsInBackground } from '../../util/backgroundMode';
import buildClassName from '../../util/buildClassName';
import { clamp } from '../../util/math';
import { random } from '../../util/random';
import { DPR } from '../../util/windowEnvironment';

import { useGetIsIntersectingWithApp } from '../../hooks/useAppIntersectionObserver';
import useAppTheme from '../../hooks/useAppTheme';
import useDerivedSignal from '../../hooks/useDerivedSignal';

import styles from './SensitiveDataMask.module.scss';

export type SensitiveDataMaskSkin = (
  'lightTheme' | 'darkTheme' | 'cardLightText' | 'cardDarkText' | 'cardGoldText' | 'purple' | 'green'
  );

interface OwnProps {
  ref?: RefObject<HTMLCanvasElement>;
  cols: number;
  rows: number;
  cellSize: number;
  skin?: SensitiveDataMaskSkin;
  className?: string;
}

interface StateProps {
  theme: Theme;
}

interface AnimationState {
  opacityValues: number[][];
  steps: number[][];
  lastSpeedChangeAt?: number;
  isRendered: boolean;
}

interface RenderOptions {
  ctx: CanvasRenderingContext2D;
  cols: number;
  rows: number;
  width: number;
  height: number;
  cellSizeDpr: number;
  color: string;
}

// STEPS values are pre-multiplied by 1 / (1000 / 60) to compensate for FPS
const STEPS = [
  0.0001 * 0.06,
  0.0001 * 0.06,
  0.00001 * 0.06,
  0.0003 * 0.06,
  0.0001 * 0.06,
  0.0025 * 0.06,
];
const FROM = 0.07;
const TO = 0.25;
const CHANGE_SPEED_INTERVAL = 3000;
const SKIN_COLORS: Record<SensitiveDataMaskSkin, string> = {
  lightTheme: '120, 121, 122',
  darkTheme: '240, 241, 242',
  cardLightText: '250, 250, 250',
  cardDarkText: '10, 10, 10',
  cardGoldText: '101, 73, 16',
  purple: '96, 107, 215',
  green: '43, 196, 105',
};

function SensitiveDataMask({
  ref,
  cols,
  rows,
  cellSize,
  skin,
  className,
  theme,
}: OwnProps & StateProps) {
  let canvasRef = useRef<HTMLCanvasElement>();
  if (ref) {
    canvasRef = ref;
  }

  const cellSizeDpr = cellSize * DPR;

  const appTheme = useAppTheme(theme);
  const color = SKIN_COLORS[skin ?? `${appTheme}Theme`];

  const animationStateRef = useRef<AnimationState>({
    opacityValues: [],
    steps: [],
    lastSpeedChangeAt: undefined,
    isRendered: false,
  });

  const getIsIntersecting = useGetIsIntersectingWithApp(canvasRef);
  const getIsInBackground2 = getIsInBackground;
  const getShouldAnimate = useDerivedSignal(
    () => getIsIntersecting() && !getIsInBackground2(),
    [getIsIntersecting, getIsInBackground2],
  );

  useLayoutEffect(() => {
    const state = animationStateRef.current;

    if (state.isRendered && !getShouldAnimate()) return undefined;

    const canvas = canvasRef.current!;
    const ctx = canvas.getContext('2d')!;
    const width = cols * cellSizeDpr;
    const height = rows * cellSizeDpr;

    let shouldStop = false;
    let lastFrameAt: number | undefined;

    canvas.width = width;
    canvas.height = height;

    state.lastSpeedChangeAt = undefined;

    const renderOptions = { ctx, cols, rows, width, height, cellSizeDpr, color };

    animateInstantly(() => {
      if (shouldStop || (state.isRendered && !getShouldAnimate())) return false;

      const now = performance.now();
      const frameDuration = lastFrameAt ? now - lastFrameAt : 0;
      renderFrame(renderOptions, state, frameDuration);
      lastFrameAt = now;

      return true;
    }, requestMutation);

    return () => {
      shouldStop = true;
    };
  }, [cols, rows, cellSizeDpr, getShouldAnimate, color]);

  return (
    <canvas
      ref={canvasRef}
      style={`width: ${cellSize * cols}px; height: ${cellSize * rows}px`}
      className={buildClassName(styles.canvas, className)}
    />
  );
}

function renderFrame(
  options: RenderOptions,
  state: AnimationState,
  frameDuration = 0,
) {
  const {
    ctx, cols, rows, cellSizeDpr, width, height, color,
  } = options;

  const now = performance.now();
  const shouldChangeSpeed = state.lastSpeedChangeAt ? now - state.lastSpeedChangeAt >= CHANGE_SPEED_INTERVAL : false;

  if (shouldChangeSpeed || !state.lastSpeedChangeAt) {
    state.lastSpeedChangeAt = now;
  }

  ctx.clearRect(0, 0, width, height);

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      state.steps[row] ??= [];
      state.opacityValues[row] ??= [];

      if (shouldChangeSpeed) {
        state.steps[row][col] = sample(STEPS) * (state.steps[row][col] < 0 ? -1 : 1);
      } else {
        state.steps[row][col] ??= sample(STEPS);
      }

      let nextOpacity = state.opacityValues[row][col] ?? (Math.random() * (TO - FROM) + FROM);
      nextOpacity += state.steps[row][col] * frameDuration;
      if (nextOpacity > TO || nextOpacity < FROM) {
        state.steps[row][col] *= -1;
        nextOpacity = clamp(nextOpacity, FROM, TO);
      }

      state.opacityValues[row][col] = nextOpacity;

      ctx.fillStyle = `rgba(${color}, ${nextOpacity})`;
      ctx.fillRect(col * cellSizeDpr, row * cellSizeDpr, cellSizeDpr, cellSizeDpr);

      state.isRendered ||= true;
    }
  }
}

// Returns a random element from the array
function sample<T>(array: T[]): T {
  return array[random(0, array.length - 1)];
}

export default memo(withGlobal((global) => {
  return {
    theme: global.settings.theme,
  };
})(SensitiveDataMask));
