import { areSortedArraysEqual, unique } from '../../../util/iteratees';
import { callActionInMain } from '../../../util/multitab';
import { IS_DELEGATED_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { addActionHandler } from '../../index';
import { updateSettings } from '../../reducers';
import { selectNetworkAccounts } from '../../selectors';

addActionHandler('openAccountSelector', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openAccountSelector');
    return global;
  }
  return { ...global, isAccountSelectorOpen: true };
});

addActionHandler('closeAccountSelector', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('closeAccountSelector');
  }

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
