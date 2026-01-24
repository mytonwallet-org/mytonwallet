import type { GlobalState } from '../types';

export function deleteNotificationAccount(
  global: GlobalState,
  accountId: string,
): GlobalState {
  const currentEnabledAccounts = global.pushNotifications.enabledAccounts;

  const newEnabledAccounts = currentEnabledAccounts.filter((oldAccountId) => oldAccountId !== accountId);

  return {
    ...global,
    pushNotifications: {
      ...global.pushNotifications,
      enabledAccounts: newEnabledAccounts,
    },
  };
}

export function deleteAllNotificationAccounts(
  global: GlobalState,
): GlobalState {
  return {
    ...global,
    pushNotifications: {
      ...global.pushNotifications,
      enabledAccounts: [],
    },
  };
}

export function createNotificationAccount(global: GlobalState, accountId: string): GlobalState {
  const currentEnabledAccounts = global.pushNotifications.enabledAccounts;

  if (currentEnabledAccounts.includes(accountId)) {
    return global;
  }

  return {
    ...global,
    pushNotifications: {
      ...global.pushNotifications,
      enabledAccounts: [...currentEnabledAccounts, accountId],
    },
  };
}
