import React, { memo, useEffect, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type {
  WcPayFiatAmount,
  WcPayMerchant,
  WcPayPaymentInfo,
  WcPayPaymentOption,
} from '../../api/dappProtocols/adapters/walletConnect/types';
import type {
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiNetwork,
  ApiStakingState,
  ApiTokenWithPrice,
} from '../../api/types';
import type { Account, AccountSettings, GlobalState } from '../../global/types';

import { Big } from '../../lib/big.js';
import {
  selectCurrentAccountId,
  selectCurrentNetwork,
  selectOrderedAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { toDecimal } from '../../util/decimals';
import { formatCurrency, formatNumber, getShortCurrencySymbol } from '../../util/formatNumber';
import { isKeyCountGreater } from '../../util/isEmptyObject';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { doesAccountSupportWalletConnectPay } from '../../util/walletConnectPay';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import { useMultipleAccountsBalances } from '../../hooks/useMultipleAccountsBalances';

import AccountRowContent from '../common/AccountRowContent';
import TokenIcon from '../common/TokenIcon';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import Spinner from '../ui/Spinner';
import Transition from '../ui/Transition';
import WalletConnectPayAccountPill from './WalletConnectPayAccountPill';
import WalletConnectPayAmount from './WalletConnectPayAmount';
import WalletConnectPayHeader from './WalletConnectPayHeader';
import WalletConnectPayMerchantLogo from './WalletConnectPayMerchantLogo';

import modalStyles from '../ui/Modal.module.scss';
import styles from './WalletConnectPay.module.scss';

enum OptionSelectionState {
  Options = 0,
  SelectAccount = 1,
  NoOptions = 2,
}

interface StateProps {
  promiseId?: string;
  accountId?: string;
  merchant?: WcPayMerchant;
  paymentInfo?: WcPayPaymentInfo;
  options?: WcPayPaymentOption[];
  isLoading?: boolean;
  shouldSwitchWallet?: boolean;
  currentAccountId: string;
  orderedAccounts?: Array<[string, Account]>;
  accounts?: Record<string, Account>;
  settingsByAccountId?: Record<string, AccountSettings>;
  baseCurrency?: ApiBaseCurrency;
  currencyRates?: ApiCurrencyRates;
  byAccountId?: GlobalState['byAccountId'];
  tokenInfo?: GlobalState['tokenInfo'];
  stakingDefault?: ApiStakingState;
  areTokensWithNoCostHidden?: boolean;
  network?: ApiNetwork;
}

function WalletConnectPayOptionSelectionModal({
  promiseId,
  accountId,
  merchant,
  paymentInfo,
  options,
  isLoading,
  shouldSwitchWallet,
  currentAccountId,
  orderedAccounts,
  accounts,
  settingsByAccountId,
  baseCurrency,
  currencyRates,
  byAccountId,
  tokenInfo,
  stakingDefault,
  areTokensWithNoCostHidden,
  network,
}: StateProps) {
  const {
    closeWalletConnectPayOptionSelection,
    confirmWalletConnectPayOptionSelection,
    switchWalletConnectPayOptionSelectionAccount,
  } = getActions();
  const lang = useLang();
  const [state, setState] = useState<OptionSelectionState>(OptionSelectionState.Options);
  const [isConfirmingOptionSelection, setIsConfirmingOptionSelection] = useState(false);
  const isOpen = Boolean(promiseId);
  const hasOptions = Boolean(options?.length);
  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const selectedAccountId = accountId || currentAccountId;
  const shouldRenderAccountSelector = accounts && isKeyCountGreater(accounts, 1);

  // Per-account balances are only shown in the account selector slide, so skip the "Slow"
  // selectors entirely when it can't appear (single account or closed modal)
  const needsAccountBalances = isOpen && Boolean(shouldRenderAccountSelector);

  const { balancesByAccountId } = useMultipleAccountsBalances({
    filteredAccounts: needsAccountBalances ? orderedAccounts : undefined,
    sourceAccounts: needsAccountBalances ? accounts : undefined,
    byAccountId: needsAccountBalances ? byAccountId : undefined,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
    stakingDefault,
  });

  useEffect(() => {
    if (!isOpen) {
      setState(OptionSelectionState.Options);
      setIsConfirmingOptionSelection(false);
      return;
    }

    if (isLoading || state === OptionSelectionState.SelectAccount) {
      return;
    }

    if (!hasOptions) {
      if (state !== OptionSelectionState.NoOptions) {
        setState(OptionSelectionState.NoOptions);
        updateNextKey();
      }
    } else if (state === OptionSelectionState.NoOptions) {
      setState(OptionSelectionState.Options);
      updateNextKey();
    }
  }, [isOpen, isLoading, hasOptions, state, updateNextKey]);

  const handleOptionClick = useLastCallback((optionId: string) => {
    setIsConfirmingOptionSelection(true);
    confirmWalletConnectPayOptionSelection({ optionId });
  });

  const handleOpenAccountSelector = useLastCallback(() => {
    setState(OptionSelectionState.SelectAccount);
  });

  const handleAccountSelectorBack = useLastCallback(() => {
    setState(hasOptions ? OptionSelectionState.Options : OptionSelectionState.NoOptions);
  });

  const handleSelectAccount = useLastCallback((nextAccountId: string) => {
    setState(OptionSelectionState.Options);

    if (nextAccountId !== selectedAccountId) {
      switchWalletConnectPayOptionSelectionAccount({ accountId: nextAccountId });
    }
  });

  function renderAccountSelector() {
    const account = accounts?.[selectedAccountId];
    if (!account || !shouldRenderAccountSelector) {
      return undefined;
    }

    return (
      <WalletConnectPayAccountPill
        accountId={selectedAccountId}
        title={account.title}
        onClick={!isConfirmingOptionSelection ? handleOpenAccountSelector : undefined}
      />
    );
  }

  function renderSelectAccountSlide() {
    return (
      <>
        <ModalHeader
          title={lang('Choose Wallet')}
          onBackButtonClick={handleAccountSelectorBack}
          onClose={closeWalletConnectPayOptionSelection}
        />
        <div className={modalStyles.transitionContent}>
          <span className={buildClassName(styles.accountSelectorTitle, styles.accountSelectorTitle_2)}>
            {lang('Wallet to use for payment')}
          </span>
          <div className={styles.accountList}>
            {(orderedAccounts ?? []).map(([nextAccountId, account]) => {
              const { title, byChain, type } = account;
              const isDisabled = !network || !doesAccountSupportWalletConnectPay(account, network);
              const isSelected = nextAccountId === selectedAccountId;
              const { cardBackgroundNft } = settingsByAccountId?.[nextAccountId] || {};
              const balanceData = balancesByAccountId?.[nextAccountId];

              return (
                <AccountRowContent
                  key={nextAccountId}
                  accountId={nextAccountId}
                  byChain={byChain}
                  accountType={type}
                  title={title}
                  cardBackgroundNft={cardBackgroundNft}
                  balanceData={balanceData}
                  isSelected={isSelected}
                  isDisabled={isDisabled}
                  className={styles.accountListItem}
                  onClick={handleSelectAccount}
                />
              );
            })}
          </div>
        </div>
      </>
    );
  }

  function renderOption(option: WcPayPaymentOption) {
    const { display, slug } = option;
    const token = slug ? tokenInfo?.bySlug[slug] : undefined;
    const balance = slug
      ? (byAccountId?.[selectedAccountId]?.balances?.bySlug[slug] ?? 0n)
      : 0n;
    const fiatFormatted = formatWcPayFiat(paymentInfo?.amount?.fiatAmount, baseCurrency, currencyRates);

    return (
      <button
        key={option.id}
        type="button"
        className={styles.optionRow}
        disabled={isConfirmingOptionSelection}
        onClick={() => handleOptionClick(option.id)}
      >
        <div className={styles.optionMain}>
          {token ? (
            <TokenIcon
              token={token}
              withChainIcon
              className={styles.optionTokenIcon}
            />
          ) : (
            <i
              className={buildClassName(styles.optionTokenIcon, styles.optionTokenIcon_fallback, 'icon-ton')}
              aria-hidden
            />
          )}
          <div className={styles.optionText}>
            <div className={styles.optionSymbol}>{display.assetName}</div>
            {slug && (
              <div className={styles.optionNetwork}>
                {lang('$available_balance', { balance: formatPayOptionWalletBalance(option, balance, token) })}
              </div>
            )}
          </div>
        </div>
        <div className={styles.optionAmountGroup}>
          <div className={styles.optionAmount}>{formatPayOptionAmount(option)}</div>
          {fiatFormatted && (
            <div className={styles.optionBalance}>≈{fiatFormatted}</div>
          )}
        </div>
      </button>
    );
  }

  function renderPaymentSummary() {
    const paymentAmount = paymentInfo?.amount;

    if (!paymentAmount) {
      return undefined;
    }

    try {
      const { fiatAmount } = paymentAmount;

      if (fiatAmount) {
        const value = toDecimal(BigInt(fiatAmount.value), fiatAmount.decimals);

        return (
          <WalletConnectPayAmount
            value={value}
            decimals={fiatAmount.decimals}
            prefix={getShortCurrencySymbol(fiatAmount.slug)}
            baseCurrencyValue={formatInBaseCurrency(value, fiatAmount.slug, baseCurrency, currencyRates)}
          />
        );
      }

      const value = toDecimal(BigInt(paymentAmount.value), paymentAmount.display.decimals);

      return (
        <WalletConnectPayAmount
          value={value}
          decimals={paymentAmount.display.decimals}
          suffix={paymentAmount.display.assetSymbol}
        />
      );
    } catch {
      return undefined;
    }
  }

  function renderOptionsContent() {
    if (isLoading) {
      return (
        <div className={styles.optionSelectionLoading}>
          <Spinner />
        </div>
      );
    }

    if (!hasOptions) {
      return undefined;
    }

    return (
      <>
        <p className={styles.label}>{lang('Choose Token')}</p>
        <div className={styles.optionList}>
          {options?.map(renderOption)}
        </div>
      </>
    );
  }

  function renderNoOptionsSlide(isActive: boolean) {
    if (!isActive) {
      return undefined;
    }

    return (
      <div className={buildClassName(
        modalStyles.transitionContent,
        styles.skeletonBackground,
        styles.optionSelectionContent,
        'custom-scroll',
      )}
      >
        <WalletConnectPayHeader
          title={merchant?.name || lang('Payment')}
          onClose={closeWalletConnectPayOptionSelection}
        >
          {renderAccountSelector()}
        </WalletConnectPayHeader>

        <WalletConnectPayMerchantLogo merchant={merchant} />
        {renderPaymentSummary()}

        <div className={styles.optionSelectionEmpty}>
          <p className={styles.optionSelectionEmptyTitle}>
            {lang(shouldSwitchWallet ? 'Unsupported Chain' : 'You don\'t have any eligible tokens for this payment')}
          </p>
          <p className={styles.optionSelectionEmptyHint}>
            {lang(shouldSwitchWallet
              ? 'Please upgrade to multichain to use this app.'
              : 'Buy, swap, or receive a supported token to continue.')}
          </p>
        </div>
      </div>
    );
  }

  function renderOptionsSlide(isActive: boolean) {
    if (!isActive) {
      return undefined;
    }

    return (
      <div className={styles.optionSelectionSlide}>
        <div className={buildClassName(
          modalStyles.transitionContent,
          styles.skeletonBackground,
          styles.optionSelectionContent,
          'custom-scroll',
        )}
        >
          <WalletConnectPayHeader
            title={merchant?.name || lang('Payment')}
            onClose={closeWalletConnectPayOptionSelection}
          >
            {renderAccountSelector()}
          </WalletConnectPayHeader>

          <WalletConnectPayMerchantLogo merchant={merchant} />
          {renderPaymentSummary()}

          {renderOptionsContent()}
        </div>

        {isConfirmingOptionSelection && (
          <div className={styles.optionSelectionConfirmingOverlay}>
            <Spinner />
          </div>
        )}
      </div>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: OptionSelectionState) {
    switch (currentKey) {
      case OptionSelectionState.Options:
        return renderOptionsSlide(isActive);
      case OptionSelectionState.NoOptions:
        return renderNoOptionsSlide(isActive);
      case OptionSelectionState.SelectAccount:
        return isActive ? renderSelectAccountSlide() : undefined;
    }
  }

  if (!isOpen) {
    return undefined;
  }

  return (
    <Modal
      isOpen={isOpen}
      dialogClassName={buildClassName(styles.modalDialog, styles.optionSelectionModalDialog)}
      onClose={closeWalletConnectPayOptionSelection}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={nextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

function formatPayOptionAmount(option: WcPayPaymentOption): string {
  const { amountValue, display } = option;

  try {
    return formatCurrency(toDecimal(BigInt(amountValue), display.decimals), display.assetSymbol);
  } catch {
    return `${amountValue} ${display.assetSymbol}`;
  }
}

function formatPayOptionWalletBalance(
  option: WcPayPaymentOption,
  balance: bigint,
  token?: ApiTokenWithPrice,
): string {
  const decimals = token?.decimals ?? option.display.decimals;

  try {
    return formatNumber(toDecimal(balance, decimals));
  } catch {
    return balance.toString();
  }
}

function formatInBaseCurrency(
  value: string,
  slug: ApiBaseCurrency,
  baseCurrency?: ApiBaseCurrency,
  currencyRates?: ApiCurrencyRates,
): string | undefined {
  if (!baseCurrency || !currencyRates || slug === baseCurrency) {
    return undefined;
  }

  const amountInUsd = slug === 'USD'
    ? Number(value)
    : Big(value).div(currencyRates[slug]).toNumber();
  const valueInBaseCurrency = calculateTokenPrice(amountInUsd, baseCurrency, currencyRates);

  return formatCurrency(valueInBaseCurrency, getShortCurrencySymbol(baseCurrency));
}

function formatWcPayFiat(
  fiatAmount: WcPayFiatAmount | undefined,
  baseCurrency?: ApiBaseCurrency,
  currencyRates?: ApiCurrencyRates,
): string | undefined {
  if (!fiatAmount) {
    return undefined;
  }

  try {
    const value = toDecimal(BigInt(fiatAmount.value), fiatAmount.decimals);

    return formatInBaseCurrency(value, fiatAmount.slug, baseCurrency, currencyRates)
      ?? formatCurrency(value, getShortCurrencySymbol(fiatAmount.slug));
  } catch {
    return undefined;
  }
}

export default memo(withGlobal((global): StateProps => {
  const selection = global.walletConnectPayOptionSelection;
  const {
    settings: {
      byAccountId: settingsByAccountId,
      baseCurrency,
      areTokensWithNoCostHidden,
    },
    currencyRates,
    byAccountId,
    tokenInfo,
    stakingDefault,
  } = global;

  return {
    promiseId: selection?.promiseId,
    accountId: selection?.accountId,
    merchant: selection?.merchant,
    paymentInfo: selection?.paymentInfo,
    options: selection?.options,
    isLoading: selection?.isLoading,
    shouldSwitchWallet: selection?.shouldSwitchWallet,
    currentAccountId: selectCurrentAccountId(global)!,
    orderedAccounts: selectOrderedAccounts(global),
    accounts: global.accounts?.byId,
    settingsByAccountId,
    baseCurrency,
    currencyRates,
    byAccountId,
    tokenInfo,
    stakingDefault,
    areTokensWithNoCostHidden,
    network: selectCurrentNetwork(global),
  };
})(WalletConnectPayOptionSelectionModal));
