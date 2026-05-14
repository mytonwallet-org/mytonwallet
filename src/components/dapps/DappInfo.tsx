import React, { memo, useMemo } from '../../lib/teact/teact';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Image from '../ui/Image';
import DappHostWarning from './DappHostWarning';

import styles from './Dapp.module.scss';

const ICON_FALLBACK = (
  <i
    className={buildClassName(styles.dappLogo, styles.dappLogo_icon, styles.dappIcon, 'icon-laptop')}
    aria-hidden
  />
);

interface OwnProps {
  dapp?: StoredDappConnection;
  variant: 'settings' | 'transfer';
  onDisconnect?: (origin: string) => void;
}

function DappInfo({
  dapp,
  variant,
  onDisconnect,
}: OwnProps) {
  const lang = useLang();

  const { name, iconUrl, url, isUrlEnsured } = dapp || {};
  const host = useMemo(() => url ? new URL(url).host : undefined, [url]);

  const shouldShowDisconnect = Boolean(onDisconnect && url);

  const handleDisconnect = useLastCallback(() => {
    onDisconnect!(url!);
  });

  function renderIcon() {
    return (
      <Image
        url={iconUrl}
        alt={name || lang('Logo')}
        forceLoaded
        className={styles.dappLogo}
        imageClassName={styles.dappLogo}
        fallback={ICON_FALLBACK}
      />
    );
  }

  const warningIconJsx = !isUrlEnsured && (
    <DappHostWarning url={url} iconClassName={styles.dappHostWarningIcon} />
  );

  return (
    <div className={buildClassName(styles.dapp, variant === 'transfer' && styles.dapp_transfer)}>
      {variant === 'settings' && renderIcon()}
      <div className={styles.dappInfo}>
        <span className={styles.dappName}>{name}</span>
        <span className={styles.dappHost}>
          {variant === 'settings' && warningIconJsx}
          <span className={styles.dappHostText}>{host}</span>
          {variant === 'transfer' && warningIconJsx}
        </span>
      </div>
      {variant === 'transfer' && renderIcon()}
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
