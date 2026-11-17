import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsMarketAsset, ApiPerpsQuote } from '../../../api/types';
import type { PerpsTradeState } from '../../../global/types';

import { isPerpsTradeDisabledBy, selectPerpsTradeBlockReason } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { getChainTitle } from '../../../util/chain';
import { vibrate } from '../../../util/haptics';
import {
  formatPerpsFeeEstimate,
  formatPerpsMoney,
  formatPerpsMoneyEstimate,
  formatPerpsUsdc,
  formatPerpsUsdcEstimate,
  getOperationTitle,
  getPerpsErrorText,
} from '../helpers/formatPerps';

import useFlag from '../../../hooks/useFlag';
import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import TradeNotice from '../../swap/TradeNotice';
import Button from '../../ui/Button';
import ModalFooter from '../../ui/ModalFooter';
import ModalHeader from '../../ui/ModalHeader';
import Spinner from '../../ui/Spinner';
import DetailRow from '../DetailRow';
import ErrorText from './ErrorText';
import FeeModal from './FeeModal';
import PositionSummary from './PositionSummary';
import RemainingCollateral from './RemainingCollateral';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface OwnProps {
  isActive: boolean;
  trade: PerpsTradeState;
  asset?: ApiPerpsMarketAsset;
}

interface StateProps {
  tradeBlockReason?: string;
}

