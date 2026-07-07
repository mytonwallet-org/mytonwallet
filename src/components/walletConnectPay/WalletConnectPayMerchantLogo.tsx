import React, { memo } from '../../lib/teact/teact';

import type { WcPayMerchant } from '../../api/dappProtocols/adapters/walletConnect/types';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import Image from '../ui/Image';
import Skeleton from '../ui/Skeleton';

import styles from './WalletConnectPay.module.scss';

interface OwnProps {
  merchant?: WcPayMerchant;
  className?: string;
}

function WalletConnectPayMerchantLogo({ merchant, className }: OwnProps) {
  const lang = useLang();

  if (!merchant) {
    return (
      <div className={buildClassName(styles.merchantLogoWrap, className)}>
        <Skeleton className={styles.merchantLogo} />
      </div>
    );
  }

  return (
    <div className={buildClassName(styles.merchantLogoWrap, className)}>
      {merchant.iconUrl && (
        <Image
          url={merchant.iconUrl}
          forceLoaded
          className={buildClassName(styles.merchantLogo, styles.merchantLogoGlow)}
        />
      )}
      <Image
        url={merchant.iconUrl}
        alt={merchant.name || lang('Logo')}
        forceLoaded
        className={buildClassName(styles.merchantLogo, styles.merchantIcon)}
        fallback={(
          <i
            className={buildClassName(
              styles.merchantLogo,
              styles.merchantLogo_icon,
              styles.merchantIcon,
              'icon-card',
            )}
            aria-hidden
          />
        )}
      />
    </div>
  );
}

export default memo(WalletConnectPayMerchantLogo);
