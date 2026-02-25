import { areSortedArraysEqual, unique } from '../../../util/iteratees';
import { addActionHandler } from '../../index';
import { updateAuth, updateSettings } from '../../reducers';
import { selectNetworkAccounts } from '../../selectors';

addActionHandler('openAccountSelector', (global) => {
  global = updateAuth(global, {
    forceAddingTonOnlyAccount: undefined,
    initialAddAccountState: undefined,
    shouldHideAddAccountBackButton: undefined,
  });

  return { ...global, isAccountSelectorOpen: true };
});

addActionHandler('closeAccountSelector', (global) => {
  global = updateAuth(global, {
    forceAddingTonOnlyAccount: undefined,
    initialAddAccountState: undefined,
    shouldHideAddAccountBackButton: undefined,
  });

  return { ...global, isAccountSelectorOpen: undefined };
});

addActionHandler('setAccountSelectorTab', (global, actions, { tab }) => {
  return { ...global, accountSelectorActiveTab: tab };
});

addActionHandler('setAccountSelectorViewMode', (global, actions, { mode }) => {
  return { ...global, accountSelectorViewMode: mode };
});

addActionHandler('rebuildOrderedAccountIds', (global) => {
  const { orderedAccountIds = [] } = global.settings;
  const accounts = selectNetworkAccounts(global);
  const allAccountIds = accounts ? Object.keys(accounts) : [];
  const newOrderedAccountIds = unique([...orderedAccountIds, ...allAccountIds]);

  if (areSortedArraysEqual(orderedAccountIds, newOrderedAccountIds)) {
    return global;
  }

  return updateSettings(global, {
    orderedAccountIds: newOrderedAccountIds,
  });
});

addActionHandler('updateOrderedAccountIds', (global, actions, { orderedAccountIds }) => {
  return updateSettings(global, {
    orderedAccountIds,
  });
});
