import { useEffect, useRef, useState } from '../../../lib/teact/teact';

import type { ApiChain, ApiNetwork } from '../../../api/types';
import type { WalletSuggestion } from '../helpers/utils';

import { logDebugError } from '../../../util/logs';
import { debounce } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { validateAddressForChains } from '../helpers/utils';

import useFlag from '../../../hooks/useFlag';

const CALL_API_DELAY = 200;

export default function useWalletSuggestions(network: ApiNetwork, searchValue: string): [WalletSuggestion[], boolean] {
  const [walletSuggestions, setWalletSuggestions] = useState<WalletSuggestion[]>([]);
  const [isLoading, markIsLoading, unmarkIsLoading] = useFlag(false);
  const requestIdRef = useRef(0);

  // Shared debounced resolver, stable across renders
  const debouncedResolveRef = useRef(
    debounce(async (value: string, network: ApiNetwork, chain: ApiChain, localRequestId: number) => {
      try {
        const result = await callApi('getAddressInfo', chain, network, value);

        if (localRequestId !== requestIdRef.current) return;

        if (!result || 'error' in result || !result.resolvedAddress) {
          setWalletSuggestions([]);

          if (result && 'error' in result) {
            logDebugError('[useWalletSuggestions] Failed to resolve domain', result.error);
          }
          return;
        }

        const resolvedSuggestion: WalletSuggestion = {
          chain,
          address: result.resolvedAddress,
          title: result.addressName,
        };

        setWalletSuggestions([resolvedSuggestion]);
      } catch (err: any) {
        logDebugError('[useWalletSuggestions] Failed to resolve domain', err);
      } finally {
        if (localRequestId === requestIdRef.current) {
          unmarkIsLoading();
        }
      }
    }, CALL_API_DELAY, false),
  );

  useEffect(() => {
    const value = searchValue.trim();

    requestIdRef.current += 1;
    const localRequestId = requestIdRef.current;

    if (!value) {
      setWalletSuggestions([]);
      unmarkIsLoading();

      return () => {
        requestIdRef.current += 1;
      };
    }

    const validationResult = validateAddressForChains(value);
    const result = validationResult.filter(({ isValid }) => isValid);

    if (!result.length) {
      setWalletSuggestions([]);
      unmarkIsLoading();

      return () => {
        requestIdRef.current += 1;
      };
    }

    markIsLoading();
    debouncedResolveRef.current(value, network, result[0].chain, localRequestId);

    return () => {
      requestIdRef.current += 1;
    };
  }, [searchValue, network]);

  return [walletSuggestions, isLoading];
}
