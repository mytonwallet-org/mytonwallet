import type { ElementRef } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { AddressBookItemData } from '../../global/types';

import AddressBookItem from './AddressBookItem';
import Menu from './Menu';

import styles from '../transfer/Transfer.module.scss';

interface OwnProps {
  isOpen: boolean;
  items: AddressBookItemData[];
  activeIndex?: number;
  menuRef?: ElementRef<HTMLDivElement>;
  onClose: NoneToVoidFunction;
  onAddressSelect: (address: string) => void;
  onSavedAddressDelete: (address: string) => void;
}

function AddressBook({
  isOpen, items, activeIndex, menuRef,
  onAddressSelect, onSavedAddressDelete, onClose,
}: OwnProps) {
  const shouldRender = items.length > 0;

  if (!shouldRender) return undefined;

  return (
    <Menu
      positionX="right"
      type="suggestion"
      role="listbox"
      noBackdrop
      bubbleClassName={styles.savedAddressBubble}
      menuRef={menuRef}
      isOpen={isOpen}
      onClose={onClose}
    >
      {items.map((item, index) => (
        <AddressBookItem
          key={`${item.isSavedAddress ? 'saved' : 'address'}-${item.address}-${item.chain || ''}`}
          item={item}
          isSelected={activeIndex === index}
          onClick={onAddressSelect}
          onDeleteClick={item.isSavedAddress ? onSavedAddressDelete : undefined}
        />
      ))}
    </Menu>
  );
}

export default memo(AddressBook);
