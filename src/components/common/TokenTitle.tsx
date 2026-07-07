import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import TokenLabel from './TokenLabel';

import styles from './TokenTitle.module.scss';

interface OwnProps {
  tokenName: string;
  tokenLabel?: string;
  isRwaStock?: boolean;
  isPinned?: boolean;
  isDisabled?: boolean;
}

function TokenTitle({
  tokenName,
  tokenLabel,
  isRwaStock,
  isPinned,
  isDisabled,
}: OwnProps) {
  return (
    <div className={buildClassName(styles.tokenTitle, isDisabled && styles.disabled)}>
      {isPinned && <i className={buildClassName(styles.pinIcon, 'icon-pin')} aria-hidden />}
      <div className={styles.labelContainer}>
        <span className={styles.tokenName}>{tokenName}</span>
        {tokenLabel && <TokenLabel label={tokenLabel} isRwaStock={isRwaStock} />}
      </div>
    </div>
  );
}

export default TokenTitle;
