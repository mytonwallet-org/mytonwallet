import React, { memo, useMemo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { Account, AccountChain, SavedAddress } from '../../global/types';

import { TONCOIN } from '../../config';
import { selectCurrentAccountState, selectIsMultichainAccount, selectNetworkAccounts } from '../../global/selectors';
import { shortenAddress } from '../../util/shortenAddress';

import useLang from '../../hooks/useLang';

import AddressBookItem from './AddressBookItem';
import Menu from './Menu';

import styles from '../transfer/Transfer.module.scss';

interface OwnProps {
  isOpen: boolean;
  currentChain?: ApiChain;
  currentAddress?: string;
  otherAccountIds?: string[];
  onClose: NoneToVoidFunction;
  onAddressSelect: (address: string) => void;
  onSavedAddressDelete: (address: string) => void;
}

interface StateProps {
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
  isMultichainAccount?: boolean;
}

function AddressBook({
  isOpen, currentChain, currentAddress = '', otherAccountIds,
  accounts, savedAddresses, isMultichainAccount,
  onAddressSelect, onSavedAddressDelete, onClose,
}: OwnProps & StateProps) {
  const lang = useLang();

  const renderedSavedAddresses = useMemo(() => {
    if (!savedAddresses || savedAddresses.length === 0) {
      return undefined;
    }

    return savedAddresses
      .filter((item) => {
        return (!currentChain || item.chain === currentChain) && doesSavedAddressFitSearch(item, currentAddress);
      })
      .map((item) => (
        <AddressBookItem
          key={`saved-${item.address}-${item.chain}`}
          address={item.address}
          name={item.name}
          chain={isMultichainAccount ? item.chain : undefined}
          deleteLabel={lang('Delete')}
          isSavedAddress
          onClick={onAddressSelect}
          onDeleteClick={onSavedAddressDelete}
        />
      ));
  }, [currentAddress, isMultichainAccount, currentChain, lang, onAddressSelect, onSavedAddressDelete, savedAddresses]);

  const renderedOtherAccounts = useMemo(() => {
    if (!otherAccountIds || otherAccountIds.length === 0) return undefined;

    const addressesToBeIgnored = savedAddresses?.map((item) => `${item.chain}:${item.address}`) ?? [];
    const uniqueAddresses = new Set<string>();
    const otherAccounts = otherAccountIds
      .reduce((acc, accountId) => {
        const account = accounts![accountId];

        (Object.entries(account.byChain) as [ApiChain, AccountChain][]).forEach(([chain, { address }]) => {
          const key = `${chain}:${address}`;
          if (
            address
            && !uniqueAddresses.has(key)
            && (!currentChain || chain === currentChain)
            && (isMultichainAccount || chain === TONCOIN.chain)
            && !addressesToBeIgnored.includes(`${chain}:${address}`)
          ) {
            uniqueAddresses.add(key);
            acc.push({
              name: account.title || shortenAddress(address)!,
              address,
              chain,
              isHardware: account.type === 'hardware',
            });
          }
        });

        return acc;
      }, [] as (SavedAddress & { isHardware?: boolean })[]);

    return otherAccounts.filter(
      (item) => doesSavedAddressFitSearch(item, currentAddress),
    ).map(({
      address, name, chain: addressChain, isHardware,
    }) => (
      <AddressBookItem
        key={`address-${address}-${addressChain}`}
        address={address}
        name={name}
        chain={isMultichainAccount ? addressChain : undefined}
        isHardware={isHardware}
        onClick={onAddressSelect}
      />
    ));
  }, [otherAccountIds, savedAddresses, accounts, currentChain, isMultichainAccount, currentAddress, onAddressSelect]);

  const shouldRender = Boolean(renderedOtherAccounts?.length || renderedSavedAddresses?.length);

  if (!shouldRender) {
    return undefined;
  }

  return (
    <Menu
      positionX="right"
      type="suggestion"
      noBackdrop
      bubbleClassName={styles.savedAddressBubble}
      isOpen={isOpen}
      onClose={onClose}
    >
      {renderedSavedAddresses}
      {renderedOtherAccounts}
    </Menu>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountState = selectCurrentAccountState(global);

  return {
    savedAddresses: accountState?.savedAddresses,
    isMultichainAccount: selectIsMultichainAccount(global, global.currentAccountId!),
    accounts: selectNetworkAccounts(global),
  };
})(AddressBook));

function doesSavedAddressFitSearch(savedAddress: SavedAddress, search: string) {
  const searchQuery = search.toLowerCase();
  const { address, name } = savedAddress;

  return (
    address.toLowerCase().startsWith(searchQuery)
    || address.toLowerCase().endsWith(searchQuery)
    || name.toLowerCase().split(/\s+/).some((part) => part.startsWith(searchQuery))
  );
}
