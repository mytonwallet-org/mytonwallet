import type {
  ApiChain,
  ApiCheckTransactionDraftResult,
  ApiSubmitTransferOptions,
  ApiTransferPayload,
} from '../../../api/types';
import type { GlobalState } from '../../types';
import { ApiTransactionDraftError } from '../../../api/types';
import { ScamWarningType, TransferState } from '../../types';

import { NFT_BATCH_SIZE } from '../../../config';
import { bigintDivideToNumber } from '../../../util/bigint';
import { getDoesUsePinPad } from '../../../util/biometrics';
import { getChainConfig } from '../../../util/chain';
import { explainApiTransferFee, getDieselTokenAmount } from '../../../util/fee/transferFee';
import { split } from '../../../util/iteratees';
import { callActionInNative } from '../../../util/multitab';
import { shouldShowDomainScamWarning, shouldShowSeedPhraseScamWarning } from '../../../util/scamDetection';
import { getIsTonToken } from '../../../util/tokens';
import { IS_DELEGATING_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { handleTransferResult, prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  clearCurrentTransfer,
  clearIsPinAccepted,
  preserveMaxTransferAmount,
  updateAccountState,
  updateCurrentTransfer,
  updateCurrentTransferByCheckResult,
  updateCurrentTransferLoading,
} from '../../reducers';
import {
  selectAccountState,
  selectCurrentAccount,
  selectCurrentAccountTokens,
  selectCurrentNetwork,
  selectIsHardwareAccount,
  selectToken,
} from '../../selectors';

addActionHandler('submitTransferInitial', async (global, actions, payload) => {
  if (IS_DELEGATING_BOTTOM_SHEET) {
    callActionInNative('submitTransferInitial', payload);
    return;
  }

  const {
    tokenSlug,
    toAddress,
    amount,
    comment,
    shouldEncrypt,
    nfts,
    isGasless,
    stateInit,
    isGaslessWithStars,
    binPayload,
  } = payload;

  setGlobal(updateCurrentTransferLoading(global, true));

  const isNftTransfer = Boolean(nfts?.length);
  let result: ApiCheckTransactionDraftResult | undefined;

  if (isNftTransfer) {
    result = await callApi('checkNftTransferDraft', {
      accountId: global.currentAccountId!,
      nfts,
      toAddress,
      comment,
    });
  } else {
    const { tokenAddress, chain } = selectToken(global, tokenSlug);
    result = await callApi('checkTransactionDraft', chain, {
      accountId: global.currentAccountId!,
      tokenAddress,
      toAddress,
      amount,
      payload: getTransferPayload(chain, binPayload, comment, shouldEncrypt),
      stateInit,
      allowGasless: true,
    });
  }

  global = getGlobal();
  global = updateCurrentTransferLoading(global, false);

  if (result) {
    global = updateCurrentTransferByCheckResult(global, result);
  }

  if (!result || 'error' in result) {
    setGlobal(global);

    if (result?.error === ApiTransactionDraftError.InsufficientBalance && !isNftTransfer) {
      actions.showDialog({ message: 'The network fee has slightly changed, try sending again.' });
    } else {
      actions.showError({ error: result?.error });
    }

    return;
  }

  setGlobal(updateCurrentTransfer(global, {
    state: TransferState.Confirm,
    error: undefined,
    toAddress,
    resolvedAddress: result.resolvedAddress,
    amount,
    comment,
    shouldEncrypt,
    tokenSlug,
    isToNewAddress: result.isToAddressNew,
    isGasless,
    isGaslessWithStars,
  }));
});

addActionHandler('fetchTransferFee', async (global, actions, payload) => {
  global = updateCurrentTransfer(global, { isLoading: true, error: undefined });
  setGlobal(global);

  const {
    tokenSlug, toAddress, comment, shouldEncrypt, binPayload, stateInit,
  } = payload;

  const { tokenAddress, chain } = selectToken(global, tokenSlug);

  const result = await callApi('checkTransactionDraft', chain, {
    accountId: global.currentAccountId!,
    toAddress,
    payload: getTransferPayload(chain, binPayload, comment, shouldEncrypt),
    tokenAddress,
    stateInit,
    allowGasless: true,
  });

  global = getGlobal();
  if (hasCurrentTokenChanged(global, tokenSlug)) {
    return;
  }

  global = updateCurrentTransfer(global, { isLoading: false });
  if (result) {
    global = updateCurrentTransferByCheckResult(global, result);
  }
  setGlobal(global);

  if (result?.error && result.error !== ApiTransactionDraftError.InsufficientBalance) {
    actions.showError({ error: result.error });
  }

  if (result?.error === ApiTransactionDraftError.InsufficientBalance) {
    const currentAccount = selectCurrentAccount(global)!;
    const accountTokens = selectCurrentAccountTokens(global)!;
    const { chain } = selectToken(global, tokenSlug);

    if (shouldShowSeedPhraseScamWarning(currentAccount, accountTokens, chain)) {
      global = getGlobal();
      global = updateCurrentTransfer(global, { scamWarningType: ScamWarningType.SeedPhrase });
      setGlobal(global);
    }
  }

  if (result?.error !== ApiTransactionDraftError.DomainNotResolved && shouldShowDomainScamWarning(toAddress)) {
    global = getGlobal();
    global = updateCurrentTransfer(global, { scamWarningType: ScamWarningType.DomainLike });
    setGlobal(global);
  }
});

addActionHandler('fetchNftFee', async (global, actions, payload) => {
  const { toAddress, nfts, comment } = payload;
  const chain = 'ton';

  global = updateCurrentTransfer(global, { isLoading: true, error: undefined });
  setGlobal(global);

  const result = await callApi('checkNftTransferDraft', {
    accountId: global.currentAccountId!,
    nfts,
    toAddress,
    comment: getNftTransferComment(chain, comment),
  });

  global = getGlobal();

  if (!global.currentTransfer.nfts?.length) {
    // For cases when the user switches the token transfer mode before the result arrives
    return;
  }

  global = updateCurrentTransfer(global, { isLoading: false });
  if (result) {
    global = updateCurrentTransferByCheckResult(global, result);
  }
  if (shouldShowDomainScamWarning(toAddress)) {
    global = updateCurrentTransfer(global, { scamWarningType: ScamWarningType.DomainLike });
  }
  setGlobal(global);

  if (result?.error) {
    actions.showError({
      error: result?.error === ApiTransactionDraftError.InsufficientBalance
        ? 'Insufficient TON for fee.'
        : result.error,
    });
  }
});

addActionHandler('submitTransfer', async (global, actions, { password } = {}) => {
  const {
    resolvedAddress,
    comment,
    amount,
    promiseId,
    tokenSlug,
    shouldEncrypt,
    binPayload,
    nfts,
    isGasless,
    diesel,
    stateInit,
    isGaslessWithStars,
  } = global.currentTransfer;

  if (!await prepareTransfer(TransferState.ConfirmHardware, updateCurrentTransfer, password)) {
    return;
  }

  // This is a part of the legacy dapp transaction mechanism. See `promiseId` in `src/global/types.ts` for more details.
  if (promiseId) {
    await callApi('confirmDappRequest', promiseId, password);
    return;
  }

  global = getGlobal();
  const explainedFee = explainApiTransferFee(global.currentTransfer);
  const fullNativeFee = explainedFee.fullFee?.nativeSum;
  const realNativeFee = explainedFee.realFee?.nativeSum;

  let result: { activityId: string } | { activityIds: string[] } | { error: string } | undefined;

  if (nfts?.length) {
    const chain = 'ton';
    const chunks = split(nfts, selectIsHardwareAccount(global) ? 1 : NFT_BATCH_SIZE);

    for (const chunk of chunks) {
      const batchResult = await callApi(
        'submitNftTransfers',
        global.currentAccountId!,
        password,
        chunk,
        resolvedAddress!,
        getNftTransferComment(chain, comment),
        realNativeFee && bigintDivideToNumber(realNativeFee, nfts.length / chunk.length),
      );

      global = getGlobal();
      global = updateCurrentTransfer(global, {
        sentNftsCount: (global.currentTransfer.sentNftsCount || 0) + chunk.length,
      });
      setGlobal(global);
      // TODO - process all responses from the API
      result = batchResult;
    }
  } else {
    const { tokenAddress, chain } = selectToken(global, tokenSlug);

    const options: ApiSubmitTransferOptions = {
      accountId: global.currentAccountId!,
      password,
      toAddress: resolvedAddress!,
      amount: amount!,
      payload: getTransferPayload(chain, binPayload, comment, shouldEncrypt),
      tokenAddress,
      fee: fullNativeFee,
      realFee: realNativeFee,
      isGasless,
      dieselAmount: diesel && getDieselTokenAmount(diesel),
      stateInit,
      isGaslessWithStars,
      noFeeCheck: true,
    };

    result = await callApi('submitTransfer', chain, options);
  }

  if (!handleTransferResult(result, updateCurrentTransfer)) {
    return;
  }

  setGlobal(updateCurrentTransfer(getGlobal(), {
    state: TransferState.Complete,
    txId: ('activityIds' in result && result.activityIds[0])
      || ('activityId' in result && result.activityId)
      || undefined,
  }));

  if (getIsTonToken(tokenSlug)) {
    actions.fetchTransferDieselState({ tokenSlug });
  }
});

addActionHandler('cancelTransfer', (global, actions, { shouldReset } = {}) => {
  const { promiseId, tokenSlug } = global.currentTransfer;

  if (shouldReset) {
    if (promiseId) {
      void callApi('cancelDappRequest', promiseId, 'Canceled by the user');
    }

    global = clearCurrentTransfer(global);
    global = updateCurrentTransfer(global, { tokenSlug });

    setGlobal(global);
    return;
  }

  if (getDoesUsePinPad()) {
    global = clearIsPinAccepted(global);
  }
  global = updateCurrentTransfer(global, { state: TransferState.None });
  setGlobal(global);
});

addActionHandler('fetchTransferDieselState', async (global, actions, { tokenSlug }) => {
  const { tokenAddress, chain } = selectToken(global, tokenSlug);
  if (!tokenAddress) return;

  const diesel = await callApi('fetchEstimateDiesel', global.currentAccountId!, chain, tokenAddress);
  if (!diesel) return;

  global = getGlobal();
  if (hasCurrentTokenChanged(global, tokenSlug)) {
    return;
  }

  const accountState = selectAccountState(global, global.currentAccountId!);
  global = preserveMaxTransferAmount(global, updateCurrentTransfer(global, { diesel }));
  if (accountState?.isDieselAuthorizationStarted && diesel.status !== 'not-authorized') {
    global = updateAccountState(global, global.currentAccountId!, { isDieselAuthorizationStarted: undefined });
  }
  setGlobal(global);
});

addActionHandler('checkTransferAddress', async (global, actions, { address }) => {
  if (!address) {
    global = updateCurrentTransfer(global, { toAddressName: undefined, resolvedAddress: undefined });
    setGlobal(global);

    return;
  }

  const network = selectCurrentNetwork(global);
  const result = await callApi('getAddressInfo', network, address);

  global = getGlobal();
  if (!result || 'error' in result) {
    global = updateCurrentTransfer(global, { toAddressName: undefined, resolvedAddress: undefined });
  } else {
    global = updateCurrentTransfer(global, {
      toAddressName: result.addressName,
      resolvedAddress: result.resolvedAddress,
    });
  }
  setGlobal(global);
});

function getTransferPayload(
  chain: ApiChain,
  binPayload?: string,
  comment?: string,
  shouldEncryptComment?: boolean,
): ApiTransferPayload | undefined {
  if (!getChainConfig(chain).isTransferPayloadSupported) {
    return undefined;
  }

  if (binPayload) return { type: 'base64', data: binPayload };
  if (comment) return { type: 'comment', text: comment, shouldEncrypt: shouldEncryptComment };
  return undefined;
}

function getNftTransferComment(chain: ApiChain, comment?: string) {
  return getChainConfig(chain).isTransferPayloadSupported ? comment : undefined;
}

/** For cases when the user switches the token before the API result arrives */
function hasCurrentTokenChanged(currentGlobal: GlobalState, oldSlug: string) {
  const { tokenSlug, nfts } = currentGlobal.currentTransfer;
  return oldSlug !== tokenSlug || nfts?.length;
}
