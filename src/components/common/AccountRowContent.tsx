import type { ElementRef, TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { ApiChain, ApiNft } from '../../api/types';
import type { Account, AccountType } from '../../global/types';
import type { AccountBalance } from '../../hooks/useAccountsBalances';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import AccountRowInner from './AccountRowInner';

import styles from './AccountRowContent.module.scss';

export interface AccountRowContentProps {
  ref?: ElementRef<HTMLDivElement>;
  accountId: string;
  byChain: Account['byChain'];
  visibleChains?: ApiChain[];
  accountType: AccountType;
  title?: string;
  isTestnet?: boolean;
  isRecoveryRequired?: true;
  isSelected?: boolean;
  isDisabled?: boolean;
  balanceData?: AccountBalance;
  cardBackgroundNft?: ApiNft;
  isSensitiveDataHidden?: true;
  suffixIcon?: TeactNode;
  className?: string;
  avatarClassName?: string;
  avatarUrl?: string;
  onClick?: (accountId: string) => void;
  onMouseDown?: (e: React.MouseEvent) => void;
  onContextMenu?: (e: React.MouseEvent) => void;
}

function AccountRowContent({
  ref,
  accountId,
  byChain,
  visibleChains,
  accountType,
  title,
  isTestnet,
  isRecoveryRequired,
  isSelected,
  isDisabled,
  balanceData,
  cardBackgroundNft,
  isSensitiveDataHidden,
  suffixIcon,
  className,
  avatarClassName,
  avatarUrl,
  onClick,
  onMouseDown,
  onContextMenu,
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
      ref={ref}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick && !isDisabled ? 0 : -1}
      className={fullClassName}
      onClick={!isDisabled ? handleClick : undefined}
      onMouseDown={onMouseDown}
      onContextMenu={onContextMenu}
    >
      <AccountRowInner
        accountId={accountId}
        byChain={byChain}
        visibleChains={visibleChains}
        accountType={accountType}
        title={title}
        isTestnet={isTestnet}
        isRecoveryRequired={isRecoveryRequired}
        balanceData={balanceData}
        cardBackgroundNft={cardBackgroundNft}
        isSensitiveDataHidden={isSensitiveDataHidden}
        suffixIcon={suffixIcon}
        avatarClassName={avatarClassName}
        avatarUrl={avatarUrl}
      />
    </div>
  );
}

export default memo(AccountRowContent);
