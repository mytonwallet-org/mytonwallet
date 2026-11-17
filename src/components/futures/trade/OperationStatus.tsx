import React, { memo, useMemo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsFill, ApiPerpsMarketAsset, ApiPerpsOperation } from '../../../api/types';
import type { PerpsTradeState } from '../../../global/types';

import { findPerpsOperationFill, isPerpsWithdrawalRejected } from '../../../global/helpers/perps';
import {
  isPerpsOperationBlocking,
  selectCurrentAccountPerps,
  selectCurrentAccountPerpsOperation,
} from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { formatShortDay } from '../../../util/dateFormat';
import {
  formatPerpsMoney,
  formatPerpsQuantity,
  formatPerpsUsdc,
  getOperationBannerTitle,
  getOperationMessage,
} from '../helpers/formatPerps';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import usePerpsOperationRefresh from '../hooks/usePerpsOperationRefresh';

import Button from '../../ui/Button';
import ModalFooter from '../../ui/ModalFooter';
import ModalHeader from '../../ui/ModalHeader';
import Spinner from '../../ui/Spinner';
import WarningMessage from '../../ui/WarningMessage';
import DetailRow from '../DetailRow';
import ErrorText from './ErrorText';
import TransferId from './TransferId';
import WithdrawalDetails from './WithdrawalDetails';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface OwnProps {
  trade: PerpsTradeState;
  asset?: ApiPerpsMarketAsset;
}

interface StateProps {
  operation?: ApiPerpsOperation;
  fills?: ApiPerpsFill[];
}

