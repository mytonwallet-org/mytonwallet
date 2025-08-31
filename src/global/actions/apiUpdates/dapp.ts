import { SignDataState, TransferState } from '../../types';

import { TONCOIN } from '../../../config';
import { processDeeplink } from '../../../util/deeplink';
import { callActionInNative } from '../../../util/multitab';
import { IS_DELEGATING_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { addActionHandler, setGlobal } from '../../index';
import {
  clearCurrentDappTransfer,
  clearCurrentSignature,
  clearCurrentTransfer,
  clearDappConnectRequest,
  updateCurrentDappSignData,
  updateCurrentDappTransfer,
  updateCurrentSignature,
  updateCurrentTransfer,
  updateCurrentTransferByCheckResult,
} from '../../reducers';

addActionHandler('apiUpdate', (global, actions, update) => {
  switch (update.type) {
    case 'createTransaction': {
      const {
        promiseId,
        amount,
        toAddress,
        comment,
        rawPayload,
        stateInit,
        checkResult,
      } = update;

      global = clearCurrentTransfer(global);
      global = updateCurrentTransfer(global, {
        state: TransferState.Confirm,
        toAddress,
        resolvedAddress: checkResult.resolvedAddress,
        isToNewAddress: checkResult.isToAddressNew,
        amount,
        comment,
        promiseId,
        tokenSlug: TONCOIN.slug,
        rawPayload,
        stateInit,
      });
      global = updateCurrentTransferByCheckResult(global, checkResult);
      setGlobal(global);

      break;
    }

    case 'completeTransaction': {
      const { activityId } = update;
      setGlobal(updateCurrentTransfer(global, {
        state: TransferState.Complete,
        txId: activityId,
      }));

      break;
    }

    case 'createSignature': {
      const { promiseId, dataHex } = update;

      global = clearCurrentSignature(global);
      global = updateCurrentSignature(global, {
        promiseId,
        dataHex,
      });
      setGlobal(global);

      break;
    }

    case 'showError': {
      const { error } = update;
      actions.showError({ error });

      break;
    }

    case 'dappConnect': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdateDappConnect', update);
      }

      actions.apiUpdateDappConnect(update);

      break;
    }

    case 'dappConnectComplete': {
      global = clearDappConnectRequest(global);
      setGlobal(global);

      break;
    }

    case 'dappDisconnect': {
      const { url } = update;

      if (global.currentDappTransfer.dapp?.url === url) {
        global = clearCurrentDappTransfer(global);
        setGlobal(global);
      }
      break;
    }

    case 'dappLoading': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdateDappLoading', update);
      }

      actions.apiUpdateDappLoading(update);

      break;
    }

    case 'dappCloseLoading': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdateDappCloseLoading', update);
      }

      actions.apiUpdateDappCloseLoading(update);

      break;
    }

    case 'dappSendTransactions': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdateDappSendTransaction', update);
      }

      actions.apiUpdateDappSendTransaction(update);
      break;
    }

    case 'dappSignData': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdateDappSignData', update);
      }

      actions.apiUpdateDappSignData(update);
      break;
    }

    case 'updateDapps': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('getDapps');
      }

      actions.getDapps();
      break;
    }

    case 'prepareTransaction': {
      const {
        amount,
        toAddress,
        comment,
        binPayload,
      } = update;

      global = clearCurrentTransfer(global);
      global = updateCurrentTransfer(global, {
        state: TransferState.Initial,
        toAddress,
        amount: amount ?? 0n,
        comment,
        tokenSlug: TONCOIN.slug,
        binPayload,
      });

      setGlobal(global);
      break;
    }

    case 'processDeeplink': {
      const { url } = update;

      void processDeeplink(url);
      break;
    }

    case 'dappTransferComplete': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdate', update);
      }

      if (global.currentDappTransfer.state !== TransferState.None) {
        global = updateCurrentDappTransfer(global, {
          state: TransferState.Complete,
          isLoading: false,
        });
        setGlobal(global);
      }
      break;
    }

    case 'dappSignDataComplete': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdate', update);
      }

      if (global.currentDappSignData.state !== SignDataState.None) {
        global = updateCurrentDappSignData(global, {
          state: SignDataState.Complete,
          isLoading: false,
        });
        setGlobal(global);
      }
      break;
    }
  }
});
