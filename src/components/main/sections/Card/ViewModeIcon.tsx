import React, { memo } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import { IS_EXPLORER } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';

import useLang from '../../../../hooks/useLang';

import styles from './Card.module.scss';

interface OwnProps {
  isMinimized?: boolean;
  isTemporary?: boolean;
}

function ViewModeIcon({ isMinimized, isTemporary }: OwnProps) {
  const { saveTemporaryAccount } = getActions();

  const lang = useLang();

  if (isMinimized) return undefined;

  if (isTemporary) {
    if (IS_EXPLORER) {
      return (
        <span className={styles.addressLabel}>
          <i className={buildClassName(styles.icon, 'icon-eye-filled')} aria-hidden />
          {lang('$view_mode')}
        </span>
      );
    }

    return (
      <button type="button" className={styles.saveTemporaryButton} onClick={() => saveTemporaryAccount()}>
        <i className={buildClassName(styles.addIcon, 'icon-eye-filled-plus')} aria-hidden />
        {lang('$view_mode')}
      </button>
    );
  }

  return (
    <span className={styles.addressLabel}>
      <i className={buildClassName(styles.icon, 'icon-eye-filled')} aria-hidden />
      {lang('$view_mode')}
    </span>
  );
}

export default memo(ViewModeIcon);
