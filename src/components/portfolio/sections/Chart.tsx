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
            <>
              <div ref={containerRef} className={styles.chartContainer} data-stricterdom-ignore />
              {data.isAssetLimitExceeded && (
                <span className={styles.lockedChip}>
                  <i className={buildClassName(styles.lockedChipIcon, 'icon-lock')} aria-hidden />
                </span>
              )}
            </>
          )
          : <div className={styles.empty}>{lang('No data')}</div>}
      </div>
    </section>
  );
}

export default memo(Chart);
