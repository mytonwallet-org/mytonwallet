import type { TeactNode } from '../../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../../lib/teact/teact';

import type { ApiPerpsMarketAsset, ApiPerpsPositionSide } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';
import type {
  PerpsReceiptData, PerpsReceiptEstimate, PerpsReceiptEvent, PerpsReceiptStatus,
} from '../helpers/perpsReceipt';

import { ARBITRUM_USDC_MAINNET } from '../../../config';
import { isPerpsNumber } from '../../../global/helpers/perps';
import { DAY, formatShortDay, formatTimeUnit, HOUR, MINUTE } from '../../../util/dateFormat';
import { animateHeightReveal, animateShift } from '../../../util/layoutChangeAnimation';
import { shareUrl } from '../../../util/share';
import { getPerpsExplorerTransactionUrl } from '../../../util/url';
import { buildPerpsToken } from '../helpers/buildPerpsSections';
import {
  formatPerpsMoney,
  formatPerpsMoneyEstimate,
  formatPerpsQuantity,
  formatPerpsSignedMoney,
  formatPerpsUsdc,
  formatPerpsUsdcEstimate,
  formatPositionLabel,
  getPerpsErrorText,
  getPerpsValueTone,
  getSideLabel,
  PERPS_CURRENCY_SYMBOL,
} from '../helpers/formatPerps';
import { buildPerpsFeeHint, buildPerpsFeeLines } from '../helpers/perpsFees';
import { getPerpsReceiptStatus, getPerpsReceiptSummary, isReceiptEstimate } from '../helpers/perpsReceipt';

import useHeightChange from '../../../hooks/useHeightChange';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';
import WarningMessage from '../../ui/WarningMessage';
import DetailRow from '../DetailRow';
import RemainingCollateral from './RemainingCollateral';
import TradeSummary from './TradeSummary';
import TransferId from './TransferId';

