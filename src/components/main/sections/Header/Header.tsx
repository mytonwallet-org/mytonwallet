import React, { memo } from '../../../../lib/teact/teact';

import { SELF_UNIVERSAL_HOST_URL } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { tryOpenNativeApp } from '../../../../util/deeplink';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';

import AccountSelector from './AccountSelector';

import styles from './Header.module.scss';

import logoSrc from '../../../../assets/logoMinimalistic.svg';

export const HEADER_HEIGHT_REM = 3;

interface OwnProps {
  isScrolled?: boolean;
  withBalance?: boolean;
}

function Header({ isScrolled, withBalance }: OwnProps) {
  const lang = useLang();

  const { isPortrait } = useDeviceScreen();

  const handleOpenInAppClick = (e: React.MouseEvent) => {
    e.preventDefault();
    tryOpenNativeApp(SELF_UNIVERSAL_HOST_URL);
  };

  return (
    <div className={buildClassName(styles.header, isScrolled && styles.isScrolled)}>
      <div className={styles.headerInner} style="--icons-amount: 3">
        <AccountSelector withBalance={withBalance} />
        {isPortrait && (
          <div className={styles.portraitActionsRight}>
            <a
              href={SELF_UNIVERSAL_HOST_URL}
              className={styles.openLink}
              onClick={handleOpenInAppClick}
            >
              <img src={logoSrc} alt="" className={styles.mtLogo} />
              {lang('Open')}
            </a>
          </div>
        )}
      </div>
    </div>
  );
}

export default memo(Header);
