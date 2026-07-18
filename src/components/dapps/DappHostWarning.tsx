import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { ApiDappurlTrustStatusStatus } from '../../api/types';

import { APP_INSTALL_URL, APP_NAME } from '../../config';
import renderText from '../../global/helpers/renderText';

import useLang from '../../hooks/useLang';

import IconWithTooltip from '../ui/IconWithTooltip';

import styles from './Dapp.module.scss';

interface OwnProps {
  url?: string;
  iconClassName?: string;
  /** When omitted, treated as `unknown` (legacy). */
  urlTrustStatus?: ApiDappurlTrustStatusStatus;
}

function DappHostWarning({ url, iconClassName, urlTrustStatus = 'unknown' }: OwnProps) {
  const lang = useLang();

  if (urlTrustStatus === 'verified') {
    return;
  }

  const reopenBody = (
    <p className={styles.dappHostWarningText}>
      {renderText(lang('$reopen_in_iab', {
        app_name: APP_NAME,
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
  );

  let title: string;
  let body: TeactNode;

  if (urlTrustStatus === 'invalid') {
    title = lang('DappurlTrustStatusInvalidTitle');
    body = <p className={styles.dappHostWarningText}>{lang('$DappurlTrustStatusInvalidHelp')}</p>;
  } else if (urlTrustStatus === 'dangerous') {
    title = lang('DappurlTrustStatusDangerousTitle');
    body = <p className={styles.dappHostWarningText}>{lang('$DappurlTrustStatusDangerousHelp')}</p>;
  } else {
    title = lang('Unverified Source');
    body = reopenBody;
  }

  return (
    <IconWithTooltip
      direction="bottom"
      message={(
        <>
          <b>{title}</b>
          {body}
        </>
      )}
      type={urlTrustStatus === 'dangerous' ? 'danger' : 'warning'}
      size="small"
      iconClassName={iconClassName}
      canHoverOnTooltip
    />
  );
}

export default memo(DappHostWarning);
