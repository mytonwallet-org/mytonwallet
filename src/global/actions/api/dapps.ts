import type { ApiDappConnectionType } from '../../../api/types';
import type { GlobalState } from '../../types';
import { DappConnectState, SignDataState, TransferState } from '../../types';

import { ANIMATION_END_DELAY } from '../../../config';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { getDoesUsePinPad } from '../../../util/biometrics';
import { getDappConnectionUniqueId } from '../../../util/getDappConnectionUniqueId';
import { callActionInMain, callApiInMain } from '../../../util/multitab';
import { pause, waitFor } from '../../../util/schedulers';
import { IS_DELEGATED_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { handleDappSignatureResult, prepareDappOperation } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  clearConnectedDapps,
  clearCurrentDappSignData,
  clearCurrentDappTransfer,
  clearDappConnectRequest,
  clearIsPinAccepted,
  removeConnectedDapp,
  updateConnectedDapps,
  updateCurrentDappSignData,
  updateCurrentDappTransfer,
  updateDappConnectRequest,
} from '../../reducers';
import { selectIsHardwareAccount } from '../../selectors';
import { switchAccount } from './auth';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

import { CLOSE_DURATION, CLOSE_DURATION_PORTRAIT } from '../../../components/ui/Modal';

const GET_DAPPS_PAUSE = 250;

addActionHandler('submitDappConnectRequestConfirm', async (global, actions, { password, accountId }) => {
  const {
    promiseId, permissions, proof,
  } = global.dappConnectRequest!;

  if (!await prepareDappOperation(
    accountId,
    DappConnectState.ConfirmHardware,
    updateDappConnectRequest,
    !!permissions?.isPasswordRequired,
    password,
  )) {
    return;
  }

  const signingResult = proof
    ? await callApi('signTonProof', accountId, proof, password)
    : { signature: undefined };

  if (!handleDappSignatureResult(signingResult, updateDappConnectRequest)) {
    return;
  }

  actions.switchAccount({ accountId });

  // It's important to call the API methods including promiseId in the main window, because the Bottom Sheet window
  // knows nothing about that promiseId.
  await callApiInMain('confirmDappRequestConnect', promiseId!, {
    accountId,
    proofSignature: signingResult.signature,
  });

  global = getGlobal();
  global = clearDappConnectRequest(global);
  setGlobal(global);

  await pause(GET_DAPPS_PAUSE);
  actions.getDapps();
});

addActionHandler('cancelDappConnectRequestConfirm', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('clearDappConnectRequestConfirm');
  }

  cancelDappOperation(
    (global) => global.dappConnectRequest,
    clearDappConnectRequest,
  );
});

// Clear state after closing the NBS modal.
// TODO: Remove after fully migrating to Air app.
addActionHandler('clearDappConnectRequestConfirm', (global) => {
  return clearDappConnectRequest(global);
});

addActionHandler('setDappConnectRequestState', (global, actions, { state }) => {
  setGlobal(updateDappConnectRequest(global, { state }));
});

addActionHandler('cancelDappTransfer', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('clearDappTransfer');
  }

  cancelDappOperation(
    (global) => global.currentDappTransfer,
    clearCurrentDappTransfer,
  );
});

// Clear state after closing the NBS modal.
// TODO: Remove after fully migrating to Air app.
addActionHandler('clearDappTransfer', (global) => {
  return clearCurrentDappTransfer(global);
});

function cancelDappOperation(
  getState: (global: GlobalState) => { promiseId?: string } | undefined,
  clearState: (global: GlobalState) => GlobalState,
) {
  let global = getGlobal();
  const { promiseId } = getState(global) ?? {};

  if (promiseId) {
    void callApiInMain('cancelDappRequest', promiseId, 'Canceled by the user');
  }

  if (getDoesUsePinPad()) {
    global = clearIsPinAccepted(global);
  }
  global = clearState(global);
  setGlobal(global);
}

addActionHandler('submitDappTransfer', async (global, actions, { password } = {}) => {
  const { promiseId } = global.currentDappTransfer;
  if (!promiseId) {
    return;
  }

  if (!await prepareDappOperation(
    global.currentAccountId!,
    TransferState.ConfirmHardware,
    updateCurrentDappTransfer,
    true,
    password,
  )) {
    return;
  }

  global = getGlobal();
  const { transactions, validUntil, vestingAddress } = global.currentDappTransfer;
  const accountId = global.currentAccountId!;
  const signedTransactions = await callApi('signTransfers', accountId, transactions!, {
    password,
    validUntil,
    vestingAddress,
  });

  if (!handleDappSignatureResult(signedTransactions, updateCurrentDappTransfer)) {
    return;
  }

  await callApiInMain('confirmDappRequestSendTransaction', promiseId, signedTransactions);
});

