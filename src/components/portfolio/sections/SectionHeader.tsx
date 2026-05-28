import React, { memo } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';

import styles from './SectionHeader.module.scss';

interface OwnProps {
  title: string;
  range?: string;
  className?: string;
}

function SectionHeader({ title, range, className }: OwnProps) {
  return (
    <div className={buildClassName(styles.root, className)}>
      <h2 className={styles.title}>{title}</h2>
      {range && <span className={styles.range}>{range}</span>}
    </div>
  );
}

export default memo(SectionHeader);
