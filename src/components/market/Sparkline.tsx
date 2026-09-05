import React, { memo, useMemo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useUniqueId from '../../hooks/useUniqueId';

import styles from './Market.module.scss';

interface OwnProps {
  points: number[];
  className?: string;
}

const WIDTH = 160;
const HEIGHT = 40;
// The curve occupies the upper part of the box, while the fill below it reaches the card edge
const CURVE_HEIGHT = 24;
const CURVE_PADDING = 2;
const MIN_VALUE_RANGE = 1e-9;

function Sparkline({ points, className }: OwnProps) {
  const gradientId = useUniqueId('market-sparkline-');
  const paths = useMemo(() => buildPaths(points), [points]);

  if (!paths) {
    return undefined;
  }

  return (
    <svg
      className={buildClassName(styles.sparkline, className)}
      width={WIDTH}
      height={HEIGHT}
      viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
      preserveAspectRatio="none"
      xmlns="http://www.w3.org/2000/svg"
      role="presentation"
    >
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" className={styles.sparklineGradientTop} />
          <stop offset="1" className={styles.sparklineGradientBottom} />
        </linearGradient>
      </defs>
      <path d={paths.area} fill={`url(#${gradientId})`} />
      <path d={paths.line} className={styles.sparklineLine} />
    </svg>
  );
}

export default memo(Sparkline);

function buildPaths(values: number[]) {
  if (values.length < 2) {
    return undefined;
  }

  const min = Math.min(...values);
  const max = Math.max(...values);
  const valueRange = Math.max(MIN_VALUE_RANGE, max - min);
  const stepX = WIDTH / (values.length - 1);
  const plotHeight = CURVE_HEIGHT - CURVE_PADDING * 2;

  const line = values
    .map((value, index) => {
      const x = index * stepX;
      const y = CURVE_PADDING + plotHeight - ((value - min) / valueRange) * plotHeight;

      return `${index === 0 ? 'M' : 'L'} ${x.toFixed(2)} ${y.toFixed(2)}`;
    })
    .join(' ');

  return { line, area: `${line} L ${WIDTH} ${HEIGHT} L 0 ${HEIGHT} Z` };
}
