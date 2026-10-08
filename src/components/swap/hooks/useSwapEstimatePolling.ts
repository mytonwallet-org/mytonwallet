import { useEffect, useRef } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { GlobalState } from '../../../global/types';

import { getSwapEstimateInputKey } from '../../../global/helpers/swap';

import { isBackgroundModeActive } from '../../../hooks/useBackgroundMode';
import useLastCallback from '../../../hooks/useLastCallback';

const ESTIMATE_REQUEST_INTERVAL = 1_000;
/** The longest gap a run of failing estimates can stretch the refresh to, in intervals */
const MAX_ESTIMATE_BACKOFF_TICKS = 32;

/**
 * Keeps the swap quote fresh while the form is on screen: estimates as soon as the form asks for it and
 * refreshes the quote every second after that.
 */
export default function useSwapEstimatePolling(currentSwap: GlobalState['currentSwap'], isActive?: boolean) {
  const { estimateSwap } = getActions();
  const { errorType, isEstimating } = currentSwap;

  // A form nobody is looking at has no quote to keep fresh, and an estimate already in flight is a
  // reason to hold rather than to start another one.
  const canRequestEstimate = useLastCallback(() => isActive && !isBackgroundModeActive());

  const handleEstimateSwap = useLastCallback(() => {
    if (!canRequestEstimate()) return;

    estimateSwap();
  });

  // The refresh exists to follow a moving market, which a failing estimate is not doing: a pair with
  // no route or an amount the network fee already exceeds answers the same way however often it is
  // asked. Repeated failures therefore stretch the gap between attempts instead of holding at one a
  // second, while a success returns to the full rate. Backing off rather than stopping is what keeps
  // the form alive - the estimate always resumes on its own, even if nothing here notices why it
  // started failing.
  const failedAttemptsRef = useRef(0);
  const ticksSinceAttemptRef = useRef(0);

  // The backoff belongs to one question. The moment the form starts asking a different one - a token,
  // an amount, the slippage, the maximum toggle - the failures that earned it say nothing about the
  // answer, so the rate returns to full.
  const estimateInputKey = getSwapEstimateInputKey(currentSwap);

  useEffect(() => {
    failedAttemptsRef.current = 0;
    ticksSinceAttemptRef.current = 0;
  }, [estimateInputKey]);

  const handleEstimateSwapTick = useLastCallback(() => {
    // A tick that cannot send anything must not count either, or a form left in the background would
    // come back owing the whole backoff for attempts it never made.
    if (!canRequestEstimate()) return;

    // An attempt still unsettled a whole tick later did not produce a quote either. That covers the
    // case the form cannot show: a rate-limited estimate returns no error and leaves the request
    // loading, so counting only `errorType` would let exactly the rate we are being asked to lower
    // continue at full speed.
    const hasLastAttemptFailed = errorType !== undefined || isEstimating;

    if (!hasLastAttemptFailed) {
      failedAttemptsRef.current = 0;
    }

    ticksSinceAttemptRef.current += 1;
    const ticksToWait = Math.min(2 ** failedAttemptsRef.current, MAX_ESTIMATE_BACKOFF_TICKS);
    if (ticksSinceAttemptRef.current < ticksToWait) return;

    ticksSinceAttemptRef.current = 0;
    if (hasLastAttemptFailed) {
      failedAttemptsRef.current += 1;
    }

    handleEstimateSwap();
  });

  // `isActive` is a dependency so that a form that becomes visible with an estimate already requested
  // (the Buy / Sell screen leaving the fiat mode) does not wait for the next tick
  useEffect(() => {
    if (isEstimating) {
      handleEstimateSwap();
    }

    const intervalId = setInterval(handleEstimateSwapTick, ESTIMATE_REQUEST_INTERVAL);
    return () => clearInterval(intervalId);
  }, [isEstimating, isActive]);
}
