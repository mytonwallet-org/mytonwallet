import React, { memo } from '../../lib/teact/teact';

import type { ApiSite } from '../../api/types';

import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';
import { openUrl } from '../../util/openUrl';
import { getHostnameFromUrl, isTelegramUrl } from '../../util/url';

import useLang from '../../hooks/useLang';

import Image from '../ui/Image';

import styles from './Site.module.scss';

interface OwnProps {
  site: ApiSite;
  className?: string;
  role?: 'option' | 'button';
  isEmbedded?: boolean;
  isSelected?: boolean;
  shouldHideIcon?: boolean;
}

function Site({
  site: { url, icon, name, description, isExternal, isVerified, badgeText },
  className,
  role = 'button',
  isEmbedded = false,
  isSelected,
  shouldHideIcon = false,
}: OwnProps) {
  const lang = useLang();

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

  return (
    <div
      className={buildClassName(styles.item, className, isEmbedded && styles.embedded)}
      tabIndex={isSelected ? 0 : -1}
      role={role}
      aria-selected={isSelected}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
    >
      {!shouldHideIcon && (
        <Image
          url={icon}
          className={styles.imageWrapper}
          imageClassName={styles.image}
        />
      )}

      <div className={styles.infoWrapper}>
        <b className={styles.title}>
          {name}
          {isEmbedded && isVerified && (
            <i className={buildClassName(styles.titleIcon, styles.verificationIcon, 'icon-verification')} aria-hidden />
          )}
          {!isEmbedded && isTelegramUrl(url) && (
            <i className={buildClassName(styles.titleIcon, 'icon-telegram-filled')} aria-hidden />
          )}
          {!isEmbedded && badgeText && <div className={styles.badgeLabel}>{badgeText}</div>}
        </b>

        <div className={styles.description}>{renderText(description, ['simple_markdown'])}</div>
      </div>

      {!isEmbedded && (
        <div className={styles.button}>
          {lang('Open')}
        </div>
      )}
    </div>
  );
}

export default memo(Site);
