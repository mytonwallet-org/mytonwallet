import { persistCache } from '../../cache';
import { addActionHandler, setGlobal } from '../../index';
import { updatePerpsAssets, updatePerpsBalanceDeposit, updatePerpsOperation } from '../../reducers';

addActionHandler('apiUpdate', (global, actions, update) => {
  switch (update.type) {
    case 'perpsOperationUpdated':
      setGlobal(updatePerpsOperation(global, update.operation));
      persistCache();
      break;

    case 'updatePerpsAssets':
      setGlobal(updatePerpsAssets(global, update.assets, update.langCode, update.fetchedAt));
      break;

    case 'perpsDepositSubmitted':
      if (update.flow !== 'deposit') break;
      setGlobal(updatePerpsBalanceDeposit(global, update.accountId, {
        phase: 'submitted',
        depositTxHash: update.depositTxHash,
        at: Date.now(),
      }));
      break;

    case 'perpsExecuteComplete':
      if (update.flow !== 'deposit') break;
      setGlobal(updatePerpsBalanceDeposit(global, update.accountId, {
        phase: 'complete',
        depositTxHash: update.depositTxHash,
        status: update.result.status,
        at: Date.now(),
      }));
      break;

    case 'perpsExecuteFailed':
      if (update.flow !== 'deposit') break;
      setGlobal(updatePerpsBalanceDeposit(global, update.accountId, {
        phase: 'failed',
        depositTxHash: update.depositTxHash,
        error: update.error,
        at: Date.now(),
      }));
      break;

    default:
      break;
  }
});
