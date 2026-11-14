import './dapps';
import './walletConnectPay';
import '../ui/dapps';

import type { GlobalState } from '../../types';
import { SignDataState, TransferState, WalletConnectPayState } from '../../types';

import Deferred from '../../../util/Deferred';
import { cloneDeep } from '../../../util/iteratees';
import { pause } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { addActionHandler, getActions, getGlobal, getPromiseActions, setGlobal } from '../../index';
import { INITIAL_STATE } from '../../initialState';
import { switchAccount } from './auth';

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../../util/schedulers', () => ({
  ...jest.requireActual('../../../util/schedulers'),
  pause: jest.fn(() => Promise.resolve()),
}));

const CURRENT_ACCOUNT_ID = '0-mainnet';
const REQUEST_ACCOUNT_ID = '1-mainnet';
const NEWER_ACCOUNT_ID = '2-mainnet';
const REQUEST_ID = 'incoming-request';
const OPEN_REQUEST_ID = 'open-request';
const DAPP = { name: 'Test', url: 'https://dapp.example', connectedAt: 0 };
const REQUEST_TYPES = ['transfer', 'signData', 'payTransaction', 'paySignData'] as const;
const submitPayTransaction = jest.fn();
const submitPaySignData = jest.fn();

type RequestType = typeof REQUEST_TYPES[number];

addActionHandler('closeSettings', jest.fn());
addActionHandler('changeNetwork', jest.fn());

beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(0);
  jest.spyOn(getActions(), 'submitWalletConnectPaySignTransaction').mockImplementation(submitPayTransaction);
  jest.spyOn(getActions(), 'submitWalletConnectPaySignData').mockImplementation(submitPaySignData);
  submitPayTransaction.mockClear();
  submitPaySignData.mockClear();
  jest.mocked(callApi).mockReset();
  jest.mocked(pause).mockReset().mockResolvedValue(undefined);
  const global = cloneDeep(INITIAL_STATE);
  const account = { title: 'Wallet', type: 'mnemonic', byChain: { ton: { address: 'ton-address' } } } as const;
  setGlobal({
    ...global,
    enclaveSession: { token: 'test-token', validUntil: 1000 },
    currentAccountId: CURRENT_ACCOUNT_ID,
    accounts: {
      byId: {
        [CURRENT_ACCOUNT_ID]: account,
        [REQUEST_ACCOUNT_ID]: account,
        [NEWER_ACCOUNT_ID]: account,
      },
    },
  });
});

afterEach(() => {
  jest.restoreAllMocks();
});

it.each(REQUEST_TYPES)('rejects %s when a newer switch supersedes its activation', async (requestType) => {
  const activationStarted = new Deferred<void>();
  const activationFinished = new Deferred<void>();
  jest.mocked(callApi).mockImplementation(async (method, ...args) => {
    if (method === 'activateAccount' && args[0] === REQUEST_ACCOUNT_ID) {
      activationStarted.resolve();
      return activationFinished.promise;
    }
    return undefined;
  });

  const request = receiveRequest(requestType);
  await activationStarted.promise;
  await switchAccount(getGlobal(), NEWER_ACCOUNT_ID, 'mainnet');
  activationFinished.resolve();
  await request;

  expect(getGlobal().currentAccountId).toBe(NEWER_ACCOUNT_ID);
  expect(getRequestPromiseId(requestType)).not.toBe(REQUEST_ID);
  expect(callApi).toHaveBeenCalledWith(getCancelMethod(requestType), REQUEST_ID, expect.any(String));
  expect(callApi).not.toHaveBeenCalledWith('recordTonConnectEvent', expect.objectContaining({ promiseId: REQUEST_ID }));
  expect(submitPayTransaction).not.toHaveBeenCalled();
  expect(submitPaySignData).not.toHaveBeenCalled();
});

it.each(REQUEST_TYPES)('rejects %s when a switch to another account starts during the close animation', async (
  requestType,
) => {
  await receiveRequestWithSwitchDuringClose(requestType, NEWER_ACCOUNT_ID);

  expect(getGlobal().currentAccountId).toBe(NEWER_ACCOUNT_ID);
  expect(getRequestPromiseId(requestType)).not.toBe(REQUEST_ID);
  expect(callApi).toHaveBeenCalledWith(getCancelMethod(requestType), REQUEST_ID, expect.any(String));
  expect(callApi).not.toHaveBeenCalledWith('recordTonConnectEvent', expect.objectContaining({ promiseId: REQUEST_ID }));
  expect(submitPayTransaction).not.toHaveBeenCalled();
  expect(submitPaySignData).not.toHaveBeenCalled();
});

