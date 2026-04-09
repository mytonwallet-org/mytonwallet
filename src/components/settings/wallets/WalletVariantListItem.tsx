import React, { memo } from '../../../lib/teact/teact';

import type { ApiChain, ApiWalletByChain } from '../../../api/types';

import buildClassName from '../../../util/buildClassName';

import MenuItem from '../../ui/MenuItem';

import styles from '../Settings.module.scss';

type ClickArg = {
  chain: ApiChain;
  isTestnetSubwalletId?: boolean;
  newWallet: Omit<ApiWalletByChain[ApiChain], 'index'>;
  isReplace: boolean;
};

interface WalletVariantListItemProps {
  title: string;
  subtitle: string;
  label?: string;
  tokens: string;
  totalBalance: string;
  onClick: (
    e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    arg: ClickArg
  ) => void;
  clickArg: ClickArg;
}

function WalletVariantListItem({
  title,
  subtitle,
  label,
  tokens,
  totalBalance,
  onClick,
  clickArg,
}: WalletVariantListItemProps) {
  return (
    <MenuItem<ClickArg>
      ignoreBaseClassName
      className={buildClassName(styles.item, styles.item_wallet_no_arrow)}
      onClick={onClick}
      clickArg={clickArg}
    >
      <div className={styles.walletVersionInfo}>
        <div className={styles.walletVariantLabelContainer}>
          <span className={styles.walletVersionTitle}>{title}</span>
          {label && (
            <span className={styles.walletVariantLabel}>{label}</span>
          )}
        </div>
        <span className={styles.walletVersionAddress}>{subtitle}</span>
      </div>
      <div className={styles.walletVersionInfoRight}>
        {tokens !== undefined && (
          <span className={styles.walletVersionTokens}>{tokens}</span>
        )}
        {totalBalance !== undefined && (
          <span className={styles.walletVersionAmount}>
            ≈&thinsp;{totalBalance}
          </span>
        )}
      </div>
    </MenuItem>
  );
}

export default memo(WalletVariantListItem);
