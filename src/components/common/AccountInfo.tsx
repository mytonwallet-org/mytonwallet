import React, { memo, useMemo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import type { Account } from '../../global/types';
import type { AccountBalance } from '../main/modals/accountSelector/hooks/useAccountsBalances';

import { selectAccountSettings, selectCurrentAccount, selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { formatAccountAddresses } from '../../util/formatAccountAddress';
import { formatCurrency } from '../../util/formatNumber';
import getPseudoRandomNumber from '../../util/getPseudoRandomNumber';
import isViewAccount from '../../util/isViewAccount';

import CustomCardPreview from '../main/modals/accountSelector/CustomCardPreview';
import SensitiveData from '../ui/SensitiveData';
import WalletAvatar from '../ui/WalletAvatar';

import styles from './AccountInfo.module.scss';

interface StateProps {
  currentAccount?: Account;
  currentAccountId?: string;
  cardBackgroundNft?: ApiNft;
  isSensitiveDataHidden?: boolean;
  isTestnet?: boolean;
}

interface OwnProps {
  balanceData?: AccountBalance;
}

function AccountInfo({
  currentAccount,
  currentAccountId,
  cardBackgroundNft,
  isSensitiveDataHidden,
  isTestnet,
  balanceData,
}: StateProps & OwnProps) {
  if (!currentAccount) return;

  const isHardware = currentAccount.type === 'hardware';
  const isView = isViewAccount(currentAccount.type);
  const formattedAddress = formatAccountAddresses(currentAccount.byChain, 'list');

  const amountCols = useMemo(() => getPseudoRandomNumber(4, 12, currentAccount.title || ''), [currentAccount.title]);
  const fiatAmountCols = 5 + (amountCols % 6);

  return (
    <div className={styles.info}>
      <WalletAvatar
        title={currentAccount.title}
        accountId={currentAccountId}
        className={styles.avatar}
      />

      <div className={styles.titleRow}>
        <span className={styles.title}>{currentAccount.title}</span>

        {balanceData && (
          <SensitiveData
            isActive={isSensitiveDataHidden}
            rows={2}
            cols={fiatAmountCols}
            cellSize={8}
            align="right"
          >
            <div className={buildClassName(styles.balance, 'rounded-font')}>
              {formatCurrency(balanceData.value, balanceData.currencySymbol)}
            </div>
          </SensitiveData>
        )}

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
  );
}

export default memo(withGlobal((global): StateProps => {
  const currentAccount = selectCurrentAccount(global);
  const currentAccountId = selectCurrentAccountId(global);
  const accountSettings = selectAccountSettings(global, currentAccountId!);

  const { isSensitiveDataHidden, isTestnet } = global.settings;

  return {
    currentAccount,
    currentAccountId,
    cardBackgroundNft: accountSettings?.cardBackgroundNft,
    isSensitiveDataHidden,
    isTestnet,
  };
})(AccountInfo));
