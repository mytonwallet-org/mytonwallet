import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsFill, ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsActivityListItem } from '../helpers/perpsActivity';

import buildClassName from '../../../util/buildClassName';

import useInfiniteLoader from '../../../hooks/useInfiniteLoader';
import useLastCallback from '../../../hooks/useLastCallback';

import LoadError from '../LoadError';
import ActivityRow from './ActivityRow';

import futuresStyles from '../Futures.module.scss';
import styles from './ActivityList.module.scss';

interface OwnProps {
  title: string;
  items: PerpsActivityListItem[];
  nextCursor?: string;
  isStale: boolean;
  /** The market of every trade, when the list shows one market */
  asset?: ApiPerpsMarketAsset;
  assetsByName?: Record<string, ApiPerpsMarketAsset>;
  /** Present when the history failed to load, so an empty list offers a retry */
  onRetry?: NoneToVoidFunction;
  onLoadMore: NoneToVoidFunction;
}

interface StateProps {
  isSensitiveDataHidden?: true;
}

/** A list of trades, older pages loading on scroll */
function ActivityList({
  title, items, nextCursor, isStale, asset, assetsByName, isSensitiveDataHidden, onRetry, onLoadMore,
}: OwnProps & StateProps) {
  const { openPerpsActivity } = getActions();

  const handleItemClick = useLastCallback((fill: ApiPerpsFill) => {
    openPerpsActivity({ fill });
  });

  const { handleIntersection } = useInfiniteLoader({ loadMore: onLoadMore });

  // The loader gets a new element with each page, so a page that leaves it in view loads the next one too
  const loader = nextCursor && (
    <div key={nextCursor} ref={handleIntersection} className={styles.loader} />
  );

  // A page can hold only trades the list skips, so the loader alone fetches the next one
  if (!items.length && !onRetry) return loader || undefined;

  return (
    <section className={styles.root}>
      <h2 className={styles.heading}>{title}</h2>
      {items.length ? (
        <div className={buildClassName(futuresStyles.card, futuresStyles.dimmable, isStale && futuresStyles.stale)}>
          {items.map((item) => (
            <ActivityRow
              key={item.key}
              fill={item.fill}
              asset={asset ?? assetsByName?.[item.fill.coin]}
              isSensitiveDataHidden={isSensitiveDataHidden}
              onClick={handleItemClick}
            />
          ))}
          {loader}
        </div>
      ) : (
        <LoadError onRetry={onRetry!} />
      )}
    </section>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
  };
})(ActivityList));
