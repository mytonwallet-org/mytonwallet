import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import WalletAvatar from '../ui/WalletAvatar';

import styles from './WalletConnectPay.module.scss';

interface OwnProps {
  accountId: string;
  title?: string;
  onClick?: NoneToVoidFunction;
}

function WalletConnectPayAccountPill({ accountId, title, onClick }: OwnProps) {
  const lang = useLang();

  const content = (
    <>
      <WalletAvatar
        title={title}
        accountId={accountId}
        className={styles.accountSelectorAvatar}
      />
      <i className={buildClassName(styles.accountSelectorCaret, 'icon-expand')} aria-hidden />
    </>
  );

  if (!onClick) {
    return (
      <div className={buildClassName(styles.accountSelectorPill, styles.accountSelectorPill_disabled)}>
        {content}
      </div>
    );
  }

  return (
    <button
      type="button"
      className={styles.accountSelectorPill}
      aria-label={lang('Selected Wallet')}
      onClick={onClick}
    >
      {content}
    </button>
  );
}

export default memo(WalletConnectPayAccountPill);
