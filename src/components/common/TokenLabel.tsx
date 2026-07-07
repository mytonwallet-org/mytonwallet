import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './TokenLabel.module.scss';

interface OwnProps {
  label: string;
  isRwaStock?: boolean;
}

function TokenLabel({ label, isRwaStock }: OwnProps) {
  const fullClassName = buildClassName(
    styles.label,
    isRwaStock ? styles.rwaStockLabel : styles.chainLabel,
  );

  return <span className={fullClassName}>{label}</span>;
}

export default memo(TokenLabel);
