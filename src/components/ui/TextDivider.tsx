import React, { type TeactNode } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './TextDivider.module.scss';

function TextDivider({ children, className }: { children: TeactNode; className?: string }) {
  return <div className={buildClassName(styles.root, className)}>{children}</div>;
}

export default TextDivider;
