import React, { memo, useMemo } from '../../lib/teact/teact';

import type { ApiHistoryList } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import {
  disableTelegramMiniAppSwipeToClose,
  enableTelegramMiniAppSwipeToClose,
} from '../../util/telegram';

import useLang from '../../hooks/useLang';

import Transition from '../ui/Transition';

interface OwnProps {
  width: number;
  height: number;
  prices: ApiHistoryList;
  selectedIndex: number;
  className?: string;
  imgClassName?: string;
  onSelectIndex: (index: number) => void;
  isUpdating?: boolean;
}

const IS_SMOOTH = true;
const PATH_SMOOTHING = 0.0001;
const MIN_CHART_HEIGHT = 0.000000001;

function TokenPriceChart({
  width,
  height,
  prices,
  selectedIndex,
  className,
  imgClassName,
  onSelectIndex,
  isUpdating,
}: OwnProps) {
  const lang = useLang();

  const boundingPoints = useMemo(() => {
    const priceValues = prices.map(([, price]) => price);
    const min = Math.min(...priceValues);
    const max = Math.max(...priceValues);

    return {
      width: prices.length - 1,
      height: Math.max(MIN_CHART_HEIGHT, max - min),
      min,
    };
  }, [prices]);

  const points = useMemo(() => {
    const scaleX = width / boundingPoints.width;
    const scaleY = height / boundingPoints.height;

    return prices.map(([, y], i) => ({ x: i * scaleX + 3, y: (y - boundingPoints.min) * scaleY + 3 }));
  }, [boundingPoints.height, boundingPoints.min, boundingPoints.width, height, width, prices]);

  function getBasisPoint(i: number) {
    const indexesCount = points.length - 1;
    const index = i < 0 ? 0 : i > indexesCount ? indexesCount : i;
    const point = points[index];
    const ratio = 1 - PATH_SMOOTHING;
    const tangent = index / indexesCount;
    const firstPoint = points[0];
    const distance = {
      x: points[indexesCount].x - firstPoint.x,
      y: points[indexesCount].y - firstPoint.y,
    };

    return {
      x: ratio * point.x + (1 - ratio) * (firstPoint.x + tangent * distance.x),
      y: ratio * point.y + (1 - ratio) * (firstPoint.y + tangent * distance.y),
    };
  }

  function getCurvePath(i: number) {
    const pCurrent = getBasisPoint(i);
    const pMinus1 = getBasisPoint(i - 1);
    const pMinus2 = getBasisPoint(i - 2);

    const x1 = (2 * pMinus2.x + pMinus1.x) / 3;
    const y1 = (2 * pMinus2.y + pMinus1.y) / 3;
    const x2 = (pMinus2.x + 2 * pMinus1.x) / 3;
    const y2 = (pMinus2.y + 2 * pMinus1.y) / 3;
    const x3 = (pMinus2.x + 4 * pMinus1.x + pCurrent.x) / 6;
    const y3 = (pMinus2.y + 4 * pMinus1.y + pCurrent.y) / 6;

    return `C ${x1} ${y1} ${x2} ${y2} ${x3} ${y3}`;
  }

  function getLinePath(point: { x: number; y: number }) {
    return `L ${point.x} ${point.y}`;
  }

  function getPath() {
    let d = points.reduce((acc, point, i) => {
      const partialPath = IS_SMOOTH
        ? getCurvePath(i)
        : getLinePath(point);
      return i === 0
        ? `M ${point.x} ${point.y} `
        : `${acc} ${partialPath} `;
    }, '');

    if (IS_SMOOTH) {
      d += getCurvePath(points.length);
      d += getLinePath(points[points.length - 1]);
    }

    return d;
  }

  function getAreaPath() {
    const linePath = getPath();
    const firstPoint = points[0];
    const lastPoint = points[points.length - 1];

    // Close the path by going down to the bottom, across, and back up to the start
    return `${linePath} L ${lastPoint.x} 3 L ${firstPoint.x} 3 Z`;
  }

  function renderSvg() {
    const activePoint = points[selectedIndex] || points[points.length - 1];
    const gradientId = 'chartGradient';
    const gradientDimmedId = 'chartGradientDimmed';
    const isHovering = selectedIndex >= 0;
    const clipX = activePoint.x;
    const svgWidth = width + 6;
    const svgHeight = height + 6;

    const svg = `<svg viewBox="0 0 ${svgWidth} ${svgHeight}" height="${svgHeight}" width="${svgWidth}"
        xmlns="http://www.w3.org/2000/svg" style="transform: scale(1,-1)">
        <defs>
          <linearGradient id="${gradientId}" x1="0" y1="1" x2="0" y2="0">
            <stop offset="0%25" stop-color="white" stop-opacity="0.25" />
            <stop offset="100%25" stop-color="white" stop-opacity="0" />
          </linearGradient>
          <linearGradient id="${gradientDimmedId}" x1="0" y1="1" x2="0" y2="0">
            <stop offset="0%25" stop-color="white" stop-opacity="0.0625" />
            <stop offset="100%25" stop-color="white" stop-opacity="0" />
          </linearGradient>
          <clipPath id="clipLeft">
            <rect x="0" y="0" width="${clipX}" height="${svgHeight}" />
          </clipPath>
          <clipPath id="clipRight">
            <rect x="${clipX}" y="0" width="${svgWidth - clipX}" height="${svgHeight}" />
          </clipPath>
        </defs>
        ${isHovering ? `
          <g clip-path="url(%23clipLeft)">
            <path d="${getAreaPath()}" fill="url(%23${gradientId})" />
          </g>
          <g clip-path="url(%23clipRight)">
            <path d="${getAreaPath()}" fill="url(%23${gradientDimmedId})" />
          </g>
          <g fill="none" stroke="white" clip-path="url(%23clipLeft)">
            <path stroke-linejoin="round" stroke-width="1.5" d="${getPath()}" style="stroke-linecap: round" />
          </g>
          <g fill="none" stroke="white" opacity="0.25" clip-path="url(%23clipRight)">
            <path stroke-linejoin="round" stroke-width="1.5" d="${getPath()}" style="stroke-linecap: round" />
          </g>
        ` : `
          <path d="${getAreaPath()}" fill="url(%23${gradientId})" />
          <g fill="none" stroke="white">
            <path stroke-linejoin="round" stroke-width="1.5" d="${getPath()}" style="stroke-linecap: round" />
          </g>
        `}
        <circle r="2.5" fill="white" cx="${activePoint.x}" cy="${activePoint.y}" />
      </svg>`;

    return `data:image/svg+xml;utf8,${(svg)}`;
  }

  function handleMouseMove(e: React.MouseEvent<HTMLDivElement> | React.TouchEvent<HTMLDivElement>) {
    const { x: containerX, width: containerWidth } = e.currentTarget.getBoundingClientRect();
    const { clientX } = 'touches' in e ? e.touches[0] : e;
    const segmentHalfWidth = (containerWidth / points.length) / 2;
    const x = clientX - containerX - segmentHalfWidth;
    const nextIndex = Math.max(0, Math.min(Math.round(points.length * (x / containerWidth)), points.length - 1));

    onSelectIndex(nextIndex);
  }

  function handleTouchStart(e: React.TouchEvent<HTMLDivElement>) {
    handleMouseMove(e);

    disableTelegramMiniAppSwipeToClose();
  }

  function handleMouseLeave() {
    onSelectIndex(-1);

    enableTelegramMiniAppSwipeToClose();
  }

  return (
    <div
      className={className}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      onTouchStart={handleTouchStart}
      onTouchMove={handleMouseMove}
      onTouchEnd={handleMouseLeave}
      onTouchCancel={handleMouseLeave}
    >
      <Transition activeKey={isUpdating ? 1 : 0} name="semiFade" shouldCleanup>
        <img
          src={renderSvg()}
          className={buildClassName(imgClassName, isUpdating && 'glare-image')}
          alt={lang('Currency History')}
        />
      </Transition>
    </div>
  );
}

export default memo(TokenPriceChart);