it.each(REQUEST_TYPES)('installs %s when a switch to its own account starts during the close animation', async (
  requestType,
) => {
  await receiveRequestWithSwitchDuringClose(requestType, REQUEST_ACCOUNT_ID);

  expect(getGlobal().currentAccountId).toBe(REQUEST_ACCOUNT_ID);
  expect(getRequestPromiseId(requestType)).toBe(REQUEST_ID);
  expect(callApi).not.toHaveBeenCalledWith(getCancelMethod(requestType), REQUEST_ID, expect.anything());
});

it.each(REQUEST_TYPES)('installs %s when its account is already active', async (requestType) => {
  setGlobal({ ...getGlobal(), currentAccountId: REQUEST_ACCOUNT_ID });

  await receiveRequest(requestType);

  expect(getRequestPromiseId(requestType)).toBe(REQUEST_ID);
  expect(callApi).not.toHaveBeenCalledWith(getCancelMethod(requestType), REQUEST_ID, expect.anything());
  if (requestType === 'payTransaction') {
    expect(submitPayTransaction).toHaveBeenCalledWith({ enclaveToken: 'test-token' });
  }
  if (requestType === 'paySignData') expect(submitPaySignData).toHaveBeenCalledWith({ enclaveToken: 'test-token' });
});

function receiveRequest(requestType: RequestType) {
  const actions = getPromiseActions();
  const payload = { promiseId: REQUEST_ID, accountId: REQUEST_ACCOUNT_ID, operationChain: 'ton' as const };

  switch (requestType) {
    case 'transfer':
      return actions.apiUpdateDappSendTransaction({
        ...payload, type: 'dappSendTransactions', dapp: DAPP, transactions: [],
      });
    case 'signData':
      return actions.apiUpdateDappSignData({
        ...payload, type: 'dappSignData', dapp: DAPP, payloadToSign: { type: 'text', text: 'Hello' },
      });
    case 'payTransaction':
      return actions.apiUpdateWalletConnectPaySignTransaction({
        ...payload, type: 'walletConnectPaySignTransaction', merchant: DAPP, transactions: [], isSignOnly: false,
      });
    case 'paySignData':
      return actions.apiUpdateWalletConnectPaySignData({
        ...payload, type: 'walletConnectPaySignData', merchant: DAPP, payloadToSign: { type: 'text', text: 'Hello' },
      });
  }
}

async function receiveRequestWithSwitchDuringClose(requestType: RequestType, accountId: string) {
  const closeStarted = new Deferred<void>();
  const closeFinished = new Deferred<void>();
  setOpenRequest(requestType);
  jest.mocked(pause).mockImplementationOnce(() => {
    closeStarted.resolve();
    return closeFinished.promise;
  });

  const request = receiveRequest(requestType);
  await closeStarted.promise;
  await switchAccount(getGlobal(), accountId, 'mainnet');
  closeFinished.resolve();
  await request;
}

function getRequestPromiseId(requestType: RequestType) {
  const global = getGlobal();
  if (requestType === 'transfer') return global.currentDappTransfer.promiseId;
  if (requestType === 'signData') return global.currentDappSignData.promiseId;
  return global.currentWalletConnectPay.promiseId;
}

function getCancelMethod(requestType: RequestType) {
  return requestType === 'transfer' || requestType === 'signData' ? 'cancelDappRequest' : 'cancelWalletConnectPay';
}

function setOpenRequest(requestType: RequestType) {
  let global: GlobalState = getGlobal();
  if (requestType === 'transfer') {
    global = { ...global, currentDappTransfer: { state: TransferState.Initial, promiseId: OPEN_REQUEST_ID } };
  } else if (requestType === 'signData') {
    global = { ...global, currentDappSignData: { state: SignDataState.Initial, promiseId: OPEN_REQUEST_ID } };
  } else {
    global = {
      ...global, currentWalletConnectPay: { state: WalletConnectPayState.Password, promiseId: OPEN_REQUEST_ID },
    };
  }
  setGlobal(global);
}
