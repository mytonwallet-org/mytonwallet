import React, { memo, useMemo } from '../../lib/teact/teact';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Image from '../ui/Image';
import DappHostWarning from './DappHostWarning';

import styles from './Dapp.module.scss';

const ICON_FALLBACK_CLASS_NAME = buildClassName(styles.dappLogo, styles.dappLogo_icon, styles.dappIcon, 'icon-laptop');

interface OwnProps {
  dapp?: StoredDappConnection;
  onDisconnect?: (origin: string) => void;
}

function DappInfo({
  dapp,
  onDisconnect,
}: OwnProps) {
  const lang = useLang();

  const { name, iconUrl, url, urlTrustStatus } = dapp || {};
  const host = useMemo(() => url ? new URL(url).host : undefined, [url]);

  const shouldShowDisconnect = Boolean(onDisconnect && url);

  const handleDisconnect = useLastCallback(() => {
    onDisconnect!(url!);
  });

  return (
    <div className={styles.dapp}>
      <Image
        url={iconUrl}
        alt={name || lang('Logo')}
        forceLoaded
        className={styles.dappLogo}
        imageClassName={styles.dappLogo}
        fallbackClassName={ICON_FALLBACK_CLASS_NAME}
      />
      <div className={styles.dappInfo}>
        <span className={styles.dappName}>{name}</span>
        <span className={styles.dappHost}>
          {urlTrustStatus !== 'verified' && (
            <DappHostWarning urlTrustStatus={urlTrustStatus} iconClassName={styles.dappHostWarningIcon} />
          )}
          <span className={styles.dappHostText}>{host}</span>
        </span>
      </div>
      {shouldShowDisconnect && (
        <Button
          isSmall
          isPrimary
          className={styles.dappDisconnect}
          onClick={handleDisconnect}
        >
          {lang('Disconnect')}
        </Button>
      )}
    </div>
  );
}

export default memo(DappInfo);
