import type { LovelyChartInstance, LovelyChartParams } from 'lovely-chart';
import {
  useEffect, useLayoutEffect, useRef, useState,
} from '../../../lib/teact/teact';

import { requestMeasure } from '../../../lib/fasterdom/fasterdom';
import { handleChunkLoadError } from '../../../util/chunkLoading';
import { ensureLovelyChart } from './lovelyChart.async';

import styles from './useLovelyChart.module.scss';

const CHART_SWAP_DURATION_MS = 250;

interface ChartLayer {
  instance: LovelyChartInstance;
  element: HTMLElement;
}

export default function useLovelyChart(params?: LovelyChartParams, isZoomable = false) {
  const containerRef = useRef<HTMLDivElement>();
  const currentLayerRef = useRef<ChartLayer>();
  const pendingLayerRef = useRef<ChartLayer>();
  const [isReady, setIsReady] = useState(false);
  const [isZoomed, setIsZoomed] = useState(false);

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container || !params) return undefined;

    let isCancelled = false;
    let swapTimerId: number | undefined;

    // On a failed load the chart stays unrendered until the next `params` change retries it
    void ensureLovelyChart().then((LovelyChart) => {
      requestMeasure(() => {
        if (isCancelled) return;
        pendingLayerRef.current?.instance.destroy();
        pendingLayerRef.current = undefined;

        const previous = currentLayerRef.current;
        const instance = new LovelyChart(container, params);
        const element = container.lastElementChild as HTMLElement | null;
        if (!element) {
          instance.destroy();
          return;
        }

        currentLayerRef.current = { instance, element };
        element.classList.add(styles.chartEntering);
        setIsReady(true);

        if (previous) {
          previous.element.classList.add(styles.chartUnder);
          pendingLayerRef.current = previous;
          swapTimerId = window.setTimeout(() => {
            previous.instance.destroy();
            if (pendingLayerRef.current === previous) pendingLayerRef.current = undefined;
          }, CHART_SWAP_DURATION_MS);
        }
      });
    }).catch(handleChunkLoadError('useLovelyChart'));

    return () => {
      isCancelled = true;
      if (swapTimerId !== undefined) window.clearTimeout(swapTimerId);
    };
  }, [params]);

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

  useEffect(() => () => {
    destroyLovelyChartInstances(
      pendingLayerRef.current?.instance,
      currentLayerRef.current?.instance,
    );
    pendingLayerRef.current = undefined;
    currentLayerRef.current = undefined;
  }, []);

  return { containerRef, isReady, isZoomed };
}

export function destroyLovelyChartInstances(...instances: Array<LovelyChartInstance | undefined>) {
  new Set(instances.filter(Boolean)).forEach((instance) => instance.destroy());
}