addActionHandler('submitDappSignData', async (global, actions, { password } = {}) => {
  const { promiseId } = global.currentDappSignData;
  if (!promiseId) {
    return;
  }

  if (!await prepareDappOperation(
    global.currentAccountId!,
    0 as never, // Ledger doesn't support SignData yet, so this value is never used
    updateCurrentDappSignData,
    true,
    password,
  )) {
    return;
  }

  global = getGlobal();
  const { dapp, payloadToSign } = global.currentDappSignData;
  const accountId = global.currentAccountId!;
  const signedData = await callApi('signData', accountId, dapp!.url, payloadToSign!, password);

  if (!handleDappSignatureResult(signedData, updateCurrentDappSignData)) {
    return;
  }

  await callApiInMain('confirmDappRequestSignData', promiseId, signedData);
});

addActionHandler('getDapps', async (global, actions) => {
  const { currentAccountId } = global;

  let result = await callApi('getDapps', currentAccountId!);

  if (!result) {
    return;
  }

  // Check for broken dapps without URL
  const brokenDapp = result.find(({ url }) => !url);
  if (brokenDapp) {
    actions.deleteDapp({ url: brokenDapp.url, uniqueId: getDappConnectionUniqueId(brokenDapp) });
    result = result.filter(({ url }) => url);
  }

  global = getGlobal();
  global = updateConnectedDapps(global, result);
  setGlobal(global);
});

addActionHandler('deleteAllDapps', (global) => {
  const { currentAccountId } = global;

  void callApi('deleteAllDapps', currentAccountId!);

  global = getGlobal();
  global = clearConnectedDapps(global);
  setGlobal(global);
});

addActionHandler('deleteDapp', (global, actions, { url, uniqueId }) => {
  const { currentAccountId } = global;

  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('deleteDapp', { url, uniqueId });
  } else {
    void callApi('deleteDapp', currentAccountId!, url, uniqueId);
  }

  global = getGlobal();
  global = removeConnectedDapp(global, url);
  setGlobal(global);
});

addActionHandler('cancelDappSignData', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('clearDappSignData');
  }

  cancelDappOperation(
    (global) => global.currentDappSignData,
    clearCurrentDappSignData,
  );
});

// Clear state after closing the NBS modal.
// TODO: Remove after fully migrating to Air app.
addActionHandler('clearDappSignData', (global) => {
  return clearCurrentDappSignData(global);
});

addActionHandler('apiUpdateDappConnect', async (global, actions, {
  accountId, dapp, permissions, promiseId, proof,
}) => {
  // We only need to apply changes in NBS when Dapp Connect Modal is already open
  if (IS_DELEGATED_BOTTOM_SHEET) {
    if (!(await waitFor(() => Boolean(getGlobal().dappConnectRequest), 300, 5))) {
      return;
    }

    global = getGlobal();
  }

  global = updateDappConnectRequest(global, {
    state: DappConnectState.Info,
    promiseId,
    accountId,
    dapp,
    permissions: {
      isAddressRequired: permissions.address,
      isPasswordRequired: permissions.proof,
    },
    proof,
  });
  setGlobal(global);

  actions.addSiteToBrowserHistory({ url: dapp.url });
});

addActionHandler('apiUpdateDappSendTransaction', async (global, actions, payload) => {
  const { promiseId, transactions, emulation, dapp, validUntil, vestingAddress } = payload;

  await apiUpdateDappOperation(
    payload,
    (global) => global.currentDappTransfer,
    actions.closeDappTransfer,
    (global) => global.currentDappTransfer.state !== TransferState.None,
    clearCurrentDappTransfer,
    (global) => updateCurrentDappTransfer(global, {
      state: selectIsHardwareAccount(global) && transactions.length > 1
        ? TransferState.WarningHardware
        : TransferState.Initial,
      promiseId,
      transactions,
      emulation,
      dapp,
      validUntil,
      vestingAddress,
    }),
  );
});

