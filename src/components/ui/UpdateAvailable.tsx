import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { AppReloadReason } from '../../global/types';

import {
  APP_INSTALL_URL,
  APP_NAME,
  APP_REPO_URL,
  IS_ANDROID_DIRECT,
  IS_FIREFOX_EXTENSION,
} from '../../config';
import buildClassName from '../../util/buildClassName';
import { openUrl } from '../../util/openUrl';
import {
  IS_CHROME_EXTENSION,
  IS_EDGE,
  IS_WEB,
} from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './UpdateAvailable.module.scss';

interface StateProps {
  isAppUpdateAvailable?: boolean;
  isAppUpdateRequired?: boolean;
  appReloadReason?: AppReloadReason;
  newAppVersion?: string;
}

function UpdateAvailable({
  isAppUpdateAvailable, newAppVersion, isAppUpdateRequired, appReloadReason,
}: StateProps) {
  const lang = useLang();

  const isUpdate = (IS_ANDROID_DIRECT && isAppUpdateAvailable) || isAppUpdateRequired
    || appReloadReason === 'buildOutdated';

  const { shouldRender, ref } = useShowTransition<HTMLButtonElement>({
    isOpen: Boolean(isUpdate || appReloadReason),
    withShouldRender: true,
  });

  const handleClick = () => {
    if (IS_WEB || appReloadReason) {
      window.location.reload();
      return;
    }

    void openUrl(getUrl(newAppVersion), { isExternal: true });
  };

  if (!shouldRender) {
    return undefined;
  }

  return (
    <button ref={ref} type="button" className={styles.wrapper} onClick={handleClick}>
      <i className={buildClassName('icon icon-download-filled', styles.icon)} aria-hidden />
      {isUpdate ? lang('Update %app_name%', { app_name: APP_NAME }) : lang('Reload App')}
    </button>
  );
}

export default memo(withGlobal((global): StateProps => ({
  isAppUpdateAvailable: global.isAppUpdateAvailable,
  newAppVersion: global.latestAppVersion,
  isAppUpdateRequired: global.isAppUpdateRequired,
  appReloadReason: global.appReloadReason,
}))(UpdateAvailable));

function getUrl(appVersion?: string) {
  if (IS_ANDROID_DIRECT) {
    return appVersion
      ? `${APP_REPO_URL}/releases/download/v${encodeURIComponent(appVersion || '')}/${encodeURIComponent(APP_NAME)}.apk`
      : 'https://github.com/mytonwallet-org/mytonwallet/releases/latest';
  }

  if (IS_CHROME_EXTENSION) {
    return `${APP_INSTALL_URL}${IS_EDGE ? 'edge-extension' : 'chrome-extension'}`;
  }

  if (IS_FIREFOX_EXTENSION) {
    return `${APP_INSTALL_URL}firefox-extension`;
  }

  return APP_INSTALL_URL;
}
