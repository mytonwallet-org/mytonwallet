import type { GlobalState } from '../../types';
import { WalletConnectPayState } from '../../types';

import { parseAccountId } from '../../../util/account';
import { getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import { getDoesUsePinPad } from '../../../util/biometrics';
import { pause } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { handleDappSignatureResult, prepareDappOperation } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  clearCurrentWalletConnectPay,
  clearIsPinAccepted,
  clearWalletConnectPayDataCollection,
  clearWalletConnectPayOptionSelection,
  updateCurrentWalletConnectPay,
  updateWalletConnectPayDataCollection,
} from '../../reducers';
import { selectCurrentAccountId, selectIsHardwareAccount } from '../../selectors';
import { switchAccount } from './auth';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

import { CLOSE_DURATION, CLOSE_DURATION_PORTRAIT } from '../../../components/ui/Modal';

const ANIMATION_END_DELAY = 300;

const WALLET_CONNECT_PAY_SIGN_URL = 'https://walletconnect.com/pay';

async function beginWalletConnectPayPasswordEntry(actions: {
  showError: (payload: { error: string }) => void;
  cancelWalletConnectPay: () => void;
  submitWalletConnectPaySignData: (payload: { password: string }) => void;
  submitWalletConnectPaySignTransaction: (payload: { password: string }) => void;
}) {
  const inMemoryPassword = await getInMemoryPassword();
  let global = getGlobal();

  if (selectIsHardwareAccount(global)) {
    actions.showError({ error: 'Not supported by Ledger accounts' });
    actions.cancelWalletConnectPay();

    return;
  }

  if (inMemoryPassword) {
    global = updateCurrentWalletConnectPay(global, { isLoading: true });
    setGlobal(global);

    if (global.currentWalletConnectPay.operation === 'signData') {
      actions.submitWalletConnectPaySignData({ password: inMemoryPassword });
    } else {
      actions.submitWalletConnectPaySignTransaction({ password: inMemoryPassword });
    }
  }
}

function cancelWalletConnectPayOperation(global: GlobalState) {
  const { promiseId } = global.currentWalletConnectPay;

  if (promiseId) {
    void callApi('cancelWalletConnectPay', promiseId, 'Canceled by the user');
  }

  if (getDoesUsePinPad()) {
    global = clearIsPinAccepted(global);
  }
  global = clearCurrentWalletConnectPay(global);
  setGlobal(global);
}

async function apiUpdateWalletConnectPayOperation(
  payload: { accountId: string },
  getState: (global: GlobalState) => { promiseId?: string },
  close: NoneToVoidFunction,
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
  global = clearWalletConnectPayDataCollection(global);
  global = updateState(global);

  setGlobal(global);
}

addActionHandler('apiUpdateWalletConnectPayLoading', (global, actions, { accountId }) => {
  actions.switchAccount({ accountId });
  global = getGlobal();

  if (global.currentWalletConnectPay.state === WalletConnectPayState.Password) {
    global = updateCurrentWalletConnectPay(global, {
      isLoading: true,
      error: undefined,
    });
    setGlobal(global);
  }
});

addActionHandler('apiUpdateWalletConnectPayProcessing', (global, actions, { accountId, merchant, operationChain }) => {
  actions.switchAccount({ accountId });
  global = getGlobal();
  global = updateCurrentWalletConnectPay(global, {
    state: WalletConnectPayState.Processing,
    operation: 'payment',
    merchant,
    operationChain,
    isLoading: false,
    error: undefined,
  });
  setGlobal(global);
});

addActionHandler('apiUpdateWalletConnectPayPaymentComplete', (global, actions, payload) => {
  const { merchant, operationChain, txId, paymentAmount } = payload;

  global = updateCurrentWalletConnectPay(global, {
    state: WalletConnectPayState.Complete,
    operation: 'payment',
    merchant,
    operationChain,
    txId,
    paymentAmount,
    isLoading: false,
    error: undefined,
  });
  setGlobal(global);
});

