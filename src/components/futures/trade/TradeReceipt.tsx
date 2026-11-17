import React, { memo, useEffect, useMemo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsFill, ApiPerpsMarketAsset, ApiPerpsOperation } from '../../../api/types';
import type { PerpsOperationReceipt, PerpsTradeState } from '../../../global/types';

import { findPerpsOperationFill } from '../../../global/helpers/perps';
import {
  selectCurrentAccountPerps,
  selectCurrentAccountPerpsOperation,
  selectCurrentAccountState,
} from '../../../global/selectors';
import { buildOperationReceipt } from '../helpers/perpsReceipt';

import useFlag from '../../../hooks/useFlag';
import useLastCallback from '../../../hooks/useLastCallback';
import usePerpsOperationRefresh from '../hooks/usePerpsOperationRefresh';

import Receipt from './Receipt';

interface OwnProps {
  trade: PerpsTradeState;
  asset?: ApiPerpsMarketAsset;
}

interface StateProps {
  operation?: ApiPerpsOperation;
  receipt?: PerpsOperationReceipt;
  fills?: ApiPerpsFill[];
  snapshotTimestamp?: number;
}

function TradeReceipt({
  trade, asset, operation, receipt, fills, snapshotTimestamp,
}: OwnProps & StateProps) {
  const {
    cancelPerpsTrade, loadPerpsReceiptDetails, setPerpsTradeStep,
  } = getActions();

  const [isExpanded, expand] = useFlag();
  const operationState = operation?.state;
  const fill = useMemo(() => operation && findPerpsOperationFill(operation, fills), [operation, fills]);

  usePerpsOperationRefresh(operation, Boolean(fill));

  // The fill and the position come with the history and the snapshot, which load after the operation completes
  const operationId = operation?.id;
  useEffect(() => {
    if (operationId && operationState !== 'running') loadPerpsReceiptDetails({ operationId });
  }, [operationId, operationState, fill, snapshotTimestamp]);

  // The receipt saved with the operation outlives this modal. Until it is saved, the quote of the trade fills its
  // place.
  const quote = receipt?.quote ?? trade.quote;
  const data = useMemo(
    () => operation && quote && buildOperationReceipt(operation, quote, asset, {
      fill, position: receipt?.position, details: receipt?.details,
    }),
    [asset, fill, operation, quote, receipt],
  );

  const handleStatusClick = useLastCallback(() => {
    setPerpsTradeStep({ step: 'status' });
  });

  if (!data) return undefined;

  return (
    <Receipt
      data={data}
      asset={asset}
      isExpanded={isExpanded}
      onDetailsClick={expand}
      onStatusClick={handleStatusClick}
      onClose={cancelPerpsTrade}
    />
  );
}

export default memo(withGlobal<OwnProps>((global, { trade }): StateProps => {
  const accountState = selectCurrentAccountState(global);
  const accountPerps = selectCurrentAccountPerps(global);

  return {
    operation: trade.operationId ? selectCurrentAccountPerpsOperation(global, trade.operationId) : undefined,
    receipt: trade.operationId ? accountState?.perpsReceipts?.[trade.operationId] : undefined,
    fills: accountPerps?.history?.fills,
    snapshotTimestamp: accountPerps?.snapshot?.timestamp,
  };
})(TradeReceipt));
