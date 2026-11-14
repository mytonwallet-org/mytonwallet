import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiSite } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import getTestId from '../../util/getTestId';

import useHistoryBack from '../../hooks/useHistoryBack';
import useScrolledState from '../../hooks/useScrolledState';

import CategoryHeader from './CategoryHeader';
import Site from './Site';

import styles from './SiteList.module.scss';

interface OwnProps {
  isActive?: boolean;
  categoryId: number;
  sites: ApiSite[];
}

function SiteList({ isActive, categoryId, sites }: OwnProps) {
  const { closeSiteCategory } = getActions();

  useHistoryBack({
    isActive,
    onBack: closeSiteCategory,
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  return (
    <div
      onScroll={handleContentScroll}
      className={buildClassName(styles.root, 'custom-scroll')}
      data-testid={isActive ? getTestId('explore_site_list') : undefined}
    >
      <CategoryHeader id={categoryId} withNotch={isScrolled} />
      <div className={styles.list}>
        {sites.map((site) => (
          <Site
            key={`${site.url}-${site.name}`}
            site={site}
            testId={getTestId('explore_site_row')}
          />
        ))}
      </div>
    </div>
  );
}

export default memo(SiteList);
