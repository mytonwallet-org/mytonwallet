import type { MouseEvent } from 'react';
import React, { memo } from '../../lib/teact/teact';

import type { ApiChain } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { shortenAddress } from '../../util/shortenAddress';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';

import styles from '../transfer/Transfer.module.scss';

interface OwnProps {
  address: string;
  name?: string;
  chain?: ApiChain;
  isHardware?: boolean;
  isSavedAddress?: boolean;
  isSelected?: boolean;
  deleteLabel?: string;
  onClick: (address: string) => void;
  onDeleteClick?: (address: string) => void;
}

export const SUGGESTION_ITEM_CLASS_NAME = styles.savedAddressItem;

function AddressBookItem({
  address,
  name,
  chain,
  isHardware,
  isSavedAddress,
  isSelected,
  deleteLabel,
  onClick,
  onDeleteClick,
}: OwnProps) {
  const lang = useLang();

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
            {deleteLabel}
          </span>
        </span>
      )}
      {name && (
        <span className={styles.savedAddressAddress}>
          {chain && <i className={buildClassName(styles.chainIcon, `icon-chain-${chain}`)} aria-hidden />}
          {shortenAddress(address)}
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
