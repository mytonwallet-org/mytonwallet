import React, {
  memo, useMemo, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { Account } from '../../global/types';
import type { LedgerWalletInfo } from '../../util/ledger/types';

import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { shortenAddress } from '../../util/shortenAddress';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';

import settingsStyles from '../settings/Settings.module.scss';
import styles from './LedgerModal.module.scss';

type OwnProps = {
  isActive?: boolean;
  isStatic?: boolean;
  hardwareWallets?: LedgerWalletInfo[];
  accounts?: Record<string, Account>;
  onBackButtonClick?: NoneToVoidFunction;
  onCancel?: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
};

const ACCOUNT_ADDRESS_SHIFT = 4;
const ACCOUNT_BALANCE_DECIMALS = 3;

function LedgerSelectWallets({
  isActive,
  isStatic,
  hardwareWallets,
  accounts,
  onBackButtonClick,
  onCancel,
  onClose,
}: OwnProps) {
  const {
    afterSelectHardwareWallets,
    loadMoreHardwareWallets,
  } = getActions();
  const lang = useLang();

  const [selectedAccountIndices, setSelectedAccountIndices] = useState<number[]>([]);
  const shouldCloseOnCancel = !onCancel;

  useHistoryBack({
    isActive,
    onBack: onCancel ?? onClose,
  });

  const handleAccountToggle = useLastCallback((index: number) => {
    if (selectedAccountIndices.includes(index)) {
      setSelectedAccountIndices(selectedAccountIndices.filter((id) => id !== index));
    } else {
      setSelectedAccountIndices(selectedAccountIndices.concat([index]));
    }
  });

  const handleAddLedgerWallets = useLastCallback(() => {
    afterSelectHardwareWallets({ hardwareSelectedIndices: selectedAccountIndices });
    onClose();
  });

  const alreadyConnectedList = useMemo(
    () => Object.values(accounts ?? [])
      .map((account) => account.byChain.ton?.address)
      .filter(Boolean),
    [accounts],
  );

  const handleAddWalletClick = useLastCallback(() => {
    const list = hardwareWallets ?? [];
    const lastIndex = list[list.length - 1]?.index ?? 0;

    loadMoreHardwareWallets({ lastIndex });
  });

  function renderAddAccount() {
    return (
      <Button
        className={styles.addAccountContainer}
        onClick={handleAddWalletClick}
      >
        {lang('Add Wallet')}
        <i className={buildClassName(styles.addAccountIcon, 'icon-plus')} aria-hidden />
      </Button>
    );
  }

  function renderAccount(address: string, balance: bigint, index: number, isConnected: boolean) {
    const isActiveAccount = isConnected || selectedAccountIndices.includes(index);

    return (
      <div
        key={address}
        className={buildClassName(styles.account, isActiveAccount && styles.account_current)}
        onClick={isConnected ? undefined : () => handleAccountToggle(index)}
      >
        <span className={styles.accountName}>
          <i className={buildClassName(styles.accountCurrencyIcon, 'icon-ton')} aria-hidden />
          {formatCurrency(toDecimal(balance), '', ACCOUNT_BALANCE_DECIMALS)}
        </span>
        <div className={styles.accountFooter}>
          <span className={styles.accountAddress}>
            {shortenAddress(address, ACCOUNT_ADDRESS_SHIFT, ACCOUNT_ADDRESS_SHIFT)}
          </span>
        </div>

        <div className={buildClassName(styles.accountCheckMark, isActiveAccount && styles.accountCheckMark_active)} />
      </div>
    );
  }

  function renderAccounts() {
    const list = hardwareWallets ?? [];
    const fullClassName = buildClassName(
      styles.accounts,
      list.length === 1 && styles.accounts_two,
      'custom-scroll',
    );

    return (
      <div className={fullClassName}>
        {list.map(
          ({ address, balance, index }) => renderAccount(
            address,
            balance,
            index,
            alreadyConnectedList.includes(address),
          ),
        )}
        {renderAddAccount()}
      </div>
    );
  }

  const areAccountsSelected = !selectedAccountIndices.length;
  const title = selectedAccountIndices.length
    ? lang('%1$d Selected', selectedAccountIndices.length) as string
    : lang('Select Ledger Wallets');

  return (
    <>
      {!isStatic ? (
        <ModalHeader
          title={title}
          onBackButtonClick={onBackButtonClick}
          onClose={!onBackButtonClick ? onClose : undefined}
        />
      ) : (
        <div className={settingsStyles.header}>
          <Button isSimple isText onClick={onClose} className={settingsStyles.headerBack}>
            <i className={buildClassName(settingsStyles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={settingsStyles.headerTitle}>{title}</span>
        </div>
      )}
      <div className={buildClassName(
        styles.container, isStatic && styles.containerStatic, isStatic && 'static-container',
      )}
      >
        {renderAccounts()}
        <div className={styles.actionBlock}>
          <Button
            className={styles.button}
            onClick={shouldCloseOnCancel ? onClose : onCancel}
          >
            {lang(shouldCloseOnCancel ? 'Cancel' : 'Back')}
          </Button>
          <Button
            isPrimary
            isDisabled={areAccountsSelected}
            onClick={handleAddLedgerWallets}
            className={styles.button}
          >
            {lang('Add')}
          </Button>
        </div>
      </div>
    </>
  );
}

export default memo(LedgerSelectWallets);
