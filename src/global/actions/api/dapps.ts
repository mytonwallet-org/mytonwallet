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
  const shouldRequireMfa = Boolean(global.accounts?.byId?.[accountId]?.byChain?.ton?.mfa);
  if (!await prepareDappOperation(
    accountId,
    DappConnectState.ConfirmHardware,
    updateDappConnectRequest,
    Boolean(permissions?.isPasswordRequired) || shouldRequireMfa,
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

  if (shouldRequireMfa) {
    actions.switchAccount({ accountId });

    const mfaResult = await callApi('createDappConnectMfaRequest', accountId, password);
    if (!handleDappSignatureResult(mfaResult, updateDappConnectRequest)) {
      return;
    }

    global = getGlobal();
    global = updateDappConnectRequest(global, {
      state: DappConnectState.ConfirmMfa,
      isLoading: false,
      proofSignatures: signingResult.signatures,
      mfaRequestHash: mfaResult.mfaRequestHash,
    });
    setGlobal(global);
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

  if (signedTransactions && typeof signedTransactions === 'object' && 'mfaRequestHash' in signedTransactions) {
    global = getGlobal();
    global = updateCurrentDappTransfer(global, {
      state: TransferState.ConfirmMfa,
      isLoading: false,
      mfaRequestHash: signedTransactions.mfaRequestHash,
    });
    setGlobal(global);

    await callApi('confirmDappRequestSendTransaction', promiseId, {
      mfaRequestHash: signedTransactions.mfaRequestHash,
    });
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

// Clears the placeholder transfer modal (opened by a wake deeplink, no request yet) so a `signData`/`connect`
// event can supersede it.
function clearPlaceholderDappTransfer(global: GlobalState): GlobalState {
  const transfer = global.currentDappTransfer;
  if (transfer.state === TransferState.Initial && transfer.isWaitingForRequest && !transfer.promiseId) {
    return clearCurrentDappTransfer(global);
  }
  return global;
}

addActionHandler('apiUpdateDappLoading', (global, actions, {
  connectionType, isSse, accountId, isWaitingForRequest, returnUrl,
}) => {
  // If the SSE event already opened a request modal (event arrived before the wake deeplink), ignore the placeholder.
  if (isWaitingForRequest && (
    global.currentDappTransfer.state !== TransferState.None
    || global.currentDappSignData.state !== SignDataState.None
    || global.dappConnectRequest?.state !== undefined
  )) {
    return;
  }

  if (accountId) {
    actions.switchAccount({ accountId });
  }

  if (connectionType === 'connect') {
    global = clearPlaceholderDappTransfer(global);
    global = updateDappConnectRequest(global, {
      state: DappConnectState.Info,
      isSse,
    });
  } else if (connectionType === 'sendTransaction') {
    global = updateCurrentDappTransfer(global, {
      state: TransferState.Initial,
      isSse,
      isWaitingForRequest,
      returnUrl,
    });
  } else if (connectionType === 'signData') {
    global = clearPlaceholderDappTransfer(global);
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

addActionHandler('updateDappMfaRequestStatus', async (global) => {
  const hash = global.currentDappTransfer.mfaRequestHash;
  if (!hash) return;
  const result = await callApi('fetchMfaRequest', hash);

  if (result?.isConfirmed) {
    global = getGlobal();
    global = updateCurrentDappTransfer(global, { state: TransferState.Complete });
    setGlobal(global);
  }
});

addActionHandler('updateDappConnectMfaRequestStatus', async (global, actions) => {
  const hash = global.dappConnectRequest?.mfaRequestHash;
  const promiseId = global.dappConnectRequest?.promiseId;
  const accountId = global.dappConnectRequest?.accountId;
  const proofSignatures = global.dappConnectRequest?.proofSignatures;

  if (!hash || !promiseId || !accountId) return;

  const result = await callApi('fetchMfaRequest', hash);
  if (!result?.isConfirmed) return;

  await callApi('confirmDappRequestConnect', promiseId, {
    accountId,
    proofSignatures,
  });

  global = getGlobal();
  global = clearDappConnectRequest(global);
  setGlobal(global);

  await pause(GET_DAPPS_PAUSE);
  actions.getDapps();
});
