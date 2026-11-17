import React, { memo, useEffect, useMemo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsMarketAsset, ApiPerpsOperation } from '../../../api/types';
import type { PerpsOpenedActivity, PerpsOperationReceipt } from '../../../global/types';

import { selectCurrentAccountState, selectPerpsMarketAssetsByName } from '../../../global/selectors';
import { buildFillReceipt, buildOperationReceipt } from '../helpers/perpsReceipt';

import useCurrentOrPrev from '../../../hooks/useCurrentOrPrev';
import useFlag from '../../../hooks/useFlag';
import useLastCallback from '../../../hooks/useLastCallback';
import usePerpsOperationRefresh from '../hooks/usePerpsOperationRefresh';

import Modal from '../../ui/Modal';
import Receipt from '../trade/Receipt';

import tradeStyles from '../trade/TradeModal.module.scss';

interface StateProps {
  activity?: PerpsOpenedActivity;
  assetsByName?: Record<string, ApiPerpsMarketAsset>;
  operations?: Record<string, ApiPerpsOperation>;
  receipts?: Record<string, PerpsOperationReceipt>;
}

/**
 * The receipt of a trade from the history. A trade this app submitted shows the receipt of its operation and follows
 * it, as on iOS.
 */
function ActivityModal({
  activity, assetsByName, operations, receipts,
}: StateProps) {
  const { closePerpsActivity, openPerpsOperation, loadPerpsReceiptDetails } = getActions();

  const [isExpanded, expand, collapse] = useFlag();
  const fill = useCurrentOrPrev(activity, true)?.fill;
  const asset = fill && assetsByName?.[fill.coin];
  // The operation this app submitted for the trade tells whether it still waits for a withdrawal
  const operation = useMemo(() => {
    if (fill?.oid === undefined || !operations) return undefined;

    return Object.values(operations).find(({ orderId, assetId }) => orderId === fill.oid && assetId === asset?.id);
  }, [asset, fill, operations]);
  const operationReceipt = operation && receipts?.[operation.id];

  const receipt = useMemo(() => {
    if (!fill) return undefined;

    return operation && operationReceipt
      ? buildOperationReceipt(operation, operationReceipt.quote, asset, {
        fill, position: operationReceipt.position, details: operationReceipt.details,
      })
      : buildFillReceipt(fill, asset, operation);
  }, [asset, fill, operation, operationReceipt]);

  usePerpsOperationRefresh(activity ? operation : undefined, true);

  const operationId = operation?.id;
  const hasOperationReceipt = Boolean(operationReceipt);
  useEffect(() => {
    if (activity && operationId && hasOperationReceipt) loadPerpsReceiptDetails({ operationId });
  }, [activity, hasOperationReceipt, operationId]);

  // Each receipt opens compact, as on iOS
  useEffect(() => {
    if (!activity) collapse();
  }, [activity]);

  const handleStatusClick = useLastCallback(() => {
    closePerpsActivity();
    openPerpsOperation({ operationId: operation!.id });
  });

  return (
    <Modal
      isOpen={Boolean(activity)}
      dialogClassName={tradeStyles.receiptDialog}
      onClose={closePerpsActivity}
    >
      {receipt && (
        <Receipt
          data={receipt}
          asset={asset}
          isExpanded={isExpanded}
          onDetailsClick={expand}
          onStatusClick={operation && handleStatusClick}
          onClose={closePerpsActivity}
        />
      )}
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountState = selectCurrentAccountState(global);

  return {
    activity: global.perps.openedActivity,
    assetsByName: selectPerpsMarketAssetsByName(global),
    operations: accountState?.perpsOperations,
    receipts: accountState?.perpsReceipts,
  };
})(ActivityModal));
