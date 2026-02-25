import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiSite } from '../../api/types';

import buildClassName from '../../util/buildClassName';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
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

  const { isPortrait } = useDeviceScreen();

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
      onScroll={isPortrait ? handleContentScroll : undefined}
      className={buildClassName(styles.root, 'custom-scroll')}
    >
      {isPortrait && <CategoryHeader id={categoryId} withNotch={isScrolled} />}
      <div className={styles.list}>
        {sites.map((site) => (
          <Site
            key={`${site.url}-${site.name}`}
            site={site}
          />
        ))}
      </div>
    </div>
  );
}

export default memo(SiteList);
