import { persistCache } from '../../cache';
import { addActionHandler, setGlobal } from '../../index';
import {
  prunePerpsReceipts,
  updatePerpsAssets,
  updatePerpsBalanceDeposit,
  updatePerpsOperation,
  updatePerpsTrade,
} from '../../reducers';

addActionHandler('apiUpdate', (global, actions, update) => {
  switch (update.type) {
    case 'perpsOperationUpdated': {
      const { operation } = update;
      global = updatePerpsOperation(global, operation);
      // Storing an operation may drop old resolved ones from the journal, and their receipts go with them
      global = prunePerpsReceipts(global, operation.accountId);
      const { trade } = global.perps;

      // Once the operation is submitted, its receipt replaces the progress and follows the settlement, as on iOS. An
      // operation that failed before the submission goes back to the review, which the execution result decides.
      const isSubmitted = operation.state !== 'failed'
        && (operation.state !== 'running' || operation.stage !== 'preparing');
      if (trade?.step === 'progress' && trade.operationId === operation.id && isSubmitted) {
        global = updatePerpsTrade(global, { step: trade.kind ? 'receipt' : 'status' });
      }
      setGlobal(global);
      persistCache();
      break;
    }

    case 'updatePerpsAssets': {
      global = updatePerpsAssets(global, update.assets, update.langCode, update.fetchedAt);
      setGlobal(global);

      const { market } = global.perps;
      // A catalogue in another language than the app is about to be replaced by the next refresh. A catalogue the
      // market is already built from needs no reload.
      const isOtherLanguage = update.langCode !== undefined && update.langCode !== global.settings.langCode;
      const isApplied = market !== undefined
        && market.langCode === update.langCode
        && market.assetsFetchedAt >= update.fetchedAt;
      if (!isOtherLanguage && !isApplied) {
        actions.loadPerpsMarket();
      }
      break;
    }

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
