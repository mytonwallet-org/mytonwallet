import './transfer';
import './swap';
import './staking';

import { StakingState, SwapState, TransferState } from '../../types';

import Deferred from '../../../util/Deferred';
import { cloneDeep } from '../../../util/iteratees';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, getPromiseActions, setGlobal } from '../../index';
import { INITIAL_STATE } from '../../initialState';
import { switchAccount } from './auth';

jest.mock('../../../api', () => ({ callApi: jest.fn(), callApiWithThrow: jest.fn() }));
jest.mock('../../helpers/misc', () => ({
  ...jest.requireActual('../../helpers/misc'),
  closeAllOverlays: jest.fn(() => Promise.resolve()),
}));

const CURRENT_ACCOUNT_ID = '0-mainnet';
const REQUEST_ACCOUNT_ID = '1-mainnet';
const NEWER_ACCOUNT_ID = '2-mainnet';
const ACTIONS = [
  'switchTransferAccount', 'switchSwapAccount', 'switchStakingAccount', 'openAnyAccountStakingInfo',
] as const;

addActionHandler('closeSettings', jest.fn());
addActionHandler('changeNetwork', jest.fn());

beforeEach(() => {
  jest.mocked(callApi).mockReset();
  const global = cloneDeep(INITIAL_STATE);
  const account = { title: 'Wallet', type: 'mnemonic', byChain: { ton: { address: 'ton-address' } } } as const;
  setGlobal({
    ...global,
    currentAccountId: CURRENT_ACCOUNT_ID,
    accounts: { byId: {
      [CURRENT_ACCOUNT_ID]: account,
      [REQUEST_ACCOUNT_ID]: account,
      [NEWER_ACCOUNT_ID]: account,
    } },
    currentTransfer: {
      ...global.currentTransfer, state: TransferState.Initial, toAddress: 'old-recipient', amount: 1n,
    },
    currentSwap: { ...global.currentSwap, state: SwapState.Initial, amountIn: '1' },
    currentStaking: { state: StakingState.StakeInitial, initialAmount: 1n },
  });
});

it.each(ACTIONS)('ignores %s after a newer account switch owns the screen', async (actionName) => {
  const activationStarted = new Deferred<void>();
  const activationFinished = new Deferred<void>();
  jest.mocked(callApi).mockImplementation(async (method, ...args) => {
    if (method === 'activateAccount' && args[0] === REQUEST_ACCOUNT_ID) {
      activationStarted.resolve();
      return activationFinished.promise;
    }
    return undefined;
  });

  const request = getPromiseActions()[actionName]({
    accountId: REQUEST_ACCOUNT_ID, mode: 'stake', network: 'mainnet', stakingId: 'old-staking',
  });
  await activationStarted.promise;
  await switchAccount(getGlobal(), NEWER_ACCOUNT_ID, 'mainnet');
  const global = getGlobal();
  const currentTransfer = {
    ...global.currentTransfer, state: TransferState.Password, toAddress: 'new-recipient', amount: 2n,
  };
  const currentSwap = { ...global.currentSwap, state: SwapState.Password, amountIn: '2' };
  const currentStaking = { state: StakingState.StakePassword, initialAmount: 2n };
  setGlobal({ ...global, currentTransfer, currentSwap, currentStaking, isStakingInfoModalOpen: undefined });
  activationFinished.resolve();
  await request;

  expect(getGlobal().currentAccountId).toBe(NEWER_ACCOUNT_ID);
  expect(getGlobal().currentTransfer).toEqual(currentTransfer);
  expect(getGlobal().currentSwap).toEqual(currentSwap);
  expect(getGlobal().currentStaking).toEqual(currentStaking);
  expect(getGlobal().isStakingInfoModalOpen).toBeUndefined();
});
