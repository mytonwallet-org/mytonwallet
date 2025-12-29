import React, { memo } from '../../lib/teact/teact';

import { APP_INSTALL_URL } from '../../config';
import renderText from '../../global/helpers/renderText';

import useLang from '../../hooks/useLang';

import IconWithTooltip from '../ui/IconWithTooltip';

import styles from './Dapp.module.scss';

interface OwnProps {
  url?: string;
  iconClassName?: string;
}

function DappHostWarning({ url, iconClassName }: OwnProps) {
  const lang = useLang();

  return (
    <IconWithTooltip
      direction="bottom"
      message={(
        <>
          <b>{lang('Unverified Source')}</b>
          <p className={styles.dappHostWarningText}>
            {renderText(lang('$reopen_in_iab', {
              mobileAppButton: (
                <a
                  href={`${APP_INSTALL_URL}/mobile`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {lang('mobile app')}
                </a>
              ),
              browserExtensionButton: (
                <a
                  href={`${APP_INSTALL_URL}/chrome-extension`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {lang('browser extension')}
                </a>
              ),
            }))}
          </p>
        </>
      )}
      type="warning"
      size="small"
      iconClassName={iconClassName}
      canHoverOnTooltip
    />
  );
}

export default memo(DappHostWarning);
