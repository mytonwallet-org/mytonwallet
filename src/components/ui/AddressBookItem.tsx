import type { MouseEvent } from 'react';
import React, { memo } from '../../lib/teact/teact';

import type { AddressBookItemData } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { shortenAddress } from '../../util/shortenAddress';
import { shortenDomain } from '../../util/shortenDomain';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';

import styles from '../transfer/Transfer.module.scss';

interface OwnProps {
  item: AddressBookItemData;
  isSelected?: boolean;
  onClick: (address: string) => void;
  onDeleteClick?: (address: string) => void;
}

const ACCOUNT_ADDRESS_SHIFT_START = 0;
const ACCOUNT_ADDRESS_SHIFT_END = 4;
export const SUGGESTION_ITEM_CLASS_NAME = styles.savedAddressItem;

function AddressBookItem({
  item,
  isSelected,
  onClick,
  onDeleteClick,
}: OwnProps) {
  const lang = useLang();
  const { address, name, chain, domain, isHardware, isSavedAddress } = item;
  const title = domain
    ? `${shortenDomain(domain)} · ${shortenAddress(
      address, ACCOUNT_ADDRESS_SHIFT_START, ACCOUNT_ADDRESS_SHIFT_END,
    )}`
    : shortenAddress(address);

  const handleClick = () => {
    onClick(address);
  };

  const handleDeleteClick = (e: MouseEvent) => {
    stopEvent(e);

    onDeleteClick!(address);
  };

  return (
    <div
      tabIndex={-1}
      role="option"
      aria-selected={isSelected}
      onMouseDown={IS_TOUCH_ENV ? undefined : handleClick}
      onClick={IS_TOUCH_ENV ? handleClick : undefined}
      className={styles.savedAddressItem}
    >
      <span className={styles.savedAddressName}>
        <span className={styles.savedAddressNameText}>
          {name || shortenAddress(address)}
        </span>
        {isHardware && <i className={buildClassName(styles.iconLedger, 'icon-ledger')} aria-hidden />}
      </span>
      {isSavedAddress && onDeleteClick && (
        <span className={styles.savedAddressDelete}>
          <span
            tabIndex={-1}
            role="button"
            className={styles.savedAddressDeleteInner}
            onMouseDown={handleDeleteClick}
          >
            {lang('Delete')}
          </span>
        </span>
      )}
      {name && (
        <span className={styles.savedAddressAddress}>
          {chain && <i className={buildClassName(styles.chainIcon, `icon-chain-${chain}`)} aria-hidden />}
          {title}
        </span>
      )}
      {isSavedAddress && onDeleteClick && (
        <span
          className={styles.savedAddressDeleteIcon}
          role="button"
          tabIndex={-1}
          onMouseDown={handleDeleteClick}
          onClick={stopEvent}
          aria-label={lang('Delete')}
        >
          <i className="icon-trash" aria-hidden />
        </span>
      )}
    </div>
  );
}

export default memo(AddressBookItem);
