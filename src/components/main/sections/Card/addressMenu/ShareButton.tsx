import React, { memo } from '../../../../../lib/teact/teact';

import buildClassName from '../../../../../util/buildClassName';

import useLang from '../../../../../hooks/useLang';

import menuStyles from '../../../../ui/Dropdown.module.scss';
import styles from '../Card.module.scss';

interface OwnProps {
  onClick: (e: React.MouseEvent) => void;
  onMouseEnter?: NoneToVoidFunction;
}

function ShareButton({
  onClick,
  onMouseEnter,
}: OwnProps) {
  const lang = useLang();

  return (
    <button
      type="button"
      className={buildClassName(menuStyles.item, styles.shareItem)}
      onClick={onClick}
      onMouseEnter={onMouseEnter}
    >
      <i className={buildClassName('icon-link', styles.shareItemIcon)} aria-hidden />
      <span className={styles.shareItemName}>{lang('Copy Wallet Link')}</span>
    </button>
  );
}

export default memo(ShareButton);
