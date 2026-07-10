import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import Button from '../ui/Button';

import styles from './WalletConnectPayHeader.module.scss';

interface OwnProps {
  title?: string;
  subtitle?: string;
  children?: TeactNode;
  onClose?: NoneToVoidFunction;
}

function WalletConnectPayHeader({ title, subtitle, children, onClose }: OwnProps) {
  const lang = useLang();

  return (
    <div className={styles.header}>
      {children}

      {(title || subtitle) && (
        <div className={styles.titleWrap}>
          {title && <div className={styles.title}>{title}</div>}
          {subtitle && <div className={styles.subtitle}>{subtitle}</div>}
        </div>
      )}

      {onClose && (
        <Button
          isRound
          className={styles.closeButton}
          ariaLabel={lang('Close')}
          onClick={onClose}
        >
          <i className={buildClassName(styles.closeIcon, 'icon-close')} aria-hidden />
        </Button>
      )}
    </div>
  );
}

export default memo(WalletConnectPayHeader);
