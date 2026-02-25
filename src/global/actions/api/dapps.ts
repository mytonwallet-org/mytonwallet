import type { GlobalState } from '../../types';
import { DappConnectState, SignDataState, TransferState } from '../../types';

import { ANIMATION_END_DELAY } from '../../../config';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { getDoesUsePinPad } from '../../../util/biometrics';
import { getDappConnectionUniqueId } from '../../../util/getDappConnectionUniqueId';
import { pause } from '../../../util/schedulers';
import { USER_AGENT_LANG_CODE } from '../../../util/windowEnvironment';
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
import { selectCurrentAccountId } from '../../selectors';
import { switchAccount } from './auth';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

import { CLOSE_DURATION, CLOSE_DURATION_PORTRAIT } from '../../../components/ui/Modal';

const GET_DAPPS_PAUSE = 250;

addActionHandler('submitDappConnectRequestConfirm', async (global, actions, { password, accountId }) => {
  const {
    promiseId, permissions, proof, dapp,
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
    ? await callApi(
      'signDappProof',
      dapp.chains,
      accountId,
      { ...proof, type: 'tonProof' },
      password,
    )
    : { signatures: undefined };

  if (!handleDappSignatureResult(signingResult, updateDappConnectRequest)) {
    return;
  }

  actions.switchAccount({ accountId });

  await callApi('confirmDappRequestConnect', promiseId!, {
    accountId,
    proofSignatures: signingResult.signatures,
  });

  global = getGlobal();
  global = clearDappConnectRequest(global);
  setGlobal(global);

  await pause(GET_DAPPS_PAUSE);
  actions.getDapps();
});

addActionHandler('cancelDappConnectRequestConfirm', (global) => {
  cancelDappOperation(
    (global) => global.dappConnectRequest,
    clearDappConnectRequest,
  );
});

addActionHandler('setDappConnectRequestState', (global, actions, { state }) => {
  setGlobal(updateDappConnectRequest(global, { state }));
});

addActionHandler('cancelDappTransfer', (global) => {
  cancelDappOperation(
    (global) => global.currentDappTransfer,
    clearCurrentDappTransfer,
  );
});

function cancelDappOperation(
  getState: (global: GlobalState) => { promiseId?: string } | undefined,
  clearState: (global: GlobalState) => GlobalState,
) {
  let global = getGlobal();
  const { promiseId } = getState(global) ?? {};

  if (promiseId) {
    void callApi('cancelDappRequest', promiseId, 'Canceled by the user');
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
    selectCurrentAccountId(global)!,
    TransferState.ConfirmHardware,
    updateCurrentDappTransfer,
    true,
    password,
  )) {
    return;
  }

  global = getGlobal();
  const { transactions, validUntil, vestingAddress, operationChain, dapp, isLegacyOutput } = global.currentDappTransfer;
  const currentChain = dapp?.chains?.find((e) => e.chain === operationChain);
  if (!currentChain) {
    return;
  }
  const accountId = selectCurrentAccountId(global)!;

  const signedTransactions = await callApi(
    'signDappTransfers',
    currentChain,
    accountId,
    transactions!,
    {
      password,
      validUntil,
      vestingAddress,
      isLegacyOutput,
    });

  if (!handleDappSignatureResult(signedTransactions, updateCurrentDappTransfer)) {
    return;
  }

  await callApi('confirmDappRequestSendTransaction', promiseId, signedTransactions);
});

addActionHandler('submitDappSignData', async (global, actions, { password } = {}) => {
  const { promiseId } = global.currentDappSignData;
  if (!promiseId) {
    return;
  }

  if (!await prepareDappOperation(
    selectCurrentAccountId(global)!,
    0 as never, // Ledger doesn't support SignData yet, so this value is never used
    updateCurrentDappSignData,
    true,
    password,
  )) {
    return;
  }

  global = getGlobal();
  const { dapp, payloadToSign, operationChain } = global.currentDappSignData;
  const currentChain = dapp?.chains?.find((e) => e.chain === operationChain);
  if (!currentChain) {
    return;
  }
  const accountId = selectCurrentAccountId(global)!;

  const signedData = await callApi(
    'signDappData',
    currentChain,
    accountId,
    dapp!.url,
    payloadToSign!,
    password,
  );

  if (!handleDappSignatureResult(signedData, updateCurrentDappSignData)) {
    return;
  }

  await callApi('confirmDappRequestSignData', promiseId, signedData);
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

  void callApi('deleteDapp', currentAccountId!, url, uniqueId);

  global = getGlobal();
  global = removeConnectedDapp(global, url);
  setGlobal(global);
});

addActionHandler('cancelDappSignData', (global) => {
  cancelDappOperation(
    (global) => global.currentDappSignData,
    clearCurrentDappSignData,
  );
});

addActionHandler('apiUpdateDappConnect', (global, actions, {
  accountId, dapp, permissions, promiseId, proof,
}) => {
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
  const {
    promiseId,
    transactions,
    emulation,
    dapp,
    validUntil,
    vestingAddress,
    operationChain,
    shouldHideTransfers,
    isLegacyOutput,
  } = payload;

  await apiUpdateDappOperation(
    payload,
    (global) => global.currentDappTransfer,
    actions.closeDappTransfer,
    (global) => global.currentDappTransfer.state !== TransferState.None,
    clearCurrentDappTransfer,
    (global) => updateCurrentDappTransfer(global, {
      state: TransferState.Initial,
      operationChain,
      promiseId,
      transactions,
      emulation,
      dapp,
      validUntil,
      vestingAddress,
      shouldHideTransfers,
      isLegacyOutput,
    }),
  );
});

addActionHandler('apiUpdateDappSignData', async (global, actions, payload) => {
  const { promiseId, dapp, payloadToSign, operationChain } = payload;

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
      operationChain,
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

  if (currentPromiseId) {
    close();
    const closeDuration = getIsPortrait() ? CLOSE_DURATION_PORTRAIT : CLOSE_DURATION;
    await pause(closeDuration + ANIMATION_END_DELAY);
  }

  global = getGlobal();
  global = clearState(global);
  global = updateState(global);
  setGlobal(global);
}

addActionHandler('apiUpdateDappLoading', (global, actions, { connectionType, isSse, accountId }) => {
  if (accountId) {
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

addActionHandler('apiUpdateDappCloseLoading', (global, actions, { connectionType }) => {
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

addActionHandler('loadExploreSites', async (global, _, { isLandscape, langCode = USER_AGENT_LANG_CODE }) => {
  const exploreData = await callApi('loadExploreSites', { isLandscape, langCode });
  global = getGlobal();
  if (areDeepEqual(exploreData, global.exploreData)) {
    return;
  }

  global = { ...global, exploreData };
  setGlobal(global);
});
