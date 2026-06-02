import React, { memo } from '../../../lib/teact/teact';

import type { ApiPriceHistoryPeriod } from '../../../api/types';

import buildClassName from '../../../util/buildClassName';
import buildStyle from '../../../util/buildStyle';
import { PORTFOLIO_TIME_RANGES } from '../../../util/portfolio/timeRange';
import { SWIPE_DISABLED_CLASS_NAME } from '../../../util/swipeController';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useDraggablePill from '../../main/sections/Actions/hooks/useDraggablePill';

import Pill from '../../main/sections/Actions/Pill';

import styles from './TimeRangeSelector.module.scss';

interface RangeButtonProps {
  range: ApiPriceHistoryPeriod;
  isActive: boolean;
  isSelected: boolean;
  label: string;
  onClick: (range: ApiPriceHistoryPeriod) => void;
}

interface OwnProps {
  value: ApiPriceHistoryPeriod;
  onChange: (range: ApiPriceHistoryPeriod) => void;
}

const TAB_COUNT = PORTFOLIO_TIME_RANGES.length;

// The range value matches the backend (`1D/7D/…`); these are the short display labels
const RANGE_LABEL_KEYS: Record<ApiPriceHistoryPeriod, string> = {
  ALL: 'All',
  '1Y': 'Y',
  '3M': '3M',
  '1M': 'M',
  '7D': 'W',
  '1D': 'D',
};

function TimeRangeSelector({ value, onChange }: OwnProps) {
  const lang = useLang();

  const activeIndex = Math.max(0, PORTFOLIO_TIME_RANGES.indexOf(value));

  const handleCommit = useLastCallback((index: number) => {
    const range = PORTFOLIO_TIME_RANGES[index];
    if (range !== undefined) onChange(range);
  });

  const {
    capsuleRef,
    isDragging,
    squeeze,
    renderedActiveIndex,
    pointerHandlers,
  } = useDraggablePill({
    tabCount: TAB_COUNT,
    activeIndex,
    onCommit: handleCommit,
  });

  const rootStyle = buildStyle(
    `--tab-count: ${TAB_COUNT}`,
    `--active-index: ${activeIndex}`,
  );

  return (
    <div
      ref={capsuleRef}
      role="tablist"
      className={buildClassName(styles.root, isDragging && styles.dragging, SWIPE_DISABLED_CLASS_NAME)}
      style={rootStyle}
      {...pointerHandlers}
    >
      <Pill isDragging={isDragging} squeeze={squeeze} />
      {PORTFOLIO_TIME_RANGES.map((range, index) => (
        <RangeButton
          key={range}
          range={range}
          isActive={renderedActiveIndex === index}
          isSelected={range === value}
          label={lang(RANGE_LABEL_KEYS[range])}
          onClick={onChange}
        />
      ))}
    </div>
  );
}

export default memo(TimeRangeSelector);

const RangeButton = memo(({
  range, isActive, isSelected, label, onClick,
}: RangeButtonProps) => {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={isSelected}
      className={buildClassName(styles.option, isActive && styles.optionActive)}
      onClick={() => onClick(range)}
    >
      {label}
    </button>
  );
});
