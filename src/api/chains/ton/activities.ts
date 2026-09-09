import type {
  ApiActivity,
  ApiDecryptCommentOptions,
  ApiFetchActivitySliceOptions,
  ApiNetwork,
  ApiSwapActivity,
} from '../../types';
import type { AnyAction, CallContractAction, JettonTransferAction } from './toncenter/types';
import type { ParsedAction, ParsedTrace, TraceOutput } from './types';

import { TONCOIN } from '../../../config';
import { pauseWithAbortSignal, raceWithAbortSignal, throwIfAborted } from '../../../util/abortSignal';
import { parseAccountId } from '../../../util/account';
import {
  getActivityTokenSlugs,
  getIsActivityPending,
  getIsBackendSwapId,
  getIsTxIdLocal,
} from '../../../util/activities';
import { mergeSortedActivities } from '../../../util/activities/order';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import { extractKey, findDifference, split } from '../../../util/iteratees';
import { logDebug, logDebugError } from '../../../util/logs';
import withCacheAsync from '../../../util/withCacheAsync';
import { getSigner } from './util/signer';
import { fetchTokenWalletAddress, resolveTokenWalletAddress } from './util/tonCore';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { getTokenBySlug, tokensPreload } from '../../common/tokens';
import { SEC } from '../../constants';
import { OpCode } from './constants';
import { fetchActions, fetchTransactions, isOurSwapFeePayload, parseActionActivityId } from './toncenter';
import { fetchAndParseTrace } from './traces';

const GET_TRANSACTIONS_LIMIT = 128;

const RELOAD_ACTIVITIES_ATTEMPTS = 4;
const RELOAD_ACTIVITIES_PAUSE = SEC;

const TRACE_ATTEMPT_COUNT = 5;
const TRACE_RETRY_DELAY = SEC;

export const checkHasTransaction = withCacheAsync(fetchHasTransaction);

export async function fetchHasTransaction(network: ApiNetwork, address: string, signal?: AbortSignal) {
  const transactions = await fetchTransactions({
    network,
    address,
    limit: 1,
    signal,
  });
  return Boolean(transactions.length);
}

export async function fetchActivitySlice({
  accountId,
  tokenSlug,
  toTimestamp,
  fromTimestamp,
  limit,
  signal,
}: ApiFetchActivitySliceOptions): Promise<ApiActivity[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  let activities: ApiActivity[];

  if (!tokenSlug) {
    activities = await fetchActions({
      network,
      filter: { address },
      walletAddress: address,
      limit: limit ?? GET_TRANSACTIONS_LIMIT,
      fromTimestamp,
      toTimestamp,
      signal,
    });
  } else {
    let tokenWalletAddress = address;

    if (tokenSlug !== TONCOIN.slug) {
      await raceWithAbortSignal(tokensPreload.promise, signal);
      const token = getTokenBySlug(tokenSlug);
      if (!token?.tokenAddress) {
        // Returning [] would make upstream `addPastActivities` set
        // `isHistoryEndReachedBySlug[tokenSlug]=true` and stop polling this slug.
        // Throwing makes `callApi` return undefined - the next cycle retries.
        throw new Error(`fetchActivitySlice: token ${tokenSlug} not in cache`);
      }
      tokenWalletAddress = signal
        ? await fetchTokenWalletAddress(network, address, token.tokenAddress, signal)
        : await resolveTokenWalletAddress(network, address, token.tokenAddress);
    }

    activities = await fetchActions({
      network,
      filter: { address: tokenWalletAddress },
      walletAddress: address,
      limit: limit ?? GET_TRANSACTIONS_LIMIT,
      fromTimestamp,
      toTimestamp,
      signal,
    });

    activities = activities.filter((activity) => getActivityTokenSlugs(activity).includes(tokenSlug));
  }

  return reloadIncompleteActivities(network, address, activities, signal);
}

