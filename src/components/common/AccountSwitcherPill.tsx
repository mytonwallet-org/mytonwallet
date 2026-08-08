import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import WalletAvatar from '../ui/WalletAvatar';

import styles from './AccountSwitcherPill.module.scss';

interface OwnProps {
  accountId: string;
  title?: string;
  className?: string;
  onClick?: NoneToVoidFunction;
}

function AccountSwitcherPill({
  accountId, title, className, onClick,
}: OwnProps) {
  const lang = useLang();

  const content = (
    <>
      <WalletAvatar
        title={title}
        accountId={accountId}
        className={styles.pillAvatar}
      />
      <i className={buildClassName(styles.pillCaret, 'icon-expand')} aria-hidden />
    </>
  );

  if (!onClick) {
    return (
      <div className={buildClassName(styles.pill, styles.pill_disabled, className)}>
        {content}
      </div>
    );
  }

  return (
    <button
      type="button"
      className={buildClassName(styles.pill, className)}
      aria-label={lang('Selected Wallet')}
      onClick={onClick}
    >
      {content}
    </button>
  );
}

export default memo(AccountSwitcherPill);