function OperationStatus({
  trade, asset, operation, fills,
}: OwnProps & StateProps) {
  const {
    cancelPerpsTrade, acknowledgePerpsOperation, preparePerpsWithdrawal, hidePerpsOperationBanner, openPerpsActivity,
  } = getActions();
  const lang = useLang();

  const [isAcknowledging, startAcknowledging] = useFlag();
  const symbol = asset?.symbol ?? '';

  const operationFill = useMemo(() => operation && findPerpsOperationFill(operation, fills), [fills, operation]);
  // The trade of the operation in the history, whose receipt the Details button opens. Like the history list, it needs
  // the market in the loaded catalogue.
  const fill = operationFill?.eventKind && operationFill.coin === asset?.name ? operationFill : undefined;

  const handleRefresh = usePerpsOperationRefresh(operation, Boolean(operationFill));

  // The user has seen the status, so the banner of the operation hides until its state changes
  const handleClose = useLastCallback(() => {
    if (operation) hidePerpsOperationBanner({ operationId: operation.id });
    cancelPerpsTrade();
  });

  const handleDetailsClick = useLastCallback(() => {
    cancelPerpsTrade();
    openPerpsActivity({ fill: fill! });
  });

  const handleAcknowledge = useLastCallback(() => {
    acknowledgePerpsOperation({ operationId: operation!.id });
  });

  const handleWithdraw = useLastCallback(() => {
    preparePerpsWithdrawal({ operationId: operation!.id });
  });

  if (!operation) return undefined;

  const { state } = operation;
  const isUnknown = state === 'unknown' && operation.acknowledgedAt === undefined;
  const isBalanceWithdrawal = operation.kind === 'withdraw';
  const isAttentionNeeded = operation.error === 'PerpsPartialFill' || isPerpsWithdrawalRejected(operation);
  const isDone = state === 'completed' && !isAttentionNeeded;

  function renderWithdrawalDetails(current: ApiPerpsOperation) {
    const { balanceWithdrawal } = current;

    return (
      <>
        <div className={styles.card}>
          {/* A failed withdrawal moved nothing */}
          {balanceWithdrawal && state !== 'failed' && (
            <DetailRow label={lang('You Receive')} value={formatPerpsUsdc(balanceWithdrawal.receiveAmount)} />
          )}
          <DetailRow label={lang('Date')} value={formatShortDay(lang.code!, current.createdAt, true)} />
        </div>
        {balanceWithdrawal && (
          <div className={styles.cardGroup}>
            <WithdrawalDetails withdrawal={balanceWithdrawal} />
            {state === 'completed' && <p className={styles.cardNote}>{lang('PerpsWithdrawalOnItsWay')}</p>}
          </div>
        )}
      </>
    );
  }

  function renderTradeDetails(current: ApiPerpsOperation) {
    return (
      <>
        <div className={styles.card}>
          <DetailRow label={lang('Order')} value={getOperationBannerTitle(lang, current, symbol)} />
          <DetailRow label={lang('Date')} value={formatShortDay(lang.code!, current.createdAt, true)} />
          {current.orderId !== undefined && (
            <DetailRow label={lang('Order ID')} value={String(current.orderId)} />
          )}
        </div>
        {/* The average price shows only together with the filled size */}
        {current.filledSize !== undefined && (
          <div className={styles.card}>
            <DetailRow label={lang('Position Size')} value={formatPerpsQuantity(symbol, current.filledSize)} />
            {current.averagePrice !== undefined && (
              <DetailRow label={lang('Price')} value={formatPerpsMoney(current.averagePrice)} />
            )}
          </div>
        )}
        {current.depositTxHash && (
          <div className={styles.card}>
            <TransferId hash={current.depositTxHash} />
          </div>
        )}
      </>
    );
  }

  // The icon, the title and the message of the state, as on iOS. A done trade with its receipt needs no message.
  function renderStatus(current: ApiPerpsOperation) {
    const message = isDone && fill ? undefined : getOperationMessage(lang, current);
    const iconTone = isDone ? styles.statusIconDone : state === 'failed' ? styles.statusIconFailed : undefined;

    return (
      <div className={styles.status}>
        {state === 'running' ? (
          <Spinner className={styles.statusSpinner} />
        ) : (
          <span className={buildClassName(styles.statusIcon, iconTone)}>
            <i className={isDone ? 'icon-check' : 'icon-exclamation'} aria-hidden />
          </span>
        )}
        <h3 className={buildClassName(styles.statusTitle, isDone && styles.positive)}>
          {isDone
            ? lang(isBalanceWithdrawal ? 'PerpsWithdrawalCompleted' : 'PerpsCompleted')
            : lang(isBalanceWithdrawal ? 'PerpsWithdrawalStatus' : 'PerpsOperationStatus')}
        </h3>
        {message && <p className={styles.statusText}>{message}</p>}
      </div>
    );
  }

  return (
    <>
      <ModalHeader
        title={lang(isBalanceWithdrawal ? 'PerpsWithdrawalStatus' : 'PerpsOperationStatus')}
        onClose={handleClose}
      />
      <div className={buildClassName(modalStyles.transitionContent, styles.content)}>
        {renderStatus(operation)}

        {isBalanceWithdrawal ? renderWithdrawalDetails(operation) : renderTradeDetails(operation)}

        {trade.error && <ErrorText error={trade.error} />}
        {isAcknowledging && (
          <WarningMessage>
            {lang(isBalanceWithdrawal ? 'PerpsAcknowledgeWithdrawalUnknown' : 'PerpsAcknowledgeUnknown')}
          </WarningMessage>
        )}

        <ModalFooter>
          <div className={styles.statusFooter}>
            <Button isText className={modalStyles.buttonFullWidth} onClick={handleRefresh}>{lang('Refresh')}</Button>
            {isUnknown && (
              <Button
                isPrimary
                isLoading={trade.isPreparing}
                isDisabled={trade.isPreparing}
                className={modalStyles.buttonFullWidth}
                onClick={isAcknowledging ? handleAcknowledge : startAcknowledging}
              >
                {lang('PerpsAllowNewOrders')}
              </Button>
            )}
            {state === 'partial' && (
              <Button
                isPrimary
                isLoading={trade.isPreparing}
                className={modalStyles.buttonFullWidth}
                onClick={handleWithdraw}
              >
                {lang('PerpsWithdrawReleased')}
              </Button>
            )}
            {!isUnknown && state !== 'partial' && (
              fill ? (
                <Button isPrimary className={modalStyles.buttonFullWidth} onClick={handleDetailsClick}>
                  {lang('Details')}
                </Button>
              ) : (
                <Button isPrimary className={modalStyles.buttonFullWidth} onClick={handleClose}>
                  {lang(isPerpsOperationBlocking(operation) ? 'Hide' : 'Close')}
                </Button>
              )
            )}
          </div>
        </ModalFooter>
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global, { trade }): StateProps => {
  return {
    operation: trade.operationId ? selectCurrentAccountPerpsOperation(global, trade.operationId) : undefined,
    fills: selectCurrentAccountPerps(global)?.history?.fills,
  };
})(OperationStatus));
