import React, {
  memo, useEffect, useLayoutEffect, useRef,
} from '../../../lib/teact/teact';

import type { LovelyChartInstance } from '../../../lib/LovelyChart/LovelyChart';
import type { ChartData } from '../helpers/graphKitAdapter';

import { requestMeasure } from '../../../lib/fasterdom/fasterdom';
import { ensureLovelyChart } from '../../../lib/LovelyChart/LovelyChart.async';
import buildClassName from '../../../util/buildClassName';
import { SWIPE_DISABLED_CLASS_NAME } from '../../../util/swipeController';

import useLang from '../../../hooks/useLang';

import Spinner from '../../ui/Spinner';
import SectionHeader from './SectionHeader';

import styles from './Chart.module.scss';

interface OwnProps {
  title: string;
  dateRange?: string;
  data?: ChartData;
  isRefreshing?: boolean;
  cardClassName?: string;
}

function Chart({
  title, dateRange, data, isRefreshing, cardClassName,
}: OwnProps) {
  const lang = useLang();
  const containerRef = useRef<HTMLDivElement>();
  // LovelyChart leaks a MutationObserver + window listeners unless its instance is destroyed
  const instanceRef = useRef<LovelyChartInstance>();

  useLayoutEffect(() => {
    const container = containerRef.current;
    // When `data` disappears, the chart container unmounts too - tear the instance down here so its
    // global listeners don't outlive the DOM and a future re-mount doesn't `update()` a dead instance
    if (!container || !data) {
      instanceRef.current?.destroy();
      instanceRef.current = undefined;
      return;
    }

    void ensureLovelyChart().then((LovelyChart) => {
      requestMeasure(() => {
        // Container guard catches stale promises - if the ref points elsewhere, the effect re-ran
        if (containerRef.current !== container) return;
        const params = data.params as unknown as Record<string, unknown>;
        // Reuse the instance across range changes - cheaper, no canvas flash, and avoids re-attaching
        // the library's global listeners. Chart type (line/area/pie) stays stable across ranges
        if (instanceRef.current) {
          instanceRef.current.update(params);
        } else {
          instanceRef.current = LovelyChart.create(container, params);
        }
      });
    });
  }, [data]);

  // LovelyChart replaces its root element on every teardown/redraw (resize, orientation, data change),
  // wiping the lock chip. Observe only the direct child — that's the only thing the library swaps,
  // and it skips noisy nested mutations like tooltip updates on hover
  useEffect(() => {
    const container = containerRef.current;
    if (!container || !data?.isAssetLimitExceeded) return undefined;

    appendLockedChip(container);
    const observer = new MutationObserver(() => appendLockedChip(container));
    observer.observe(container, { childList: true });

    return () => observer.disconnect();
  }, [data]);

  useEffect(() => {
    return () => {
      instanceRef.current?.destroy();
      instanceRef.current = undefined;
    };
  }, []);

  return (
    <section className={buildClassName(styles.root, 'portfolio-chart-card', cardClassName, SWIPE_DISABLED_CLASS_NAME)}>
      <SectionHeader title={title} range={dateRange} />

      <div className={styles.card}>
        {isRefreshing && <Spinner className={styles.refreshIndicator} />}
        {data
          ? (
            <div ref={containerRef} className={styles.chartContainer} data-stricterdom-ignore />
          )
          : <div className={styles.empty}>{lang('No data')}</div>}
      </div>
    </section>
  );
}

export default memo(Chart);

// LovelyChart owns its legend DOM, so the lock chip is injected as the last legend item rather than
// rendered by Teact. The chip removes itself with the chart container on teardown
function appendLockedChip(container: HTMLElement) {
  const tools = container.querySelector('.lovely-chart--tools');
  if (!tools || tools.querySelector(`.${styles.lockedChip}`)) return;

  const chip = document.createElement('span');
  chip.className = styles.lockedChip;
  const icon = document.createElement('i');
  icon.className = 'icon-lock';
  icon.setAttribute('aria-hidden', 'true');
  chip.appendChild(icon);
  tools.appendChild(chip);
}
