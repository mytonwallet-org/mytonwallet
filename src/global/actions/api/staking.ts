import type { ApiEthenaStakingState, ApiJettonStakingState } from '../../../api/types';
import { StakingState } from '../../types';

import { getDoesUsePinPad } from '../../../util/biometrics';
import { getTonStakingFees } from '../../../util/fee/getTonOperationFees';
import { pause } from '../../../util/schedulers';
import { getIsActiveStakingState, getIsLongUnstake } from '../../../util/staking';
import { callApi } from '../../../api';
import { closeAllOverlays } from '../../helpers/misc';
import { handleTransferResult, isErrorTransferResult, prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  clearCurrentStaking,
  clearIsPinAccepted,
  resetHardware,
  updateAccountStaking,
  updateAccountState,
  updateCurrentStaking,
} from '../../reducers';
import {
  selectAccountStakingState,
  selectAccountStakingStatesBySlug,
  selectCurrentAccountId,
  selectIsHardwareAccount,
} from '../../selectors';
import { switchAccount } from './auth';

const MODAL_CLOSING_DELAY = 50;

addActionHandler('startStaking', (global, actions, payload) => {
  const { tokenSlug } = payload || {};

  if (tokenSlug) {
    const currentAccountId = selectCurrentAccountId(global)!;
    const stakingState = selectAccountStakingStatesBySlug(global, currentAccountId)[tokenSlug];
    if (stakingState) {
      global = getGlobal();
      global = updateAccountStaking(global, currentAccountId, { stakingId: stakingState.id });
      setGlobal(global);

      global = getGlobal();
    }
  }

  const state = StakingState.StakeInitial;

  setGlobal(updateCurrentStaking(global, {
    state,
    error: undefined,
  }));
});

addActionHandler('startUnstaking', (global, actions, payload) => {
  const { stakingId } = payload || {};

  if (stakingId) {
    global = getGlobal();
    global = updateAccountStaking(global, selectCurrentAccountId(global)!, { stakingId });
    setGlobal(global);

    global = getGlobal();
  }

  const state = StakingState.UnstakeInitial;

  setGlobal(updateCurrentStaking(global, {
    state,
    error: undefined,
  }));
});

addActionHandler('fetchStakingFee', async (global, actions, payload) => {
  const { amount } = payload;
  const currentAccountId = selectCurrentAccountId(global);

  if (!currentAccountId) {
    return;
  }

  const state = selectAccountStakingState(global, currentAccountId);

  const result = await callApi(
    'checkStakeDraft',
    currentAccountId,
    amount,
    state,
  );
  if (isErrorTransferResult(result)) {
    return;
  }

  global = getGlobal();
  global = updateCurrentStaking(global, {
    fee: result.fee,
  });
  setGlobal(global);
});

addActionHandler('submitStakingInitial', async (global, actions, payload) => {
  const { isUnstaking, amount } = payload ?? {};
  const currentAccountId = selectCurrentAccountId(global);

  if (!currentAccountId) {
    return;
  }

  setGlobal(updateCurrentStaking(global, { isLoading: true, error: undefined }));

  const state = selectAccountStakingState(global, currentAccountId);

  if (isUnstaking) {
    const result = await callApi('checkUnstakeDraft', currentAccountId, amount!, state);
    global = getGlobal();
    global = updateCurrentStaking(global, { isLoading: false });

    if (result) {
      if ('error' in result) {
        global = updateCurrentStaking(global, { error: result.error });
      } else {
        if (selectIsHardwareAccount(global)) {
          global = resetHardware(global, 'ton');
          global = updateCurrentStaking(global, { state: StakingState.UnstakeConnectHardware });
        } else {
          global = updateCurrentStaking(global, { state: StakingState.UnstakePassword });
        }

        global = updateCurrentStaking(global, {
          fee: result.fee,
          amount,
          error: undefined,
          tokenAmount: result.tokenAmount,
        });
      }
    }
  } else {
    const result = await callApi(
      'checkStakeDraft',
      currentAccountId,
      amount!,
      state,
    );
    global = getGlobal();
    global = updateCurrentStaking(global, { isLoading: false });

    if (result) {
      if ('error' in result) {
        global = updateCurrentStaking(global, { error: result.error });
      } else {
        if (selectIsHardwareAccount(global)) {
          global = resetHardware(global, 'ton');
          global = updateCurrentStaking(global, { state: StakingState.StakeConnectHardware });
        } else {
          global = updateCurrentStaking(global, { state: StakingState.StakePassword });
        }

        global = updateCurrentStaking(global, {
          fee: result.fee,
          amount,
          error: undefined,
        });
      }
    }
  }

  setGlobal(global);
});

