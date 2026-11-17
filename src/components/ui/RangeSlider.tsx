import type { TeactNode } from '../../lib/teact/teact';
import React, { useRef } from '../../lib/teact/teact';

import buildStyle from '../../util/buildStyle';
import { findLast } from '../../util/iteratees';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import styles from './RangeSlider.module.scss';

interface OwnProps {
  /** The thumb position in the `[0, 1]` range */
  position: number;
  /** The dots under the track, in the `[0, 1]` range and in ascending order */
  tickPositions: number[];
  ariaLabel: string;
  /** The value of the thumb as the screen shows it, which a screen reader reads instead of the step number */
  ariaValueText?: string;
  /** The value between the Min and Max buttons */
  children: TeactNode;
  onChange: (position: number) => void;
  onMinClick: NoneToVoidFunction;
  onMaxClick: NoneToVoidFunction;
}

/** How many steps the thumb takes from one end of the track to the other */
const STEP_COUNT = 1000;
/** A thumb dragged this close to a tick, in pixels, lands on the tick */
const TICK_SNAP_DISTANCE_PX = 8;

/** The Min and Max buttons with the value between them, and the slider below them */
function RangeSlider({
  position,
  tickPositions,
  ariaLabel,
  ariaValueText,
  children,
  onChange,
  onMinClick,
  onMaxClick,
}: OwnProps) {
  const lang = useLang();

  // The dots span the path of the thumb center, which is the input width without the thumb
  const ticksRef = useRef<HTMLDivElement>();
  // A key moves the thumb by one step, which is too small to see, and the snap would return the thumb to the tick it
  // leaves. So the keyboard moves the thumb to the next tick instead.
  const isKeyPressedRef = useRef(false);

  const handleKeyDown = useLastCallback(() => {
    isKeyPressedRef.current = true;
  });

  const handleKeyRelease = useLastCallback(() => {
    isKeyPressedRef.current = false;
  });

  const handleSliderChange = useLastCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const nextPosition = Number(e.currentTarget.value) / STEP_COUNT;
    const tick = isKeyPressedRef.current
      ? findNextTick(tickPositions, nextPosition, nextPosition > position)
      : findSnapTick(tickPositions, nextPosition, ticksRef.current!.offsetWidth);

    onChange(tick ?? nextPosition);
  });

  return (
    <>
      <div className={styles.controls}>
        <button type="button" className={styles.boundButton} onClick={onMinClick}>
          {lang('Min')}
        </button>
        {children}
        <button type="button" className={styles.boundButton} onClick={onMaxClick}>
          {lang('Max')}
        </button>
      </div>

      <div className={styles.sliderArea} style={buildStyle(`--fill: ${position}`)}>
        <div className={styles.track} />
        <div ref={ticksRef} className={styles.ticks} aria-hidden>
          {tickPositions.map((tick) => (
            <i key={tick} className={styles.tick} style={buildStyle(`--position: ${tick * 100}%`)} />
          ))}
        </div>
        <input
          type="range"
          min="0"
          max={STEP_COUNT}
          step="1"
          value={Math.round(position * STEP_COUNT)}
          className={styles.slider}
          aria-label={ariaLabel}
          aria-valuetext={ariaValueText}
          onChange={handleSliderChange}
          onKeyDown={handleKeyDown}
          onKeyUp={handleKeyRelease}
          onBlur={handleKeyRelease}
        />
      </div>
    </>
  );
}

export default RangeSlider;

// The browser has already moved the value in the direction of the key, so the next tick is the first one at or past
// the new value in that direction
function findNextTick(tickPositions: number[], nextPosition: number, isForward: boolean) {
  return isForward
    ? tickPositions.find((tick) => tick >= nextPosition)
    : findLast(tickPositions, (tick) => tick <= nextPosition);
}

function findSnapTick(tickPositions: number[], position: number, pathWidth: number) {
  let nearestTick: number | undefined;
  let nearestDistance = TICK_SNAP_DISTANCE_PX;

  tickPositions.forEach((tick) => {
    const distance = Math.abs(tick - position) * pathWidth;
    if (distance >= nearestDistance) return;

    nearestTick = tick;
    nearestDistance = distance;
  });

  return nearestTick;
}
