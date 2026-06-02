import type { ApiNft } from '../../../api/types';
import type { ErrorTransferResult } from '../../helpers/transfer';
import type { GlobalState } from '../../types';
import { DomainLinkingState, DomainRenewalState } from '../../types';

import { callApi } from '../../../api';
import { isErrorTransferResult } from '../../helpers/transfer';
import { handleTransferResults, prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
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
    return;
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
    return;
  }

  setGlobal(updateState(getGlobal(), {
    state,
    ...(results.length === 1 && typeof results[0] === 'string' ? { txId: results[0] } : undefined),
    mfaRequestHash: undefined,
  }));
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

addActionHandler('submitDomainsRenewal', async (global, actions, { password } = {}) => {
  const accountId = selectCurrentAccountId(global)!;
  const nftsByAddress = selectCurrentAccountState(global)?.nfts?.byAddress;
  if (!nftsByAddress) return;

  const nftAddresses = global.currentDomainRenewal.addresses!;
  const realFee = global.currentDomainRenewal.realFee!;
  const nfts = nftAddresses
    .map((address) => nftsByAddress[address])
    .filter<ApiNft>(Boolean);

  if (!nfts.length) return;

  if (!await prepareTransfer(DomainRenewalState.ConfirmHardware, updateCurrentDomainRenewal, password)) {
    return;
  }

  const result = await callApi('submitDnsRenewal', accountId, password, nfts, realFee) ?? [undefined];

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
});

addActionHandler('checkDomainLinkingDraft', async (global, actions, { nft }) => {
  const accountId = selectCurrentAccountId(global)!;
  const currentAddress = selectCurrentAccount(global)!.byChain.ton!.address;

  const result = await callApi('checkDnsChangeWalletDraft', accountId, nft, currentAddress);
  if (!result || 'error' in result) {
    actions.showError({ error: result?.error });
    return;
  }

  global = getGlobal();
  global = updateCurrentDomainLinking(global, { realFee: result.realFee });
  setGlobal(global);
});

addActionHandler('submitDomainLinking', async (global, actions, { password } = {}) => {
  const accountId = selectCurrentAccountId(global)!;
  const network = selectCurrentNetwork(global);
  const nftsByAddress = selectCurrentAccountState(global)?.nfts?.byAddress;
  const nftAddress = global.currentDomainLinking.address!;
  const realFee = global.currentDomainLinking.realFee!;
  const nft = nftsByAddress?.[nftAddress];
  const currentAddress = global.currentDomainLinking.walletAddress!;
  const checkAddressResult = await callApi('getAddressInfo', 'ton', network, currentAddress);

  if (isErrorTransferResult(checkAddressResult)) {
    actions.showError({ error: checkAddressResult?.error });
    return;
  }

  if (!nft) {
    return;
  }

  if (!await prepareTransfer(DomainLinkingState.ConfirmHardware, updateCurrentDomainLinking, password)) {
    return;
  }

  const result = await callApi(
    'submitDnsChangeWallet',
    accountId,
    password,
    nft,
    checkAddressResult.resolvedAddress,
    realFee,
  );

  handleDomainOperationResult<'linking'>(
    [result && 'activityId' in result ? result.activityId
      : result && 'mfaRequestHash' in result ? { mfaRequestHash: result.mfaRequestHash }
        : result],
    updateCurrentDomainLinking,
    DomainLinkingState.Complete,
    DomainLinkingState.ConfirmMfa,
  );
});

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
  const hash = global.currentDomainLinking.mfaRequestHash;
  if (!hash) return;

  const result = await callApi('fetchMfaRequest', hash);

  if (result?.isConfirmed) {
    global = getGlobal();
    global = updateCurrentDomainLinking(global, {
      state: DomainLinkingState.Complete,
      mfaRequestHash: undefined,
    });
    setGlobal(global);
  }
});
