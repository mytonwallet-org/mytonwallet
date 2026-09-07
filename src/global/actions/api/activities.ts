import type { ApiActivity } from '../../../api/types';

import { getActivityContinuationTimestamp, getIsHiddenNftActivity } from '../../../util/activities';
import { mergeSortedActivities } from '../../../util/activities/order';
import { getIsTransactionWithPoisoning } from '../../../util/poisoningHash';
import { throttle, waitFor } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { SEC } from '../../../api/constants';
import { getIsTinyOrScamTransaction } from '../../helpers';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { addPastActivities, updateActivitiesLoadError, updateActivity } from '../../reducers';
import {
  selectAccount,
  selectAccountState,
  selectCurrentAccountId,
  selectIsHistoryEndReached,
  selectLastActivityTimestamp,
} from '../../selectors';

const PAST_ACTIVITY_DELAY = 200;
const PAST_ACTIVITY_BATCH = 50;

const pastActivityThrottle: Record<string, NoneToVoidFunction> = {};
const initialActivityWaitingByAccountId: Record<string, Promise<unknown>> = {};

addActionHandler('fetchPastActivities', (global, actions, payload) => {
  const accountId = payload.accountId ?? selectCurrentAccountId(global);
  if (!accountId) return;

  const { slug, shouldLoadWithBudget } = payload;
  const throttleKey = `${accountId} ${slug ?? '__main__'}`;

  // Besides the throttling itself, the `throttle` avoids concurrent activity loading
  pastActivityThrottle[throttleKey] ||= throttle(
    fetchPastActivities.bind(undefined, accountId, slug),
    PAST_ACTIVITY_DELAY,
    true,
  );

  pastActivityThrottle[throttleKey]();
  if (shouldLoadWithBudget) {
    pastActivityThrottle[throttleKey]();
  }
});

async function fetchPastActivities(accountId: string, slug?: string) {
  // To avoid gaps in the history, we need to wait until the initial activities are loaded. The worker starts watching
  // for new activities at the moment the initial activities are loaded. This also prevents requesting the activities
  // that the worker is already loading.
  await waitInitialActivityLoading(accountId);

  let global = getGlobal();

  if (selectIsHistoryEndReached(global, accountId, slug)) {
    return;
  }

  // Every call is a fresh attempt, including a retry after a failure, so the list goes back to the
  // loading state instead of keeping the previous failure on screen
  global = updateActivitiesLoadError(global, accountId, slug, false);
  setGlobal(global);

  let fetchedActivities: ApiActivity[] = [];
  let toTimestamp = selectLastActivityTimestamp(global, accountId, slug);
  let hasMore = true;
  let isEndReached = false;

  while (hasMore) {
    const result = await callApi('fetchPastActivities', accountId, PAST_ACTIVITY_BATCH, slug, toTimestamp);
    if (!result) {
      // The request failed and the list stays without ids. The flag tells the list apart from one
      // that is still loading, which would otherwise show a spinner until the screen is reopened.
      setGlobal(updateActivitiesLoadError(getGlobal(), accountId, slug, true));
      return;
    }

    const { activities, hasMore: apiHasMore } = result;

    global = getGlobal();

    if (!activities.length) {
      isEndReached = true;
      break;
    }

    const { areTinyTransfersHidden, areUnverifiedNftsHidden } = global.settings;
    const { blacklistedNftAddresses, whitelistedNftAddresses } = selectAccountState(global, accountId) || {};

    const filteredResult = activities.filter((tx) => {
      if (tx.shouldHide === true) return false;

      const shouldHide = tx.kind === 'transaction'
        && (
          getIsTransactionWithPoisoning(tx)
          || getIsHiddenNftActivity(tx, blacklistedNftAddresses, whitelistedNftAddresses, areUnverifiedNftsHidden)
          || (areTinyTransfersHidden && getIsTinyOrScamTransaction(tx))
        );

      return !shouldHide;
    });

    fetchedActivities = mergeSortedActivities(fetchedActivities, activities);
    hasMore = apiHasMore
      && (
        filteredResult.length < PAST_ACTIVITY_BATCH
        && fetchedActivities.length < PAST_ACTIVITY_BATCH
      );
    const nextTimestamp = getActivityContinuationTimestamp(activities, (activity) => activity);
    // The cursor must move backwards on every iteration. Upstream is asked for activities mined
    // before it, so a page can only push it back; a cursor that fails to move means the next
    // request would repeat this page forever. Stopping defers at most one page - the next trigger
    // resumes from the stored anchor - while spinning here is unbounded.
    if (nextTimestamp === undefined || (toTimestamp !== undefined && nextTimestamp >= toTimestamp)) {
      break;
    }

    toTimestamp = nextTimestamp;
  }

  global = addPastActivities(global, accountId, slug, fetchedActivities, isEndReached);
  setGlobal(global);
}

addActionHandler('fetchActivityDetails', async (global, actions, { id }) => {
  const accountId = selectCurrentAccountId(global)!;
  const activity = selectAccountState(global, accountId)?.activities?.byId[id];

  if (!activity?.shouldLoadDetails) {
    return;
  }

  const newActivity = await callApi('fetchActivityDetails', accountId, activity);

  if (!newActivity) {
    return;
  }

  global = updateActivity(getGlobal(), accountId, newActivity);
  setGlobal(global);
});

function waitInitialActivityLoading(accountId: string) {
  initialActivityWaitingByAccountId[accountId] ||= waitFor(() => {
    const global = getGlobal();

    return !selectAccount(global, accountId) // The account has been removed, the initial activities will never appear
      || selectAccountState(global, accountId)?.activities?.idsMain !== undefined;
  }, SEC, 60);

  return initialActivityWaitingByAccountId[accountId];
}
