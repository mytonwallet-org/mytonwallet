import React, { memo } from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useShowTransition from '../../../../hooks/useShowTransition';

import styles from './Warnings.module.scss';

type OwnProps = {
  isRequired: boolean;
  onOpenBackupWallet: () => void;
};

function BackupWarning({ isRequired, onOpenBackupWallet }: OwnProps) {
  const { shouldRender, ref } = useShowTransition({
    isOpen: isRequired,
    noMountTransition: true,
    withShouldRender: true,
  });
  const { isLandscape } = useDeviceScreen();

  const lang = useLang();

  const handleClick = () => {
    onOpenBackupWallet();
  };

  if (!shouldRender) {
    return undefined;
  }

  return (
    <div
      ref={ref}
      className={buildClassName(styles.wrapper, isLandscape && styles.wrapper_landscape)}
      onClick={handleClick}
    >
      {lang('Wallet is not backed up')}
      <i className={buildClassName(styles.icon, 'icon-chevron-right')} aria-hidden />
      <p className={styles.text}>
        {lang('Back up wallet to have full access to it')}
      </p>
    </div>
  );
}

export default memo(BackupWarning);