addActionHandler('submitStaking', async (global, actions, payload = {}) => {
  const { password, isUnstaking } = payload;
  const { amount, tokenAmount } = global.currentStaking;
  const currentAccountId = selectCurrentAccountId(global)!;

  if (!await prepareTransfer(
    isUnstaking ? StakingState.UnstakeConfirmHardware : StakingState.StakeConfirmHardware,
    updateCurrentStaking,
    password,
  )) {
    return;
  }

  global = getGlobal();
  const state = selectAccountStakingState(global, currentAccountId);

  if (isUnstaking) {
    const unstakeAmount = state.type === 'nominators' ? state.balance : tokenAmount!;
    const result = await callApi(
      'submitUnstake',
      // This may be different from the `currentAccountId` if the user switched accounts
      // while the transaction was being signed
      selectCurrentAccountId(global)!,
      password,
      unstakeAmount,
      state,
      getTonStakingFees(state.type).unstake.real,
    );

    if (!handleTransferResult(result, updateCurrentStaking)) {
      return;
    }

    const isLongUnstakeRequested = getIsLongUnstake(state, unstakeAmount);

    global = getGlobal();
    global = updateAccountState(global, currentAccountId, { isLongUnstakeRequested });
    global = updateCurrentStaking(global, { state: StakingState.UnstakeComplete });
    setGlobal(global);
  } else {
    const result = await callApi(
      'submitStake',
      // This may be different from the `currentAccountId` if the user switched accounts
      // while the transaction was being signed
      selectCurrentAccountId(global)!,
      password,
      amount!,
      state,
      getTonStakingFees(state.type).stake.real,
    );

    if (!handleTransferResult(result, updateCurrentStaking)) {
      return;
    }

    global = getGlobal();
    global = updateCurrentStaking(global, { state: StakingState.StakeComplete });
    setGlobal(global);
  }
});

addActionHandler('clearStakingError', (global) => {
  setGlobal(updateCurrentStaking(global, { error: undefined }));
});

addActionHandler('cancelStaking', (global) => {
  if (getDoesUsePinPad()) {
    global = clearIsPinAccepted(global);
  }

  global = clearCurrentStaking(global);
  setGlobal(global);
});

addActionHandler('setStakingScreen', (global, actions, payload) => {
  const { state } = payload;

  setGlobal(updateCurrentStaking(global, { state }));
});

addActionHandler('fetchStakingHistory', async (global) => {
  const stakingHistory = await callApi('getStakingHistory', selectCurrentAccountId(global)!);

  if (!stakingHistory) {
    return;
  }

  global = getGlobal();
  global = updateAccountState(global, selectCurrentAccountId(global)!, { stakingHistory }, true);
  setGlobal(global);
});

addActionHandler('openAnyAccountStakingInfo', async (global, actions, { accountId, network, stakingId }) => {
  await Promise.all([
    closeAllOverlays(),
    switchAccount(global, accountId, network),
  ]);

  actions.changeCurrentStaking({ stakingId });
  actions.openStakingInfo();
});

// Should be called only when you're sure that the staking is active. Otherwise, call `openStakingInfoOrStart`.
addActionHandler('openStakingInfo', (global) => {
  global = { ...global, isStakingInfoModalOpen: true };
  setGlobal(global);
});

addActionHandler('closeStakingInfo', (global) => {
  global = { ...global, isStakingInfoModalOpen: undefined };
  setGlobal(global);
});

addActionHandler('changeCurrentStaking', async (global, actions, { stakingId, shouldReopenModal }) => {
  if (shouldReopenModal) {
    await pause(MODAL_CLOSING_DELAY);
  }

  global = getGlobal();
  global = updateAccountStaking(global, selectCurrentAccountId(global)!, { stakingId });
  setGlobal(global);

  if (shouldReopenModal) {
    actions.openStakingInfoOrStart();
  }
});

addActionHandler('startStakingClaim', (global, actions, payload) => {
  const { stakingId } = payload || {};

  if (stakingId) {
    global = getGlobal();
    global = updateAccountStaking(global, selectCurrentAccountId(global)!, { stakingId });
    setGlobal(global);

    global = getGlobal();
  }

  if (selectIsHardwareAccount(global)) {
    global = resetHardware(global, 'ton');
    global = updateCurrentStaking(global, { state: StakingState.ClaimConnectHardware });
  } else {
    global = updateCurrentStaking(global, { state: StakingState.ClaimPassword });
  }
  setGlobal(global);
});

addActionHandler('cancelStakingClaim', (global) => {
  global = updateCurrentStaking(global, { state: StakingState.None });
  setGlobal(global);
});

addActionHandler('submitStakingClaim', async (global, actions, { password } = {}) => {
  const accountId = selectCurrentAccountId(global)!;

  if (!await prepareTransfer(StakingState.ClaimConfirmHardware, updateCurrentStaking, password)) {
    return;
  }

  global = getGlobal();

  const stakingState = selectAccountStakingState(global, accountId) as ApiEthenaStakingState | ApiJettonStakingState;
  const isEthenaStaking = stakingState.type === 'ethena';

  const result = await callApi(
    'submitStakingClaimOrUnlock',
    accountId,
    password,
    stakingState,
    getTonStakingFees(stakingState.type).claim?.real,
  );

  if (!handleTransferResult(result, updateCurrentStaking)) {
    return;
  }

  global = getGlobal();
  global = updateCurrentStaking(global, {
    state: isEthenaStaking ? StakingState.ClaimComplete : StakingState.None,
  });
  setGlobal(global);
});

// Opens the staking info modal if the modal is available. Otherwise, opens the staking start modal.
addActionHandler('openStakingInfoOrStart', (global, actions) => {
  const currentAccountId = selectCurrentAccountId(global);

  if (!currentAccountId) {
    return;
  }

  const stakingState = selectAccountStakingState(global, currentAccountId);

  if (getIsActiveStakingState(stakingState)) {
    actions.openStakingInfo();
  } else {
    actions.startStaking();
  }
});
