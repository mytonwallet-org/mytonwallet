import type {
  ApiActivity,
  ApiDecryptCommentOptions,
  ApiFetchActivitySliceOptions,
  ApiNetwork,
  ApiSwapActivity,
} from '../../types';
import type { AnyAction, CallContractAction, JettonTransferAction, SwapAction } from './toncenter/types';
import type { ParsedAction, ParsedTrace, TraceOutput } from './types';

import { TONCOIN } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { getActivityTokenSlugs, getIsActivityPending } from '../../../util/activities';
import { mergeSortedActivities } from '../../../util/activities/order';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import { extractKey, findDifference, split } from '../../../util/iteratees';
import { logDebug, logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import withCacheAsync from '../../../util/withCacheAsync';
import { getSigner } from './util/signer';
import { resolveTokenWalletAddress } from './util/tonCore';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { getTokenBySlug, tokensPreload } from '../../common/tokens';
import { SEC } from '../../constants';
import { OpCode, OUR_FEE_PAYLOAD_BOC } from './constants';
import { fetchActions, fetchTransactions, parseActionActivityId } from './toncenter';
import { fetchAndParseTrace } from './traces';

const GET_TRANSACTIONS_LIMIT = 128;

const RELOAD_ACTIVITIES_ATTEMPTS = 4;
const RELOAD_ACTIVITIES_PAUSE = SEC;

const TRACE_ATTEMPT_COUNT = 5;
const TRACE_RETRY_DELAY = SEC;

export const checkHasTransaction = withCacheAsync(async (network: ApiNetwork, address: string) => {
  const transactions = await fetchTransactions({
    network,
    address,
    limit: 1,
  });
  return Boolean(transactions.length);
});

export async function fetchActivitySlice({
  accountId,
  tokenSlug,
  toTimestamp,
  fromTimestamp,
  limit,
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
    });
  } else {
    let tokenWalletAddress = address;

    if (tokenSlug !== TONCOIN.slug) {
      await tokensPreload.promise;
      tokenWalletAddress = await resolveTokenWalletAddress(network, address, getTokenBySlug(tokenSlug)!.tokenAddress!);
    }

    activities = await fetchActions({
      network,
      filter: { address: tokenWalletAddress },
      walletAddress: address,
      limit: limit ?? GET_TRANSACTIONS_LIMIT,
      fromTimestamp,
      toTimestamp,
    });

    activities = activities.filter((activity) => getActivityTokenSlugs(activity).includes(tokenSlug));
  }

  return reloadIncompleteActivities(network, address, activities);
}

export async function reloadIncompleteActivities(network: ApiNetwork, address: string, activities: ApiActivity[]) {
  try {
    let actionIdsToReload = activities
      .filter((activity) => activity.shouldReload)
      .map((activity) => parseActionActivityId(activity.id).actionId);

    for (let attempt = 0; attempt < RELOAD_ACTIVITIES_ATTEMPTS && actionIdsToReload.length; attempt++) {
      logDebug(`Reload incomplete activities #${attempt + 1}`, actionIdsToReload);
      await pause(RELOAD_ACTIVITIES_PAUSE);

      ({ activities, actionIdsToReload } = await tryReloadIncompleteActivities(
        network,
        address,
        activities,
        actionIdsToReload,
      ));
    }
  } catch (err) {
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
) {
  const actionIdBatches = split(actionIdsToReload, GET_TRANSACTIONS_LIMIT);

  const batchResults = await Promise.all(actionIdBatches.map(async (actionIds) => {
    const reloadedActivities = await fetchActions({
      network,
      filter: { actionId: actionIds },
      walletAddress: address,
      limit: GET_TRANSACTIONS_LIMIT,
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

export async function decryptComment({ accountId, activity, password }: ApiDecryptCommentOptions) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, password);
  return signer.decryptComment(Buffer.from(activity.encryptedComment, 'base64'), activity.fromAddress);
}

export async function fetchActivityDetails(
  accountId: string,
  activity: ApiActivity,
): Promise<ApiActivity | undefined> {
  const { network } = parseAccountId(accountId);
  const { address: walletAddress } = await fetchStoredWallet(accountId, 'ton');
  let result: ApiActivity | undefined;

  // The trace can be unavailable immediately after the action is received, so a couple of delayed retries are made
  for (let attempt = 0; attempt < TRACE_ATTEMPT_COUNT && !result; attempt++) {
    if (attempt > 0) {
      await pause(TRACE_RETRY_DELAY);
    }

    const parsedTrace = await fetchAndParseTrace(
      network,
      walletAddress,
      activity.externalMsgHashNorm!,
      getIsActivityPending(activity),
    );
    if (!parsedTrace) {
      continue;
    }

    activity = fillActivityDetails(activity, parsedTrace);
  }

  if (!result) {
    logDebugError('Trace unavailable for activity', activity.id);
  }

  return activity;
}

export function fillActivityDetails(activity: ApiActivity, parsedTrace: ParsedTrace): ApiActivity {
  const { actionId } = parseActionActivityId(activity.id);
  const { traceOutput, parsedAction } = findParsedAction(parsedTrace, actionId) ?? {};

  if (!traceOutput || !parsedAction) {
    return { ...activity, shouldLoadDetails: undefined };
  }

  const { action } = parsedAction;
  const { realFee } = traceOutput;

  if (activity.kind === 'swap') {
    const ourFee = getSwapOurFee(activity, parsedTrace.actions, action as SwapAction);
    const networkFee = toDecimal(realFee, TONCOIN.decimals);
    activity = { ...activity, ourFee, networkFee };
  } else {
    activity = { ...activity, fee: realFee };
  }

  activity = { ...activity, shouldLoadDetails: undefined };

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

function getSwapOurFee(activity: ApiSwapActivity, actions: AnyAction[], action: SwapAction): string {
  let ourFee: bigint | undefined;
  if (!action.details.asset_in) {
    const ourFeeAction = actions.find((_action) => {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
      return _action.type === 'call_contract' && Number(_action.details.opcode) === OpCode.OurFee;
    }) as CallContractAction | undefined;
    if (ourFeeAction?.success) {
      ourFee = BigInt(ourFeeAction.details.value);
    }
  } else {
    const ourFeeAction = actions.find((_action) => {
      return _action.type === 'jetton_transfer' && _action.details.forward_payload === OUR_FEE_PAYLOAD_BOC;
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
