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

  const otherAccountId = accounts && findOtherAccountId({ address, chain, currentAccountId, accounts });

  return otherAccountId
    ? accounts[otherAccountId].title
    : savedAddresses && findSavedAddressName({ address, chain, savedAddresses });
}

export function findOtherAccountId({
  address, chain, currentAccountId, accounts,
}: {
  address: string;
  chain: ApiChain;
  currentAccountId: string;
  accounts: Record<string, Account>;
}) {
  return Object.keys(accounts).find((accountId) => {
    return accountId !== currentAccountId && accounts[accountId].byChain[chain]?.address === address;
  });
}

export function findSavedAddressName({
  address, chain, savedAddresses,
}: {
  address: string;
  chain: ApiChain;
  savedAddresses: SavedAddress[];
}) {
  return savedAddresses.find((item) => item.address === address && item.chain === chain)?.name;
}
