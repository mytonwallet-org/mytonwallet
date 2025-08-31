import type { ApiSubmitTransferOptions } from '../../../api/methods/types';
import type { FormReducer } from '../../helpers/transfer';
import { VestingUnfreezeState } from '../../types';

import {
  CLAIM_ADDRESS,
  CLAIM_AMOUNT,
  CLAIM_COMMENT,
  MYCOIN,
  MYCOIN_TESTNET,
} from '../../../config';
import { callActionInMain } from '../../../util/multitab';
import { IS_DELEGATED_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { handleTransferResult } from '../../helpers/transfer';
import { prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateVesting } from '../../reducers';
import { selectVestingPartsReadyToUnfreeze } from '../../selectors';

addActionHandler('submitClaimingVesting', async (global, actions, { password } = {}) => {
  const accountId = global.currentAccountId!;
  const updateVestingState: FormReducer<VestingUnfreezeState> = (global, update) => {
    return updateVesting(global, accountId, update);
  };

  if (!await prepareTransfer(VestingUnfreezeState.ConfirmHardware, updateVestingState, password)) {
    return;
  }

  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('submitClaimingVesting', { password });
    return;
  }

  global = getGlobal();
  const unfreezeRequestedIds = selectVestingPartsReadyToUnfreeze(global, accountId);

  const options: ApiSubmitTransferOptions = {
    accountId: global.currentAccountId!,
    password,
    toAddress: CLAIM_ADDRESS,
    amount: CLAIM_AMOUNT,
    comment: CLAIM_COMMENT,
  };
  const result = await callApi('submitTransfer', 'ton', options);

  if (!handleTransferResult(result, updateVestingState)) {
    return;
  }

  global = getGlobal();
  global = updateVesting(global, accountId, {
    isConfirmRequested: undefined,
    unfreezeRequestedIds,
  });
  setGlobal(global);

  actions.openVestingModal();
});

addActionHandler('loadMycoin', (global, actions) => {
  const { isTestnet } = global.settings;

  actions.importToken({ address: isTestnet ? MYCOIN_TESTNET.minterAddress : MYCOIN.minterAddress });
});
