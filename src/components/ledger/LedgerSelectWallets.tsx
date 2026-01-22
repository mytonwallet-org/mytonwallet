import React, {
  memo, useMemo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain, ApiLedgerWalletInfo } from '../../api/types';
import type { Account } from '../../global/types';

import { TOKEN_CUSTOM_STYLES } from '../../config';
import { selectNetworkAccounts } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { shortenAddress } from '../../util/shortenAddress';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useViewTransitionedState from '../../hooks/useViewTransitionedState';

import Button from '../ui/Button';
import LoadingDots from '../ui/LoadingDots';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';

import settingsStyles from '../settings/Settings.module.scss';
import styles from './LedgerModal.module.scss';

type OwnProps = {
  isActive?: boolean;
  isStatic?: boolean;
  withCloseButton?: boolean;
  onBackButtonClick?: NoneToVoidFunction;
  onCancel?: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
};

type StateProps = {
  chain: ApiChain;
  hardwareWallets?: ApiLedgerWalletInfo[];
  accounts?: Record<string, Account>;
  isLoading?: boolean;
};

const ACCOUNT_ADDRESS_SHIFT = 4;
const ACCOUNT_BALANCE_DECIMALS = 3;

function LedgerSelectWallets({
  isActive,
  isStatic,
  chain,
  hardwareWallets,
  accounts,
  isLoading,
  withCloseButton,
  onBackButtonClick,
  onCancel,
  onClose,
}: OwnProps & StateProps) {
  const {
    afterSelectHardwareWallets,
    loadMoreHardwareWallets,
  } = getActions();
  const lang = useLang();
  const balanceToken = getChainConfig(chain).nativeToken;
  const balanceTokenFontIcon = TOKEN_CUSTOM_STYLES[balanceToken.slug]?.fontIcon;

  const { renderedValue: renderedWallets, vtnStyle } = useViewTransitionedState(
    hardwareWallets,
    { transitionName: 'acc-list' },
  );
  const [selectedAccountIndices, setSelectedAccountIndices] = useState<number[]>([]);
  const shouldCloseOnCancel = !onCancel;
  const shouldUseVerticalButtons = Boolean(onBackButtonClick);

  useHistoryBack({
    isActive,
    onBack: onCancel ?? onClose,
  });

  // Use functional state update to avoid stale closures on rapid toggles
  const handleAccountToggle = useLastCallback((index: number) => {
    setSelectedAccountIndices((prev) => (
      prev.includes(index)
        ? prev.filter((id) => id !== index)
        : prev.concat([index])
    ));
  });

  const handleAddLedgerWallets = useLastCallback(() => {
    afterSelectHardwareWallets({ hardwareSelectedIndices: selectedAccountIndices });
    onClose();
  });

  const alreadyConnectedList = useMemo(
    () => new Set(
      Object.values(accounts ?? [])
        .map((account) => account.byChain[chain]?.address)
        .filter(Boolean),
    ),
    [accounts, chain],
  );

  function renderAddAccount() {
    return (
      <Button
        className={styles.addAccountContainer}
        onClick={!isLoading ? loadMoreHardwareWallets : undefined}
      >
        {lang('Show More')}
        <Transition
          name="fade"
          activeKey={isLoading ? 1 : 0}
          slideClassName={styles.addAccountIconTransition}
        >
          {isLoading ? (
            <LoadingDots isActive className={styles.addAccountLoading} />
          ) : (
            <i className={buildClassName(styles.addAccountIcon, 'icon-plus')} aria-hidden />
          )}
        </Transition>
      </Button>
    );
  }

  function renderAccount(address: string, balance: bigint, index: number, isConnected: boolean) {
    const isSelected = selectedAccountIndices.includes(index);
    const balanceNumber = toDecimal(balance, balanceToken.decimals);

    return (
      <div
        key={address}
        className={buildClassName(
          styles.account,
          isConnected && styles.account_connected,
          isSelected && styles.account_current,
        )}
        onClick={isConnected ? undefined : () => handleAccountToggle(index)}
      >
        <span className={styles.accountName}>
          {balanceTokenFontIcon ? (
            <>
              <i
                className={buildClassName(styles.accountCurrencyIcon, balanceTokenFontIcon)}
                aria-label={balanceToken.symbol}
              />
              {formatCurrency(balanceNumber, '', ACCOUNT_BALANCE_DECIMALS)}
            </>
          ) : (
            formatCurrency(balanceNumber, balanceToken.symbol, ACCOUNT_BALANCE_DECIMALS)
          )}
        </span>
        <div className={styles.accountFooter}>
          <span className={styles.accountAddress}>
            {shortenAddress(address, ACCOUNT_ADDRESS_SHIFT, ACCOUNT_ADDRESS_SHIFT)}
          </span>
        </div>

        <div
          className={buildClassName(
            styles.accountCheckMark,
            (isConnected || isSelected) && styles.accountCheckMark_active,
          )}
        />
      </div>
    );
  }

  function renderAccounts() {
    const fullClassName = buildClassName(
      styles.accounts,
      (renderedWallets || []).length === 1 && styles.accounts_two,
      'custom-scroll',
    );

    return (
      <div className={fullClassName} style={vtnStyle}>
        {(renderedWallets || []).map(
          ({ wallet: { index, address }, balance }) => renderAccount(
            address,
            balance,
            index,
            alreadyConnectedList.has(address),
          ),
        )}
        {renderAddAccount()}
      </div>
    );
  }

  const title = selectedAccountIndices.length
    ? lang('%1$d Selected', selectedAccountIndices.length) as string
    : lang('Select Ledger Wallets');

  return (
    <>
      {!isStatic ? (
        <ModalHeader
          title={title}
          onBackButtonClick={onBackButtonClick}
          onClose={!onBackButtonClick || withCloseButton ? onClose : undefined}
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
        <div className={buildClassName(
          styles.actionBlock,
          shouldUseVerticalButtons ? styles.actionBlockVertical : styles.actionBlockHorizontal,
          isStatic && styles.actionBlockStatic,
        )}
        >
          <Button
            isPrimary
            isDisabled={selectedAccountIndices.length === 0}
            onClick={handleAddLedgerWallets}
            className={buildClassName(styles.button, styles.buttonFullWidth)}
          >
            {lang('Add')}
          </Button>
          <Button
            className={buildClassName(styles.button, shouldUseVerticalButtons && styles.buttonFullWidth)}
            onClick={shouldCloseOnCancel ? onClose : onCancel}
          >
            {lang(shouldCloseOnCancel ? 'Cancel' : 'Back')}
          </Button>
        </div>
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { chain, hardwareWallets, isLoading } = global.hardware;
  const accounts = selectNetworkAccounts(global);

  return {
    chain,
    hardwareWallets,
    accounts,
    isLoading,
  };
})(LedgerSelectWallets));
