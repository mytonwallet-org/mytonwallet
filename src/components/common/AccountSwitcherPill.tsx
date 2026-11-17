import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import WalletAvatar from '../ui/WalletAvatar';

import styles from './AccountSwitcherPill.module.scss';

interface OwnProps {
  accountId: string;
  title?: string;
  /** The pill only names the account, which the screen does not let change */
  isReadOnly?: boolean;
  className?: string;
  testId?: string;
  onClick?: NoneToVoidFunction;
}

function AccountSwitcherPill({
  accountId, title, isReadOnly, className, testId, onClick,
}: OwnProps) {
  const lang = useLang();

  const content = (
    <>
      <WalletAvatar
        title={title}
        accountId={accountId}
        className={styles.pillAvatar}
      />
      {!isReadOnly && <i className={buildClassName(styles.pillCaret, 'icon-expand')} aria-hidden />}
    </>
  );

  if (!onClick) {
    return (
      <div className={buildClassName(styles.pill, styles.pill_disabled, isReadOnly && styles.pill_readOnly, className)}>
        {content}
      </div>
    );
  }

  return (
    <button
      type="button"
      className={buildClassName(styles.pill, className)}
      aria-label={lang('Selected Wallet')}
      data-testid={testId}
      onClick={onClick}
    >
      {content}
    </button>
  );
}

export default memo(AccountSwitcherPill);