function TradeReview({
  isActive, trade, asset, tradeBlockReason,
}: OwnProps & StateProps) {
  const { setPerpsTradeStep, cancelPerpsTrade, confirmPerpsTrade } = getActions();
  const lang = useLang();
  const [isFeeModalOpen, openFeeModal, closeFeeModal] = useFlag();

  const {
    kind, quote, isPreparing, reviewNotice, error, errorDetails,
  } = trade;
  const symbol = asset?.symbol ?? '';
  // A close starts on this screen, so it has nothing to go back to
  const isClose = kind === 'close';
  // A market that stops trading while the screen is open disables the button, so the screen names the reason
  const isBlocked = isPerpsTradeDisabledBy(tradeBlockReason);
  const shownError = error || (isBlocked ? tradeBlockReason : undefined);

  const handleBack = useLastCallback(() => {
    if (isClose) {
      cancelPerpsTrade();
    } else {
      setPerpsTradeStep({ step: 'form' });
    }
  });

  const handleConfirm = useLastCallback(() => {
    vibrate();
    confirmPerpsTrade();
  });

  useHistoryBack({ isActive, onBack: handleBack });

  // The released margin is known only after the reduce or the close settles, so "You Receive" shows the SDK estimate
  function renderPositionDetails(reviewed: ApiPerpsQuote) {
    const isReceiving = reviewed.kind === 'reduce';
    const hasPrevious = reviewed.kind !== 'open';

    return (
      <>
        <div className={styles.card}>
          <DetailRow
            label={lang('Position Size')}
            hint={lang(hasPrevious ? '$perps_position_size_change_hint' : '$perps_position_size_details_hint')}
            value={formatPerpsMoney(reviewed.notional)}
            prevValue={hasPrevious && reviewed.previousNotional !== undefined
              ? formatPerpsMoney(reviewed.previousNotional)
              : undefined}
          />
        </div>
        <div className={styles.card}>
          <DetailRow
            label={lang('$perps_asset_price', { asset: symbol })}
            value={formatPerpsMoney(reviewed.markPrice)}
          />
          {/* The previous price alone would read as the new one, so it shows only next to an estimate */}
          <DetailRow
            label={lang('Liquidation')}
            hint={lang('$perps_liquidation_price_hint')}
            value={formatPerpsMoneyEstimate(reviewed.estimatedLiquidationPrice)}
            prevValue={reviewed.liquidationPrice !== undefined && reviewed.estimatedLiquidationPrice !== undefined
              ? formatPerpsMoney(reviewed.liquidationPrice)
              : undefined}
          />
        </div>
        <div className={styles.card}>
          <DetailRow
            label={lang(isReceiving ? 'You Receive' : 'You Pay')}
            value={isReceiving ? formatPerpsUsdcEstimate(reviewed.estimatedReceiveAmount) : formatPayment(reviewed)}
          />
        </div>

        <TradeNotice message={lang('$perps_liquidation_acknowledgment')} />
      </>
    );
  }

  function renderCloseDetails(reviewed: ApiPerpsQuote) {
    return (
      <>
        <div className={styles.card}>
          <DetailRow
            label={lang('Invested')}
            hint={lang('$perps_invested_hint')}
            value={formatPerpsMoney(reviewed.previousCollateral)}
          />
          <DetailRow
            label={lang('Current Value')}
            hint={lang('$perps_current_value_hint')}
            value={formatPerpsMoney(reviewed.equity)}
          />
        </div>
        <div className={styles.card}>
          <DetailRow
            label={lang('$perps_price_when_opened', { asset: symbol })}
            value={formatPerpsMoney(reviewed.entryPrice)}
          />
          <DetailRow
            label={lang('$perps_price_now', { asset: symbol })}
            value={formatPerpsMoney(reviewed.markPrice)}
          />
        </div>
        <div className={styles.card}>
          <DetailRow
            label={lang('You Receive')}
            value={formatPerpsUsdcEstimate(reviewed.estimatedReceiveAmount)}
          />
        </div>
      </>
    );
  }

  function renderContent() {
    if (!quote || quote.kind === 'unchanged') {
      return (
        <div className={buildClassName(modalStyles.transitionContent, styles.progress)}>
          {error ? <ErrorText error={error} details={errorDetails} /> : <Spinner />}
        </div>
      );
    }

    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.content, styles.reviewContent)}>
        <div className={styles.reviewBody}>
          <PositionSummary quote={quote} asset={asset} className={styles.reviewSummary} />

          {quote.kind === 'close' ? renderCloseDetails(quote) : renderPositionDetails(quote)}

          {quote.estimatedRemainingCollateral && (
            <RemainingCollateral amount={quote.estimatedRemainingCollateral} isEstimated />
          )}

          {/* The notices inform and ask for nothing, as on iOS */}
          {quote.switchesToUnified && <p className={styles.cardNote}>{lang('PerpsSwitchesToUnifiedAccount')}</p>}
          {reviewNotice && <p className={styles.cardNote}>{getPerpsErrorText(lang, reviewNotice)}</p>}
          {shownError && <ErrorText error={shownError} details={error ? errorDetails : undefined} />}
        </div>

        <ModalFooter>
          <div className={buildClassName(styles.footer, styles.reviewFooter)}>
            <button type="button" className={styles.feeButton} onClick={openFeeModal}>
              {lang('$fee_value_with_colon', { fee: formatPerpsFeeEstimate(quote.estimatedFees?.total) })}
            </button>
            <Button
              isPrimary
              isLoading={isPreparing}
              isDisabled={isPreparing || Boolean(error) || isBlocked}
              className={modalStyles.buttonFullWidth}
              onClick={handleConfirm}
            >
              {lang('Confirm')}
            </Button>
          </div>
        </ModalFooter>

        <FeeModal isOpen={isFeeModalOpen} quote={quote} onClose={closeFeeModal} />
      </div>
    );
  }

  const title = quote && quote.kind !== 'unchanged'
    ? getOperationTitle(lang, quote.kind)
    : lang(isClose ? 'Close Position' : 'Review');

  return (
    <>
      <ModalHeader
        title={title}
        onBackButtonClick={isClose ? undefined : handleBack}
        onClose={cancelPerpsTrade}
      />
      {renderContent()}
    </>
  );
}

export default memo(withGlobal<OwnProps>((global, { trade }): StateProps => {
  const kind = trade.quote?.kind;

  return {
    tradeBlockReason: selectPerpsTradeBlockReason(global, trade.assetId, kind === 'unchanged' ? undefined : kind),
  };
})(TradeReview));

// A payment from the Hyperliquid balance names its source, since a payment from the wallet is the usual one
function formatPayment({ paymentAmount, funding }: ApiPerpsQuote) {
  const payment = formatPerpsUsdc(paymentAmount);

  return funding === 'balance' ? `${payment} · ${getChainTitle('hyperliquid')}` : payment;
}