addActionHandler('apiUpdateDappSignData', async (global, actions, payload) => {
  const { promiseId, dapp, payloadToSign } = payload;

  await apiUpdateDappOperation(
    payload,
    (global) => global.currentDappSignData,
    actions.closeDappSignData,
    (global) => global.currentDappSignData.state !== SignDataState.None,
    clearCurrentDappSignData,
    (global) => updateCurrentDappSignData(global, {
      state: SignDataState.Initial,
      promiseId,
      dapp,
      payloadToSign,
    }),
  );
});

async function apiUpdateDappOperation(
  payload: { accountId: string },
  getState: (global: GlobalState) => { promiseId?: string },
  close: NoneToVoidFunction,
  isStateActive: (global: GlobalState) => boolean,
  clearState: (global: GlobalState) => GlobalState,
  updateState: (global: GlobalState) => GlobalState,
) {
  let global = getGlobal();

  const { accountId } = payload;
  const { promiseId: currentPromiseId } = getState(global);

  await switchAccount(global, accountId);

  if (currentPromiseId && !IS_DELEGATED_BOTTOM_SHEET) {
    close();
    const closeDuration = getIsPortrait() ? CLOSE_DURATION_PORTRAIT : CLOSE_DURATION;
    await pause(closeDuration + ANIMATION_END_DELAY);
  }

  // We only need to apply changes in NBS when dapp operation modal is already open
  if (IS_DELEGATED_BOTTOM_SHEET) {
    if (!(await waitFor(() => isStateActive(getGlobal()), 300, 5))) {
      return;
    }
  }

  global = getGlobal();
  global = clearState(global);
  global = updateState(global);
  setGlobal(global);
}

addActionHandler('apiUpdateDappLoading', async (global, actions, { connectionType, isSse, accountId }) => {
  // We only need to apply changes in NBS when Dapp Connect Modal is already open
  if (IS_DELEGATED_BOTTOM_SHEET) {
    if (!(await waitFor(() => isAnyDappModalActive(getGlobal(), connectionType), 300, 5))) {
      return;
    }

    global = getGlobal();
  }

  if (!IS_DELEGATED_BOTTOM_SHEET && accountId) {
    actions.switchAccount({ accountId });
  }

  if (connectionType === 'connect') {
    global = updateDappConnectRequest(global, {
      state: DappConnectState.Info,
      isSse,
    });
  } else if (connectionType === 'sendTransaction') {
    global = updateCurrentDappTransfer(global, {
      state: TransferState.Initial,
      isSse,
    });
  } else if (connectionType === 'signData') {
    global = updateCurrentDappSignData(global, {
      state: SignDataState.Initial,
      isSse,
    });
  }
  setGlobal(global);
});

addActionHandler('apiUpdateDappCloseLoading', async (global, actions, { connectionType }) => {
  // We only need to apply changes in NBS when Dapp Modal is already open
  if (IS_DELEGATED_BOTTOM_SHEET) {
    if (!(await waitFor(() => isAnyDappModalActive(getGlobal(), connectionType), 300, 5))) {
      return;
    }

    global = getGlobal();
  }

  // But clear the state if a skeleton is displayed in the Modal
  if (connectionType === 'connect' && global.dappConnectRequest?.state === DappConnectState.Info) {
    global = clearDappConnectRequest(global);
  } else if (connectionType === 'sendTransaction' && global.currentDappTransfer.state === TransferState.Initial) {
    global = clearCurrentDappTransfer(global);
  } else if (connectionType === 'signData' && global.currentDappSignData.state === SignDataState.Initial) {
    global = clearCurrentDappSignData(global);
  }
  setGlobal(global);
});

addActionHandler('loadExploreSites', async (global, _, { isLandscape }) => {
  const exploreData = await callApi('loadExploreSites', { isLandscape });
  global = getGlobal();
  if (areDeepEqual(exploreData, global.exploreData)) {
    return;
  }

  global = { ...global, exploreData };
  setGlobal(global);
});

function isAnyDappModalActive(global: GlobalState, connectionType: ApiDappConnectionType) {
  return (connectionType === 'connect' && !!global.dappConnectRequest)
    || (connectionType === 'sendTransaction' && global.currentDappTransfer.state !== TransferState.None)
    || (connectionType === 'signData' && global.currentDappSignData.state !== SignDataState.None);
}
