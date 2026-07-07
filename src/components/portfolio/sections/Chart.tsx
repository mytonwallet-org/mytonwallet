import type { LovelyChartInstance } from 'lovely-chart';
import React, {
  memo, useEffect, useLayoutEffect, useRef, useState,
} from '../../../lib/teact/teact';

import type { ChartData } from '../helpers/graphKitAdapter';

import { requestMeasure } from '../../../lib/fasterdom/fasterdom';
import buildClassName from '../../../util/buildClassName';
import { SWIPE_DISABLED_CLASS_NAME } from '../../../util/swipeController';
import { ensureLovelyChart } from '../helpers/lovelyChart.async';

import useFlag from '../../../hooks/useFlag';
import useShowTransition from '../../../hooks/useShowTransition';

import ChartSkeleton from './ChartSkeleton';
import SectionHeader from './SectionHeader';

import styles from './Chart.module.scss';

// Keep in sync with the `chart-fade-in` animation in `Chart.module.scss`
const CHART_SWAP_DURATION_MS = 250;

// Mirrored onto the card while zoomed into the donut; the SCSS overrides key off this class instead of `:has()`,
// which is outside our browser baseline (chrome >= 86, firefox >= 91)
const ZOOMED_CLASS = 'portfolio-chart-card-zoomed';

interface ChartLayer {
  instance: LovelyChartInstance;
  element: HTMLElement;
}

interface OwnProps {
  title: string;
  dateRange?: string;
  data?: ChartData;
  cardClassName?: string;
  noAnimation?: boolean;
}

function Chart({
  title, dateRange, data, cardClassName, noAnimation,
}: OwnProps) {
  const containerRef = useRef<HTMLDivElement>();
  // LovelyChart leaks window/observer listeners unless its instance is destroyed, so track instances
  const currentLayerRef = useRef<ChartLayer>();
  const pendingLayerRef = useRef<ChartLayer>();

  const [isReady, markIsReady] = useFlag();
  const [isZoomed, setIsZoomed] = useState(false);
  const { ref: skeletonRef, shouldRender: shouldRenderSkeleton } = useShowTransition({
    isOpen: !isReady,
    withShouldRender: true,
    className: 'slow',
    noMountTransition: true,
    noCloseTransition: noAnimation,
  });

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container || !data) return undefined;

    let isCancelled = false;
    let swapTimerId: number | undefined;

    void ensureLovelyChart().then((LovelyChart) => {
      requestMeasure(() => {
        if (isCancelled) return;

        // A previous swap may still be fading; destroy it now so we never stack more than two layers
        pendingLayerRef.current?.instance.destroy();
        pendingLayerRef.current = undefined;

        const previous = currentLayerRef.current;
        const instance = new LovelyChart(container, data.params);
        const element = container.lastElementChild as HTMLElement | null;

        if (!element) {
          instance.destroy();
          return;
        }

        currentLayerRef.current = { instance, element };
        element.classList.add(styles.chartEntering);
        // Canvas is on screen now: cross-fade the skeleton out into it
        markIsReady();

        // `update()` swaps datasets instantly with no transition, so cross-fade instead: the new canvas
        // fades in while the old one (pulled out of flow) fades out beneath it, then the old is destroyed
        if (previous) {
          previous.element.classList.add(styles.chartUnder);
          pendingLayerRef.current = previous;

          swapTimerId = window.setTimeout(() => {
            previous.instance.destroy();

            if (pendingLayerRef.current === previous) pendingLayerRef.current = undefined;
          }, CHART_SWAP_DURATION_MS);
        }
      });
    });

    return () => {
      isCancelled = true;

      if (swapTimerId !== undefined) window.clearTimeout(swapTimerId);
    };
  }, [data]);

  // While zoomed into the per-date donut, LovelyChart marks its own inner container `state-zoomed-in`, not
  // the card, and we can't rely on `:has()` - so mirror the zoomed state, signalled by the visible zoom-out
  // control, onto the card via Teact (a direct classList write would trip stricterdom on the managed section).
  // Only the share chart is zoomable, flagged here by its `isPercentage` overview
  const isZoomable = Boolean(data?.params.isPercentage);
  useEffect(() => {
    const container = containerRef.current;
    if (!isZoomable || !container) return undefined;

    const sync = () => {
      setIsZoomed(Boolean(
        container.querySelector('.lovely-chart--header-zoom-out-control:not(.lovely-chart--state-hidden)'),
      ));
    };

    const observer = new MutationObserver(sync);
    observer.observe(container, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['class'],
    });
    sync();

    return () => {
      observer.disconnect();
      setIsZoomed(false);
    };
  }, [isZoomable]);

  useEffect(() => {
    return () => {
      pendingLayerRef.current?.instance.destroy();
      currentLayerRef.current?.instance.destroy();
      pendingLayerRef.current = undefined;
      currentLayerRef.current = undefined;
    };
  }, []);

  return (
    <section
      className={buildClassName(
        styles.root,
        'portfolio-chart-card',
        cardClassName,
        SWIPE_DISABLED_CLASS_NAME,
        isZoomed && ZOOMED_CLASS,
      )}
    >
      <SectionHeader title={title} range={dateRange} />

      <div className={styles.card}>
        <div ref={containerRef} className={styles.chartContainer} data-stricterdom-ignore />

        {shouldRenderSkeleton && (
          <div ref={skeletonRef} className={styles.skeletonLayer}>
            <ChartSkeleton />
          </div>
        )}
      </div>
    </section>
  );
}

export default memo(Chart);
