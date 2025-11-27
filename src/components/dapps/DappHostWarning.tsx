import React, { memo } from '../../lib/teact/teact';

import { APP_INSTALL_URL, IS_CAPACITOR } from '../../config';
import renderText from '../../global/helpers/renderText';
import { openUrl } from '../../util/openUrl';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import IconWithTooltip from '../ui/IconWithTooltip';

import styles from './Dapp.module.scss';

interface OwnProps {
  url?: string;
  iconClassName?: string;
}

function DappHostWarning({ url, iconClassName }: OwnProps) {
  const lang = useLang();

  const handleButtonClick = useLastCallback(
    (e: React.MouseEvent, platform: 'mobile' | 'chrome-extension') => {
      e.preventDefault();
      void openUrl(`${APP_INSTALL_URL}/${platform}`, { isExternal: true });
    },
  );

  return (
    <IconWithTooltip
      direction="bottom"
      message={(
        <>
          <b>{lang('Unverified Source')}</b>
          <p className={styles.dappHostWarningText}>
            {renderText(lang('$reopen_in_iab', {
              mobileAppButton: IS_CAPACITOR && url?.startsWith('http') ? (
                <button
                  type="button"
                  className={styles.dappHostWarningButton}
                  onClick={(e) => handleButtonClick(e, 'mobile')}
                >
                  {lang('mobile app')}
                </button>
              ) : (
                <b>{lang('mobile app')}</b>
              ),
              browserExtensionButton: IS_CAPACITOR && url?.startsWith('http') ? (
                <button
                  type="button"
                  className={styles.dappHostWarningButton}
                  onClick={(e) => handleButtonClick(e, 'chrome-extension')}
                >
                  {lang('browser extension')}
                </button>
              ) : (
                <b>{lang('browser extension')}</b>
              ),
            }))}
          </p>
        </>
      )}
      type="warning"
      size="small"
      iconClassName={iconClassName}
    />
  );
}

export default memo(DappHostWarning);
