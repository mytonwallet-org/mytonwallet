import type {
  ApiAnyDisplayError,
  ApiNotificationAddress,
  ApiSubscribeNotificationsProps,
  ApiSubscribeNotificationsResult,
  ApiUnsubscribeNotificationsProps,
} from '../../../api/types';

import { MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT } from '../../../config';
import { createAbortableFunction } from '../../../util/createAbortableFunction';
import isEmptyObject from '../../../util/isEmptyObject';
import { callApi } from '../../../api';
import { isErrorTransferResult } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  createNotificationAccount,
  deleteAllNotificationAccounts,
  deleteNotificationAccount,
} from '../../reducers/notifications';
import { selectAccounts } from '../../selectors';
import { selectNotificationAddressesSlow } from '../../selectors/notifications';

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
  const { langCode } = global.settings;

  let createResult: ApiSubscribeNotificationsResult | { error: ApiAnyDisplayError } | undefined;
  let { enabledAccounts } = pushNotifications;
  const accounts = selectAccounts(global) || {};
  if (!pushNotifications.userToken && !isEmptyObject(accounts)) {
    const notificationAddresses = selectNotificationAddressesSlow(
      global,
      Object.keys(accounts),
      MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT,
    );
    enabledAccounts = Object.keys(notificationAddresses);

    createResult = await callApi('subscribeNotifications', {
      userToken,
      platform,
      langCode,
      addresses: Object.values(notificationAddresses).flat(),
    });
  } else if (pushNotifications.userToken !== userToken && enabledAccounts.length) {
    [createResult] = await Promise.all([
      callApi('subscribeNotifications', {
        userToken,
        platform,
        langCode,
        addresses: Object.values(selectNotificationAddressesSlow(global, enabledAccounts)).flat(),
      }),
      callApi('unsubscribeNotifications', {
        userToken: pushNotifications.userToken!,
        addresses: Object.values(selectNotificationAddressesSlow(global, enabledAccounts)).flat(),
      }),
    ]);
  } else if (pushNotifications.userToken === userToken && enabledAccounts.length) {
    createResult = await callApi('subscribeNotifications', {
      userToken,
      platform,
      langCode,
      addresses: Object.values(selectNotificationAddressesSlow(global, enabledAccounts)).flat(),
    });
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

  if (isErrorTransferResult(createResult)) {
    setGlobal(global);
    return;
  }

  const newEnabledAccounts = enabledAccounts.filter((accountId) => {
    return Object.values(accounts[accountId].byChain).some(({ address }) => address in createResult.addressKeys);
  });

  setGlobal({
    ...global,
    pushNotifications: {
      ...global.pushNotifications,
      enabledAccounts: newEnabledAccounts,
    },
  });
});

addActionHandler('deleteNotificationAccount', async (global, actions, { accountId, withAbort }) => {
  const { userToken } = global.pushNotifications;

  if (!userToken) {
    return;
  }

  setGlobal(deleteNotificationAccount(global, accountId));

  const addresses = Object.values(selectNotificationAddressesSlow(global, [accountId])).flat();
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
    // Unsuccessful - reverting the enabled account deletion
    setGlobal(createNotificationAccount(global, accountId));
    return;
  }

  setGlobal(deleteNotificationAccount(global, accountId));
});

addActionHandler('createNotificationAccount', async (global, actions, { accountId, withAbort }) => {
  const { userToken, platform } = global.pushNotifications;
  const { langCode } = global.settings;

  if (!userToken || !platform) {
    return;
  }

  const addresses = Object.values(selectNotificationAddressesSlow(global, [accountId])).flat();
  if (!addresses.length) {
    return;
  }

  setGlobal(createNotificationAccount(global, accountId));

  const props = {
    userToken,
    platform,
    langCode,
    addresses,
  };
  const result = withAbort
    ? await abortableSubscribeNotifications(props)
    : await callApi('subscribeNotifications', props);

  if (result && 'aborted' in result) {
    return;
  }

  global = getGlobal();

  if (!result || !('ok' in result)) {
    // Unsuccessful - reverting the enabled account addition
    setGlobal(deleteNotificationAccount(
      global,
      accountId,
    ));
  }
});

addActionHandler('toggleNotifications', async (global, actions, { isEnabled }) => {
  const {
    enabledAccounts, userToken, platform, isAvailable,
  } = global.pushNotifications;
  const { langCode } = global.settings;

  if (!isAvailable || !userToken || (isEnabled && !platform)) {
    return;
  }

  let notificationAccounts: Record<string, ApiNotificationAddress[]>;

  if (isEnabled) {
    notificationAccounts = selectNotificationAddressesSlow(
      global,
      Object.keys(selectAccounts(global) || {}),
      MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT,
    );
    for (const newAccountId of Object.keys(notificationAccounts)) {
      global = createNotificationAccount(global, newAccountId);
    }
  } else {
    notificationAccounts = selectNotificationAddressesSlow(global, enabledAccounts);
    global = deleteAllNotificationAccounts(global);
  }

  setGlobal(global);
  if (isEmptyObject(notificationAccounts)) {
    return;
  }

  const addresses = Object.values(notificationAccounts).flat();
  const result = isEnabled
    ? await abortableSubscribeNotifications({
      userToken,
      platform: platform!,
      langCode,
      addresses,
    })
    : await abortableUnsubscribeNotifications({ userToken, addresses });

  if (result && 'aborted' in result) {
    return;
  }

  global = getGlobal();

  if (!result || !('ok' in result)) {
    // Unsuccessful - reverting the enabled account addition/deletion
    if (isEnabled) {
      global = deleteAllNotificationAccounts(global);
    } else {
      for (const accountId of Object.keys(notificationAccounts)) {
        global = createNotificationAccount(global, accountId);
      }
    }
    setGlobal(global);
  }
});
