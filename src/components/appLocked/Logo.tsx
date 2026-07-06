import React, { memo } from '../../lib/teact/teact';

import { IS_GRAM_WALLET, IS_TON_BRAND } from '../../config';

import useLang from '../../hooks/useLang';

import Image from '../ui/Image';

import styles from './AppLocked.module.scss';

import logoWebpPath from '../../assets/logo.webp';
import coreWalletLogoPath from '../../assets/logoCoreWallet.svg';
import gramWalletLogoPath from '../../assets/logoGramWallet.svg';

function Logo() {
  const lang = useLang();

  const logoPath = IS_GRAM_WALLET ? gramWalletLogoPath : IS_TON_BRAND ? coreWalletLogoPath : logoWebpPath;

  return (
    <div className={styles.logo}>
      <Image className={styles.logo} imageClassName={styles.logo} url={logoPath} alt={lang('Logo')} />
    </div>
  );
}

export default memo(Logo);
