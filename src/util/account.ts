import type { AccountIdParsed, ApiNetwork } from '../api/types';
import type { Account, AccountType } from '../global/types';

import { APP_NAME } from '../config';
import { shortenAddress } from './shortenAddress';

export function parseAccountId(accountId: string): AccountIdParsed {
  const parts = accountId.split('-');
  const [id, network = 'mainnet'] = (parts.length === 3 ? [parts[0], parts[2]] : parts) as [string, ApiNetwork];
  return { id: Number(id), network };
}

export function buildAccountId(account: AccountIdParsed) {
  const { id, network } = account;
  return `${id}-${network}`;
}

export function getMainAccountAddress(byChain: Account['byChain']) {
  return (byChain.ton ?? Object.values(byChain).find(Boolean))?.address;
}

export function getAccountTitle(account: Account) {
  return account.title || shortenAddress(getMainAccountAddress(account.byChain) ?? '');
}

export function generateAccountTitle(params: {
  accounts: Record<string, Account>;
  accountType: AccountType;
  network: ApiNetwork;
  titlePostfix?: string;
}) {
  const { accounts, accountType, network, titlePostfix } = params;
  const accountAmount = Object.keys(accounts).length;
  const isMainnet = network === 'mainnet';

  // Handle first account special case
  if (accountAmount === 0) {
    return isMainnet ? APP_NAME : `Testnet ${APP_NAME}`;
  }

  // Count wallets by type
  const walletCounts = Object.values(accounts).reduce((acc, wallet) => {
    if (wallet.type === 'view') acc.view++;
    if (wallet.type === 'hardware') acc.hardware++;
    if (wallet.type === 'mnemonic') acc.mnemonic++;
    return acc;
  }, { view: 0, hardware: 0, mnemonic: 0 });

  const walletTypeConfig: Record<AccountType, { prefix: string; count: string | number }> = {
    view: { prefix: 'Wallet', count: walletCounts.view + 1 },
    hardware: { prefix: 'Ledger', count: `#${walletCounts.hardware + 1}` },
    mnemonic: { prefix: 'My Wallet', count: walletCounts.mnemonic + 1 },
  };

  const config = walletTypeConfig[accountType];
  const networkPrefix = isMainnet ? '' : 'Testnet ';
  const postfix = titlePostfix ? ` ${titlePostfix}` : '';

  return `${networkPrefix}${config.prefix} ${config.count}${postfix}`;
}
