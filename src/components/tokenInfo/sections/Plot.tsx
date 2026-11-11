import React, { memo, useEffect, useLayoutEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';

import type { ApiHistoryList } from '../../../api/types';

import buildClassName from '../../../util/buildClassName';
import useTelegramMiniAppSwipeToClose from '../../../util/telegram/hooks/useTelegramMiniAppSwipeToClose';

import useLastCallback from '../../../hooks/useLastCallback';
import useUniqueId from '../../../hooks/useUniqueId';

import styles from './Plot.module.scss';

interface Point {
  x: number;
  y: number;
}

interface OwnProps {
  prices: ApiHistoryList;
  /** How many leading prices belong to the underlying stock rather than the token */
  backfillCount?: number;
  /** `-1` when the pointer is away from the plot */
  selectedIndex: number;
  className?: string;
  onSelectIndex: (index: number) => void;
}

const HEIGHT = 94;
// Keeps the end dot and its stroke inside the viewport
const EDGE_PADDING = 4;
const DOT_RADIUS = 3;
const SMOOTHING = 0.0001;
const MIN_VALUE_RANGE = 1e-9;
const DIMMED_OPACITY = 0.25;
const BACKFILL_OPACITY = 0.4;

function Plot({ prices, backfillCount = 0, selectedIndex, className, onSelectIndex }: OwnProps) {
  const containerRef = useRef<HTMLDivElement>();
  const [width, setWidth] = useState(0);

  const gradientId = useUniqueId('token-plot-gradient-');
  const pastClipId = useUniqueId('token-plot-past-');
  const restClipId = useUniqueId('token-plot-rest-');
  const backfillClipId = useUniqueId('token-plot-backfill-');
  const tokenClipId = useUniqueId('token-plot-token-');

  const { disableSwipeToClose, enableSwipeToClose } = useTelegramMiniAppSwipeToClose();

  // Leaving the screen mid-touch must not keep the gesture disabled
  useEffect(() => enableSwipeToClose, [enableSwipeToClose]);

  useLayoutEffect(() => {
    const element = containerRef.current;
    if (!element) return undefined;

    // The observer entry carries the size, so no layout read is needed
    const observer = new ResizeObserver(([entry]) => {
      setWidth(Math.round(entry.contentRect.width));
    });
    observer.observe(element);

    return () => observer.disconnect();
  }, []);

  const points = useMemo(() => buildPoints(prices, width), [prices, width]);

  // The paths depend on the data alone, while scrubbing only moves the clips and the dot
  const paths = useMemo(() => {
    if (!points) return undefined;

    const line = buildLinePath(points);
    const lastPoint = points[points.length - 1];

    return { line, area: `${line} L ${lastPoint.x} ${HEIGHT} L ${points[0].x} ${HEIGHT} Z` };
  }, [points]);

  const handleMove = useLastCallback((e: React.MouseEvent<HTMLDivElement> | React.TouchEvent<HTMLDivElement>) => {
    if (!points || points.length < 2) return;

    const { left } = e.currentTarget.getBoundingClientRect();
    const { clientX } = 'touches' in e ? e.touches[0] : e;

    onSelectIndex(findClosestIndex(points, clientX - left));
  });

  const handleTouchStart = useLastCallback((e: React.TouchEvent<HTMLDivElement>) => {
    handleMove(e);

    disableSwipeToClose();
  });

  const handleLeave = useLastCallback(() => {
    onSelectIndex(-1);

    enableSwipeToClose();
  });

  function renderSeries({ line, area }: { line: string; area: string }, isScrubbing: boolean) {
    return isScrubbing ? (
      <>
        <g clip-path={`url(#${pastClipId})`}>
          <path d={area} fill={`url(#${gradientId})`} />
          <path d={line} className={styles.line} />
        </g>
        <g clip-path={`url(#${restClipId})`} opacity={DIMMED_OPACITY}>
          <path d={area} fill={`url(#${gradientId})`} />
          <path d={line} className={styles.line} />
        </g>
      </>
    ) : (
      <>
        <path d={area} fill={`url(#${gradientId})`} />
        <path d={line} className={styles.line} />
      </>
    );
  }

  function renderPlot(allPoints: Point[], plotPaths: { line: string; area: string }) {
    const isScrubbing = selectedIndex >= 0 && selectedIndex < allPoints.length;
    const activeIndex = isScrubbing ? selectedIndex : allPoints.length - 1;
    const activePoint = allPoints[activeIndex];
    // The stock part runs up to the first token price, so the line stays continuous across the launch
    const launchX = backfillCount > 0 && backfillCount < allPoints.length ? allPoints[backfillCount].x : undefined;
    // A token without prices of its own in the period shows only the stock, which stays dimmed as a whole
    const seriesOpacity = backfillCount >= allPoints.length ? BACKFILL_OPACITY : undefined;

    return (
      <svg
        width={width}
        height={HEIGHT}
        viewBox={`0 0 ${width} ${HEIGHT}`}
        xmlns="http://www.w3.org/2000/svg"
        role="presentation"
      >
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" style="stop-color: var(--color-accent); stop-opacity: 0.1" />
            <stop offset="1" style="stop-color: var(--color-accent); stop-opacity: 0" />
          </linearGradient>
          {isScrubbing && (
            <clipPath id={pastClipId}>
              <rect x="0" y="0" width={activePoint.x} height={HEIGHT} />
            </clipPath>
          )}
          {isScrubbing && (
            <clipPath id={restClipId}>
              <rect x={activePoint.x} y="0" width={Math.max(0, width - activePoint.x)} height={HEIGHT} />
            </clipPath>
          )}
          {launchX !== undefined && (
            <clipPath id={backfillClipId}>
              <rect x="0" y="0" width={launchX} height={HEIGHT} />
            </clipPath>
          )}
          {launchX !== undefined && (
            <clipPath id={tokenClipId}>
              <rect x={launchX} y="0" width={Math.max(0, width - launchX)} height={HEIGHT} />
            </clipPath>
          )}
        </defs>

        {launchX === undefined ? (
          <g opacity={seriesOpacity}>
            {renderSeries(plotPaths, isScrubbing)}
          </g>
        ) : (
          <>
            <g clip-path={`url(#${backfillClipId})`} opacity={BACKFILL_OPACITY}>
              {renderSeries(plotPaths, isScrubbing)}
            </g>
            <g clip-path={`url(#${tokenClipId})`}>
              {renderSeries(plotPaths, isScrubbing)}
            </g>
          </>
        )}

        <circle
          className={styles.dot}
          cx={activePoint.x}
          cy={activePoint.y}
          r={DOT_RADIUS}
          opacity={activeIndex < backfillCount ? BACKFILL_OPACITY : undefined}
        />
      </svg>
    );
  }

  return (
    <div
      ref={containerRef}
      className={buildClassName(styles.root, className)}
      onMouseMove={handleMove}
      onMouseLeave={handleLeave}
      onTouchStart={handleTouchStart}
      onTouchMove={handleMove}
      onTouchEnd={handleLeave}
      onTouchCancel={handleLeave}
    >
      {points && paths && renderPlot(points, paths)}
    </div>
  );
}

function buildPoints(prices: ApiHistoryList, width: number) {
  if (!prices.length || !width) return undefined;

  let min = Infinity;
  let max = -Infinity;
  for (const [, value] of prices) {
    if (value < min) min = value;
    if (value > max) max = value;
  }

  const valueRange = Math.max(MIN_VALUE_RANGE, max - min);
  const plotWidth = Math.max(0, width - EDGE_PADDING * 2);
  const plotHeight = HEIGHT - EDGE_PADDING * 2;
  // Points are spaced by time, so a stock backfill of trading days and a daily token series share one scale
  const firstTimestamp = prices[0][0];
  const timeSpan = prices[prices.length - 1][0] - firstTimestamp;

  return prices.map(([timestamp, value]): Point => ({
    x: EDGE_PADDING + (timeSpan ? ((timestamp - firstTimestamp) / timeSpan) * plotWidth : 0),
    y: EDGE_PADDING + plotHeight - ((value - min) / valueRange) * plotHeight,
  }));
}

function findClosestIndex(points: Point[], x: number) {
  let low = 0;
  let high = points.length - 1;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (points[middle].x < x) low = middle + 1;
    else high = middle;
  }

  return low > 0 && x - points[low - 1].x < points[low].x - x ? low - 1 : low;
}

