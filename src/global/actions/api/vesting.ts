import type { ApiSubmitTransferOptions } from '../../../api/types';
import type { FormReducer } from '../../helpers/transfer';
import { VestingUnfreezeState } from '../../types';

import {
  CLAIM_ADDRESS,
  CLAIM_AMOUNT,
  CLAIM_COMMENT,
  MYCOIN_MAINNET,
  MYCOIN_TESTNET,
} from '../../../config';
import { callApi } from '../../../api';
import { withEnclaveSessionRelease } from '../../helpers/enclave';
import { handleTransferResult } from '../../helpers/transfer';
import { prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateVesting } from '../../reducers';
import { selectCurrentAccountId, selectVestingPartsReadyToUnfreeze } from '../../selectors';

addActionHandler('submitClaimingVesting', withEnclaveSessionRelease(async (global, actions, payload) => {
  const { enclaveToken } = payload ?? {};
  const accountId = selectCurrentAccountId(global)!;
  const updateVestingState: FormReducer<VestingUnfreezeState> = (global, update) => {
    return updateVesting(global, accountId, update);
  };

  if (!prepareTransfer(VestingUnfreezeState.ConfirmHardware, updateVestingState)) {
    return;
  }

  global = getGlobal();
  const unfreezeRequestedIds = selectVestingPartsReadyToUnfreeze(global, accountId);

  const options: ApiSubmitTransferOptions = {
    // This may be different from the `accountId` if the user switched accounts
    // while the transfer is preparing
    accountId: selectCurrentAccountId(global)!,
    enclaveToken,
    toAddress: CLAIM_ADDRESS,
    amount: CLAIM_AMOUNT,
    payload: { type: 'comment', text: CLAIM_COMMENT },
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
}));

addActionHandler('loadMycoin', (global, actions) => {
  const { isTestnet } = global.settings;

  actions.importToken({
    chain: 'ton',
    address: isTestnet ? MYCOIN_TESTNET.minterAddress : MYCOIN_MAINNET.minterAddress,
  });
});
