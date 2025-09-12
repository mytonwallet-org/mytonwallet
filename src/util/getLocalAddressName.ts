import type { ApiChain } from '../api/types';
import type { Account, SavedAddress } from '../global/types';

export function getLocalAddressName({
  address,
  chain,
  currentAccountId,
  accounts,
  savedAddresses,
}: {
  address?: string;
  chain: ApiChain;
  currentAccountId: string;
  accounts?: Record<string, Account>;
  savedAddresses?: SavedAddress[];
}) {
  if (!address) return undefined;

  const otherAccount = accounts
    ? Object.keys(accounts).find((accountId) => {
      return accountId !== currentAccountId && accounts[accountId].byChain[chain]?.address === address;
    })
    : undefined;

  if (otherAccount) {
    return accounts![otherAccount].title;
  }

  return savedAddresses?.find((item) => {
    return item.address === address && item.chain === chain;
  })?.name;
}
