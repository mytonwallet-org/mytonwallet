import React, { memo } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import { vibrate } from '../../../../../util/haptics';

import useLang from '../../../../../hooks/useLang';
import useLastCallback from '../../../../../hooks/useLastCallback';

import Button from '../../../../ui/Button';

import styles from './Buttons.module.scss';

function AppLockButton() {
  const { setIsManualLockActive } = getActions();

  const lang = useLang();

  const handleManualLock = useLastCallback(() => {
    setIsManualLockActive({ isActive: true, shouldHideBiometrics: true });

    vibrate();
  });

  return (
    <Button
      className={styles.button}
      isText
      isSimple
      kind="transparent"
      ariaLabel={lang('App Lock')}
      onClick={handleManualLock}
    >
      <i className="icon-manual-lock" aria-hidden />
    </Button>
  );
}

export default memo(AppLockButton);
