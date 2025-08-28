import { ActiveTab, TransferState } from '../../types';

import { getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import { callActionInMain, callActionInNative } from '../../../util/multitab';
import { IS_DELEGATED_BOTTOM_SHEET, IS_DELEGATING_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { resetHardware, setCurrentTransferAddress, updateCurrentTransfer } from '../../reducers';
import { selectIsHardwareAccount } from '../../selectors';

addActionHandler('startTransfer', (global, actions, payload) => {
  const isOpen = global.currentTransfer.state !== TransferState.None;
  if (IS_DELEGATED_BOTTOM_SHEET && !isOpen) {
    callActionInMain('startTransfer', payload);
    return;
  }

  const { isPortrait, ...rest } = payload ?? {};

  const nftTokenSlug = Symbol('nft');
  const previousFeeTokenSlug = global.currentTransfer.nfts?.length ? nftTokenSlug : global.currentTransfer.tokenSlug;
  const nextFeeTokenSlug = payload?.nfts?.length ? nftTokenSlug : payload?.tokenSlug;
  const shouldClearFee = nextFeeTokenSlug && nextFeeTokenSlug !== previousFeeTokenSlug;

  setGlobal(updateCurrentTransfer(global, {
    state: isPortrait ? TransferState.Initial : TransferState.None,
    error: undefined,
    ...(shouldClearFee ? { fee: undefined, realFee: undefined, diesel: undefined } : {}),
    ...rest,
  }));

  if (!isPortrait) {
    actions.setLandscapeActionsActiveTabIndex({ index: ActiveTab.Transfer });
  }
});

addActionHandler('changeTransferToken', (global, actions, { tokenSlug, withResetAmount }) => {
  const { amount, tokenSlug: currentTokenSlug, nfts } = global.currentTransfer;
  if (!nfts?.length && tokenSlug === currentTokenSlug && !withResetAmount) {
    return;
  }

  const currentToken = currentTokenSlug ? global.tokenInfo.bySlug[currentTokenSlug] : undefined;
  const newToken = global.tokenInfo.bySlug[tokenSlug];

  if (withResetAmount) {
    global = updateCurrentTransfer(global, { amount: undefined });
  } else if (amount && currentToken?.decimals !== newToken?.decimals) {
    global = updateCurrentTransfer(global, {
      amount: fromDecimal(toDecimal(amount, currentToken?.decimals), newToken?.decimals),
    });
  }

  setGlobal(updateCurrentTransfer(global, {
    tokenSlug,
    fee: undefined,
    realFee: undefined,
    diesel: undefined,
    nfts: undefined,
  }));
});

addActionHandler('setTransferScreen', (global, actions, payload) => {
  const { state } = payload;

  return updateCurrentTransfer(global, { state });
});

addActionHandler('setTransferAmount', (global, actions, { amount }) => {
  return updateCurrentTransfer(global, { amount });
});

addActionHandler('setTransferToAddress', (global, actions, { toAddress }) => {
  return setCurrentTransferAddress(global, toAddress);
});

addActionHandler('setTransferComment', (global, actions, { comment }) => {
  return updateCurrentTransfer(global, { comment });
});

addActionHandler('setTransferShouldEncrypt', (global, actions, { shouldEncrypt }) => {
  return updateCurrentTransfer(global, { shouldEncrypt });
});

addActionHandler('submitTransferConfirm', async (global, actions) => {
  const inMemoryPassword = await getInMemoryPassword();

  global = getGlobal();

  if (selectIsHardwareAccount(global)) {
    global = resetHardware(global);
    global = updateCurrentTransfer(global, { state: TransferState.ConnectHardware });
    setGlobal(global);
  } else if (inMemoryPassword) {
    global = updateCurrentTransfer(global, { isLoading: true });
    setGlobal(global);
    actions.submitTransfer({ password: inMemoryPassword });
  } else {
    global = updateCurrentTransfer(global, { state: TransferState.Password });
    setGlobal(global);
  }
});

addActionHandler('clearTransferError', (global) => {
  setGlobal(updateCurrentTransfer(global, { error: undefined }));
});

addActionHandler('dismissTransferScamWarning', (global) => {
  if (IS_DELEGATING_BOTTOM_SHEET) {
    callActionInNative('dismissTransferScamWarning');
  }

  global = updateCurrentTransfer(global, { scamWarningType: undefined });
  setGlobal(global);
});

addActionHandler('showTransferScamWarning', (global, actions, { type }) => {
  global = updateCurrentTransfer(global, { scamWarningType: type });
  setGlobal(global);
});
