import React, { memo } from '../../lib/teact/teact';

import { IS_CORE_WALLET } from '../../config';

import useLang from '../../hooks/useLang';

import Image from '../ui/Image';

import styles from './AppLocked.module.scss';

import logoWebpPath from '../../assets/logo.webp';
import coreWalletLogoPath from '../../assets/logoCoreWallet.svg';

function Logo() {
  const lang = useLang();

  const logoPath = IS_CORE_WALLET ? coreWalletLogoPath : logoWebpPath;

  return (
    <div className={styles.logo}>
      <Image className={styles.logo} imageClassName={styles.logo} url={logoPath} alt={lang('Logo')} />
    </div>
  );
}

export default memo(Logo);
