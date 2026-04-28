import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './WarningMessage.module.scss';

type OwnProps = {
  children: TeactNode;
  className?: string;
};

function WarningMessage({ children, className }: OwnProps) {
  return (
    <div className={buildClassName(styles.root, className)}>
      {children}
    </div>
  );
}

export default memo(WarningMessage);
