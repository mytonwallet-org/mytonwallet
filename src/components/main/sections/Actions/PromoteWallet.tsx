import React, { memo, useMemo } from '../../../../lib/teact/teact';

import { APP_INSTALL_URL, APP_NAME, MYTONWALLET_PROMO_URL, SELF_UNIVERSAL_HOST_URL } from '../../../../config';
import { tryOpenNativeApp } from '../../../../util/deeplink';
import { getTelegramNewsChannelUrl } from '../../../../util/url';

import useLang from '../../../../hooks/useLang';

import styles from './PromoteWallet.module.scss';

function PromoteWallet() {
  const lang = useLang();

  const handleOpenClick = (e: React.MouseEvent) => {
    e.preventDefault();
    tryOpenNativeApp(SELF_UNIVERSAL_HOST_URL);
  };

  const links: { name: string; url: string }[] = useMemo(() => {
    return [{
      name: lang('About'),
      url: MYTONWALLET_PROMO_URL,
    }, {
      name: lang('Blog'),
      url: `${MYTONWALLET_PROMO_URL}blog`,
    }, {
      name: lang('Apps'),
      url: APP_INSTALL_URL,
    }, {
      name: 'Telegram',
      url: getTelegramNewsChannelUrl(lang.code!),
    }];
  }, [lang]);

  return (
    <div className={styles.root}>
      <a
        href={SELF_UNIVERSAL_HOST_URL}
        className={styles.button}
        onClick={handleOpenClick}
      >
        <i className="icon-open-external" />
        {lang('Open in %app_name%', { app_name: APP_NAME })}
      </a>

      <ul className={styles.links}>
        {links.map(({ name, url }) => (
          <li key={name} className={styles.wrapper}>
            <a href={url} target="_blank" rel="noopener noreferrer" className={styles.link}>{name}</a>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default memo(PromoteWallet);
