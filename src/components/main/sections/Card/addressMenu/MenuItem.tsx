import React, { memo } from '../../../../../lib/teact/teact';

import type { ApiChain } from '../../../../../api/types';

import buildClassName from '../../../../../util/buildClassName';
import { shortenAddress } from '../../../../../util/shortenAddress';
import { shortenDomain } from '../../../../../util/shortenDomain';

import menuStyles from '../../../../ui/Dropdown.module.scss';
import styles from '../Card.module.scss';

export interface AddressMenuItem {
  chain: ApiChain;
  address: string;
  shortAddress: string;
  domain?: string;
  icon: string;
  title: string;
  label: string;
}

interface OwnProps {
  item: AddressMenuItem;
  withDelimiter?: boolean;
  onClick: (e: React.UIEvent<HTMLElement>, item: AddressMenuItem) => void;
  onMouseEnter?: (e: React.MouseEvent<HTMLElement>, item: AddressMenuItem) => void;
  onExplorerClick: (e: React.UIEvent<HTMLElement>, item: AddressMenuItem) => void;
}

const SUBTITLE_DOMAIN_MAX_LENGTH = 10;
const ADDRESS_TAIL_LENGTH = 6;

function MenuItem({
  item,
  withDelimiter,
  onClick,
  onMouseEnter,
  onExplorerClick,
}: OwnProps) {
  const hasDomain = Boolean(item.domain);

  return (
    <div
      role="button"
      tabIndex={0}
      className={buildClassName(menuStyles.item, styles.chainItem, withDelimiter && menuStyles.delimiter)}
      onClick={(e: React.MouseEvent<HTMLElement>) => { onClick(e, item); }}
      onKeyDown={(e: React.KeyboardEvent<HTMLElement>) => {
        if (e.code !== 'Enter' && e.code !== 'Space') return;
        // Space scrolls the page by default
        if (e.code === 'Space') e.preventDefault();
        onClick(e, item);
      }}
      onMouseEnter={onMouseEnter ? (e: React.MouseEvent<HTMLElement>) => { onMouseEnter(e, item); } : undefined}
    >
      <img src={item.icon} alt="" className={styles.chainItemLogo} />
      <div className={styles.chainItemContent}>
        <span className={styles.chainItemTitle}>{item.title}</span>
        <span className={styles.chainItemSubtitle}>
          {hasDomain
            ? `${shortenDomain(item.domain!, SUBTITLE_DOMAIN_MAX_LENGTH)} ${
              shortenAddress(item.address, 0, ADDRESS_TAIL_LENGTH)}`
            : item.shortAddress}
        </span>
      </div>
      <i
        className={buildClassName(
          hasDomain ? 'icon-chevron-right' : 'icon-copy',
          styles.itemActionIcon,
          hasDomain && styles.itemChevronIcon,
        )}
        aria-hidden
      />
      <i
        tabIndex={0}
        role="button"
        className={buildClassName('icon-explorer-small', styles.itemExplorerIcon)}
        aria-label={item.label}
        onClick={(e: React.MouseEvent<HTMLElement>) => { onExplorerClick(e, item); }}
        onKeyDown={(e: React.KeyboardEvent<HTMLElement>) => {
          if (e.code !== 'Enter' && e.code !== 'Space') return;
          // Space scrolls the page by default
          if (e.code === 'Space') e.preventDefault();
          onExplorerClick(e, item);
        }}
      />
    </div>
  );
}

export default memo(MenuItem);
