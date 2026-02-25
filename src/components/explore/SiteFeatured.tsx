import React, { memo } from '../../lib/teact/teact';

import type { ApiSite } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';
import { openUrl } from '../../util/openUrl';
import { getHostnameFromUrl } from '../../util/url';

import Image from '../ui/Image';
import Site from './Site';

import styles from './SiteFeatured.module.scss';

interface OwnProps {
  site: ApiSite;
  className?: string;
}

function SiteFeatured({ site, className }: OwnProps) {
  const {
    url, name, icon, isExternal, extendedIcon, withBorder, badgeText, borderColor,
  } = site;

  function handleClick() {
    void vibrate();
    void openUrl(url, { isExternal, title: name, subtitle: getHostnameFromUrl(url) });
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.code === 'Enter' || e.code === 'Space') {
      e.preventDefault();
      handleClick();
    }
  }

  const borderStyle = withBorder && borderColor
    ? `--color-site-border: linear-gradient(270deg, ${borderColor.join(', ')})`
    : undefined;

  return (
    <div
      className={buildClassName(styles.itemWrapper, className)}
      style={borderStyle}
      tabIndex={-1}
      role="button"
      onClick={handleClick}
      onKeyDown={handleKeyDown}
    >
      <div
        className={buildClassName(
          styles.item,
          extendedIcon && styles.extended,
          withBorder && styles.withBorder,
        )}
      >
        <Image
          url={extendedIcon || icon}
          className={styles.imageWrapper}
          imageClassName={styles.image}
        />

        <div className={styles.infoWrapper}>
          <Site site={site} isEmbedded shouldHideIcon={!extendedIcon} />
        </div>
      </div>

      {badgeText && (
        <div className={buildClassName(styles.badge)}>{badgeText}</div>
      )}
    </div>
  );
}

export default memo(SiteFeatured);
