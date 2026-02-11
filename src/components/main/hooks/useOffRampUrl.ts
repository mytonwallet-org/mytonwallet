import { useEffect, useRef, useState } from '../../../lib/teact/teact';

import type { ApiBaseCurrency, ApiChain, ApiToken } from '../../../api/types';
import type { Theme } from '../../../global/types';

import { SELF_UNIVERSAL_HOST_URL } from '../../../config';
import { getChainConfig } from '../../../util/chain';
import { toDecimal } from '../../../util/decimals';
import { explainApiTransferFee, getMaxTransferAmount } from '../../../util/fee/transferFee';
import { callApi } from '../../../api';

const SUPPORTED_CURRENCIES: ApiBaseCurrency[] = ['EUR'];

interface UseOffRampUrlParams {
  isOpen: boolean;
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

  useEffect(() => {
    if (!isOpen) {
      setUrl(undefined);
      setError(undefined);
      setIsLoading(true);
    }
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen || !address || !chain || balance === undefined || !tokenSlug || !accountId) return undefined;

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
            const { fullFee, canTransferFullBalance } = explainApiTransferFee({
              ...result,
              tokenSlug,
            });
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
          currency: SUPPORTED_CURRENCIES[0],
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
  }, [accountId, address, appTheme, balance, chain, tokenDecimals, isOpen, tokenSlug]);

  return { url, error, isLoading };
}