addActionHandler('apiUpdateWalletConnectPaySignTransaction', async (global, actions, payload) => {
  const {
    promiseId,
    transactions,
    emulation,
    merchant,
    validUntil,
    operationChain,
    paymentInfo,
    paymentOption,
    isSignOnly,
    isLegacyOutput,
    shouldHideTransfers,
  } = payload;

  await apiUpdateWalletConnectPayOperation(
    payload,
    (g) => g.currentWalletConnectPay,
    actions.closeWalletConnectPay,
    clearCurrentWalletConnectPay,
    (g) => updateCurrentWalletConnectPay(g, {
      state: WalletConnectPayState.Password,
      operation: 'transaction',
      promiseId,
      merchant,
      operationChain,
      transactions,
      emulation,
      paymentInfo,
      paymentOption,
      validUntil,
      isSignOnly,
      isLegacyOutput,
      shouldHideTransfers,
      isLoading: false,
      error: undefined,
    }),
  );

  await beginWalletConnectPayPasswordEntry(actions);
});

addActionHandler('apiUpdateWalletConnectPaySignData', async (global, actions, payload) => {
  const {
    promiseId,
    merchant,
    payloadToSign,
    operationChain,
    paymentInfo,
    paymentOption,
    containsApprove,
    approveOperationChain,
    approveTransactions,
    approveValidUntil,
  } = payload;

  await apiUpdateWalletConnectPayOperation(
    payload,
    (g) => g.currentWalletConnectPay,
    actions.closeWalletConnectPay,
    clearCurrentWalletConnectPay,
    (g) => updateCurrentWalletConnectPay(g, {
      state: WalletConnectPayState.Password,
      operation: 'signData',
      promiseId,
      merchant,
      operationChain,
      payloadToSign,
      paymentInfo,
      paymentOption,
      containsApprove,
      approveOperationChain,
      approveTransactions,
      approveValidUntil,
      isLoading: false,
      error: undefined,
    }),
  );

  await beginWalletConnectPayPasswordEntry(actions);
});

addActionHandler('submitWalletConnectPaySignTransaction', async (global, actions, { password } = {}) => {
  const {
    promiseId,
    transactions,
    validUntil,
    operationChain,
    isSignOnly,
    isLegacyOutput,
  } = global.currentWalletConnectPay;
  if (!promiseId || !operationChain) {
    return;
  }

  // FIXME: EVM Pay does not support Ledger, so value is unused for software accounts
  if (!await prepareDappOperation(
    selectCurrentAccountId(global)!,
    0 as never,
    updateCurrentWalletConnectPay,
    true,
    password,
  )) {
    return;
  }

  const accountId = selectCurrentAccountId(global)!;
  const account = global.accounts?.byId?.[accountId];
  const address = account?.byChain?.[operationChain]?.address;
  const { network } = parseAccountId(accountId);
  if (!address) {
    return;
  }

  const dappChain = { chain: operationChain, address, network };

  const signedTransactions = await callApi(
    'signDappTransfers',
    dappChain,
    accountId,
    transactions!,
    {
      password,
      validUntil,
      isLegacyOutput: isLegacyOutput ?? isSignOnly,
    },
  );

  if (!handleDappSignatureResult(signedTransactions, updateCurrentWalletConnectPay)) {
    return;
  }

  if (signedTransactions && typeof signedTransactions === 'object' && 'mfaRequestHash' in signedTransactions) {
    return;
  }

  await callApi('confirmWalletConnectPaySignTransaction', promiseId, signedTransactions);
});

