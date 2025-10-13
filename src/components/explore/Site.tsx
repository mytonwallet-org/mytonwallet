import React, { memo } from '../../lib/teact/teact';

import type { ApiSite } from '../../api/types';

import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';
import { openUrl } from '../../util/openUrl';
import { getHostnameFromUrl, isTelegramUrl } from '../../util/url';

import useLang from '../../hooks/useLang';

import Image from '../ui/Image';

import styles from './Explore.module.scss';

interface OwnProps {
  site: ApiSite;
  isFeatured?: boolean;
  isInList?: boolean;
  className?: string;
}

function Site({
  site: {
    url, icon, name, description, isExternal, isVerified, extendedIcon, withBorder, badgeText,
  },
  isFeatured,
  isInList,
  className,
}: OwnProps) {
  const lang = useLang();

  function handleClick() {
    void vibrate();
    void openUrl(url, { isExternal, title: name, subtitle: getHostnameFromUrl(url) });
  }

  return (
    <div
      className={buildClassName(
        styles.item,
        (extendedIcon && isFeatured) && styles.extended,
        isFeatured && styles.featured,
        !isInList && withBorder && styles.withBorder,
        className,
      )}
      tabIndex={0}
      role="button"
      onClick={handleClick}
    >
      <Image
        url={extendedIcon && isFeatured ? extendedIcon : icon}
        className={buildClassName(styles.imageWrapper, !isFeatured && styles.imageWrapperScalable)}
        imageClassName={buildClassName(styles.image, isFeatured && styles.featuredImage)}
      />
      <div className={buildClassName(styles.infoWrapper, !isFeatured && styles.wide)}>
        <b className={styles.title}>
          {name}

          {!isFeatured && isTelegramUrl(url) && (
            <i className={buildClassName(styles.titleIcon, 'icon-telegram-filled')} aria-hidden />
          )}
          {isFeatured && isVerified && (
            <i className={buildClassName(styles.titleIcon, 'icon-verification')} aria-hidden />
          )}
          {isInList && badgeText && <div className={styles.badgeLabel}>{badgeText}</div>}
        </b>
        <div className={styles.description}>{renderText(description, ['simple_markdown'])}</div>
      </div>
      {isInList && <div className={styles.button}>{lang('Open')}</div>}
      {!isInList && badgeText && <div className={styles.badge}>{badgeText}</div>}
    </div>
  );
}

export default memo(Site);
