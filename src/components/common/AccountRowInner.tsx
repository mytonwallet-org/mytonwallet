import type { TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import type { ApiNft } from '../../api/types';
import type { Account, AccountType } from '../../global/types';
import type { AccountBalance } from '../main/modals/accountSelector/hooks/useAccountsBalances';

import buildClassName from '../../util/buildClassName';
import { formatAccountAddresses } from '../../util/formatAccountAddress';
import { formatCurrency } from '../../util/formatNumber';
import isViewAccount from '../../util/isViewAccount';

import CustomCardPreview from '../main/modals/accountSelector/CustomCardPreview';
import SensitiveData from '../ui/SensitiveData';
import WalletAvatar from '../ui/WalletAvatar';

import styles from './AccountRowContent.module.scss';

export interface AccountRowInnerProps {
  accountId: string;
  byChain: Account['byChain'];
  accountType: AccountType;
  title?: string;
  isTestnet?: boolean;
  balanceData?: AccountBalance;
  cardBackgroundNft?: ApiNft;
  isSensitiveDataHidden?: true;
  suffixIcon?: TeactNode;
  avatarClassName?: string;
}

/**
 * Renders just the inner content of an account row (avatar, info, balance, suffix).
 * Does NOT include a wrapper div - meant to be used inside parent's wrapper.
 */
function AccountRowInner({
  accountId,
  byChain,
  accountType,
  title,
  isTestnet,
  balanceData,
  cardBackgroundNft,
  isSensitiveDataHidden,
  suffixIcon,
  avatarClassName,
}: AccountRowInnerProps) {
  const isHardware = accountType === 'hardware';
  const isView = isViewAccount(accountType);
  const formattedAddress = formatAccountAddresses(byChain, 'list');

  return (
    <>
      <WalletAvatar
        title={title}
        accountId={accountId}
        className={buildClassName(styles.avatar, avatarClassName)}
      />

      <div className={styles.info}>
        <div className={styles.titleRow}>
          <span className={styles.title}>{title}</span>
          {cardBackgroundNft && (
            <CustomCardPreview nft={cardBackgroundNft} className={styles.nftIndicator} />
          )}
        </div>
        <div className={styles.address}>
          {isTestnet && <i className={buildClassName(styles.icon, 'icon-testnet')} aria-hidden />}
          {isHardware && <i className={buildClassName(styles.icon, 'icon-ledger')} aria-hidden />}
          {isView && <i className={buildClassName(styles.icon, 'icon-eye-filled')} aria-hidden />}
          {formattedAddress}
        </div>
      </div>

      {balanceData && (
        <SensitiveData
          isActive={isSensitiveDataHidden}
          rows={2}
          min={5}
          max={10}
          seed={title || ''}
          cellSize={8}
          align="right"
        >
          <div className={styles.balance}>
            {formatCurrency(balanceData.value, balanceData.currencySymbol)}
          </div>
        </SensitiveData>
      )}

      {suffixIcon}
    </>
  );
}

export default AccountRowInner;
