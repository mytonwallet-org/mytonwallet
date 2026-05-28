import React, { memo, useMemo, useState } from '../../../lib/teact/teact';

import type { PortfolioStackSegment } from '../helpers/buildStackSegments';

import buildClassName from '../../../util/buildClassName';

import useLastCallback from '../../../hooks/useLastCallback';

import StackChart from './StackChart';

import styles from './InsightCard.module.scss';

interface OwnProps {
  segments: PortfolioStackSegment[];
  emptyText: string;
}

const PERCENT_UNITS = 1000; // 0.1% granularity

function InsightCard({ segments, emptyText }: OwnProps) {
  const total = useMemo(() => segments.reduce((sum, s) => sum + s.rawAmount, 0), [segments]);
  const isEmpty = segments.length === 0 || total <= 0;

  const percentLabels = useMemo(() => buildPercentLabels(segments, total), [segments, total]);

  const [hoveredId, setHoveredId] = useState<string | undefined>(undefined);

  const handleHover = useLastCallback((id: string | undefined) => {
    setHoveredId(id);
  });

  return (
    <section className={styles.root}>
      <div className={styles.card}>
        {isEmpty ? (
          <div className={styles.empty}>{emptyText}</div>
        ) : (
          <>
            <StackChart segments={segments} hoveredId={hoveredId} onHover={handleHover} />
            <ul className={styles.legend}>
              {segments.map((segment, index) => (
                <li
                  key={segment.id}
                  className={buildClassName(
                    styles.legendItem,
                    hoveredId !== undefined && hoveredId !== segment.id && styles.legendItemFaded,
                  )}
                  onMouseEnter={() => handleHover(segment.id)}
                  onMouseLeave={() => handleHover(undefined)}
                >
                  <span className={styles.legendTitle} style={`color: ${segment.colorHex};`}>
                    {segment.title}
                  </span>
                  <span className={styles.legendValue}>{percentLabels[index]}</span>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </section>
  );
}

export default memo(InsightCard);

// Largest-remainder rounding at 0.1% granularity so the displayed shares always sum to exactly 100%
function buildPercentLabels(segments: PortfolioStackSegment[], total: number): string[] {
  const exact = segments.map((s) => (s.rawAmount / total) * PERCENT_UNITS);
  const units = exact.map(Math.floor);
  let remainder = PERCENT_UNITS - units.reduce((sum, u) => sum + u, 0);

  const byFraction = exact
    .map((value, index) => ({ index, fraction: value - units[index] }))
    .sort((a, b) => b.fraction - a.fraction);

  for (let i = 0; i < byFraction.length && remainder > 0; i++) {
    units[byFraction[i].index] += 1;
    remainder -= 1;
  }

  return units.map((u) => {
    const whole = Math.floor(u / 10);
    const decimal = u % 10;

    return decimal === 0 ? `${whole}%` : `${whole}.${decimal}%`;
  });
}
