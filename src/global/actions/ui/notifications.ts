import { MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT } from '../../../config';
import { isKeyCountGreater } from '../../../util/isEmptyObject';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  deleteAllNotificationAccounts,
} from '../../reducers/notifications';
import { selectAccounts } from '../../selectors';
import { selectNotificationAddressesSlow } from '../../selectors/notifications';

addActionHandler('tryAddNotificationAccount', (global, actions, { accountId }) => {
  if (
    global.pushNotifications.isAvailable
    && !isKeyCountGreater(selectAccounts(global) || {}, MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT)
  ) {
    actions.createNotificationAccount({ accountId });
  }
});

addActionHandler('renameNotificationAccount', (global, actions, { accountId }) => {
  const { enabledAccounts, isAvailable } = global.pushNotifications;

  if (isAvailable && enabledAccounts.includes(accountId)) {
    actions.createNotificationAccount({ accountId });
  }
});

addActionHandler('toggleNotificationAccount', (global, actions, { accountId }) => {
  const {
    enabledAccounts, userToken, platform,
  } = global.pushNotifications;

  if (!userToken || !platform) {
    return;
  }

  const doesExist = enabledAccounts.includes(accountId);

  if (!doesExist && enabledAccounts.length >= MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT) {
    return;
  }

  if (doesExist) {
    actions.deleteNotificationAccount({ accountId, withAbort: true });
  } else {
    actions.createNotificationAccount({ accountId, withAbort: true });
  }
});

addActionHandler('deleteAllNotificationAccounts', async (global, actions, props) => {
  const {
    enabledAccounts, userToken,
  } = global.pushNotifications;

  if (!userToken) {
    return;
  }

  const accountIds = props?.accountIds || enabledAccounts;

  await callApi(
    'unsubscribeNotifications',
    {
      userToken,
      addresses: Object.values(selectNotificationAddressesSlow(global, accountIds)).flat(),
    },
  );

  global = getGlobal();
  setGlobal(deleteAllNotificationAccounts(global));
});
