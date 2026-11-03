import { useEffect, useState } from '../../lib/teact/teact';

import type { ApiPerpsPositionSide, ApiPerpsQuote } from '../../api/types';

import { callApiWithThrow } from '../../api';
import { PERPS_CCTP_FORWARD_FEE_USDC } from '../../api/common/perps';

import { isBackgroundModeActive } from '../../hooks/useBackgroundMode';

const ESTIMATE_REQUEST_INTERVAL = 1_000;
/** The longest gap a run of failing estimates can stretch the refresh to, in intervals. */
const MAX_ESTIMATE_BACKOFF_TICKS = 32;
/** The USDC field settles before the first quote. */
const ESTIMATE_INPUT_DEBOUNCE = 500;

type EstimateInput = {
  isActive: boolean;
  accountId?: string;
  asset: string;
  side: ApiPerpsPositionSide;
  depositAmount: string;
  leverage: number;
};

export default function usePerpsOpenEstimate({
  isActive,
  accountId,
  asset,
  side,
  depositAmount,
  leverage,
}: EstimateInput) {
  const [estimate, setEstimate] = useState<ApiPerpsQuote | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [isEstimating, setIsEstimating] = useState(false);

  const assetId = asset.trim();
  const deposit = Number(depositAmount);
  const canEstimate = Boolean(
    isActive
    && accountId
    && assetId
    && Number.isFinite(deposit)
    && deposit > PERPS_CCTP_FORWARD_FEE_USDC
    && Number.isFinite(leverage)
    && leverage >= 1,
  );

  useEffect(() => {
    if (!canEstimate || !accountId) {
      setEstimate(undefined);
      setError(undefined);
      setIsEstimating(false);
      return undefined;
    }

    const request = {
      kind: 'open' as const,
      assetId,
      side,
      depositAmount,
      leverage,
    };

    let stopped = false;
    let inFlight = false;
    let lastFailed = false;
    let failedAttempts = 0;
    let ticksSinceAttempt = 0;
    let intervalId: number | undefined;

    setEstimate(undefined);
    setError(undefined);
    setIsEstimating(false);

    const requestEstimate = async () => {
      if (stopped || inFlight || isBackgroundModeActive()) return;

      inFlight = true;
      setIsEstimating(true);
      try {
        const result = await callApiWithThrow('perpsPreviewOrder', accountId, request);
        if (stopped) return;

        if (!result) {
          lastFailed = true;
          setError('Estimate unavailable.');
          return;
        }

        lastFailed = false;
        failedAttempts = 0;
        setEstimate(result);
        setError(undefined);
      } catch (err) {
        if (!stopped) {
          lastFailed = true;
          setError(err instanceof Error ? err.message : String(err));
        }
      } finally {
        inFlight = false;
        if (!stopped) setIsEstimating(false);
      }
    };

    const handleTick = () => {
      if (stopped || isBackgroundModeActive()) return;

      if (inFlight) {
        lastFailed = true;
      }
      if (!lastFailed) {
        failedAttempts = 0;
      }

      ticksSinceAttempt += 1;
      const ticksToWait = Math.min(2 ** failedAttempts, MAX_ESTIMATE_BACKOFF_TICKS);
      if (ticksSinceAttempt < ticksToWait) return;

      ticksSinceAttempt = 0;
      if (lastFailed || inFlight) {
        failedAttempts += 1;
      }
      void requestEstimate();
    };

    const debounceId = window.setTimeout(() => {
      void requestEstimate();
      intervalId = window.setInterval(handleTick, ESTIMATE_REQUEST_INTERVAL);
    }, ESTIMATE_INPUT_DEBOUNCE);

    return () => {
      stopped = true;
      window.clearTimeout(debounceId);
      if (intervalId !== undefined) window.clearInterval(intervalId);
    };
  }, [canEstimate, accountId, assetId, side, depositAmount, leverage]);

  return { estimate, error, isEstimating };
}
