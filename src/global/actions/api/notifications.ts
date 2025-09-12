import type {
  ApiNotificationAddress,
  ApiNotificationsAccountValue,
  ApiSubscribeNotificationsProps,
  ApiSubscribeNotificationsResult,
  ApiUnsubscribeNotificationsProps,
} from '../../../api/types';

import { MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT } from '../../../config';
import { createAbortableFunction } from '../../../util/createAbortableFunction';
import isEmptyObject from '../../../util/isEmptyObject';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  createNotificationAccount,
  deleteAllNotificationAccounts,
  deleteNotificationAccount,
  updateNotificationAccount,
} from '../../reducers/notifications';
import { selectAccounts } from '../../selectors';
import { selectNotificationTonAddressesSlow } from '../../selectors/notifications';

const abortableSubscribeNotifications = createAbortableFunction(
  { aborted: true },
  (request: ApiSubscribeNotificationsProps) => {
    return callApi('subscribeNotifications', request);
  },
);

const abortableUnsubscribeNotifications = createAbortableFunction(
  { aborted: true },
  (request: ApiUnsubscribeNotificationsProps) => {
    return callApi('unsubscribeNotifications', request);
  },
);

addActionHandler('registerNotifications', async (global, actions, { userToken, platform }) => {
  const { pushNotifications } = global;

  let createResult;
  let enabledAccounts = Object.keys(pushNotifications.enabledAccounts);
  const accounts = selectAccounts(global) || {};
  if (!pushNotifications.userToken && !isEmptyObject(accounts)) {
    const notificationAddresses = selectNotificationTonAddressesSlow(
      global,
      Object.keys(accounts),
      MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT,
    );
    enabledAccounts = Object.keys(notificationAddresses);

    createResult = await callApi('subscribeNotifications', {
      userToken,
      platform,
      addresses: Object.values(notificationAddresses),
    });
  } else if (pushNotifications.userToken !== userToken && enabledAccounts.length) {
    [createResult] = await Promise.all([
      callApi('subscribeNotifications', {
        userToken,
        platform,
        addresses: Object.values(selectNotificationTonAddressesSlow(global, enabledAccounts)),
      }),
      callApi('unsubscribeNotifications', {
        userToken: pushNotifications.userToken!,
        addresses: Object.values(selectNotificationTonAddressesSlow(global, enabledAccounts)),
      }),
    ]);
  }

  global = getGlobal();
  global = {
    ...global,
    pushNotifications: {
      ...global.pushNotifications,
      userToken,
      platform,
    },
  };

  if (!createResult || 'error' in createResult) {
    setGlobal(global);
    return;
  }

  const newEnabledAccounts = enabledAccounts.reduce((acc, accountId) => {
    const tonAddress = accounts[accountId].byChain.ton?.address;
    if (tonAddress) {
      acc[accountId] = createResult.addressKeys[tonAddress];
    }

    return acc;
  }, {} as Record<string, ApiNotificationsAccountValue>);

  setGlobal({
    ...global,
    pushNotifications: {
      ...global.pushNotifications,
      enabledAccounts: newEnabledAccounts,
    },
  });
});

addActionHandler('deleteNotificationAccount', async (global, actions, { accountId, withAbort }) => {
  const { userToken, enabledAccounts } = global.pushNotifications;
  const pushNotificationsAccount = enabledAccounts[accountId];

  if (!userToken) {
    return;
  }

  setGlobal(deleteNotificationAccount(global, accountId));

  const addresses = Object.values(selectNotificationTonAddressesSlow(global, [accountId]));
  if (addresses.length === 0) {
    return;
  }

  const props = { userToken, addresses };
  const result = withAbort
    ? await abortableUnsubscribeNotifications(props)
    : await callApi('unsubscribeNotifications', props);

  if (result && 'aborted' in result) {
    return;
  }

  global = getGlobal();

  if (!result || !('ok' in result)) {
    setGlobal(createNotificationAccount(
      global,
      accountId,
      pushNotificationsAccount,
    ));
    return;
  }

  setGlobal(deleteNotificationAccount(global, accountId));
});

addActionHandler('createNotificationAccount', async (global, actions, { accountId, withAbort }) => {
  const { userToken, platform } = global.pushNotifications;

  if (!userToken || !platform) {
    return;
  }

  const addresses = Object.values(selectNotificationTonAddressesSlow(global, [accountId]));
  if (!addresses.length) {
    return;
  }

  setGlobal(createNotificationAccount(
    global,
    accountId,
    {},
  ));

  const props = { userToken, platform, addresses };
  const result = withAbort
    ? await abortableSubscribeNotifications(props)
    : await callApi('subscribeNotifications', props);

  if (result && 'aborted' in result) {
    return;
  }

  global = getGlobal();

  if (!result || !('ok' in result)) {
    setGlobal(deleteNotificationAccount(
      global,
      accountId,
    ));
    return;
  }

  setGlobal(updateNotificationAccount(
    global,
    accountId,
    result.addressKeys[addresses[0].address],
  ));
});

addActionHandler('toggleNotifications', async (global, actions, { isEnabled }) => {
  const {
    enabledAccounts = {}, userToken = '', platform, isAvailable,
  } = global.pushNotifications;

  if (!isAvailable) {
    return;
  }

  let notificationAccounts: Record<string, ApiNotificationAddress>;

  if (isEnabled) {
    notificationAccounts = selectNotificationTonAddressesSlow(
      global,
      Object.keys(selectAccounts(global) || {}),
      MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT,
    );
    for (const newAccountId of Object.keys(notificationAccounts)) {
      global = createNotificationAccount(global, newAccountId, {});
    }
  } else {
    notificationAccounts = selectNotificationTonAddressesSlow(global, Object.keys(enabledAccounts));
    global = deleteAllNotificationAccounts(global);
  }

  setGlobal(global);
  if (isEmptyObject(notificationAccounts)) {
    return;
  }

  const props = { userToken, addresses: Object.values(notificationAccounts), platform: platform! };
  const result = isEnabled
    ? await abortableSubscribeNotifications(props)
    : await abortableUnsubscribeNotifications(props);

  if (result && 'aborted' in result) {
    return;
  }

  global = getGlobal();

  if (!result || !('ok' in result)) {
    if (isEnabled) {
      global = deleteAllNotificationAccounts(global);
    } else {
      for (const accountId of Object.keys(notificationAccounts)) {
        global = createNotificationAccount(global, accountId, enabledAccounts[accountId]);
      }
    }
    setGlobal(global);
    return;
  }

  if (isEnabled && 'addressKeys' in result) {
    const addressKeys = (result as ApiSubscribeNotificationsResult).addressKeys;
    for (const [accountId, { address }] of Object.entries(notificationAccounts)) {
      if (addressKeys[address]) {
        global = createNotificationAccount(global, accountId, addressKeys[address]);
      }
    }
  }

  setGlobal(global);
});
