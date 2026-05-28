import React, { memo, useLayoutEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';

import type { PortfolioStackSegment } from '../helpers/buildStackSegments';

import buildClassName from '../../../util/buildClassName';

import useUniqueId from '../../../hooks/useUniqueId';

import styles from './StackChart.module.scss';

interface Layer {
  id: string;
  colorHex: string;
  bodyPath: string;
  capPath?: string;
}

interface OwnProps {
  segments: PortfolioStackSegment[];
  hoveredId?: string;
  onHover?: (id: string | undefined) => void;
}

const WIDTH = 80;
const MIN_HEIGHT = 160;
// One cylinder seen at a single angle, so every perspective ellipse (top cap, dividers, base) shares this curvature
const RADIUS = 20;
const GAP = 2;

function StackChart({ segments, hoveredId, onHover }: OwnProps) {
  const highlightId = useUniqueId('pf-layer-hl-');
  const ref = useRef<HTMLDivElement>();
  // The chart grows to fill the card height (driven by the legend) but never shrinks below MIN_HEIGHT
  const [height, setHeight] = useState(MIN_HEIGHT);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return undefined;

    const observer = new ResizeObserver(() => {
      setHeight(Math.max(MIN_HEIGHT, Math.round(el.offsetHeight)));
    });
    observer.observe(el);

    return () => observer.disconnect();
  }, []);

  const layers = useMemo(() => buildLayers(segments, height), [segments, height]);

  if (!layers) return undefined;

  return (
    <div ref={ref} className={styles.root} style={`width: ${WIDTH}px`}>
      <svg
        className={styles.svg}
        width={WIDTH}
        height={height}
        viewBox={`0 0 ${WIDTH} ${height}`}
        xmlns="http://www.w3.org/2000/svg"
        role="presentation"
      >
        <defs>
          <linearGradient id={highlightId} x1="0" y1="0.168" x2="0" y2="0.945">
            <stop offset="0" style="stop-color: #FFFFFF; stop-opacity: 0.24" />
            <stop offset="1" style="stop-color: #FFFFFF; stop-opacity: 0" />
          </linearGradient>
        </defs>
        {layers.map((layer) => {
          const isFaded = hoveredId !== undefined && hoveredId !== layer.id;
          return (
            <g
              key={layer.id}
              className={buildClassName(styles.layer, isFaded && styles.layerFaded)}
              onMouseEnter={onHover ? () => onHover(layer.id) : undefined}
              onMouseLeave={onHover ? () => onHover(undefined) : undefined}
            >
              <path d={layer.bodyPath} fill={layer.colorHex} />
              <path d={layer.bodyPath} fill={`url(#${highlightId})`} />
              {layer.capPath !== undefined && (
                <path d={layer.capPath} fill={layer.colorHex} />
              )}
              {layer.capPath !== undefined && (
                <path d={layer.capPath} fill="rgba(255, 255, 255, 0.4)" />
              )}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

export default memo(StackChart);

function buildLayers(segments: PortfolioStackSegment[], height: number) {
  const visible = segments.filter((s) => s.rawAmount > 0);
  const total = visible.reduce((sum, s) => sum + s.rawAmount, 0);
  if (total <= 0) return undefined;

  const rx = WIDTH / 2;
  const gapsTotal = (visible.length - 1) * GAP;
  // Straight side edges share the height left after the top cap, the rounded base and the gaps,
  // so the stack fills `height` exactly while edge heights stay proportional to value
  const edgeBudget = Math.max(height - RADIUS * 2 - gapsTotal, 0);

  const layers: Layer[] = [];
  let edgeTop = RADIUS;

  for (let i = 0; i < visible.length; i++) {
    if (i > 0) edgeTop += GAP;

    const segment = visible[i];
    const edgeBottom = edgeTop + (segment.rawAmount / total) * edgeBudget;
    const isFirst = i === 0;

    layers.push({
      id: segment.id,
      colorHex: segment.colorHex,
      bodyPath: isFirst
        ? buildFirstBody(edgeTop, edgeBottom, rx)
        : buildBody(edgeTop, edgeBottom, rx),
      capPath: isFirst ? buildTopCap(edgeTop, rx) : undefined,
    });

    edgeTop = edgeBottom;
  }

  return layers;
}

// Top cap: the prominent perspective ellipse sitting above the first segment
function buildTopCap(centerY: number, rx: number): string {
  return `M0,${centerY} `
    + `A${rx},${RADIUS} 0 0,1 ${WIDTH},${centerY} `
    + `A${rx},${RADIUS} 0 0,1 0,${centerY} `
    + 'Z';
}

// First segment: flat top (hidden under the cap) with a convex rounded bottom
function buildFirstBody(edgeTop: number, edgeBottom: number, rx: number): string {
  return `M0,${edgeTop} `
    + `H${WIDTH} `
    + `V${edgeBottom} `
    + `A${rx},${RADIUS} 0 0,1 0,${edgeBottom} `
    + 'Z';
}

// Lower segments: concave top tucked under the previous segment, convex rounded bottom
function buildBody(edgeTop: number, edgeBottom: number, rx: number): string {
  return `M${WIDTH},${edgeTop} `
    + `V${edgeBottom} `
    + `A${rx},${RADIUS} 0 0,1 0,${edgeBottom} `
    + `V${edgeTop} `
    + `A${rx},${RADIUS} 0 0,0 ${WIDTH},${edgeTop} `
    + 'Z';
}
