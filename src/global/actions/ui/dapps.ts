import { SignDataState, TransferState } from '../../types';

import { BROWSER_HISTORY_LIMIT } from '../../../config';
import { unique } from '../../../util/iteratees';
import { addActionHandler, setGlobal } from '../../index';
import {
  clearDappConnectRequestError,
  resetHardware,
  updateCurrentAccountState,
  updateCurrentDappSignData,
  updateCurrentDappTransfer,
} from '../../reducers';
import {
  selectCurrentAccountState,
  selectEnclaveToken,
  selectIsEnclaveSessionValid,
  selectIsHardwareAccount,
} from '../../selectors';

addActionHandler('clearDappConnectRequestError', (global) => {
  global = clearDappConnectRequestError(global);
  setGlobal(global);
});

addActionHandler('showDappTransferTransaction', (global, actions, payload) => {
  const { transactionIdx } = payload;

  global = updateCurrentDappTransfer(global, {
    state: TransferState.Confirm,
    viewTransactionOnIdx: transactionIdx,
  });
  setGlobal(global);
});

addActionHandler('setDappTransferScreen', (global, actions, payload) => {
  const { state } = payload;

  global = updateCurrentDappTransfer(global, { state });
  setGlobal(global);
});

addActionHandler('submitDappTransferConfirm', (global, actions) => {
  if (selectIsHardwareAccount(global)) {
    global = resetHardware(global, 'ton');
    global = updateCurrentDappTransfer(global, { state: TransferState.ConnectHardware });
  } else if (selectIsEnclaveSessionValid(global)) {
    global = updateCurrentDappTransfer(global, { isLoading: true });
    actions.submitDappTransfer({ enclaveToken: selectEnclaveToken(global) });
  } else {
    global = updateCurrentDappTransfer(global, { state: TransferState.Password });
  }

  return global;
});

addActionHandler('clearDappTransferError', (global) => {
  global = updateCurrentDappTransfer(global, {
    error: undefined,
  });
  setGlobal(global);
});

addActionHandler('openBrowser', (global, actions, { url, title, subtitle }) => {
  global = {
    ...global,
    currentBrowserOptions: {
      url, title, subtitle,
    },
  };
  setGlobal(global);
});

addActionHandler('closeBrowser', (global) => {
  global = {
    ...global,
    currentBrowserOptions: undefined,
  };
  setGlobal(global);
});

addActionHandler('addSiteToBrowserHistory', (global, actions, { url }) => {
  const accountState = selectCurrentAccountState(global);

  const newHistory = unique([
    url,
    ...accountState?.browserHistory || [],
  ]).slice(0, BROWSER_HISTORY_LIMIT);

  global = updateCurrentAccountState(global, {
    browserHistory: newHistory,
  });
  setGlobal(global);
});

addActionHandler('removeSiteFromBrowserHistory', (global, actions, { url }) => {
  const accountState = selectCurrentAccountState(global);

  const newHistory = accountState?.browserHistory?.filter((currentUrl) => currentUrl !== url);

  global = updateCurrentAccountState(global, {
    browserHistory: newHistory?.length ? newHistory : undefined,
  });
  setGlobal(global);
});

addActionHandler('updateDappLastOpenedAt', (global, actions, { url }) => {
  const { dappLastOpenedDatesByUrl } = selectCurrentAccountState(global)!;

  const newDates = {
    ...dappLastOpenedDatesByUrl,
    [url]: Date.now(),
  };

  global = updateCurrentAccountState(global, { dappLastOpenedDatesByUrl: newDates });
  setGlobal(global);
});

addActionHandler('openSiteCategory', (global, actions, { id }) => {
  return updateCurrentAccountState(global, { currentSiteCategoryId: id });
});

addActionHandler('closeSiteCategory', (global) => {
  return updateCurrentAccountState(global, { currentSiteCategoryId: undefined });
});

addActionHandler('closeDappTransfer', (global) => {
  global = updateCurrentDappTransfer(global, { state: TransferState.None });
  setGlobal(global);
});

addActionHandler('setDappSignDataScreen', (global, actions, payload) => {
  const { state } = payload;

  return updateCurrentDappSignData(global, { state });
});

addActionHandler('submitDappSignDataConfirm', (global, actions) => {
  if (selectIsEnclaveSessionValid(global)) {
    global = updateCurrentDappSignData(global, { isLoading: true });
    actions.submitDappSignData({ enclaveToken: selectEnclaveToken(global) });
  } else {
    global = updateCurrentDappSignData(global, { state: SignDataState.Password });
  }

  return global;
});

addActionHandler('clearDappSignDataError', (global) => {
  return updateCurrentDappSignData(global, { error: undefined });
});

addActionHandler('closeDappSignData', (global) => {
  return updateCurrentDappSignData(global, { state: SignDataState.None });
});
