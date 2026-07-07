import { useEffect, useRef, useState } from '../../../lib/teact/teact';

import type { ApiBaseCurrency, ApiChain, ApiToken } from '../../../api/types';
import type { Theme } from '../../../global/types';

import { SELF_UNIVERSAL_HOST_URL, TONCOIN } from '../../../config';
import { buildAvanchangeUrl } from '../../../util/avanchange';
import { getChainConfig } from '../../../util/chain';
import { toDecimal } from '../../../util/decimals';
import { getMaxTransferAmount } from '../../../util/fee/transferFee';
import { callApi } from '../../../api';

const MOONPAY_CURRENCY: ApiBaseCurrency = 'EUR';

interface UseOffRampUrlParams {
  isOpen: boolean;
  currency: ApiBaseCurrency;
  chain?: ApiChain;
  address?: string;
  token?: ApiToken;
  balance?: bigint;
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

    const amount = balance && balance > 0n ? toDecimal(balance, TONCOIN.decimals) : undefined;

    setUrl(buildAvanchangeUrl({
      address,
      give: 'GRAM',
      take: 'CARDRUB',
      type: 'sell',
      amount,
    }));
    setError(undefined);
    setIsLoading(false);
  }, [isOpen, isAvanchange, address, balance]);

  // MoonPay (EUR): resolve the off-ramp URL from the backend with the max transferable amount
  useEffect(() => {
    if (!isOpen || isAvanchange || !address || !chain || balance === undefined || !tokenSlug || !accountId) {
      return undefined;
    }

    setIsLoading(true);

    let isCancelled = false;

    const loadUrl = async () => {
      try {
        const chainConfig = getChainConfig(chain);
        let maxAmount: bigint | undefined;

        if (chainConfig.canTransferFullNativeBalance) {
          maxAmount = balance;
        } else {
          const result = await callApi('checkTransactionDraft', chain, {
            accountId,
            toAddress: chainConfig.feeCheckAddress,
            amount: balance,
          });

          if (isCancelled || !isOpenRef.current) return;

          if (result && !('error' in result)) {
            const { fullFee, canTransferFullBalance } = result.explainedFee ?? {
              fullFee: undefined,
              canTransferFullBalance: false,
            };

            maxAmount = getMaxTransferAmount({
              tokenBalance: balance,
              tokenSlug,
              fullFee: fullFee?.terms,
              canTransferFullBalance,
            });
          } else {
            maxAmount = balance;
          }
        }

        if (isCancelled || !isOpenRef.current) return;

        if (maxAmount === undefined || maxAmount === 0n) {
          setError('Insufficient balance');
          setIsLoading(false);
          return;
        }

        const response = await callApi('getMoonpayOfframpUrl', {
          chain,
          address,
          theme: appTheme,
          currency: MOONPAY_CURRENCY,
          amount: toDecimal(maxAmount, tokenDecimals),
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
  }, [accountId, address, appTheme, balance, chain, tokenDecimals, isOpen, isAvanchange, tokenSlug]);

  return { url, error, isLoading };
}
