import { useEffect, useState } from '../../lib/teact/teact';

import type { ApiPerpsQuote } from '../../api/types';

import { callApiWithThrow } from '../../api';
import { PERPS_CCTP_FORWARD_FEE_USDC } from '../../api/common/perps';

import { isBackgroundModeActive } from '../../hooks/useBackgroundMode';

const ESTIMATE_REQUEST_INTERVAL = 1_000;
/** The longest gap a run of failing estimates can stretch the refresh to, in intervals. */
const MAX_ESTIMATE_BACKOFF_TICKS = 32;
/** The USDC field settles before the first quote. */
const ESTIMATE_INPUT_DEBOUNCE = 500;

type ModifyEstimateInput = {
  isActive: boolean;
  accountId?: string;
  asset: string;
  depositAmount: string;
  leverage: number;
  maxLeverage?: number;
};

type EstimateChannel<T> = {
  value?: T;
  error?: string;
};

function readPositionEstimate(
  result: ApiPerpsQuote | { error: string } | undefined,
): EstimateChannel<ApiPerpsQuote> & { transportFailed: boolean } {
  if (!result) return { error: 'Estimate unavailable.', transportFailed: true };
  if ('error' in result) return { error: result.error, transportFailed: false };
  return { value: result, transportFailed: false };
}

export default function usePerpsModifyEstimate({
  isActive,
  accountId,
  asset,
  depositAmount,
  leverage,
  maxLeverage,
}: ModifyEstimateInput) {
  const [add, setAdd] = useState<EstimateChannel<ApiPerpsQuote>>({});
  const [reduce, setReduce] = useState<EstimateChannel<ApiPerpsQuote>>({});
  const [leverageDeposit, setLeverageDeposit] = useState<EstimateChannel<ApiPerpsQuote>>({});
  const [isEstimating, setIsEstimating] = useState(false);

  const assetId = asset.trim();
  const deposit = Number(depositAmount);
  const canEstimateSize = Boolean(
    isActive
    && accountId
    && assetId
    && Number.isFinite(deposit)
    && deposit > PERPS_CCTP_FORWARD_FEE_USDC,
  );
  const canEstimateLeverage = Boolean(
    isActive
    && accountId
    && assetId
    && Number.isInteger(leverage)
    && leverage >= 1
    && (maxLeverage === undefined || leverage <= maxLeverage),
  );

  useEffect(() => {
    if ((!canEstimateSize && !canEstimateLeverage) || !accountId) {
      setAdd({});
      setReduce({});
      setLeverageDeposit({});
      setIsEstimating(false);
      return undefined;
    }

    const wallet = accountId;
    let stopped = false;
    let inFlight = false;
    let lastFailed = false;
    let failedAttempts = 0;
    let ticksSinceAttempt = 0;
    let intervalId: number | undefined;

    setAdd({});
    setReduce({});
    setLeverageDeposit({});
    setIsEstimating(false);

    const requestEstimate = async () => {
      if (stopped || inFlight || isBackgroundModeActive()) return;

      inFlight = true;
      setIsEstimating(true);
      let transportFailed = false;
      try {
        const jobs: Promise<void>[] = [];
        if (canEstimateSize) {
          jobs.push(loadSizeEstimate(false));
          jobs.push(loadSizeEstimate(true));
        }
        if (canEstimateLeverage) jobs.push(loadLeverageEstimate());
        await Promise.all(jobs);
        lastFailed = transportFailed;
        if (!transportFailed) failedAttempts = 0;
      } finally {
        inFlight = false;
        if (!stopped) setIsEstimating(false);
      }

      async function loadSizeEstimate(reduceOnly: boolean) {
        let result: ApiPerpsQuote | { error: string } | undefined;
        try {
          result = await callApiWithThrow('perpsPreviewOrder', wallet, {
            kind: reduceOnly ? 'reduce' : 'increase',
            assetId,
            amount: depositAmount,
          });
        } catch (err) {
          result = { error: err instanceof Error ? err.message : String(err) };
          transportFailed = true;
        }
        if (stopped) return;

        const channel = readPositionEstimate(result);
        transportFailed = channel.transportFailed || transportFailed;
        const setChannel = reduceOnly ? setReduce : setAdd;
        setChannel({ value: channel.value, error: channel.error });
      }

      async function loadLeverageEstimate() {
        let result: ApiPerpsQuote | undefined;
        try {
          result = await callApiWithThrow('perpsPreviewOrder', wallet, { kind: 'leverage', assetId, leverage });
        } catch (err) {
          transportFailed = true;
          if (!stopped) setLeverageDeposit({ error: err instanceof Error ? err.message : String(err) });
          return;
        }
        if (stopped) return;

        if (!result) {
          transportFailed = true;
          setLeverageDeposit({ error: 'Estimate unavailable.' });
          return;
        }
        setLeverageDeposit({ value: result });
      }
    };

    const handleTick = () => {
      if (stopped || isBackgroundModeActive()) return;

      if (inFlight) lastFailed = true;
      if (!lastFailed) failedAttempts = 0;

      ticksSinceAttempt += 1;
      const ticksToWait = Math.min(2 ** failedAttempts, MAX_ESTIMATE_BACKOFF_TICKS);
      if (ticksSinceAttempt < ticksToWait) return;

      ticksSinceAttempt = 0;
      if (lastFailed || inFlight) failedAttempts += 1;
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
  }, [accountId, assetId, canEstimateLeverage, canEstimateSize, depositAmount, leverage]);

  return {
    add: add.value,
    addError: add.error,
    reduce: reduce.value,
    reduceError: reduce.error,
    leverageDeposit: leverageDeposit.value?.paymentAmount,
    leverageEstimate: leverageDeposit.value,
    leverageError: leverageDeposit.error,
    isEstimating,
  };
}
