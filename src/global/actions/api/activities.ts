import type { ApiActivity } from '../../../api/types';

import { mergeSortedActivities } from '../../../util/activities/order';
import { getIsTransactionWithPoisoning } from '../../../util/poisoningHash';
import { throttle, waitFor } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { SEC } from '../../../api/constants';
import { getIsTinyOrScamTransaction } from '../../helpers';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { addPastActivities, updateActivity } from '../../reducers';
import {
  selectAccount,
  selectAccountState,
  selectIsHistoryEndReached,
  selectLastActivityTimestamp,
} from '../../selectors';

const PAST_ACTIVITY_DELAY = 200;
const PAST_ACTIVITY_BATCH = 50;

const pastActivityThrottle: Record<string, NoneToVoidFunction> = {};
const initialActivityWaitingByAccountId: Record<string, Promise<unknown>> = {};

addActionHandler('fetchPastActivities', (global, actions, { slug, shouldLoadWithBudget }) => {
  const accountId = global.currentAccountId!;
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

  let fetchedActivities: ApiActivity[] = [];
  let toTimestamp = selectLastActivityTimestamp(global, accountId, slug);
  let shouldFetchMore = true;
  let isEndReached = false;

  while (shouldFetchMore) {
    const result = await callApi('fetchPastActivities', accountId, PAST_ACTIVITY_BATCH, slug, toTimestamp);
    if (!result) {
      return;
    }

    global = getGlobal();

    if (!result.length) {
      isEndReached = true;
      break;
    }

    const { areTinyTransfersHidden } = global.settings;

    const filteredResult = result.filter((tx) => {
      const shouldHide = tx.kind === 'transaction'
        && (
          getIsTransactionWithPoisoning(tx)
          || (areTinyTransfersHidden && getIsTinyOrScamTransaction(tx))
        );

      return !shouldHide;
    });

    fetchedActivities = mergeSortedActivities(fetchedActivities, result);
    shouldFetchMore = filteredResult.length < PAST_ACTIVITY_BATCH && fetchedActivities.length < PAST_ACTIVITY_BATCH;
    toTimestamp = result[result.length - 1].timestamp;
  }

  global = addPastActivities(global, accountId, slug, fetchedActivities, isEndReached);
  setGlobal(global);
}

addActionHandler('fetchActivityDetails', async (global, actions, { id }) => {
  const accountId = global.currentAccountId!;
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
