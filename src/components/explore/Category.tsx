import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiSite, ApiSiteCategory } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import getTestId from '../../util/getTestId';
import { openUrl } from '../../util/openUrl';
import { getHostnameFromUrl } from '../../util/url';

import useLang from '../../hooks/useLang';

import Image from '../ui/Image';

import styles from './Category.module.scss';

interface OwnProps {
  category: ApiSiteCategory;
  sites: ApiSite[];
}

function Category({ category, sites }: OwnProps) {
  const { openSiteCategory } = getActions();

  const lang = useLang();
  const [bigSites, smallSites] = useMemo(() => {
    if (sites.length <= 4) {
      return [sites, []];
    }

    return [
      sites.slice(0, 3),
      sites.slice(3, 7),
    ];
  }, [sites]);

  function handleCategoryClick() {
    openSiteCategory({ id: category.id });
  }

  return (
    <div className={styles.root}>
      <h3
        className={styles.header}
        role="button"
        tabIndex={0}
        data-testid={getTestId('explore_category')}
        onClick={handleCategoryClick}
      >
        {lang(category.name)}
      </h3>

      <div
        className={buildClassName(styles.folder, smallSites.length > 0 && styles.interactive)}
        onClick={smallSites.length > 0 ? handleCategoryClick : undefined}
      >
        {bigSites.map((site) => (
          <button
            key={`${site.url}-${site.name}`}
            type="button"
            className={buildClassName(styles.site, styles.scalable)}
            onClick={(e: React.MouseEvent) => {
              stopEvent(e);

              void openUrl(
                site.url, { isExternal: site.isExternal, title: site.name, subtitle: getHostnameFromUrl(site.url) },
              );
            }}
          >
            <Image
              url={site.icon}
              alt={site.name}
              imageClassName={styles.icon}
            />
          </button>
        ))}
        {smallSites.length > 0 && (
          <div className={buildClassName(styles.subfolder, styles.scalable)}>
            {smallSites.map((site) => (
              <Image
                key={`${site.url}-${site.name}`}
                url={site.icon}
                alt={site.name}
                className={buildClassName(styles.site, styles.small)}
                imageClassName={styles.icon}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export default memo(Category);