export async function reloadIncompleteActivities(
  network: ApiNetwork,
  address: string,
  activities: ApiActivity[],
  signal?: AbortSignal,
) {
  try {
    let actionIdsToReload = activities
      .filter((activity) => activity.shouldReload)
      .map((activity) => parseActionActivityId(activity.id).actionId);

    for (let attempt = 0; attempt < RELOAD_ACTIVITIES_ATTEMPTS && actionIdsToReload.length; attempt++) {
      logDebug(`Reload incomplete activities #${attempt + 1}`, actionIdsToReload);
      await pauseWithAbortSignal(RELOAD_ACTIVITIES_PAUSE, signal);

      ({ activities, actionIdsToReload } = await tryReloadIncompleteActivities(
        network,
        address,
        activities,
        actionIdsToReload,
        signal,
      ));
    }
  } catch (err) {
    throwIfAborted(signal);
    logDebugError('reloadIncompleteActivities', err);
  }

  // We want to return the latest modified activities list in case of an error in the above `try { }`
  return activities;
}

async function tryReloadIncompleteActivities(
  network: ApiNetwork,
  address: string,
  activities: ApiActivity[],
  actionIdsToReload: string[],
  signal?: AbortSignal,
) {
  const actionIdBatches = split(actionIdsToReload, GET_TRANSACTIONS_LIMIT);

  const batchResults = await Promise.all(actionIdBatches.map(async (actionIds) => {
    const reloadedActivities = await fetchActions({
      network,
      filter: { actionId: actionIds },
      walletAddress: address,
      limit: GET_TRANSACTIONS_LIMIT,
      signal,
    });
    return reloadedActivities.filter((activity) => !activity.shouldReload);
  }));

  const reloadedActivities = batchResults.flat();

  if (reloadedActivities.length) {
    const replacedIds = new Set(extractKey(reloadedActivities, 'id'));
    const reloadedActionIds = reloadedActivities.map((activity) => parseActionActivityId(activity.id).actionId);

    activities = mergeSortedActivities(
      activities.filter((activity) => !replacedIds.has(activity.id)),
      reloadedActivities,
    );
    actionIdsToReload = findDifference(actionIdsToReload, reloadedActionIds);
  }

  return { activities, actionIdsToReload };
}

export async function decryptComment({ accountId, activity, enclaveToken }: ApiDecryptCommentOptions) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, enclaveToken);
  return signer.decryptComment(Buffer.from(activity.encryptedComment, 'base64'), activity.fromAddress);
}

export async function fetchActivityDetails(
  accountId: string,
  activity: ApiActivity,
  signal?: AbortSignal,
): Promise<ApiActivity | undefined> {
  // A swap summary without chain evidence yet has no trace to read
  if (!activity.externalMsgHashNorm) {
    return { ...activity, shouldLoadDetails: undefined };
  }

  const { network } = parseAccountId(accountId);
  const { address: walletAddress } = await fetchStoredWallet(accountId, 'ton');
  let result: ApiActivity | undefined;

  // The trace can be unavailable immediately after the action is received, so a couple of delayed retries are made
  for (let attempt = 0; attempt < TRACE_ATTEMPT_COUNT && !result; attempt++) {
    if (attempt > 0) {
      await pauseWithAbortSignal(TRACE_RETRY_DELAY, signal);
    }

    const parsedTrace = await fetchAndParseTrace(
      network,
      walletAddress,
      activity.externalMsgHashNorm,
      getIsActivityPending(activity),
      signal,
    );
    if (!parsedTrace) {
      continue;
    }

    result = fillActivityDetails(activity, parsedTrace);
  }

  if (!result) {
    logDebugError('Trace unavailable for activity', activity.id);
  }

  return result ?? activity;
}

export function fillActivityDetails(activity: ApiActivity, parsedTrace: ParsedTrace): ApiActivity {
  const detailed = isSummaryRow(activity)
    ? fillSwapSummaryDetails(activity, parsedTrace)
    : fillActionDetails(activity, parsedTrace);

  return { ...detailed, shouldLoadDetails: undefined };
}

