import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './TransactionBanner.module.scss';

interface OwnProps {
  icon?: string;
  text?: string | TeactNode[];
  secondText?: string | TeactNode[];
  color?: 'purple' | 'green';
  className?: string;
}

function Banner({ icon, text, secondText, color, className }: OwnProps) {
  const fullClassName = buildClassName(
    styles.root,
    color && styles[color],
    className,
  );

  return (
    <div className={fullClassName}>
      {icon && (
        <i className={buildClassName(icon, styles.tokenIcon)} aria-hidden />
      )}
      <span className={styles.text}>
        {secondText
          ? text
            ? (
              <div>
                <span className={buildClassName(styles.bold)}>
                  {text}
                </span>
                {' · '}
                <span className={buildClassName(styles.bold)}>{secondText}</span>
              </div>
            )
            : undefined
          : <span className={styles.bold}>{text}</span>}
      </span>
    </div>
  );
}

export default memo(Banner);