addActionHandler('submitWalletConnectPaySignData', async (global, actions, { password } = {}) => {
  const {
    promiseId,
    payloadToSign,
    operationChain,
    containsApprove,
    approveOperationChain,
    approveTransactions,
    approveValidUntil,
  } = global.currentWalletConnectPay;
  if (!promiseId || !operationChain || !payloadToSign) {
    return;
  }

  if (!await prepareDappOperation(
    selectCurrentAccountId(global)!,
    0 as never,
    updateCurrentWalletConnectPay,
    true,
    password,
  )) {
    return;
  }

  const accountId = selectCurrentAccountId(global)!;
  const account = global.accounts?.byId?.[accountId];
  const address = account?.byChain?.[operationChain]?.address;
  if (!address) {
    return;
  }

  const { network } = parseAccountId(accountId);
  const dappChain = { chain: operationChain, address, network };

  const signedData = await callApi(
    'signDappData',
    dappChain,
    accountId,
    WALLET_CONNECT_PAY_SIGN_URL,
    payloadToSign,
    password,
  );

  if (!handleDappSignatureResult(signedData, updateCurrentWalletConnectPay)) {
    return;
  }

  if (!containsApprove) {
    await callApi('confirmWalletConnectPaySignData', promiseId, signedData);
    return;
  }

  if (!approveOperationChain || !approveTransactions?.length) {
    return;
  }

  global = updateCurrentWalletConnectPay(getGlobal(), { isLoading: true, error: undefined });
  setGlobal(global);

  const approveAddress = account?.byChain?.[approveOperationChain]?.address;
  if (!approveAddress) {
    return;
  }

  const approveDappChain = { chain: approveOperationChain, address: approveAddress, network };
  const signedApproveTransactions = await callApi(
    'signDappTransfers',
    approveDappChain,
    accountId,
    approveTransactions,
    {
      password,
      validUntil: approveValidUntil,
      isLegacyOutput: false,
    },
  );

  if (!handleDappSignatureResult(signedApproveTransactions, updateCurrentWalletConnectPay)) {
    return;
  }

  if (
    signedApproveTransactions
    && typeof signedApproveTransactions === 'object'
    && 'mfaRequestHash' in signedApproveTransactions
  ) {
    return;
  }

  await callApi('confirmWalletConnectPaySignData', promiseId, {
    signDataSignature: signedData.result.signature,
    signedApproveTransactions,
  });
});

addActionHandler('cancelWalletConnectPay', (global) => {
  cancelWalletConnectPayOperation(global);
});

addActionHandler('closeWalletConnectPay', (global) => {
  const { state } = global.currentWalletConnectPay;
  if (state === WalletConnectPayState.Complete) {
    global = clearCurrentWalletConnectPay(global);
    setGlobal(global);
  } else {
    cancelWalletConnectPayOperation(global);
  }
});

addActionHandler('completeWalletConnectPayDataCollection', (global) => {
  const { promiseId } = global.walletConnectPayDataCollection ?? {};
  if (promiseId) {
    void callApi('completeWalletConnectPayDataCollection', promiseId);
  }
  global = updateWalletConnectPayDataCollection(global, { isCompleting: true });
  setGlobal(global);
});

addActionHandler('closeWalletConnectPayDataCollection', (global) => {
  const { promiseId } = global.walletConnectPayDataCollection ?? {};
  if (promiseId) {
    void callApi('cancelWalletConnectPay', promiseId, 'Canceled by the user');
  }
  global = clearWalletConnectPayDataCollection(global);
  setGlobal(global);
});

addActionHandler('confirmWalletConnectPayOptionSelection', (global, actions, { optionId }) => {
  const { promiseId } = global.walletConnectPayOptionSelection ?? {};
  if (!promiseId) {
    return;
  }

  void callApi('confirmWalletConnectPayOptionSelection', promiseId, optionId);
});

addActionHandler('closeWalletConnectPayOptionSelection', (global) => {
  const { promiseId } = global.walletConnectPayOptionSelection ?? {};
  if (promiseId) {
    void callApi('cancelWalletConnectPay', promiseId, 'Canceled by the user');
  }
  global = clearWalletConnectPayOptionSelection(global);
  setGlobal(global);
});

addActionHandler('switchWalletConnectPayOptionSelectionAccount', async (global, actions, { accountId }) => {
  const selection = global.walletConnectPayOptionSelection;
  if (!selection?.promiseId || !selection.paymentLink || accountId === selection.accountId) {
    return;
  }

  global = {
    ...global,
    walletConnectPayOptionSelection: {
      ...selection,
      accountId,
      isLoading: true,
    },
  };
  setGlobal(global);

  await switchAccount(global, accountId);

  void callApi(
    'refreshWalletConnectPayOptionSelection',
    selection.paymentLink,
    accountId,
    selection.promiseId,
  );
});
