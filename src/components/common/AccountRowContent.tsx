import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { ApiNft } from '../../api/types';
import type { Account, AccountType } from '../../global/types';
import type { AccountBalance } from '../main/modals/accountSelector/hooks/useAccountsBalances';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import AccountRowInner from './AccountRowInner';

import styles from './AccountRowContent.module.scss';

export interface AccountRowContentProps {
  accountId: string;
  byChain: Account['byChain'];
  accountType: AccountType;
  title?: string;
  isTestnet?: boolean;
  isSelected?: boolean;
  isDisabled?: boolean;
  balanceData?: AccountBalance;
  cardBackgroundNft?: ApiNft;
  isSensitiveDataHidden?: true;
  suffixIcon?: TeactNode;
  className?: string;
  avatarClassName?: string;
  onClick?: (accountId: string) => void;
}

/**
 * Renders a complete account row with wrapper div.
 * For use in lists where the component manages its own wrapper element.
 */
function AccountRowContent({
  accountId,
  byChain,
  accountType,
  title,
  isTestnet,
  isSelected,
  isDisabled,
  balanceData,
  cardBackgroundNft,
  isSensitiveDataHidden,
  suffixIcon,
  className,
  avatarClassName,
  onClick,
}: AccountRowContentProps) {
  const handleClick = useLastCallback(() => {
    onClick?.(accountId);
  });

  const fullClassName = buildClassName(
    styles.row,
    isSelected && styles.selected,
    isDisabled && styles.disabled,
    onClick && styles.interactive,
    className,
  );

  return (
    <div
      role={onClick ? 'button' : undefined}
      tabIndex={onClick && !isDisabled ? 0 : -1}
      className={fullClassName}
      onClick={!isDisabled ? handleClick : undefined}
    >
      <AccountRowInner
        accountId={accountId}
        byChain={byChain}
        accountType={accountType}
        title={title}
        isTestnet={isTestnet}
        balanceData={balanceData}
        cardBackgroundNft={cardBackgroundNft}
        isSensitiveDataHidden={isSensitiveDataHidden}
        suffixIcon={suffixIcon}
        avatarClassName={avatarClassName}
      />
    </div>
  );
}

export default memo(AccountRowContent);
