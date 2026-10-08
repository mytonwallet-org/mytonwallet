import type { ApiChain } from '../../../../api/types';

import { getChainConfig } from '../../../../util/chain';
import { getMaxTransferAmount } from '../../../../util/fee/transferFee';
import { callApi } from '../../../../api';

/**
 * The largest native amount the account can send to the off-ramp once the network fee is set aside.
 * Returns `undefined` when the fee cannot be estimated.
 */
export async function resolveOffRampMaxAmount({ accountId, chain, tokenSlug, balance }: {
  accountId: string;
  chain: ApiChain;
  tokenSlug: string;
  balance: bigint;
}) {
  const chainConfig = getChainConfig(chain);

  if (chainConfig.canTransferFullNativeBalance) {
    return balance;
  }

  const result = await callApi('checkTransactionDraft', chain, {
    accountId,
    toAddress: chainConfig.feeCheckAddress,
    amount: balance,
  });

  // A whole-balance draft reports `InsufficientBalance` (fee on top of the amount) and still carries the fee.
  if (!result?.explainedFee) {
    return undefined;
  }

  const { fullFee, canTransferFullBalance } = result.explainedFee;

  return getMaxTransferAmount({
    tokenBalance: balance,
    tokenSlug,
    fullFee: fullFee?.terms,
    canTransferFullBalance,
  });
}
