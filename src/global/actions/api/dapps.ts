import type { TonConnectEventName } from '../../../api/dappProtocols/adapters/tonConnect/analytics';
import type { GlobalState } from '../../types';
import { DappConnectState, SignDataState, TransferState } from '../../types';

import { ANIMATION_END_DELAY } from '../../../config';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { getDoesUsePinPad } from '../../../util/biometrics';
import { getDappConnectionUniqueId } from '../../../util/getDappConnectionUniqueId';
import { getTranslation } from '../../../util/langProvider';
import { pause } from '../../../util/schedulers';
import { USER_AGENT_LANG_CODE } from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { requestAbortDappConnectWalletCreation } from '../../helpers/abortDappConnectWalletCreation';
import { withEnclaveSessionRelease } from '../../helpers/enclave';
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
import { getIsAccountSwitchCurrent, switchAccount } from './auth';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

import { CLOSE_DURATION, CLOSE_DURATION_PORTRAIT } from '../../../components/ui/Modal';

const GET_DAPPS_PAUSE = 250;

// Reports a TON Connect UI event (modal shown / approved / rejected) for a real request; the worker enriches it
// from the flow context by `promiseId`. No-op for the speculative placeholder, which has no `promiseId`.
function recordTonConnectUiEvent(eventName: TonConnectEventName, promiseId?: string) {
  if (!promiseId) {
    return;
  }

  void callApi('recordTonConnectEvent', { event_name: eventName, promiseId });
}

addActionHandler('submitDappConnectRequestConfirm', withEnclaveSessionRelease(async (
  global, actions, { enclaveToken, accountId },
) => {
  const {
    promiseId, permissions, proof, dapp,
  } = global.dappConnectRequest!;

  recordTonConnectUiEvent('wallet-connect-accepted', promiseId);
  if (!prepareDappOperation(
    accountId,
    DappConnectState.ConfirmHardware,
    updateDappConnectRequest,
    Boolean(permissions?.isPasswordRequired),
  )) {
    return;
  }

  const signingResult = proof
    ? await callApi(
      'signDappProof',
      dapp.chains,
      accountId,
      { ...proof, type: 'tonProof' },
      enclaveToken,
    )
    : { signatures: undefined, publicKeys: undefined };

  if (!handleDappSignatureResult(signingResult, updateDappConnectRequest)) {
    return;
  }

  actions.switchAccount({ accountId });

  await callApi('confirmDappRequestConnect', promiseId!, {
    accountId,
    proofSignatures: signingResult.signatures,
    proofPublicKeys: signingResult.publicKeys,
  });

  global = getGlobal();
  global = clearDappConnectRequest(global);
  setGlobal(global);

  await pause(GET_DAPPS_PAUSE);
  actions.getDapps();
}));

addActionHandler('cancelDappConnectRequestConfirm', (global, actions, payload) => {
  const { promiseId, isCreatingAccount } = global.dappConnectRequest ?? {};
  if (isCreatingAccount && (!payload?.promiseId || payload.promiseId === promiseId)) {
    requestAbortDappConnectWalletCreation();
  }

  recordTonConnectUiEvent('wallet-connect-rejected', payload?.promiseId ?? global.dappConnectRequest?.promiseId);
  cancelDappOperation(
    (global) => global.dappConnectRequest,
    clearDappConnectRequest,
    payload?.promiseId,
  );
});

addActionHandler('setDappConnectRequestState', (global, actions, { state }) => {
  setGlobal(updateDappConnectRequest(global, { state }));
});

addActionHandler('cancelDappTransfer', (global, actions, payload) => {
  recordTonConnectUiEvent('wallet-transaction-declined', payload?.promiseId ?? global.currentDappTransfer.promiseId);
  cancelDappOperation(
    (global) => global.currentDappTransfer,
    clearCurrentDappTransfer,
    payload?.promiseId,
  );
});

