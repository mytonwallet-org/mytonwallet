import { VestingUnfreezeState } from '../../types';

import { addActionHandler, setGlobal } from '../../index';
import { resetHardware, updateVesting } from '../../reducers';
import { selectCurrentAccountId, selectIsHardwareAccount } from '../../selectors';

addActionHandler('openVestingModal', (global) => {
  setGlobal({ ...global, isVestingModalOpen: true });
});

addActionHandler('closeVestingModal', (global) => {
  setGlobal({ ...global, isVestingModalOpen: undefined });
});

addActionHandler('startClaimingVesting', (global) => {
  const accountId = selectCurrentAccountId(global)!;
  global = { ...global, isVestingModalOpen: undefined };
  global = updateVesting(global, accountId, { isConfirmRequested: true });
  if (selectIsHardwareAccount(global)) {
    global = resetHardware(global, 'ton');
    global = updateVesting(global, accountId, { unfreezeState: VestingUnfreezeState.ConnectHardware });
  } else {
    global = updateVesting(global, accountId, { unfreezeState: VestingUnfreezeState.Password });
  }
  setGlobal(global);
});

addActionHandler('cancelClaimingVesting', (global) => {
  const accountId = selectCurrentAccountId(global)!;
  global = updateVesting(global, accountId, { isConfirmRequested: undefined });
  setGlobal(global);
});

addActionHandler('clearVestingError', (global) => {
  const accountId = selectCurrentAccountId(global)!;
  global = updateVesting(global, accountId, { error: undefined });
  setGlobal(global);
});
