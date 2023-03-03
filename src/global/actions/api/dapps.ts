import { addActionHandler, getGlobal, setGlobal } from '../../index';

import { callApi } from '../../../api';
import {
  clearConnectedDapps,
  clearCurrentDappTransfer,
  clearDappConnectRequest,
  removeConnectedDapp,
  updateConnectedDapps,
  updateCurrentDappTransfer,
  updateDappConnectRequest,
} from '../../reducers';

addActionHandler('submitDappConnectRequestConfirm', async (global, actions, payload) => {
  const { password, additionalAccountIds } = payload;
  const { promiseId, permissions } = global.dappConnectRequest!;

  if (permissions?.isPasswordRequired && (!password || !(await callApi('verifyPassword', password)))) {
    global = getGlobal();
    setGlobal(updateDappConnectRequest(global, { error: 'Wrong password, please try again' }));

    return;
  }

  void callApi('confirmDappRequestConnect', promiseId!, password, additionalAccountIds);

  global = getGlobal();
  global = clearDappConnectRequest(global);
  setGlobal(global);
});

addActionHandler('cancelDappConnectRequestConfirm', (global) => {
  const { promiseId } = global.dappConnectRequest || {};

  if (!promiseId) {
    return;
  }

  void callApi('cancelDappRequest', promiseId!, 'Canceled by the user');

  global = getGlobal();
  global = clearDappConnectRequest(global);
  setGlobal(global);
});

addActionHandler('cancelDappTransfer', (global) => {
  const { promiseId } = global.currentDappTransfer;

  if (promiseId) {
    void callApi('cancelDappRequest', promiseId, 'Canceled by the user');
  }

  setGlobal(clearCurrentDappTransfer(global));
});

addActionHandler('submitDappTransferPassword', async (global, actions, payload) => {
  const { password } = payload;
  const { promiseId } = global.currentDappTransfer;

  if (!promiseId) {
    return;
  }

  if (!(await callApi('verifyPassword', password))) {
    global = getGlobal();
    global = updateCurrentDappTransfer(global, {
      error: 'Wrong password, please try again',
    });
    setGlobal(global);

    return;
  }

  global = getGlobal();
  global = updateCurrentDappTransfer(global, {
    isLoading: true,
    error: undefined,
  });
  setGlobal(global);

  void callApi('confirmDappRequest', promiseId, password);

  global = getGlobal();
  global = clearCurrentDappTransfer(global);
  setGlobal(global);
});

addActionHandler('getDapps', async (global) => {
  const { currentAccountId } = global;

  const result = await callApi('getDapps', currentAccountId!);

  if (!result) {
    return;
  }

  global = getGlobal();
  global = updateConnectedDapps(global, { dapps: result });
  setGlobal(global);
});

addActionHandler('deleteAllDapps', (global) => {
  const { currentAccountId } = global;

  void callApi('deleteAllDapps', currentAccountId!);

  global = getGlobal();
  global = clearConnectedDapps(global);
  setGlobal(global);
});

addActionHandler('deleteDapp', (global, actions, payload) => {
  const { currentAccountId } = global;
  const { origin } = payload;

  void callApi('deleteDapp', currentAccountId!, origin);

  global = getGlobal();
  global = removeConnectedDapp(global, origin);
  setGlobal(global);
});