/**
 * Rejects `promiseIdToCancel`, or the request in the state when none is given. The state is cleared only when it still
 * holds the rejected request: a late close animation of a replaced request must not take down the one replacing it.
 */
function cancelDappOperation(
  getState: (global: GlobalState) => { promiseId?: string } | undefined,
  clearState: (global: GlobalState) => GlobalState,
  promiseIdToCancel?: string,
) {
  let global = getGlobal();
  const { promiseId: currentPromiseId } = getState(global) ?? {};
  const promiseId = promiseIdToCancel ?? currentPromiseId;

  if (promiseId) {
    void callApi('cancelDappRequest', promiseId, 'Canceled by the user');
  }

  // The state holds another request, or a skeleton for one that is still loading
  if (promiseIdToCancel && promiseIdToCancel !== currentPromiseId) {
    return;
  }

  if (getDoesUsePinPad()) {
    global = clearIsPinAccepted(global);
  }
  global = clearState(global);
  setGlobal(global);
}

addActionHandler('submitDappTransfer', withEnclaveSessionRelease(async (global, actions, payload) => {
  const { enclaveToken } = payload ?? {};
  const { promiseId } = global.currentDappTransfer;
  if (!promiseId) {
    return;
  }

  recordTonConnectUiEvent('wallet-transaction-accepted', promiseId);

  if (!prepareDappOperation(
    selectCurrentAccountId(global)!,
    TransferState.ConfirmHardware,
    updateCurrentDappTransfer,
    true,
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
      enclaveToken,
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
}));

addActionHandler('submitDappSignData', withEnclaveSessionRelease(async (global, actions, payload) => {
  const { enclaveToken } = payload ?? {};
  const { promiseId } = global.currentDappSignData;
  if (!promiseId) {
    return;
  }

  recordTonConnectUiEvent('wallet-sign-data-accepted', promiseId);

  if (!prepareDappOperation(
    selectCurrentAccountId(global)!,
    0 as never, // Ledger doesn't support SignData yet, so this value is never used
    updateCurrentDappSignData,
    true,
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
    enclaveToken,
  );

  if (!handleDappSignatureResult(signedData, updateCurrentDappSignData)) {
    return;
  }

  await callApi('confirmDappRequestSignData', promiseId, signedData);
}));

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

addActionHandler('cancelDappSignData', (global, actions, payload) => {
  recordTonConnectUiEvent('wallet-sign-data-declined', payload?.promiseId ?? global.currentDappSignData.promiseId);
  cancelDappOperation(
    (global) => global.currentDappSignData,
    clearCurrentDappSignData,
    payload?.promiseId,
  );
});

addActionHandler('apiUpdateDappConnect', (global, actions, {
  accountId, dapp, permissions, promiseId, proof, multichainResolution,
}) => {
  // A newer connect request takes the modal over; the dapp that sent the open one gets a rejection instead of waiting
  const previousPromiseId = global.dappConnectRequest?.promiseId;
  if (previousPromiseId && previousPromiseId !== promiseId) {
    // A wallet being created for the replaced request must not be saved or activated under the new one
    if (global.dappConnectRequest?.isCreatingAccount) {
      requestAbortDappConnectWalletCreation();
    }
    void callApi('cancelDappRequest', previousPromiseId, 'Canceled by the user');
    global = clearDappConnectRequest(global);
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
    multichainResolution,
  });
  setGlobal(global);

  recordTonConnectUiEvent('wallet-connect-request-ui-displayed', promiseId);
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

  const isInstalled = await apiUpdateDappOperation(
    payload,
    (global) => global.currentDappTransfer,
    actions.closeDappTransfer,
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

  if (isInstalled) recordTonConnectUiEvent('wallet-transaction-confirmation-ui-displayed', promiseId);
});

addActionHandler('apiUpdateDappSignData', async (global, actions, payload) => {
  const { promiseId, dapp, payloadToSign, operationChain, parsedPayloadToSign } = payload;

  const isInstalled = await apiUpdateDappOperation(
    payload,
    (global) => global.currentDappSignData,
    actions.closeDappSignData,
    clearCurrentDappSignData,
    (global) => updateCurrentDappSignData(global, {
      state: SignDataState.Initial,
      promiseId,
      dapp,
      operationChain,
      payloadToSign,
      parsedPayloadToSign,
    }),
  );

  if (isInstalled) recordTonConnectUiEvent('wallet-sign-data-confirmation-ui-displayed', promiseId);
});

// Requests replace one another one at a time, in arrival order: each reads the request the previous one installed,
// so every replaced request is rejected, including one that arrived while another was still being switched to
let dappOperationQueue: Promise<unknown> = Promise.resolve();

function apiUpdateDappOperation(...args: Parameters<typeof replaceDappOperation>) {
  const operation = dappOperationQueue.then(() => replaceDappOperation(...args));
  dappOperationQueue = operation.catch(() => undefined);
  return operation;
}

async function replaceDappOperation(
  payload: { accountId: string; promiseId: string },
  getState: (global: GlobalState) => { promiseId?: string },
  close: NoneToVoidFunction,
  clearState: (global: GlobalState) => GlobalState,
  updateState: (global: GlobalState) => GlobalState,
) {
  let global = getGlobal();

  const { accountId } = payload;
  const { promiseId: currentPromiseId } = getState(global);

  const switchId = await switchAccount(global, accountId);

  if (currentPromiseId && getIsAccountSwitchCurrent(switchId)) {
    close();
    // Rejected here rather than by the modal's close animation, which never ends if the new request renders first
    void callApi('cancelDappRequest', currentPromiseId, 'Canceled by the user');
    const closeDuration = getIsPortrait() ? CLOSE_DURATION_PORTRAIT : CLOSE_DURATION;
    await pause(closeDuration + ANIMATION_END_DELAY);
  }

  if (!getIsAccountSwitchCurrent(switchId)) {
    void callApi('cancelDappRequest', payload.promiseId, 'Canceled by the user');
    return false;
  }

  global = getGlobal();
  global = clearState(global);
  global = updateState(global);
  setGlobal(global);

  return true;
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

  // A filled request of the same type stays as it is; the next request replaces it once its own data arrives
  if (
    (connectionType === 'connect' && global.dappConnectRequest?.promiseId)
    || (connectionType === 'sendTransaction' && global.currentDappTransfer.promiseId)
    || (connectionType === 'signData' && global.currentDappSignData.promiseId)
  ) {
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
  // Clear only a skeleton; a filled request (one with a `promiseId`) belongs to another request that is still open
  const { dappConnectRequest, currentDappTransfer, currentDappSignData } = global;
  if (
    connectionType === 'connect'
    && dappConnectRequest?.state === DappConnectState.Info
    && !dappConnectRequest.promiseId
  ) {
    global = clearDappConnectRequest(global);
  } else if (
    connectionType === 'sendTransaction'
    && currentDappTransfer.state === TransferState.Initial
    && !currentDappTransfer.promiseId
  ) {
    global = clearCurrentDappTransfer(global);
  } else if (
    connectionType === 'signData'
    && currentDappSignData.state === SignDataState.Initial
    && !currentDappSignData.promiseId
  ) {
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

addActionHandler('updateDappMfaRequestStatus', async (global, actions) => {
  const hash = global.currentDappTransfer.mfaRequestHash;
  if (!hash) return;
  const result = await callApi('fetchMfaRequest', hash);

  // The status is polled every second, so a slow response may arrive after the modal is closed or shows another request
  global = getGlobal();
  const { state, mfaRequestHash } = global.currentDappTransfer;
  if (result?.isConfirmed && state === TransferState.ConfirmMfa && mfaRequestHash === hash) {
    actions.closeDappTransfer();
    actions.showToast({ message: getTranslation('Successfully Sent'), icon: 'icon-check' });
  }
});
