import type { ApiPerpsActivitiesSnapshot, ApiPerpsRawActivityItem, ApiPerpsTradeActivity } from '../types/perps';
import type { ApiPerpsActivityHistory, ApiPerpsFill } from '../types/perpsTrading';

import { Big } from '../../lib/big.js';
import { normalizePerpsCashFlows } from './perpsCashFlows';
import { normalizePerpsActivityFills } from './perpsFills';

const eventKinds = { open: 'opened', increase: 'increased', reduce: 'reduced', close: 'closed',
  liquidation: 'liquidated' } as const;

/** Preserve backend order IDs and event IDs. Unreported position sizes stay unknown. */
export function normalizePerpsActivityPage(
  snapshot: ApiPerpsActivitiesSnapshot, address: string,
): ApiPerpsActivityHistory {
  if (!snapshot || snapshot.address?.toLowerCase() !== address.toLowerCase() || !Array.isArray(snapshot.activities)) {
    throw new Error('PerpsIncompleteData');
  }
  const raw: ApiPerpsRawActivityItem[] = [];
  const fills: ApiPerpsFill[] = [];
  for (const item of snapshot.activities) {
    if (['fill', 'fundingPayment', 'historicalOrder', 'ledgerUpdate'].includes(item.kind)) {
      raw.push(item as ApiPerpsRawActivityItem);
      continue;
    }
    const trade = item as ApiPerpsTradeActivity;
    if (!(trade.kind in eventKinds) || !trade.id || !Number.isSafeInteger(trade.timestamp)
      || !['long', 'short'].includes(trade.side)) throw new Error('PerpsIncompleteData');
    if (!trade.assetId) continue;
    for (const amount of [trade.size, trade.entryPrice, trade.exitPrice, trade.notional, trade.realizedPnl,
      trade.collateralBefore, trade.collateralAfter, trade.positionSizeBefore, trade.positionSizeAfter,
      trade.transferredAmount, trade.fees?.trading, trade.fees?.builder, trade.fees?.bridge]) {
      if (amount !== undefined) Big(amount);
    }
    const coin = trade.assetId.replace(/^hyperliquid:(hl:)?/, '');
    const price = trade.exitPrice ?? trade.entryPrice;
    const positionValue = (size?: string) => (
      size === undefined || price === undefined ? undefined : Big(size).mul(price).toFixed()
    );
    fills.push({
      activityId: trade.id, assetId: trade.assetId, coin, oid: trade.orderId, fillIds: trade.fillIds,
      time: trade.timestamp, eventKind: eventKinds[trade.kind], positionSide: trade.side,
      px: price, sz: trade.size, notional: trade.notional,
      entryPrice: trade.entryPrice, positionOpenedAt: trade.positionOpenedAt, leverage: trade.leverage,
      collateralBefore: trade.collateralBefore, collateralAfter: trade.collateralAfter,
      transferredAmount: trade.transferredAmount,
      previousSize: trade.positionSizeBefore, positionSize: trade.positionSizeAfter,
      previousNotional: positionValue(trade.positionSizeBefore),
      positionNotional: positionValue(trade.positionSizeAfter),
      closedPnl: trade.realizedPnl, fee: trade.fees?.trading, builderFee: trade.fees?.builder,
      receiptFees: trade.fees?.trading === undefined ? undefined : {
        trading: trade.fees.trading, service: trade.fees.builder, bridge: trade.fees.bridge,
        exchange: trade.fees.builder === undefined ? undefined
          : Big(trade.fees.trading).minus(trade.fees.builder).toFixed(),
        total: Big(trade.fees.trading).plus(trade.fees.bridge ?? 0).toFixed(),
      },
      bridgeFee: trade.fees?.bridge, feeToken: 'USDC',
      netPnl: trade.realizedPnl !== undefined && trade.fees?.trading !== undefined
        ? Big(trade.realizedPnl).minus(trade.fees.trading).toFixed() : undefined,
      deposit: trade.deposit, withdrawal: trade.withdrawal,
    });
  }
  return { fills: [...fills, ...normalizePerpsActivityFills(raw)].sort((a, b) => b.time - a.time),
    cashFlows: normalizePerpsCashFlows(raw, address).filter((flow) => flow.kind !== 'funding'),
    nextCursor: snapshot.nextCursor,
    hasActivity: snapshot.hasActivity === true || snapshot.activities.length > 0 || Boolean(snapshot.nextCursor) };
}
