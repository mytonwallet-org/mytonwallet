import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { ApiPerpsMarketAsset } from '../../api/types';

import { requestMeasure } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import { formatCompactCurrency } from '../../util/formatNumber';
import {
  formatLeverage, formatPerpsFundingRate, MISSING_VALUE, PERPS_CURRENCY_SYMBOL,
} from './helpers/formatPerps';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';

import InfoMetric from '../tokenInfo/sections/InfoMetric';

import styles from '../tokenInfo/sections/Info.module.scss';
import futuresStyles from './Futures.module.scss';

interface OwnProps {
  /** Absent until the catalogue loads, and skeletons then keep the places of the values */
  asset?: ApiPerpsMarketAsset;
  description?: string;
  className?: string;
}

function Info({ asset, description, className }: OwnProps) {
  const lang = useLang();
  const descriptionRef = useRef<HTMLParagraphElement>();
  const [isDescriptionExpanded, expandDescription, collapseDescription] = useFlag();
  const [isDescriptionClamped, setIsDescriptionClamped] = useState(false);

  // The line clamp cuts only a long description, and the panel width sets how many lines it takes. `ResizeObserver`
  // reports the first size right away and runs outside the fasterdom phases, so a measure task reads the sizes.
  useEffect(() => {
    if (!description || isDescriptionExpanded) return undefined;

    const element = descriptionRef.current!;
    const observer = new ResizeObserver(() => {
      requestMeasure(() => {
        // The expansion resizes the text before the observer stops, and the uncut text must not hide Show Less
        if (!element.classList.contains(futuresStyles.descriptionCollapsed)) return;

        setIsDescriptionClamped(element.scrollHeight > element.clientHeight);
      });
    });
    observer.observe(element);

    return () => observer.disconnect();
  }, [description, isDescriptionExpanded]);

  return (
    <section className={buildClassName(styles.root, className)}>
      <h3 className={styles.title}>{lang('Info')}</h3>

      <div className={styles.details}>
        <p
          ref={descriptionRef}
          className={buildClassName(
            styles.description,
            futuresStyles.description,
            !isDescriptionExpanded && futuresStyles.descriptionCollapsed,
          )}
        >
          {description || lang('$token_info_no_description')}
        </p>
        {description && isDescriptionClamped && (
          <button
            type="button"
            className={futuresStyles.descriptionToggle}
            onClick={isDescriptionExpanded ? collapseDescription : expandDescription}
          >
            {lang(isDescriptionExpanded ? 'Show Less' : 'Show More')}
          </button>
        )}

        <div className={styles.metrics}>
          <InfoMetric
            label={lang('Funding Rate')}
            hint={lang('$perps_funding_rate_hint')}
            value={asset && formatPerpsFundingRate(lang, asset)}
          />
          <InfoMetric
            label={lang('Max Leverage')}
            hint={lang('$perps_max_leverage_hint')}
            value={asset && formatLeverage(asset.maxLeverage)}
          />
          <InfoMetric
            label={lang('24h Volume')}
            hint={lang('$perps_volume_24h_hint')}
            value={asset && formatCompactCurrency(Number(asset.context.dayNtlVlm), PERPS_CURRENCY_SYMBOL)}
          />
          <InfoMetric
            label={lang('Open Interest')}
            hint={lang('$perps_open_interest_hint')}
            value={asset && (asset.context.openInterestUsd !== undefined
              ? formatCompactCurrency(Number(asset.context.openInterestUsd), PERPS_CURRENCY_SYMBOL)
              : MISSING_VALUE)}
          />
        </div>
      </div>
    </section>
  );
}

export default memo(Info);
