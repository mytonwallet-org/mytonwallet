import React, { memo, useEffect, useMemo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiTonWalletVersion } from '../../../../api/chains/ton/types';
import type { ApiBaseCurrency, ApiCurrencyRates } from '../../../../api/types';
import type { Account, AccountSettings, AccountType, UserToken } from '../../../../global/types';
import { type ApiStakingState } from '../../../../api/types';
import { SettingsState } from '../../../../global/types';

import { IS_CORE_WALLET } from '../../../../config';
import {
  selectAccountStakingStates,
  selectCurrentAccountTokens,
  selectNetworkAccounts,
} from '../../../../global/selectors';
import { getAccountTitle } from '../../../../util/account';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { getShortCurrencySymbol } from '../../../../util/formatNumber';
import { vibrate } from '../../../../util/haptics';
import trapFocus from '../../../../util/trapFocus';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useFlag from '../../../../hooks/useFlag';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useShowTransition from '../../../../hooks/useShowTransition';

import Button from '../../../ui/Button';
import Portal from '../../../ui/Portal';
import SensitiveData from '../../../ui/SensitiveData';
import Transition from '../../../ui/Transition';
import { calculateFullBalance } from '../Card/helpers/calculateFullBalance';
import AccountButton from './AccountButton';
import AccountRenameModal from './AccountRenameModal';

import styles from './AccountSelector.module.scss';

interface OwnProps {
  forceClose?: boolean;
  accountClassName?: string;
  accountSelectorClassName?: string;
  withAccountSelector?: boolean;
  withBalance?: boolean;
}

interface StateProps {
  currentAccountId: string;
  currentAccount?: Account;
  accounts?: Record<string, Account>;
  currentWalletVersion?: ApiTonWalletVersion;
  settingsByAccountId?: Record<string, AccountSettings>;
  tokens?: UserToken[];
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  stakingStates?: ApiStakingState[];
  isSensitiveDataHidden?: true;
}

const ACCOUNTS_AMOUNT_FOR_COMPACT_DIALOG = 2;

