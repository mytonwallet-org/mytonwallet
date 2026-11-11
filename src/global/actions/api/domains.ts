import type { ApiNft } from '../../../api/types';
import type { ErrorTransferResult } from '../../helpers/transfer';
import type { GlobalState } from '../../types';
import { DomainLinkingState, DomainRenewalState } from '../../types';

import { getTranslation } from '../../../util/langProvider';
import { callApi } from '../../../api';
import { withEnclaveSessionRelease } from '../../helpers/enclave';
import { isErrorTransferResult } from '../../helpers/transfer';
import { handleTransferResults, prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { updateCurrentDomainLinking, updateCurrentDomainRenewal } from '../../reducers';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentNetwork,
} from '../../selectors';

type DomainOperationResultSuccess = string | { mfaRequestHash: string };
type DomainOperationResult = Array<DomainOperationResultSuccess | ErrorTransferResult>;
type DomainOperationType = 'renewal' | 'linking';

type DomainStateUpdate<T extends DomainOperationType> = {
  isLoading: boolean;
  error?: string;
  txId?: string;
  mfaRequestHash?: string;
  state: T extends 'renewal' ? DomainRenewalState : DomainLinkingState;
};

type DomainStateReducer<T extends DomainOperationType> = (
  global: GlobalState,
  update: Partial<DomainStateUpdate<T>>,
) => GlobalState;

function handleDomainOperationResult<T extends DomainOperationType>(
  results: DomainOperationResult,
  updateState: DomainStateReducer<T>,
  state: T extends 'renewal' ? DomainRenewalState : DomainLinkingState,
  mfaState: T extends 'renewal' ? DomainRenewalState : DomainLinkingState,
) {
  if (!handleTransferResults(results, updateState)) {
    return false;
  }

  const mfaResult = results.find((result): result is { mfaRequestHash: string } => {
    return Boolean(result) && typeof result === 'object' && 'mfaRequestHash' in result;
  });

  if (mfaResult) {
    setGlobal(updateState(getGlobal(), {
      state: mfaState,
      mfaRequestHash: mfaResult.mfaRequestHash,
      txId: undefined,
    }));
    return false;
  }

  setGlobal(updateState(getGlobal(), {
    state,
    ...(results.length === 1 && typeof results[0] === 'string' ? { txId: results[0] } : undefined),
    mfaRequestHash: undefined,
  }));

  return true;
}

addActionHandler('checkDomainsRenewalDraft', async (global, actions, { nfts }) => {
  const accountId = selectCurrentAccountId(global)!;

  const result = await callApi('checkDnsRenewalDraft', accountId, nfts);
  if (!result || 'error' in result) {
    actions.showError({ error: result?.error });
    return;
  }

  global = getGlobal();
  global = updateCurrentDomainRenewal(global, { realFee: result.realFee });
  setGlobal(global);
});

addActionHandler('submitDomainsRenewal', withEnclaveSessionRelease(async (global, actions, payload) => {
  const { enclaveToken } = payload ?? {};
  const accountId = selectCurrentAccountId(global)!;
  const nftsByAddress = selectCurrentAccountState(global)?.nfts?.byAddress;
  if (!nftsByAddress) return;

  const nftAddresses = global.currentDomainRenewal.addresses!;
  const realFee = global.currentDomainRenewal.realFee!;
  const nfts = nftAddresses
    .map((address) => nftsByAddress[address])
    .filter<ApiNft>(Boolean);

  if (!nfts.length) return;

  if (!prepareTransfer(DomainRenewalState.ConfirmHardware, updateCurrentDomainRenewal)) {
    return;
  }

  const result = await callApi('submitDnsRenewal', accountId, enclaveToken, nfts, realFee) ?? [undefined];

  handleDomainOperationResult<'renewal'>(
    result.map((subResult) => (
      subResult && 'activityIds' in subResult ? subResult.activityIds[0]
        : subResult && 'mfaRequestHash' in subResult ? { mfaRequestHash: subResult.mfaRequestHash }
          : subResult
    )),
    updateCurrentDomainRenewal,
    DomainRenewalState.Complete,
    DomainRenewalState.ConfirmMfa,
  );
}));

