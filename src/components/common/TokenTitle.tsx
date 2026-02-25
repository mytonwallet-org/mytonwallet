import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './TokenTitle.module.scss';

interface OwnProps {
  tokenName: string;
  tokenLabel?: string;
  isPinned?: boolean;
  isDisabled?: boolean;
}

function TokenTitle({
  tokenName,
  tokenLabel,
  isPinned,
  isDisabled,
}: OwnProps) {
  return (
    <div className={buildClassName(styles.tokenTitle, isDisabled && styles.disabled)}>
      {isPinned && <i className={buildClassName(styles.pinIcon, 'icon-pin')} aria-hidden />}
      <div className={styles.labelContainer}>
        <span>{tokenName}</span>
        {tokenLabel && (
          <span className={buildClassName(styles.label, styles.chainLabel)}>{tokenLabel}</span>
        )}
      </div>
    </div>
  );
}

export default TokenTitle;
