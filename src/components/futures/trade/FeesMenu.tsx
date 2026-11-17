import React, { memo } from '../../../lib/teact/teact';

import { MISSING_VALUE } from '../helpers/formatPerps';

import useLang from '../../../hooks/useLang';

import TradeHeaderMenu from '../../swap/TradeHeaderMenu';
import TradeMenuRow from '../../swap/TradeMenuRow';

import styles from './FeesMenu.module.scss';

interface OwnProps {
  bridgeFee?: string;
  tradingFee?: string;
  fundingRate: string;
  /** Absent for an order that deposits nothing, which pays no Arbitrum gas */
  networkFee?: string;
  isEdit?: boolean;
}

/** The info button of the trade form together with the fees menu it opens */
function FeesMenu({
  bridgeFee, tradingFee, fundingRate, networkFee, isEdit,
}: OwnProps) {
  const lang = useLang();

  function renderContent() {
    return (
      <>
        {bridgeFee !== undefined && (
          <TradeMenuRow
            title={lang('PerpsBridgeFee')}
            hint={lang('PerpsFeeEstimateHint')}
            value={bridgeFee}
            emptyValue={MISSING_VALUE}
          />
        )}
        {networkFee !== undefined && (
          <TradeMenuRow
            title={lang('Network Fee')}
            hint={lang('$perps_network_fee_hint')}
            value={networkFee}
            emptyValue={MISSING_VALUE}
          />
        )}
        <TradeMenuRow
          title={lang('Trading Fee')}
          hint={lang('$perps_trading_fee_hint')}
          value={tradingFee}
          emptyValue={MISSING_VALUE}
        />
        <TradeMenuRow
          title={lang('Funding Rate')}
          hint={lang('$perps_funding_rate_hint')}
          value={fundingRate}
          emptyValue={MISSING_VALUE}
        />
        <div className={styles.note}>
          {isEdit && <p className={styles.noteText}>{lang('$perps_edit_liquidation_hint')}</p>}
          <p className={styles.noteText}>{lang('$perps_position_size_hint')}</p>
        </div>
      </>
    );
  }

  return (
    <TradeHeaderMenu ariaLabel={lang('Details')} icon="icon-info">
      {renderContent}
    </TradeHeaderMenu>
  );
}

export default memo(FeesMenu);
