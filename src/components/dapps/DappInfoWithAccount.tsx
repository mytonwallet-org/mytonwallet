import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiDapp } from '../../api/types';
import type { Account } from '../../global/types';

import { TONCOIN } from '../../config';
import {
  selectCurrentAccountId,
  selectCurrentToncoinBalance,
  selectNetworkAccounts,
} from '../../global/selectors';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';

import DappInfo from './DappInfo';

import styles from './Dapp.module.scss';

interface OwnProps {
  dapp?: ApiDapp;
  customTokenBalance?: bigint;
  customTokenSymbol?: string;
  customTokenDecimals?: number;
}

interface StateProps {
  toncoinBalance: bigint;
  currentAccountId: string;
  accounts?: Record<string, Account>;
}

function DappInfoWithAccount({
  dapp,
  toncoinBalance,
  currentAccountId,
  accounts,
  customTokenBalance,
  customTokenSymbol,
  customTokenDecimals,
}: OwnProps & StateProps) {
  // Use custom token display if provided, otherwise use TON balance
  const displayBalance = customTokenBalance !== undefined ? customTokenBalance : toncoinBalance;
  const displaySymbol = customTokenSymbol || TONCOIN.symbol;
  const displayDecimals = customTokenDecimals !== undefined ? customTokenDecimals : TONCOIN.decimals;

  return (
    <div className={styles.transactionDirection}>
      <div className={styles.transactionAccount}>
        <div className={styles.accountTitle}>{accounts?.[currentAccountId]?.title}</div>
        <div className={styles.accountBalance}>
          {formatCurrency(toDecimal(displayBalance, displayDecimals), displaySymbol)}
        </div>
      </div>

      <DappInfo
        variant="transfer"
        dapp={dapp}
      />
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accounts = selectNetworkAccounts(global);

  return {
    toncoinBalance: selectCurrentToncoinBalance(global),
    currentAccountId: selectCurrentAccountId(global)!,
    accounts,
  };
})(DappInfoWithAccount));
