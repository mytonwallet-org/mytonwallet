import { WalletConnectPayState } from '../../types';

import { addActionHandler, setGlobal } from '../../index';
import {
  clearCurrentWalletConnectPay,
  clearWalletConnectPayDataCollection,
  clearWalletConnectPayOptionSelection,
} from '../../reducers';

addActionHandler('apiUpdate', (global, actions, update) => {
  switch (update.type) {
    case 'walletConnectPayLoading': {
      actions.apiUpdateWalletConnectPayLoading(update);
      break;
    }

    case 'walletConnectPayCloseLoading': {
      if (global.currentWalletConnectPay.state !== WalletConnectPayState.None) {
        global = clearCurrentWalletConnectPay(global);
      }
      global = clearWalletConnectPayOptionSelection(global);
      global = clearWalletConnectPayDataCollection(global);
      setGlobal(global);
      break;
    }

    case 'walletConnectPaySignTransaction': {
      global = clearWalletConnectPayOptionSelection(global);
      setGlobal(global);
      actions.apiUpdateWalletConnectPaySignTransaction(update);
      break;
    }

    case 'walletConnectPaySignData': {
      global = clearWalletConnectPayOptionSelection(global);
      setGlobal(global);
      actions.apiUpdateWalletConnectPaySignData(update);
      break;
    }

    case 'walletConnectPayDataCollection': {
      global = clearWalletConnectPayOptionSelection(global);
      if (global.currentWalletConnectPay.isLoading && !global.currentWalletConnectPay.promiseId) {
        global = clearCurrentWalletConnectPay(global);
      }
      global = {
        ...global,
        walletConnectPayDataCollection: {
          promiseId: update.promiseId,
          url: update.url,
        },
      };

      setGlobal(global);
      break;
    }

    case 'walletConnectPayDataCollectionComplete': {
      if (!global.walletConnectPayDataCollection?.isCompleting) {
        global = clearWalletConnectPayDataCollection(global);
      }
      setGlobal(global);
      break;
    }

    case 'walletConnectPayOptionSelection': {
      global = {
        ...global,
        walletConnectPayOptionSelection: {
          promiseId: update.promiseId,
          paymentLink: update.paymentLink,
          accountId: update.accountId,
          merchant: update.merchant,
          paymentInfo: update.paymentInfo,
          options: update.options,
          isLoading: update.isLoading,
          shouldSwitchWallet: update.shouldSwitchWallet,
        },
      };

      setGlobal(global);
      break;
    }

    case 'walletConnectPayOptionSelectionComplete':
      break;

    case 'walletConnectPayProcessing': {
      actions.apiUpdateWalletConnectPayProcessing(update);
      break;
    }

    case 'walletConnectPayPaymentComplete': {
      actions.apiUpdateWalletConnectPayPaymentComplete(update);
      break;
    }
  }
});
