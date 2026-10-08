import { useEffect, useState } from '../../../lib/teact/teact';

import type { ApiChain } from '../../../api/types';

import { resolveOffRampMaxAmount } from '../../main/modals/helpers/offRamp';

interface OffRampMaxAmountInput {
  isActive: boolean;
  accountId?: string;
  chain?: ApiChain;
  tokenSlug?: string;
  balance?: bigint;
}

/** The most the account can sell to the card, resolved from the network fee while the fiat mode is on */
export default function useOffRampMaxAmount({
  isActive, accountId, chain, tokenSlug, balance,
}: OffRampMaxAmountInput) {
  const [state, setState] = useState<{ amount?: bigint; isLoading: boolean; hasError?: boolean }>({ isLoading: true });

  useEffect(() => {
    if (!isActive || !accountId || !chain || !tokenSlug || balance === undefined) return undefined;

    let isCancelled = false;
    setState({ isLoading: true });

    resolveOffRampMaxAmount({ accountId, chain, tokenSlug, balance })
      .then((amount) => {
        if (isCancelled) return;

        setState({ amount, isLoading: false, hasError: amount === undefined });
      })
      .catch(() => {
        if (isCancelled) return;

        setState({ isLoading: false, hasError: true });
      });

    return () => {
      isCancelled = true;
    };
  }, [isActive, accountId, chain, tokenSlug, balance]);

  return state;
}
