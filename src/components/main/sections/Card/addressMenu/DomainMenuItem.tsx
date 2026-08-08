import React, { memo } from '../../../../../lib/teact/teact';

import buildClassName from '../../../../../util/buildClassName';

import menuStyles from '../../../../ui/Dropdown.module.scss';
import styles from '../Card.module.scss';

interface OwnProps {
  title: string;
  subtitle: string;
  onClick: NoneToVoidFunction;
}

function DomainMenuItem({
  title,
  subtitle,
  onClick,
}: OwnProps) {
  return (
    <button
      type="button"
      className={buildClassName(menuStyles.item, styles.chainItem, styles.domainItem)}
      onClick={onClick}
    >
      <div className={styles.chainItemContent}>
        <span className={styles.chainItemTitle}>{title}</span>
        <span className={styles.chainItemSubtitle}>{subtitle}</span>
      </div>
      <i className={buildClassName('icon-copy', styles.itemActionIcon)} aria-hidden />
    </button>
  );
}

export default memo(DomainMenuItem);
