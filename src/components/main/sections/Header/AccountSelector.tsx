import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../../../api/types';
import type { Account, UserToken } from '../../../../global/types';

import {
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountTokens,
  selectNetworkAccounts,
} from '../../../../global/selectors';
import { getAccountTitle } from '../../../../util/account';
import buildClassName from '../../../../util/buildClassName';
import { calculateFullBalance } from '../../../../util/calculateFullBalance';
import { getShortCurrencySymbol } from '../../../../util/formatNumber';

import useLang from '../../../../hooks/useLang';

import SensitiveData from '../../../ui/SensitiveData';
import Transition from '../../../ui/Transition';

import styles from './AccountSelector.module.scss';

interface OwnProps {
  withAccountSelector?: boolean;
  withBalance?: boolean;
}

interface StateProps {
  currentAccount?: Account;
  tokens?: UserToken[];
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  stakingStates?: ApiStakingState[];
  isSensitiveDataHidden?: true;
}

function AccountSelector({
  currentAccount,
  withAccountSelector,
  withBalance,
  tokens,
  baseCurrency,
  currencyRates,
  stakingStates,
  isSensitiveDataHidden,
}: OwnProps & StateProps) {
  const { openAccountSelector } = getActions();

  const lang = useLang();
  const balanceValues = useMemo(() => {
    return tokens ? calculateFullBalance(tokens, stakingStates, currencyRates[baseCurrency]) : undefined;
  }, [tokens, stakingStates, currencyRates, baseCurrency]);
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const { primaryWholePart, primaryFractionPart } = balanceValues || {};

  function handleOpenAccountSelector() {
    openAccountSelector();
  }

  const isAccountSwitchable = withAccountSelector && !withBalance;

  function renderAccountTitle(account: Account) {
    const title = <span className={styles.accountTitleInner}>{getAccountTitle(account)}</span>;

    if (!isAccountSwitchable) {
      return <div className={buildClassName(styles.accountTitle, withBalance && styles.withBalance)}>{title}</div>;
    }

    return (
      <button
        type="button"
        className={buildClassName(styles.accountTitle, styles.accountTitleInteractive)}
        title={lang('Switch Account')}
        aria-haspopup="dialog"
        onClick={handleOpenAccountSelector}
      >
        {title}
        <i className={buildClassName('icon icon-expand', styles.expandIcon)} aria-hidden />
      </button>
    );
  }

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
      {currentAccount && renderAccountTitle(currentAccount)}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>(
  (global): StateProps => {
    const {
      currencyRates,
      settings: {
        baseCurrency,
        isSensitiveDataHidden,
      },
    } = global;

    const accounts = selectNetworkAccounts(global);
    const currentAccountId = selectCurrentAccountId(global)!;
    const currentAccount = accounts?.[currentAccountId];
    const stakingStates = selectAccountStakingStates(global, currentAccountId);

    return {
      currentAccount,
      tokens: selectCurrentAccountTokens(global),
      baseCurrency,
      currencyRates,
      stakingStates,
      isSensitiveDataHidden,
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
)(AccountSelector));
