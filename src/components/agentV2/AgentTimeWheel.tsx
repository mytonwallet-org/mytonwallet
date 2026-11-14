import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import type { AgentDigestMinute, AgentDigestTime } from './agentDigestTime';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import { toNativeDigits } from '../../util/nativeDigits';
import { REM } from '../../util/windowEnvironment';
import { AGENT_DIGEST_MINUTES } from './agentDigestTime';

import useLastCallback from '../../hooks/useLastCallback';

import styles from './AgentTimeWheel.module.scss';

interface OwnProps {
  time: AgentDigestTime;
  isOpen: boolean;
  /** The columns' names for a screen reader */
  hourLabel: string;
  minuteLabel: string;
  onHourChange: (hour: number) => void;
  onMinuteChange: (minute: AgentDigestMinute) => void;
}

interface ColumnProps {
  values: readonly number[];
  index: number;
  isOpen: boolean;
  label: string;
  /** The whole time, which a screen reader tells in either column */
  valueText: string;
  className: string;
  onSelect: (index: number) => void;
}

const HOURS = Array.from({ length: 24 }, (_, hour) => hour);
// A row's height, five of which show, the chosen one on the band
const ROW_HEIGHT = 2.25 * REM;
// A turn picks the value it settles on once the column has stood still this long
const SETTLE_DELAY = 120;

/**
 * The digest's time on a wheel, as iOS's and Android's time wheels: the hours and the minutes, a quarter of an hour
 * apart, turn past a band that marks the chosen time and snap to it. A turn picks the value it settles on, a tap the
 * value tapped, and the arrow keys move a column one row at a time. It opens and closes under its row as a curtain.
 */
function AgentTimeWheel({
  time, isOpen, hourLabel, minuteLabel, onHourChange, onMinuteChange,
}: OwnProps) {
  const timeText = formatDigestTime(time);

  const handleHourSelect = useLastCallback((index: number) => {
    onHourChange(HOURS[index]);
  });

  const handleMinuteSelect = useLastCallback((index: number) => {
    onMinuteChange(AGENT_DIGEST_MINUTES[index]);
  });

  return (
    <div className={buildClassName(styles.root, isOpen && styles.open)} aria-hidden={!isOpen}>
      <div className={styles.separator} />
      <div className={styles.wheel}>
        <MemoizedWheelColumn
          values={HOURS}
          index={HOURS.indexOf(time.hour)}
          isOpen={isOpen}
          label={hourLabel}
          valueText={timeText}
          className={styles.hours}
          onSelect={handleHourSelect}
        />
        <MemoizedWheelColumn
          values={AGENT_DIGEST_MINUTES}
          index={AGENT_DIGEST_MINUTES.indexOf(time.minute)}
          isOpen={isOpen}
          label={minuteLabel}
          valueText={timeText}
          className={styles.minutes}
          onSelect={handleMinuteSelect}
        />
        <div className={styles.band} aria-hidden />
      </div>
    </div>
  );
}

function WheelColumn({
  values, index, isOpen, label, valueText, className, onSelect,
}: ColumnProps) {
  const listRef = useRef<HTMLDivElement>();
  const settleTimeoutRef = useRef<number>();
  // The row the column stands at, which a turn moves before it settles
  const centeredIndexRef = useRef(index);

  const scrollToIndex = useLastCallback((target: number, isSmooth: boolean) => {
    const list = listRef.current;
    if (!list) return;
    centeredIndexRef.current = target;
    requestMutation(() => {
      list.scrollTo({ top: target * ROW_HEIGHT, behavior: isSmooth ? 'smooth' : 'instant' });
    });
  });

  // The column opens at the chosen value and follows it when it changes elsewhere, never fighting a turn in progress
  useEffect(() => {
    if (!isOpen || settleTimeoutRef.current !== undefined) return;
    if (centeredIndexRef.current === index && listRef.current?.scrollTop === index * ROW_HEIGHT) return;
    scrollToIndex(index, false);
  }, [index, isOpen, scrollToIndex]);

  useEffect(() => () => window.clearTimeout(settleTimeoutRef.current), []);

  const select = useLastCallback((target: number) => {
    const clamped = Math.min(Math.max(target, 0), values.length - 1);
    if (clamped !== index) onSelect(clamped);
    return clamped;
  });

  const handleScroll = useLastCallback(() => {
    window.clearTimeout(settleTimeoutRef.current);
    settleTimeoutRef.current = window.setTimeout(() => {
      settleTimeoutRef.current = undefined;
      requestMeasure(() => {
        const list = listRef.current;
        if (!list) return;
        const centered = Math.round(list.scrollTop / ROW_HEIGHT);
        centeredIndexRef.current = select(centered);
      });
    }, SETTLE_DELAY);
  });

  const handleRowClick = useLastCallback((e: React.MouseEvent<HTMLDivElement>) => {
    scrollToIndex(select(Number(e.currentTarget.dataset.index)), true);
  });

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    const target = getKeyTarget(e.key, index, values.length);
    if (target === undefined) return;

    e.preventDefault();
    scrollToIndex(select(target), true);
  });

  return (
    <div
      ref={listRef}
      className={buildClassName(styles.column, className)}
      role="spinbutton"
      tabIndex={isOpen ? 0 : -1}
      aria-label={label}
      aria-valuemin={values[0]}
      aria-valuemax={values[values.length - 1]}
      aria-valuenow={values[index]}
      aria-valuetext={valueText}
      onScroll={handleScroll}
      onKeyDown={handleKeyDown}
    >
      {values.map((rowValue, rowIndex) => (
        <div
          key={rowValue}
          className={styles.row}
          data-index={rowIndex}
          onClick={handleRowClick}
        >
          {formatTwoDigits(rowValue)}
        </div>
      ))}
    </div>
  );
}

const MemoizedWheelColumn = memo(WheelColumn);

export default memo(AgentTimeWheel);

// The arrow keys move a column a row at a time, Home and End to its first and last row
function getKeyTarget(key: string, index: number, rowCount: number) {
  switch (key) {
    case 'ArrowUp':
      return index + 1;
    case 'ArrowDown':
      return index - 1;
    case 'Home':
      return 0;
    case 'End':
      return rowCount - 1;
    default:
      return undefined;
  }
}

/** The time as the clock shows it, "21:45", in the language's digits, as the feed's times are */
export function formatDigestTime({ hour, minute }: AgentDigestTime) {
  return `${formatTwoDigits(hour)}:${formatTwoDigits(minute)}`;
}

function formatTwoDigits(value: number) {
  return toNativeDigits(String(value).padStart(2, '0'));
}
