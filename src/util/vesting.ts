import type { ApiVestingInfo, ApiVestingPartStatus } from '../api/types';

import { MYCOIN_MAINNET } from '../config';
import { fromDecimal, toDecimal } from './decimals';

// Part amounts are human-unit MY amounts, and MY has the same decimals on every network
export function calcVestingAmountByStatus(vesting: ApiVestingInfo[], statuses: ApiVestingPartStatus[]) {
  const total = vesting.reduce((acc, { parts }) => parts.reduce((partsAcc, { amount, status }) => (
    statuses.includes(status) && Number.isFinite(amount)
      ? partsAcc + fromDecimal(amount, MYCOIN_MAINNET.decimals)
      : partsAcc
  ), acc), 0n);

  return toDecimal(total, MYCOIN_MAINNET.decimals, true);
}