import resultStyles from '../../common/TransferResult.module.scss';
import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface OwnProps {
  data: PerpsReceiptData;
  /** Gives the compact receipt the market icon */
  asset?: ApiPerpsMarketAsset;
  isExpanded?: boolean;
  onDetailsClick?: NoneToVoidFunction;
  onStatusClick?: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

const TITLE_KEYS: Record<PerpsReceiptEvent, string> = {
  opened: 'Position Opened',
  increased: 'Position Increased',
  reduced: 'Position Reduced',
  closed: 'Position Closed',
  liquidated: 'Position Liquidated',
  leverage: 'Leverage',
};

function Receipt({
  data, asset, isExpanded, onDetailsClick, onStatusClick, onClose,
}: OwnProps) {
  const lang = useLang();

  const contentRef = useRef<HTMLDivElement>();
  const prevDialogRectRef = useRef<DOMRect>();

  const token = useMemo(() => asset && buildPerpsToken(asset), [asset]);

  const {
    event, symbol, side, leverage,
  } = data;
  const { status, messageKey, errorCode } = getPerpsReceiptStatus(data);
  const message = messageKey
    ? lang(messageKey)
    : errorCode !== undefined ? getPerpsErrorText(lang, errorCode) : undefined;
  const hasDetailsButton = Boolean(onDetailsClick && !isExpanded);
  const hasStatusButton = Boolean(message && onStatusClick);
  const title = getReceiptTitle(lang, data, status);
  const label = getPositionLabel(lang, symbol, side, leverage);
  const summary = getPerpsReceiptSummary(data, isExpanded);
  const isClosing = event === 'closed' || event === 'liquidated';

  const handleShareClick = useLastCallback(() => {
    void shareUrl(getPerpsExplorerTransactionUrl('hyperliquid', data.txHash!));
  });

  const handleDetailsClick = useLastCallback(() => {
    prevDialogRectRef.current = getDialog().getBoundingClientRect();
    onDetailsClick!();
  });

  // The dialog grows at once, so it starts at its old top with its new part clipped, and then opens up to its new
  // size. A bottom sheet keeps its bottom edge, and a centered modal grows in both directions.
  const handleContentHeightChange = useLastCallback(() => {
    const prevRect = prevDialogRectRef.current;
    if (!prevRect) return;

    prevDialogRectRef.current = undefined;

    const dialog = getDialog();
    const { top, height } = dialog.getBoundingClientRect();
    animateShift(dialog, 0, prevRect.top - top);
    animateHeightReveal(dialog, prevRect.height, height);
  });

  useHeightChange(contentRef, handleContentHeightChange);

  function getDialog() {
    return contentRef.current!.closest<HTMLElement>(`.${modalStyles.dialog}`)!;
  }

  function renderDate() {
    const date = formatShortDay(lang.code!, data.time, true);
    const held = data.openedAt !== undefined && isClosing
      ? lang('$perps_held', { duration: formatDuration(lang, data.time - data.openedAt) }) as string
      : undefined;

    return held ? `${date} · ${held}` : date;
  }

  function renderPrice() {
    if (data.entryPrice !== undefined || data.exitPrice !== undefined) {
      // A closed position shows its prices only as a known pair, as on iOS
      if (isClosing && (data.entryPrice === undefined || data.exitPrice === undefined)) return undefined;

      const key = event === 'liquidated' ? 'Entry / Liquidation Price' : 'Entry / Exit Price';

      return (
        <DetailRow
          label={lang(key)}
          value={`${formatPerpsMoney(data.entryPrice)} / ${formatReceiptMoney(data, 'price', data.exitPrice)}`}
        />
      );
    }

    return data.price !== undefined && (
      <DetailRow
        label={lang('$perps_asset_price', { asset: symbol })}
        value={formatReceiptMoney(data, 'price', data.price)}
      />
    );
  }

  function renderSize() {
    const size = data.sizeAfter ?? data.sizeBefore;
    // The amount at the top already shows the same change of the position size
    if (size === undefined || data.isAmountPositionSize) return undefined;

    const prevSize = data.sizeAfter !== undefined ? data.sizeBefore : undefined;
    const hint = prevSize !== undefined ? '$perps_position_size_change_hint' : '$perps_position_size_details_hint';

    return (
      <DetailRow
        label={lang(data.isTradeSize ? 'Trade Size' : 'Position Size')}
        hint={data.isTradeSize ? undefined : lang(hint)}
        value={formatReceiptMoney(data, 'size', size)}
        prevValue={prevSize !== undefined ? formatPerpsMoney(prevSize) : undefined}
      />
    );
  }

  function renderFee() {
    const { fees, fee, isFeePending } = data;
    const areFeesEstimated = isReceiptEstimate(data, 'fees');
    const feeSymbol = data.feeToken ?? ARBITRUM_USDC_MAINNET.symbol;
    // A closed position lists only the fees it knows, and leaves out a fee nothing is known about, as on iOS
    const lines = fees
      ? buildPerpsFeeLines(lang, fees, (value) => formatReceiptFee(feeSymbol, areFeesEstimated, value), {
        isFromBalance: data.isFromBalance,
        shouldSkipUnknown: isClosing,
      })
      : [];
    const hasTotal = isPerpsNumber(fees ? fees.total : fee);
    if (isClosing && !hasTotal && !lines.length && !isFeePending) return undefined;

    const total = formatReceiptFee(feeSymbol, areFeesEstimated, fees ? fees.total : fee);

    return (
      <DetailRow
        label={lang('Fee')}
        hint={buildPerpsFeeHint(lang, { lines, isPending: isFeePending, isEstimated: areFeesEstimated })}
        value={total}
      />
    );
  }

  // The rows go in cards as on iOS: what the position brought, the position itself, and what moved through the wallet
  function renderDetails() {
    // A change of the position keeps its size apart from the prices
    const isChange = event === 'opened' || event === 'increased' || event === 'leverage';
    const profitTone = getPerpsValueTone(data.profit);
    const isLoss = profitTone === 'negative';

    const investedRow = data.invested !== undefined && (
      <DetailRow
        label={lang('Invested')}
        hint={lang('$perps_invested_hint')}
        value={formatPerpsMoney(data.invested)}
      />
    );
    const profitRow = data.profit !== undefined && (
      <DetailRow
        label={lang(isLoss ? 'Loss' : 'Profit')}
        hint={lang(isLoss ? '$perps_loss_hint' : '$perps_profit_hint')}
        value={formatReceiptProfit(data, data.profit)}
        valueClassName={profitTone && styles[profitTone]}
      />
    );
    const closingValueRow = data.closingValue !== undefined && (
      <DetailRow
        label={lang('Closing Value')}
        hint={lang('$perps_closing_value_hint')}
        value={formatPerpsMoney(data.closingValue)}
      />
    );
    // As on iOS and Android, a change of the position shows a dash for what the history does not know
    const liquidationRow = (data.liquidationAfter !== undefined || isChange) && (
      <DetailRow
        label={lang('Liquidation')}
        hint={lang('$perps_liquidation_price_hint')}
        value={formatReceiptMoney(data, 'liquidation', data.liquidationAfter)}
        prevValue={data.liquidationBefore !== undefined && data.liquidationAfter !== undefined
          ? formatPerpsMoney(data.liquidationBefore)
          : undefined}
      />
    );
    const paidRow = (data.paid !== undefined || isChange) && (
      <DetailRow
        label={lang(event === 'opened' ? 'You Pay' : 'You Paid')}
        value={isReceiptEstimate(data, 'paid') ? formatPerpsUsdcEstimate(data.paid) : formatPerpsUsdc(data.paid)}
      />
    );
    // As on iOS, a reduce shows a dash until the amount is known, and a closed position leaves the row out
    const receivedRow = (data.received !== undefined || event === 'reduced') && (
      <DetailRow label={lang('You Received')} value={formatPerpsUsdc(data.received)} />
    );

    return (
      <>
        {renderCard(investedRow, profitRow, closingValueRow)}
        {isChange ? (
          <>
            {renderCard(renderSize())}
            {renderCard(renderPrice(), liquidationRow)}
          </>
        ) : renderCard(renderSize(), renderPrice(), liquidationRow)}
        {renderCard(paidRow, receivedRow, renderFee())}
        {data.remainingCollateral && (
          <RemainingCollateral amount={data.remainingCollateral} isEstimated={isReceiptEstimate(data, 'remaining')} />
        )}
        {data.transferId && (
          <div className={styles.card}>
            <TransferId hash={data.transferId} />
          </div>
        )}
      </>
    );
  }

  function renderCard(first: TeactNode, second?: TeactNode, third?: TeactNode) {
    if (!first && !second && !third) return undefined;

    return (
      <div className={styles.card}>
        {first}
        {second}
        {third}
      </div>
    );
  }

  return (
    <>
      <ModalHeader
        title={(
          <div className={styles.receiptTitle}>
            <span className={styles.receiptTitleText}>{title}</span>
            <span className={styles.receiptDate}>{renderDate()}</span>
          </div>
        )}
        onShareClick={data.txHash ? handleShareClick : undefined}
        onClose={onClose}
      />
      <div ref={contentRef} className={styles.receiptContent}>
        <TradeSummary
          amount={summary.amount}
          prevAmount={summary.prevAmount}
          currency={PERPS_CURRENCY_SYMBOL}
          token={isExpanded ? undefined : token}
          caption={summary.captionKey && lang(summary.captionKey)}
          label={label}
          side={side}
          withSign={data.isAmountSigned}
          isEstimated={summary.isEstimated}
          shouldHideMissingAmount
        />
        {event === 'liquidated' && (
          <WarningMessage>
            {lang('$perps_liquidated_title')} {lang('$perps_liquidated_message')}
          </WarningMessage>
        )}
        {message && <WarningMessage>{message}</WarningMessage>}
        {isExpanded && renderDetails()}
        {(hasDetailsButton || hasStatusButton) && (
          <div className={resultStyles.buttons}>
            {hasDetailsButton && (
              <Button className={resultStyles.button} onClick={handleDetailsClick}>
                {lang('Details')}
              </Button>
            )}
            {hasStatusButton && (
              <Button className={resultStyles.button} onClick={onStatusClick}>
                {lang('PerpsOperationStatus')}
              </Button>
            )}
          </div>
        )}
        <Button isPrimary className={modalStyles.buttonFullWidth} onClick={onClose}>
          {lang('Done')}
        </Button>
      </div>
    </>
  );
}

export default memo(Receipt);

function getPositionLabel(lang: LangFn, symbol: string, side?: ApiPerpsPositionSide, leverage?: number) {
  if (!side) return symbol;

  // The history does not always know the leverage of a past trade, so the label then goes without it
  return leverage !== undefined
    ? formatPositionLabel(lang, symbol, leverage, side)
    : `${symbol} ${getSideLabel(lang, side)}`;
}

function getReceiptTitle(lang: LangFn, { event }: PerpsReceiptData, status: PerpsReceiptStatus) {
  switch (status) {
    case 'pending':
      return lang('In Progress');
    case 'failed':
      return lang('Failed');
    case 'attention':
      return lang('PerpsOperationStatus');
    default:
      return lang(TITLE_KEYS[event]);
  }
}

function formatReceiptMoney(data: PerpsReceiptData, field: PerpsReceiptEstimate, value?: string) {
  return isReceiptEstimate(data, field) ? formatPerpsMoneyEstimate(value) : formatPerpsMoney(value);
}

/** A fee in its token at full precision, as on iOS */
function formatReceiptFee(symbol: string, isEstimated: boolean, value?: string) {
  const amount = formatPerpsQuantity(symbol, value);
  return isEstimated && isPerpsNumber(value) ? `≈ ${amount}` : amount;
}

function formatReceiptProfit(data: PerpsReceiptData, value?: string) {
  return `${isReceiptEstimate(data, 'amount') ? '≈ ' : ''}${formatPerpsSignedMoney(value)}`;
}

/** The time a position was held, in at most two units, as on iOS */
function formatDuration(lang: LangFn, durationMs: number) {
  const days = Math.floor(durationMs / DAY);
  const hours = Math.floor((durationMs % DAY) / HOUR);
  const minutes = Math.floor((durationMs % HOUR) / MINUTE);

  const units: [number, 'day' | 'hour' | 'minute'][] = days
    ? [[days, 'day'], [hours, 'hour']]
    : [[hours, 'hour'], [minutes, 'minute']];

  return units
    .filter(([value], index) => value > 0 || index === units.length - 1)
    .map(([value, unit]) => formatTimeUnit(lang.code!, value, unit))
    .join(' ');
}