addActionHandler('checkDomainLinkingDraft', async (global, actions, { nft }) => {
  const accountId = selectCurrentAccountId(global)!;
  const currentAddress = global.currentDomainLinking.isUnlinking
    ? undefined
    : selectCurrentAccount(global)!.byChain.ton!.address;

  const result = await callApi('checkDnsChangeWalletDraft', accountId, nft, currentAddress);
  if (!result || 'error' in result) {
    actions.showError({ error: result?.error });
    return;
  }

  global = getGlobal();
  global = updateCurrentDomainLinking(global, { realFee: result.realFee });
  setGlobal(global);
});

addActionHandler('submitDomainLinking', withEnclaveSessionRelease(async (global, actions, payload) => {
  const { enclaveToken } = payload ?? {};
  const accountId = selectCurrentAccountId(global)!;
  const network = selectCurrentNetwork(global);
  const nftsByAddress = selectCurrentAccountState(global)?.nfts?.byAddress;
  const nftAddress = global.currentDomainLinking.address!;
  const realFee = global.currentDomainLinking.realFee!;
  const { isUnlinking } = global.currentDomainLinking;
  const nft = nftsByAddress?.[nftAddress];
  let linkedAddress: string | undefined;

  if (!isUnlinking) {
    const currentAddress = global.currentDomainLinking.walletAddress!;
    const checkAddressResult = await callApi('getAddressInfo', 'ton', network, currentAddress);

    if (isErrorTransferResult(checkAddressResult)) {
      actions.showError({ error: checkAddressResult?.error });
      return;
    }

    linkedAddress = checkAddressResult.resolvedAddress;
  }

  if (!nft) {
    return;
  }

  if (!prepareTransfer(DomainLinkingState.ConfirmHardware, updateCurrentDomainLinking)) {
    return;
  }

  const result = await callApi(
    'submitDnsChangeWallet',
    accountId,
    enclaveToken,
    nft,
    linkedAddress,
    realFee,
  );

  const isCompleted = handleDomainOperationResult<'linking'>(
    [result && 'activityId' in result ? result.activityId
      : result && 'mfaRequestHash' in result ? { mfaRequestHash: result.mfaRequestHash }
        : result],
    updateCurrentDomainLinking,
    DomainLinkingState.None,
    DomainLinkingState.ConfirmMfa,
  );
  if (isCompleted) {
    completeDomainLinking(isUnlinking);
  }
}));

addActionHandler('checkLinkingAddress', async (global, actions, { address }) => {
  if (!address) {
    global = updateCurrentDomainLinking(global, { walletAddressName: undefined, resolvedWalletAddress: undefined });
    setGlobal(global);

    return;
  }

  const network = selectCurrentNetwork(global);
  const result = await callApi('getAddressInfo', 'ton', network, address);

  global = getGlobal();
  if (isErrorTransferResult(result)) {
    global = updateCurrentDomainLinking(global, { walletAddressName: undefined, resolvedWalletAddress: undefined });
  } else {
    global = updateCurrentDomainLinking(global, {
      walletAddressName: result.addressName,
      resolvedWalletAddress: result.resolvedAddress,
    });
  }
  setGlobal(global);
});

addActionHandler('updateDomainsRenewalMfaRequestStatus', async (global) => {
  const hash = global.currentDomainRenewal.mfaRequestHash;
  if (!hash) return;

  const result = await callApi('fetchMfaRequest', hash);

  if (result?.isConfirmed) {
    global = getGlobal();
    global = updateCurrentDomainRenewal(global, {
      state: DomainRenewalState.Complete,
      mfaRequestHash: undefined,
    });
    setGlobal(global);
  }
});

addActionHandler('updateDomainLinkingMfaRequestStatus', async (global) => {
  const { mfaRequestHash: hash, isUnlinking } = global.currentDomainLinking;
  if (!hash) return;

  const result = await callApi('fetchMfaRequest', hash);

  // The status is polled every second, so a slow response may arrive after the modal is closed or shows another request
  if (result?.isConfirmed && getGlobal().currentDomainLinking.mfaRequestHash === hash) {
    completeDomainLinking(isUnlinking);
  }
});

function completeDomainLinking(isUnlinking?: boolean) {
  const actions = getActions();
  actions.cancelDomainLinking();
  actions.showToast({
    message: isUnlinking ? getTranslation('Domain Unlinked') : getTranslation('Domain Linked'),
    icon: 'icon-check',
  });
}
