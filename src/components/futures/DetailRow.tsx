import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import IconWithTooltip from '../ui/IconWithTooltip';

import styles from './DetailRow.module.scss';

interface OwnProps {
  label: TeactNode;
  /** The explanation the info icon next to the label shows */
  hint?: string;
  value: TeactNode;
  /** The value before the operation, shown with an arrow to `value` */
  prevValue?: TeactNode;
  className?: string;
  labelClassName?: string;
  valueClassName?: string;
}

function DetailRow({
  label, hint, value, prevValue, className, labelClassName, valueClassName,
}: OwnProps) {
  return (
    <div className={buildClassName(styles.root, className)}>
      <span className={buildClassName(styles.label, labelClassName)}>
        {label}
        {hint && (
          <>
            {' '}
            <IconWithTooltip message={hint} size="small" tooltipClassName={styles.hint} />
          </>
        )}
      </span>
      <span className={buildClassName(styles.value, valueClassName)}>
        {prevValue !== undefined ? (
          <span className={styles.change}>
            <span className={styles.prevValue}>{prevValue}</span>
            <span className={styles.arrow}>→</span>
            {value}
          </span>
        ) : value}
      </span>
    </div>
  );
}

export default memo(DetailRow);
