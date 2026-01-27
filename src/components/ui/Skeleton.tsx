import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './Skeleton.module.scss';

interface OwnProps {
  className?: string;
  style?: string;
}

function Skeleton({ className, style }: OwnProps) {
  return <div className={buildClassName(styles.skeleton, className)} style={style} />;
}

export default memo(Skeleton);