/**
 * A B-spline through the samples: every vertex is approached by a cubic segment, which rounds the
 * corners without letting the curve drift away from the actual prices.
 */
function buildLinePath(points: Point[]) {
  if (points.length === 1) {
    const { x, y } = points[0];
    return `M ${x} ${y} L ${x} ${y}`;
  }

  const lastIndex = points.length - 1;
  const first = points[0];
  const distance = { x: points[lastIndex].x - first.x, y: points[lastIndex].y - first.y };

  function getBasisPoint(index: number) {
    const clamped = Math.max(0, Math.min(index, lastIndex));
    const point = points[clamped];
    const ratio = 1 - SMOOTHING;
    const tangent = clamped / lastIndex;

    return {
      x: ratio * point.x + (1 - ratio) * (first.x + tangent * distance.x),
      y: ratio * point.y + (1 - ratio) * (first.y + tangent * distance.y),
    };
  }

  function getCurve(index: number) {
    const current = getBasisPoint(index);
    const minus1 = getBasisPoint(index - 1);
    const minus2 = getBasisPoint(index - 2);

    const x1 = (2 * minus2.x + minus1.x) / 3;
    const y1 = (2 * minus2.y + minus1.y) / 3;
    const x2 = (minus2.x + 2 * minus1.x) / 3;
    const y2 = (minus2.y + 2 * minus1.y) / 3;
    const x3 = (minus2.x + 4 * minus1.x + current.x) / 6;
    const y3 = (minus2.y + 4 * minus1.y + current.y) / 6;

    return `C ${x1} ${y1} ${x2} ${y2} ${x3} ${y3}`;
  }

  let path = `M ${first.x} ${first.y}`;
  for (let index = 1; index <= points.length; index++) {
    path += ` ${getCurve(index)}`;
  }
  path += ` L ${points[lastIndex].x} ${points[lastIndex].y}`;

  return path;
}

export default memo(Plot);
