import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import Spinner from './Spinner';

import styles from './ListItem.module.scss';

interface OwnProps {
  icon?: string;
  label: TeactNode;
  className?: string;
  isLoading?: boolean;
  onClick: NoneToVoidFunction;
}

function ListItem({
  icon,
  label,
  className,
  isLoading,
  onClick,
}: OwnProps) {
  return (
    <button type="button" className={buildClassName(styles.root, className)} onClick={onClick} disabled={isLoading}>
      <i className={buildClassName(styles.icon, `icon-${icon}`)} aria-hidden />
      <span className={styles.label}>{label}</span>
      {
        isLoading ? (
          <Spinner className={buildClassName(styles.rightItem, styles.spinner)} />
        ) : (
          <i className={buildClassName(styles.rightItem, 'icon-chevron-right')} aria-hidden />
        )
      }
    </button>
  );
}

export default memo(ListItem);
