import type { ElementRef, TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './components/SwapHint.module.scss';

interface OwnProps {
  ref?: ElementRef<HTMLDivElement>;
  title?: TeactNode;
  message: TeactNode;
  actionTitle?: TeactNode;
  /** A red notice, for a risk the user should not take */
  isWarning?: boolean;
  /** A notice in the accent color, for a fact that involves no risk */
  isInformational?: boolean;
  className?: string;
  onActionClick?: NoneToVoidFunction;
}

/** A notice of a trade form, in the look of the hints of the Buy / Sell screen */
function TradeNotice({
  ref, title, message, actionTitle, isWarning, isInformational, className, onActionClick,
}: OwnProps) {
  const fullClassName = buildClassName(
    styles.root, styles.trade, isWarning && styles.warning, isInformational && styles.informational, className,
  );

  return (
    <div ref={ref} className={fullClassName}>
      <div className={styles.text}>
        {Boolean(title) && <span className={styles.title}>{title}</span>}
        <span className={styles.message}>{message}</span>
      </div>
      {Boolean(actionTitle) && (
        <button type="button" className={styles.action} onClick={onActionClick}>
          {actionTitle}
        </button>
      )}
    </div>
  );
}

export default memo(TradeNotice);
