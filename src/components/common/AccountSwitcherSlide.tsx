import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type {
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiStakingState,
} from '../../api/types';
import type { Account, AccountSettings, GlobalState } from '../../global/types';

import { selectCurrentAccountId, selectOrderedAccounts } from '../../global/selectors';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { useMultipleAccountsBalances } from '../../hooks/useMultipleAccountsBalances';

import ModalHeader from '../ui/ModalHeader';
import AccountRowContent from './AccountRowContent';

import modalStyles from '../ui/Modal.module.scss';
import styles from './AccountSwitcherSlide.module.scss';

interface OwnProps {
  isActive?: boolean;
  // Defaults to the current account; pass it when the "selected" account differs (e.g. a payment account)
  selectedAccountId?: string;
  subtitle?: TeactNode;
  getIsAccountDisabled?: (account: Account, accountId: string) => boolean;
  onAccountSelect: (accountId: string) => void;
  onBack: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

interface StateProps {
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
}

function AccountSwitcherSlide({
  isActive,
  selectedAccountId,
  subtitle,
  getIsAccountDisabled,
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
  onAccountSelect,
  onBack,
  onClose,
}: OwnProps & StateProps) {
  const lang = useLang();

  const rootRef = useRef<HTMLDivElement>();

  // Prevents a visual content jump when returning to the previous slide within the `Transition` component
  useLayoutEffect(() => {
    if (!isActive) return undefined;

    const scrollContainerEl = rootRef.current?.closest<HTMLElement>('.custom-scroll');

    return () => {
      scrollContainerEl?.scrollTo({ top: 0, behavior: 'instant' });
    };
  }, [isActive]);

  const currentSelectedAccountId = selectedAccountId ?? currentAccountId;

  // The per-account balances rely on the "Slow" selectors, so skip them entirely while the slide is hidden
  const { balancesByAccountId, addressLineChainsByAccountId } = useMultipleAccountsBalances({
    filteredAccounts: isActive ? orderedAccounts : undefined,
    sourceAccounts: isActive ? accounts : undefined,
    byAccountId: isActive ? byAccountId : undefined,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
    stakingDefault,
  });

  const handleAccountClick = useLastCallback((accountId: string) => {
    if (accountId === currentSelectedAccountId) {
      onBack();
      return;
    }

    onAccountSelect(accountId);
  });

  return (
    <>
      <ModalHeader
        title={lang('Choose Wallet')}
        onBackButtonClick={onBack}
        onClose={onClose}
      />
      <div ref={rootRef} className={modalStyles.transitionContent}>
        {subtitle ? <span className={styles.subtitle}>{subtitle}</span> : undefined}
        <div className={styles.list}>
          {(orderedAccounts ?? []).map(([accountId, account]) => {
            const { title, byChain, type, isRecoveryRequired } = account;
            const { cardBackgroundNft } = settingsByAccountId?.[accountId] || {};

            return (
              <AccountRowContent
                key={accountId}
                accountId={accountId}
                byChain={byChain}
                visibleChains={addressLineChainsByAccountId?.[accountId]}
                accountType={type}
                title={title}
                isRecoveryRequired={isRecoveryRequired}
                cardBackgroundNft={cardBackgroundNft}
                balanceData={balancesByAccountId?.[accountId]}
                isSelected={accountId === currentSelectedAccountId}
                isDisabled={getIsAccountDisabled?.(account, accountId)}
                className={styles.listItem}
                onClick={handleAccountClick}
              />
            );
          })}
        </div>
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
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
  };
})(AccountSwitcherSlide));
