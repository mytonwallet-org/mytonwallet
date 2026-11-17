import { useEffect, useRef, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { PerpsTradeState } from '../../../global/types';

import { hasPerpsAmount } from '../../../global/helpers/perps';
import { SECOND } from '../../../util/dateFormat';

import useEffectWithPrevDeps from '../../../hooks/useEffectWithPrevDeps';
import useInterval from '../../../hooks/useInterval';
import useIsInForeground from '../../../hooks/useIsInForeground';
import useLastCallback from '../../../hooks/useLastCallback';

const PREVIEW_DEBOUNCE = 300;
const PREVIEW_REFRESH_INTERVAL = 10 * SECOND;
const MAX_PREVIEW_REFRESH_INTERVAL = 60 * SECOND;

/**
 * Keeps the estimate of the trade form fresh: after each change, then 10 seconds after the previous estimate ends, so
 * a slow estimate is not replaced before it arrives. After a network failure the refresh goes on, and each failure in
 * a row doubles its interval up to a minute. A payment notice or any other error stops the refresh until the form or
 * the Arbitrum balances change, so funds that arrive later clear a lack of them. The estimate also waits while the
 * leverage sheet covers the form.
 *
 * The payment requirements reload when the Arbitrum balances change or the form shows again, for example after the
 * user buys the missing token. This happens only while the form shows a payment notice, a requirements error or an
 * empty form.
 */
export default function usePerpsTradeQuotes(
  trade: PerpsTradeState,
  isActive: boolean,
  usdcBalance: bigint,
  ethBalance: bigint,
  isPaused?: boolean,
  hasFundingBlock?: boolean,
) {
  const { loadPerpsTradePreview, loadPerpsFundingRequirements } = getActions();

  const isInForeground = useIsInForeground();

  const [failureCount, setFailureCount] = useState(0);
  const {
    amount, fraction, leverage, fundingSource, error, fundingError, isPreviewLoading, preview,
  } = trade;
  const isNetworkError = error === 'PerpsUnavailable';
  const shouldQuote = isActive && isInForeground && !isPaused;
  const shouldRefresh = shouldQuote && !isPreviewLoading && !hasFundingBlock && !fundingError
    && (!error || isNetworkError);

  // A new payment source is a choice from a menu, so its quote does not wait for more typing
  const prevFundingSourceRef = useRef(fundingSource);
  useEffect(() => {
    if (!shouldQuote) return undefined;

    const isFundingChange = prevFundingSourceRef.current !== fundingSource;
    prevFundingSourceRef.current = fundingSource;

    const timeout = window.setTimeout(loadPerpsTradePreview, isFundingChange ? 0 : PREVIEW_DEBOUNCE);
    return () => window.clearTimeout(timeout);
  }, [shouldQuote, amount, fraction, leverage, fundingSource, usdcBalance, ethBalance, loadPerpsTradePreview]);

  // Each finished request sets the next interval: a network failure doubles it, and any other result restores 10
  // seconds. A repeated error leaves `error` unchanged, so the end of the request is what counts as a failure.
  useEffectWithPrevDeps(([prevIsPreviewLoading]) => {
    if (!prevIsPreviewLoading || isPreviewLoading) return;

    setFailureCount((count) => (isNetworkError ? count + 1 : 0));
  }, [isPreviewLoading, isNetworkError]);

  const refreshInterval = Math.min(PREVIEW_REFRESH_INTERVAL * 2 ** failureCount, MAX_PREVIEW_REFRESH_INTERVAL);
  useInterval(loadPerpsTradePreview, shouldRefresh ? refreshInterval : undefined, true);

  // The trade loads its requirements when it starts, so the first render does not load them again
  const isEmptyForm = !preview && !isPreviewLoading && !hasPerpsAmount(amount);
  const reloadFundingRequirements = useLastCallback(() => {
    if (hasFundingBlock || fundingError || isEmptyForm) loadPerpsFundingRequirements();
  });

  useEffectWithPrevDeps(([prevIsActive]) => {
    if (prevIsActive !== undefined && isActive) reloadFundingRequirements();
  }, [isActive, usdcBalance, ethBalance, reloadFundingRequirements]);
}
