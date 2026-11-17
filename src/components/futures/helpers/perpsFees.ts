import type { ApiPerpsBalanceWithdrawalQuote, ApiPerpsFees } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import { Big } from '../../../lib/big.js';
import { isPerpsNumber } from '../../../global/helpers/perps';
import { formatPerpsUsdc, MISSING_VALUE } from './formatPerps';

type FeeLineOptions = {
  /** The margin comes from the Hyperliquid balance, so nothing crosses the bridge */
  isFromBalance?: boolean;
  /** Parts without a known amount are left out instead of showing a dash */
  shouldSkipUnknown?: boolean;
};

/** A part of a fee, as in "Bridge Fee" and "≈ 1 USDC" */
export type PerpsFeeLine = {
  label: string;
  value: string;
};

/** The parts of the fees of a trade, as on iOS. The USDC total is listed only next to a known bridge fee. */
export function buildPerpsFeeLines(
  lang: LangFn,
  fees: ApiPerpsFees,
  formatValue: (value?: string) => string,
  { isFromBalance, shouldSkipUnknown }: FeeLineOptions = {},
): PerpsFeeLine[] {
  const parts: [labelKey: string, value?: string][] = fees.exchange !== undefined && fees.service !== undefined
    ? [['PerpsExchangeFee', fees.exchange], ['PerpsServiceFee', fees.service]]
    : [['Trading Fee', fees.trading]];

  if (!isFromBalance) parts.push(['PerpsBridgeFee', fees.bridge]);
  if (fees.firstTransfer !== undefined) parts.push(['PerpsFirstWithdrawalFee', fees.firstTransfer]);
  if (fees.bridge !== undefined) parts.push(['PerpsTotalFees', fees.total]);

  return parts
    .filter(([, value]) => !shouldSkipUnknown || isPerpsNumber(value))
    .map(([labelKey, value]) => ({ label: lang(labelKey), value: formatValue(value) }));
}

/** The fee of a withdrawal from the Hyperliquid balance: the bridge fee, and the fee of the first withdrawal on top */
export function buildPerpsWithdrawalFee(
  lang: LangFn,
  { bridgeFee, firstTransferFee }: ApiPerpsBalanceWithdrawalQuote,
) {
  const lines: PerpsFeeLine[] = [{ label: lang('PerpsBridgeFee'), value: formatPerpsUsdc(bridgeFee) }];
  if (firstTransferFee !== undefined) {
    lines.push({ label: lang('PerpsFirstWithdrawalFee'), value: formatPerpsUsdc(firstTransferFee) });
  }

  const firstTransfer = firstTransferFee ?? '0';
  const total = isPerpsNumber(bridgeFee) && isPerpsNumber(firstTransfer)
    ? formatPerpsUsdc(Big(bridgeFee).plus(firstTransfer).toFixed())
    : MISSING_VALUE;

  return { total, lines };
}

/**
 * The text behind the info icon of the fee row, as on iOS. Its paragraphs tell that the fee becomes known only at
 * execution, list the parts of the fee or describe the fee in general, and warn that the fee is an estimate.
 */
export function buildPerpsFeeHint(lang: LangFn, { lines, isPending, isEstimated }: {
  lines: PerpsFeeLine[];
  isPending?: boolean;
  isEstimated?: boolean;
}) {
  const paragraphs: string[] = [];

  if (isPending) paragraphs.push(lang('PerpsFeesAtExecution'));

  if (lines.length) {
    paragraphs.push(lines.map(({ label, value }) => `${label}: ${value}`).join('\n'));
  } else if (!isPending) {
    paragraphs.push(lang('$perps_fees_hint'));
  }

  if (isEstimated) paragraphs.push(lang('PerpsFeeEstimateHint'));

  return paragraphs.join('\n\n');
}
