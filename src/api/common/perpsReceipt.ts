import type { ApiPerpsAccountPosition, ApiPerpsFill, ApiPerpsOperation, ApiPerpsQuote,
  ApiPerpsReceiptDetails } from '../types/perpsTrading';

import { Big } from '../../lib/big.js';
import { getPerpsCoinFromAssetId, PERPS_CCTP_FORWARD_FEE_USDC } from './perps';

export function getPerpsResultingPositionSize(quote: ApiPerpsQuote, filledSize?: string): string | undefined {
  if (!filledSize || quote.kind === 'leverage' || quote.kind === 'unchanged'
    || (quote.kind !== 'open' && quote.previousSize === undefined)) return undefined;
  const filled = Big(filledSize);
  if (filled.lte(0)) return undefined;
  const size = Big(quote.previousSize ?? 0).plus(filled.mul(['reduce', 'close'].includes(quote.kind) ? -1 : 1));
  return size.gte(0) ? size.toFixed() : undefined;
}

export function getPerpsReceiptDetails({ quote, operation, position, fill }: {
  quote: ApiPerpsQuote; operation: ApiPerpsOperation; position?: ApiPerpsAccountPosition; fill?: ApiPerpsFill;
}): ApiPerpsReceiptDetails {
  const coin = getPerpsCoinFromAssetId(operation.assetId);
  if (quote.accountId !== operation.accountId || quote.assetId !== operation.assetId || quote.kind !== operation.kind
    || (fill && (operation.orderId === undefined || fill.oid !== operation.orderId || fill.coin !== coin))) return {};
  // A rejected withdrawal left the money on the HyperCore balance, so its amount was never received.
  const withdrawalAmount = operation.error?.startsWith('PerpsWithdrawalRejected')
    ? undefined : operation.withdrawalAmount;
  // A balance-funded order bridges nothing, so it has no deposit fee or unallocated deposit.
  const depositing = quote.funding !== 'balance' && (['open', 'increase'].includes(operation.kind)
    || (operation.kind === 'leverage' && Big(quote.paymentAmount).gt(0)));
  const bridge = fill?.receiptFees?.bridge ?? fill?.bridgeFee ?? fill?.deposit?.bridgeFee
    ?? (fill?.withdrawal?.status === 'completed' ? fill.withdrawal.bridgeFee : undefined)
    ?? (depositing ? (operation.depositTxHash ? quote.bridgeFee : undefined)
      : !fill?.withdrawal && withdrawalAmount && operation.state === 'completed'
        ? String(PERPS_CCTP_FORWARD_FEE_USDC) : undefined);
  const details: ApiPerpsReceiptDetails = {};
  if (fill?.withdrawal?.status === 'completed') {
    details.receiveAmount = fill.withdrawal.receivedAmount;
  } else if (!fill?.withdrawal && !depositing && bridge !== undefined && withdrawalAmount !== undefined) {
    const received = Big(withdrawalAmount).minus(bridge);
    if (received.gte(0)) details.receiveAmount = received.toFixed();
  }
  if (fill?.receiptFees) {
    details.fees = { ...fill.receiptFees };
    if (details.fees.bridge === undefined && bridge !== undefined) {
      details.fees.bridge = bridge;
      details.fees.total = Big(details.fees.trading).plus(bridge).toFixed();
    }
  }
  if (operation.kind === 'leverage' && operation.state === 'completed' && !details.fees) {
    if (!depositing || bridge !== undefined) {
      details.fees = { exchange: '0', service: '0', trading: '0', bridge: bridge ?? '0', total: bridge ?? '0' };
    }
    return details;
  }
  const trading = fill?.receiptFees?.trading;
  if (!fill || trading === undefined || fill.feeToken !== 'USDC') return details;
  const positionSize = operation.positionSize ?? fill.positionSize
    ?? getPerpsResultingPositionSize(quote, operation.filledSize ?? fill.sz);
  if (depositing && bridge !== undefined && position?.id === `${operation.accountId}/${operation.assetId}`
    && position.side === quote.side && position.size === positionSize
    && (operation.kind === 'open' || quote.previousFunding !== undefined) && position.funding !== undefined) {
    const funding = Big(position.funding).minus(quote.previousFunding ?? 0);
    const collateralChange = Big(fill.collateralAfter ?? position.collateral)
      .minus(fill.collateralBefore ?? quote.previousCollateral ?? 0);
    const remainder = Big(fill.deposit?.grossAmount ?? quote.paymentAmount).minus(bridge)
      .minus(collateralChange).minus(trading).plus(funding);
    // A negative value can indicate other account activity; do not present it as available funds.
    if (remainder.gte(0)) details.remainingCollateral = remainder.round(6, Big.roundDown).toFixed();
  }
  return details;
}
