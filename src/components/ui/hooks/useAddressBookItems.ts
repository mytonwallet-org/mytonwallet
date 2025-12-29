import { useMemo } from '../../../lib/teact/teact';

import type { ApiChain } from '../../../api/types';
import type { Account, AddressBookItemData, SavedAddress } from '../../../global/types';

import { getOrderedAccountChains } from '../../../util/chain';
import { isKeyCountGreater } from '../../../util/isEmptyObject';
import { shortenAddress } from '../../../util/shortenAddress';
import { doesSavedAddressFitSearch } from '../helpers/doesSavedAddressFitSearch';

interface OwnProps {
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
  supportedChains?: Partial<Record<ApiChain, unknown>>;
  otherAccountIds: string[];
  currentChain?: ApiChain;
  searchValue: string;
  orderedAccountIds?: string[];
}

export default function useAddressBookItems({
  savedAddresses,
  accounts,
  supportedChains,
  otherAccountIds,
  currentChain,
  searchValue,
  orderedAccountIds,
}: OwnProps): AddressBookItemData[] {
  const isMultichainAccount = isKeyCountGreater(supportedChains ?? {}, 1);

  return useMemo(() => {
    const items: AddressBookItemData[] = [];

    // Add filtered saved addresses
    if (savedAddresses) {
      savedAddresses
        .filter((item) => {
          return (!currentChain || item.chain === currentChain)
            && doesSavedAddressFitSearch(item, searchValue);
        })
        .forEach((item) => {
          items.push({
            address: item.address,
            name: item.name,
            chain: isMultichainAccount ? item.chain : undefined,
            isSavedAddress: true,
          });
        });
    }

    // Add other accounts with unique addresses
    if (otherAccountIds.length > 0 && accounts && supportedChains) {
      const uniqueAddresses = new Set<string>(
        savedAddresses?.map((item) => `${item.chain}:${item.address}`) ?? [],
      );

      // Sort account IDs according to orderedAccountIds
      const sortedAccountIds = orderedAccountIds?.length
        ? [
          ...orderedAccountIds.filter((id) => otherAccountIds.includes(id)),
          ...otherAccountIds.filter((id) => !orderedAccountIds.includes(id)),
        ]
        : otherAccountIds;

      sortedAccountIds.forEach((accountId) => {
        const account = accounts[accountId];
        if (!account) return;

        getOrderedAccountChains(account.byChain).forEach((accountChain) => {
          const { address, domain } = account.byChain[accountChain]!;
          const key = `${accountChain}:${address}`;

          if (
            address
            && !uniqueAddresses.has(key)
            && (!currentChain || accountChain === currentChain)
            && accountChain in supportedChains
            && doesSavedAddressFitSearch({ address, name: account.title || '' }, searchValue)
          ) {
            uniqueAddresses.add(key);
            items.push({
              address,
              name: account.title || shortenAddress(address)!,
              chain: isMultichainAccount ? accountChain : undefined,
              domain,
              isHardware: account.type === 'hardware',
              isSavedAddress: false,
            });
          }
        });
      });
    }

    return items;
  }, [
    savedAddresses, otherAccountIds, accounts, supportedChains,
    currentChain, searchValue, isMultichainAccount, orderedAccountIds,
  ]);
}
