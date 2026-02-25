import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type { ApiChain } from '../../api/types';
import type { Account } from '../../global/types';

import { DEFAULT_CHAIN } from '../../config';
import {
  selectCurrentAccountId,
  selectCurrentToncoinBalance,
  selectNetworkAccounts,
} from '../../global/selectors';
import { getChainConfig } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';

import DappInfo from './DappInfo';

import styles from './Dapp.module.scss';

interface OwnProps {
  chain?: ApiChain;
  dapp?: StoredDappConnection;
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
  chain,
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
  const displaySymbol = customTokenSymbol || getChainConfig(chain || DEFAULT_CHAIN).nativeToken.symbol;
  const displayDecimals = customTokenDecimals !== undefined
    ? customTokenDecimals
    : getChainConfig(chain || DEFAULT_CHAIN).nativeToken.decimals;

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