function AccountSelector({
  currentAccountId,
  currentAccount,
  forceClose,
  accountClassName,
  accountSelectorClassName,
  withAccountSelector,
  withBalance,
  tokens,
  baseCurrency,
  currencyRates,
  stakingStates,
  isSensitiveDataHidden,
  accounts,
  currentWalletVersion,
  settingsByAccountId,
}: OwnProps & StateProps) {
  const {
    switchAccount,
    openAddAccountModal,
    openSettingsWithState,
  } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const [isOpen, openAccountSelector, closeAccountSelector] = useFlag(false);
  const [isEdit, openEdit, closeEdit] = useFlag(false);
  const { shouldRender: shouldRenderDialog, ref: dialogContainerRef } = useShowTransition({
    isOpen,
    className: 'slow',
    withShouldRender: true,
  });

  // The API doesn't check the TON wallet version for BIP39 and Tron-only accounts,
  // therefore `currentWalletVersion !== 'W5'` can be incorrectly true in that cases.
  const isBip39Account = currentAccount?.type === 'mnemonic' && Boolean(currentAccount?.byChain.tron);
  const hasTonWallet = Boolean(currentAccount?.byChain.ton);
  const withAddW5Button = currentWalletVersion !== 'W5' && currentAccount?.type !== 'hardware'
    && hasTonWallet && !isBip39Account;

  const accountsAmount = useMemo(() => Object.keys(accounts || {}).length, [accounts]);

  const balanceValues = useMemo(() => {
    return tokens ? calculateFullBalance(tokens, stakingStates, currencyRates[baseCurrency]) : undefined;
  }, [tokens, stakingStates, currencyRates, baseCurrency]);
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const { primaryWholePart, primaryFractionPart } = balanceValues || {};

  useEffect(() => {
    if (isOpen && forceClose) closeAccountSelector();
  }, [forceClose, isOpen]);

  useEffect(
    () => (shouldRenderDialog ? captureEscKeyListener(closeAccountSelector) : undefined),
    [closeAccountSelector, isOpen, shouldRenderDialog],
  );
  useEffect(
    () => (shouldRenderDialog && dialogContainerRef.current ? trapFocus(dialogContainerRef.current) : undefined),
    [dialogContainerRef, shouldRenderDialog],
  );

  const handleOpenAccountSelector = () => {
    openAccountSelector();
  };

  const handleSwitchAccount = useLastCallback((accountId: string) => {
    void vibrate();
    closeAccountSelector();
    switchAccount({ accountId });
  });

  const handleAddWalletClick = useLastCallback(() => {
    void vibrate();
    closeAccountSelector();
    openAddAccountModal();
  });

  const handleAddV5WalletClick = useLastCallback(() => {
    void vibrate();
    closeAccountSelector();
    openSettingsWithState({ state: SettingsState.WalletVersion });
  });

  function renderButton(
    accountId: string,
    byChain: Account['byChain'],
    accountType: AccountType,
    title?: string,
  ) {
    const { cardBackgroundNft } = settingsByAccountId?.[accountId] || {};
    const isActive = accountId === currentAccountId;

    return (
      <AccountButton
        key={accountId}
        accountId={accountId}
        byChain={byChain}
        accountType={accountType}
        isActive={isActive}
        title={title}
        cardBackgroundNft={cardBackgroundNft}
        canEditAccount={!IS_CORE_WALLET}
        onClick={handleSwitchAccount}
        onEdit={openEdit}
      />
    );
  }

  const fullClassName = buildClassName(
    styles.container,
    accountSelectorClassName,
  );
  const accountTitleClassName = buildClassName(
    styles.accountTitle,
    withAccountSelector && !withBalance && styles.accountTitleInteractive,
    withBalance && styles.withBalance,
    accountClassName,
  );

  function renderCurrentAccount() {
    return (
      <Transition
        name="slideVerticalFade"
        activeKey={withBalance ? 1 : 0}
        className={styles.root}
        slideClassName={styles.slide}
      >
        {withBalance && (
          <div className={buildClassName(styles.balance, 'rounded-font')}>
            <SensitiveData
              isActive={isSensitiveDataHidden}
              shouldHoldSize
              align="center"
              cols={10}
              rows={2}
              cellSize={8.5}
            >
              <span
                className={styles.currencySwitcher}
              >
                {shortBaseSymbol.length === 1 && (
                  <span className={buildClassName(styles.balanceCurrency, styles.balanceCurrencyPrefix)}>
                    {shortBaseSymbol}
                  </span>
                )}
                {primaryWholePart}
                {primaryFractionPart && <span className={styles.balanceFractionPart}>.{primaryFractionPart}</span>}
                {shortBaseSymbol.length > 1 && (
                  <span className={styles.balanceCurrency}>&nbsp;{shortBaseSymbol}</span>
                )}
              </span>
            </SensitiveData>
          </div>
        )}
        <div className={accountTitleClassName} onClick={withAccountSelector ? handleOpenAccountSelector : undefined}>
          <span className={styles.accountTitleInner}>
            {(currentAccount && getAccountTitle(currentAccount)) ?? ''}
          </span>
          {withAccountSelector && !withBalance && (
            <i className={buildClassName('icon icon-caret-down', styles.arrowIcon)} aria-hidden />
          )}
        </div>
      </Transition>
    );
  }

  function renderAccountsSelector() {
    const dialogFullClassName = buildClassName(
      styles.dialog,
      accountsAmount <= ACCOUNTS_AMOUNT_FOR_COMPACT_DIALOG && styles.dialog_compact,
    );

    return (
      <div
        ref={dialogContainerRef}
        className={fullClassName}
        tabIndex={-1}
        role="dialog"
      >
        <div className={styles.backdrop} onClick={() => closeAccountSelector()} />
        <div className={dialogFullClassName}>
          {accounts && Object.entries(accounts).map(
            ([accountId, { title, byChain, type }]) => {
              return renderButton(accountId, byChain, type, title);
            },
          )}
          {withAddW5Button && (
            <Button className={styles.createAccountButton} onClick={handleAddV5WalletClick}>
              {lang('Switch to W5')}
              <i className={buildClassName(styles.createAccountIcon, 'icon-versions')} aria-hidden />
            </Button>
          )}
          <Button className={styles.createAccountButton} onClick={handleAddWalletClick}>
            {lang('Add Wallet')}
            <i className={buildClassName(styles.createAccountIcon, 'icon-plus')} aria-hidden />
          </Button>
        </div>
      </div>
    );
  }

  return (
    <>
      {renderCurrentAccount()}

      {shouldRenderDialog && (isPortrait
        ? <Portal>{renderAccountsSelector()}</Portal>
        : renderAccountsSelector()
      )}

      <AccountRenameModal
        isOpen={isEdit}
        currentAccountId={currentAccountId}
        name={currentAccount?.title ?? ''}
        onClose={closeEdit}
      />
    </>
  );
}

export default memo(withGlobal<OwnProps>(
  (global): StateProps => {
    const {
      walletVersions,
      currencyRates,
      settings: {
        byAccountId: settingsByAccountId,
        baseCurrency,
        isSensitiveDataHidden,
      },
    } = global;

    const accounts = selectNetworkAccounts(global);
    const currentAccountId = global.currentAccountId!;
    const currentAccount = accounts?.[currentAccountId];

    const stakingStates = selectAccountStakingStates(global, currentAccountId);

    return {
      currentAccountId,
      currentAccount,
      accounts,
      currentWalletVersion: walletVersions?.currentVersion,
      settingsByAccountId,
      tokens: selectCurrentAccountTokens(global),
      baseCurrency,
      currencyRates,
      stakingStates,
      isSensitiveDataHidden,
    };
  },
  (global, _, stickToFirst) => stickToFirst(global.currentAccountId),
)(AccountSelector));
