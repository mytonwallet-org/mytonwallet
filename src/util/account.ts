import type { AccountIdParsed, ApiNetwork } from '../api/types';
import type { Account } from '../global/types';

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
