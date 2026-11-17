import React, { memo } from '../../../lib/teact/teact';

import type { ApiPerpsFundingSource } from '../../../api/types';
import type { DropdownItem } from '../../ui/Dropdown';

import { ARBITRUM_USDC_MAINNET } from '../../../config';
import { formatNumber } from '../../../util/formatNumber';

import useFlag from '../../../hooks/useFlag';

import TradeCounterRow from '../../swap/TradeCounterRow';
import DropdownMenu from '../../ui/DropdownMenu';

import styles from './UsdcRow.module.scss';

interface OwnProps {
  label: string;
  /** The USDC amount; without it, the row shows only the token */
  amount?: string;
  /** The amount is an estimate of the SDK, so it gets "≈" */
  isEstimated?: boolean;
  /** The direction of the payment is not known yet */
  isLabelMuted?: boolean;
  fundingSource?: ApiPerpsFundingSource;
  /** The sources the user can pay from. With them, the row opens a menu to choose one. */
  fundingItems?: DropdownItem<ApiPerpsFundingSource>[];
  onFundingSelect?: (fundingSource: ApiPerpsFundingSource) => void;
}

// The badge tells USDC on the Hyperliquid balance from USDC in the Arbitrum wallet
const HYPERLIQUID_USDC = { ...ARBITRUM_USDC_MAINNET, chain: 'hyperliquid' as const };

/** The USDC that a trade pays or returns: in the Arbitrum wallet, or on the Hyperliquid balance */
function UsdcRow({
  label, amount, isEstimated, isLabelMuted, fundingSource, fundingItems, onFundingSelect,
}: OwnProps) {
  const [isMenuOpen, openMenu, closeMenu] = useFlag();

  function renderRow(onClick?: NoneToVoidFunction) {
    return (
      <TradeCounterRow
        token={fundingSource === 'balance' ? HYPERLIQUID_USDC : ARBITRUM_USDC_MAINNET}
        label={label}
        amount={amount !== undefined ? `${isEstimated ? '≈ ' : ''}${formatNumber(amount)}` : undefined}
        symbol={ARBITRUM_USDC_MAINNET.symbol}
        isLabelMuted={isLabelMuted}
        hasCaret={Boolean(onClick)}
        onClick={onClick}
      />
    );
  }

  if (!fundingItems) return renderRow();

  return (
    <div className={styles.selectable}>
      {renderRow(openMenu)}
      <DropdownMenu
        isOpen={isMenuOpen}
        items={fundingItems}
        selectedValue={fundingSource ?? 'wallet'}
        menuPositionX="right"
        menuPositionY="bottom"
        onSelect={onFundingSelect}
        onClose={closeMenu}
      />
    </div>
  );
}

export default memo(UsdcRow);
