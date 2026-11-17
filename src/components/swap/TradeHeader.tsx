import type { TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import Button from '../ui/Button';

import styles from './TokenTrade.module.scss';

interface OwnProps {
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
  /** Shown between the account and the buttons */
  title?: TeactNode;
  /** The menu button before the close button */
  menu: TeactNode;
  className?: string;
  /** Lets the account pill switch the account. Without it, the pill only names the account. */
  onAccountClick?: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

/** The header of a trade form: the account pill, an optional title, the menu button and the close button */
function TradeHeader({
  accountId, accountTitle, hasMultipleAccounts, title, menu, className, onAccountClick, onClose,
}: OwnProps) {
  const lang = useLang();

  return (
    <div className={buildClassName(styles.header, className)}>
      {hasMultipleAccounts && accountId ? (
        <AccountSwitcherPill
          accountId={accountId}
          title={accountTitle}
          isReadOnly={!onAccountClick}
          onClick={onAccountClick}
        />
      ) : <span />}
      {title}
      <div className={styles.headerButtons}>
        {menu}
        <Button isRound className={styles.headerButton} ariaLabel={lang('Close')} onClick={onClose}>
          <i className={buildClassName(styles.headerCloseIcon, 'icon-close')} aria-hidden />
        </Button>
      </div>
    </div>
  );
}

export default TradeHeader;