/**
 * A swap summary (a backend or local swap row) stands for the whole trace of the message the wallet signed for the
 * trade: every output of the trace is one of the messages the wallet sent for it, so the summary pays for all of
 * them, whichever actions the history slice it was projected from happened to contain, and whether or not the
 * parser attributes any of the route's legs to the wallet.
 */
function fillSwapSummaryDetails(activity: ApiSwapActivity, parsedTrace: ParsedTrace): ApiSwapActivity {
  const realFee = parsedTrace.traceOutputs.reduce((total, output) => total + output.realFee, 0n);
  const detailed = {
    ...activity,
    networkFee: toDecimal(realFee, TONCOIN.decimals),
    ourFee: getSwapOurFee(activity, parsedTrace.actions),
  };

  logDebug('Calculation of fee for swap summary', {
    id: activity.id,
    externalMsgHashNorm: activity.externalMsgHashNorm,
    activityStatus: activity.status,
    realFee: detailed.networkFee,
    outputs: parsedTrace.traceOutputs.length,
  });

  return detailed;
}

/** A chain activity is one action of its trace and pays for the output of that action */
function fillActionDetails(activity: ApiActivity, parsedTrace: ParsedTrace): ApiActivity {
  const { actionId } = parseActionActivityId(activity.id);
  const { traceOutput, parsedAction } = (actionId && findParsedAction(parsedTrace, actionId)) || {};

  if (!traceOutput || !parsedAction) {
    return activity;
  }

  const { action } = parsedAction;
  const { realFee } = traceOutput;

  if (activity.kind === 'swap') {
    const ourFee = getSwapOurFee(activity, parsedTrace.actions);
    const networkFee = toDecimal(realFee, TONCOIN.decimals);
    activity = { ...activity, ourFee, networkFee };
  } else {
    activity = { ...activity, fee: realFee };
  }

  logDebug('Calculation of fee for action', {
    actionId: action.action_id,
    externalMsgHashNorm: activity.externalMsgHashNorm,
    activityStatus: activity.status,
    networkFee: toDecimal(traceOutput.networkFee),
    realFee: toDecimal(getActivityRealFee(activity)),
    details: action.details,
  });

  return activity;
}

function isSummaryRow(activity: ApiActivity): activity is ApiSwapActivity {
  return activity.kind === 'swap' && (getIsBackendSwapId(activity.id) || getIsTxIdLocal(activity.id));
}

function findParsedAction(parsedTrace: ParsedTrace, actionId: string): {
  traceOutput: TraceOutput;
  parsedAction: ParsedAction;
} | undefined {
  for (const traceOutput of parsedTrace.traceOutputs) {
    for (const parsedAction of traceOutput.walletActions) {
      if (parsedAction.action.action_id === actionId) {
        return { traceOutput, parsedAction };
      }
    }
  }

  return undefined;
}

/** Our fee of a trade is paid in its input token: by a TON call with the fee opcode, or by a marked jetton transfer */
function getSwapOurFee(activity: ApiSwapActivity, actions: AnyAction[]): string {
  let ourFee: bigint | undefined;
  if (activity.from === TONCOIN.slug) {
    const ourFeeAction = actions.find((_action) => {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
      return _action.type === 'call_contract' && Number(_action.details.opcode) === OpCode.OurFee;
    }) as CallContractAction | undefined;
    if (ourFeeAction?.success) {
      ourFee = BigInt(ourFeeAction.details.value);
    }
  } else {
    const ourFeeAction = actions.find((_action) => {
      return _action.type === 'jetton_transfer' && isOurSwapFeePayload(_action.details.forward_payload);
    }) as JettonTransferAction | undefined;
    if (ourFeeAction?.success) {
      ourFee = BigInt(ourFeeAction.details.amount);
    }
  }

  if (ourFee) {
    const tokenIn = getTokenBySlug(activity.from);
    return toDecimal(ourFee, tokenIn?.decimals);
  } else {
    return '0';
  }
}

export function getActivityRealFee(activity: ApiActivity) {
  return activity.kind === 'swap' ? fromDecimal(activity.networkFee, TONCOIN.decimals) : activity.fee;
}
