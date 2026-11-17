import type { TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import IconWithTooltip from '../ui/IconWithTooltip';

import styles from './TokenTrade.module.scss';

interface OwnProps {
  title: string;
  value?: TeactNode;
  /** Shown in place of a missing `value` */
  emptyValue: string;
  /** The explanation that the info icon next to the title shows */
  hint?: TeactNode;
  /** A control next to the title, such as a help button */
  titleAddon?: TeactNode;
  isError?: boolean;
  /** Makes the whole row a button with a chevron at its end */
  onClick?: NoneToVoidFunction;
}

/** A row of a trade details menu: the title with its hint and the value */
function TradeMenuRow({
  title, value, emptyValue, hint, titleAddon, isError, onClick,
}: OwnProps) {
  const content = (
    <>
      <span className={buildClassName(styles.menuRowTitle, isError && styles.menuRowError)}>
        {title}
        {hint !== undefined && (
          <IconWithTooltip
            message={hint}
            size="small"
            iconClassName={styles.menuTooltipIcon}
            tooltipClassName={styles.menuTooltip}
          />
        )}
        {titleAddon}
      </span>
      <span className={buildClassName(styles.menuRowValue, isError && styles.menuRowError)}>
        {value ?? emptyValue}
      </span>
    </>
  );

  if (!onClick) {
    return <div className={styles.menuRow}>{content}</div>;
  }

  return (
    <button type="button" className={buildClassName(styles.menuRow, styles.menuRowButton)} onClick={onClick}>
      {content}
      <i className={buildClassName(styles.menuRowChevron, 'icon-chevron-right')} aria-hidden />
    </button>
  );
}

export default TradeMenuRow;
