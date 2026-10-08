import { useEffect, useRef, useState } from '../../../lib/teact/teact';

import type { ApiBaseCurrency, ApiChain, ApiToken } from '../../../api/types';
import type { Theme } from '../../../global/types';

import { SELF_UNIVERSAL_HOST_URL, TONCOIN } from '../../../config';
import { buildAvanchangeUrl } from '../../../util/avanchange';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import { callApi } from '../../../api';
import { resolveOffRampMaxAmount } from '../modals/helpers/offRamp';

interface UseOffRampUrlParams {
  isOpen: boolean;
  // Absent while the surface has no allowed currency to offer; `isOpen` is false in that case
  currency?: ApiBaseCurrency;
  chain?: ApiChain;
  address?: string;
  token?: ApiToken;
  balance?: bigint;
  /** The amount to sell, in the native token. The whole transferable balance is sold when absent */
  amount?: string;
  accountId?: string;
  appTheme: Theme;
}

interface UseOffRampUrlResult {
  url: string | undefined;
  error: string | undefined;
  isLoading: boolean;
}

export default function useOffRampUrl({
  isOpen,
  currency,
  chain,
  address,
  token,
  balance,
  amount,
  accountId,
  appTheme,
}: UseOffRampUrlParams): UseOffRampUrlResult {
  const [url, setUrl] = useState<string | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [isLoading, setIsLoading] = useState(true);
  const isOpenRef = useRef(isOpen);
  isOpenRef.current = isOpen;
  const { slug: tokenSlug, decimals: tokenDecimals } = token || {};
  // Avanchange sells GRAM, so it only applies on the TON chain regardless of the picked currency
  const isAvanchange = currency === 'RUB' && chain === 'ton';

  useEffect(() => {
    if (!isOpen) {
      setUrl(undefined);
      setError(undefined);
      setIsLoading(true);
    }
  }, [isOpen]);

  // `address`/`balance` here are the TON wallet and GRAM balance. Build the dreamwalkers URL
  // synchronously, no backend call.
  useEffect(() => {
    if (!isOpen || !isAvanchange) return;

    if (!address) {
      setUrl(undefined);
      return;
    }

    const balanceAmount = balance && balance > 0n ? toDecimal(balance, TONCOIN.decimals) : undefined;

    setUrl(buildAvanchangeUrl({
      address,
      give: 'GRAM',
      take: 'CARDRUB',
      type: 'sell',
      amount: amount ?? balanceAmount,
    }));
    setError(undefined);
    setIsLoading(false);
  }, [isOpen, isAvanchange, address, balance, amount]);

  // MoonPay: resolve the off-ramp URL from the backend with the requested or the max transferable amount
  useEffect(() => {
    if (
      !isOpen || isAvanchange || !currency || !address || !chain || balance === undefined || !tokenSlug || !accountId
    ) {
      return undefined;
    }

    setIsLoading(true);

    let isCancelled = false;

    const loadUrl = async () => {
      try {
        const maxAmount = await resolveOffRampMaxAmount({ accountId, chain, tokenSlug, balance });

        if (isCancelled || !isOpenRef.current) return;

        const requestedAmount = amount ? fromDecimal(amount, tokenDecimals) : undefined;
        const sellAmount = requestedAmount ?? maxAmount;

        if (!sellAmount || !maxAmount || sellAmount > maxAmount) {
          setError('Insufficient balance');
          setIsLoading(false);
          return;
        }

        const response = await callApi('getMoonpayOfframpUrl', {
          chain,
          address,
          theme: appTheme,
          currency,
          amount: toDecimal(sellAmount, tokenDecimals),
          baseUrl: `${SELF_UNIVERSAL_HOST_URL}/offramp/`,
        });

        if (isCancelled || !isOpenRef.current) return;

        if (!response || 'error' in response) {
          setError(response?.error || 'Unknown error');
        } else {
          setUrl(response.url);
        }
        setIsLoading(false);
      } catch (err) {
        if (!isCancelled && isOpenRef.current) {
          setError(err instanceof Error ? err.message : String(err));
          setIsLoading(false);
        }
      }
    };

    void loadUrl();

    return () => {
      isCancelled = true;
    };
  }, [accountId, address, appTheme, balance, amount, chain, currency, tokenDecimals, isOpen, isAvanchange, tokenSlug]);

  return { url, error, isLoading };
}
