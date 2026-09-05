import React, { memo, useRef } from '../../lib/teact/teact';

import type { MarketSection } from './helpers/buildMarketSections';

import buildClassName from '../../util/buildClassName';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useDragScroll from '../../hooks/useDragScroll';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useGridLimit from './hooks/useGridLimit';

import GridItem from './GridItem';
import MoverCard from './MoverCard';
import TokenRow from './TokenRow';

import styles from './Market.module.scss';

interface OwnProps {
  section: MarketSection;
  onTokenClick: (slug: string) => void;
  onShowAllClick: (sectionId: string) => void;
}

function Section({ section, onTokenClick, onShowAllClick }: OwnProps) {
  const { id, title, layout, hasMore, tokens } = section;

  const lang = useLang();
  const gridLimit = useGridLimit();
  const moversRef = useRef<HTMLDivElement>();

  useDragScroll({
    containerRef: moversRef,
    isDisabled: IS_TOUCH_ENV || layout !== 'largeHorizontal',
  });

  const visibleTokens = layout === 'grid' ? tokens.slice(0, gridLimit) : tokens;

  const handleShowAllClick = useLastCallback(() => {
    onShowAllClick(id);
  });

  function renderTokens() {
    switch (layout) {
      case 'largeHorizontal':
        return (
          <div ref={moversRef} className={buildClassName(styles.movers, 'no-swipe')}>
            {visibleTokens.map((token) => (
              <MoverCard key={token.slug} token={token} onClick={onTokenClick} />
            ))}
          </div>
        );
      case 'grid':
        return (
          <div className={buildClassName(styles.card, styles.grid)}>
            {visibleTokens.map((token) => (
              <GridItem key={token.slug} token={token} onClick={onTokenClick} />
            ))}
          </div>
        );
      case 'rows':
        return (
          <div className={buildClassName(styles.card, styles.rows)}>
            {visibleTokens.map((token) => (
              <TokenRow key={token.slug} token={token} onClick={onTokenClick} />
            ))}
          </div>
        );
    }
  }

  return (
    <div className={styles.section}>
      <div className={styles.sectionHeader}>
        <h2 className={styles.sectionTitle}>{title}</h2>
        {/* The backend decides which sections continue on the "Show All" screen, a trimmed grid alone does not */}
        {hasMore && (
          <button type="button" className={styles.showAll} onClick={handleShowAllClick}>
            {lang('Show All')}
          </button>
        )}
      </div>
      {renderTokens()}
    </div>
  );
}

export default memo(Section);
