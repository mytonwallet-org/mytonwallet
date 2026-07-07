import type {
  ApiChain,
  ApiSubmitGasfullTransferOptions,
  ApiSwapActivity,
  ApiSwapAsset,
  ApiSwapBuildTransactionRequest,
  ApiSwapBuildTransactionResponse,
  ApiSwapCexLabel,
  ApiSwapEstimateRequest,
  ApiSwapEstimateResponse,
  ApiSwapExecuteTransactionResult,
  ApiSwapHistoryItem,
  ApiSwapPairAsset,
  ApiSwapTransfer,
  ApiWalletByChain,
  OnApiUpdate,
} from '../types';

import { SWAP_API_VERSION } from '../../config';
import { buildLocalTxId } from '../../util/activities';
import chains from '../chains';
import { fetchStoredAccount, fetchStoredWallet } from '../common/accounts';
import { callBackendGet, callBackendPost } from '../common/backend';
import { getBackendConfigCache } from '../common/cache';
import {
  convertSwapItemToTrusted,
  getSwapItemSlug,
  patchSwapItem,
  swapGetHistoryItem,
  swapItemToActivity,
} from '../common/swap';
import { ApiServerError } from '../errors';
import { callHook } from '../hooks';
import { publishSignedMfaRequest } from './mfa';
import { getBackendAuthToken, getStoredBackendAuthToken } from './other';

let onUpdate: OnApiUpdate;

export function initSwap(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function swapBuildTransfer(
  accountId: string,
  password: string,
  request: ApiSwapBuildTransactionRequest,
) {
  const authToken = await getBackendAuthToken(accountId, password);

  // Provide version anyway to avoid unnecessary complexity of multichain method
  // it will be used for TON only.
  const { version } = await fetchStoredWallet(accountId, 'ton');
  request.walletVersion = version;

  const buildResponse = await swapBuild(authToken, request);

  if (buildResponse.route !== 'dex' || !buildResponse.chain) {
    throw new Error('Unexpected non-DEX response for swapBuildTransfer');
  }

  const { id, transfers, chain, transaction } = buildResponse;

  const result = await chains[chain].buildOnchainSwapTransfer({
    accountId,
    request,
    transfers,
    transaction,
    swapId: id,
    authToken,
  });

  return result;
}

export async function swapSubmit(
  chain: ApiChain,
  accountId: string,
  password: string,
  transfers: ApiSwapTransfer[] | undefined,
  historyItem: ApiSwapHistoryItem,
  isGasless?: boolean,
  transaction?: string,
): Promise<{ activityId?: string; mfaRequestHash?: string; swapId: string } | { error: string }> {
  const swapId = historyItem.id;

  const authToken = await getBackendAuthToken(accountId, password);

  const from = getSwapItemSlug(historyItem.from, chain);
  const to = getSwapItemSlug(historyItem.to, chain);

  const localActivityId = buildLocalTxId(swapId);
  const localSwap: ApiSwapActivity = {
    ...historyItem,
    id: localActivityId,
    from,
    to,
    kind: 'swap',
  };

  const result = await chains[chain].submitOnchainSwapTransfer({
    accountId,
    password,
    transfers,
    transaction,
    historyItem,
    isGasless,
    authToken,
    localSwap,
    swapId,
    executeSwap: (signedTransaction) => swapExecute(authToken, swapId, signedTransaction),
  }, onUpdate);

  if ('error' in result) {
    return result;
  }

  if ('mfaRequest' in result) {
    const { mfaRequestHash } = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);

    return { swapId, mfaRequestHash };
  }

  return { activityId: result.activityId, swapId };
}

export async function confirmSwapMfaRequest(accountId: string, swapId: string, txHash: string) {
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const authToken = await getStoredBackendAuthToken(accountId);

  if (!authToken) {
    throw new Error('Missing backend auth token for swap MFA confirmation');
  }

  await patchSwapItem({
    address,
    swapId,
    authToken,
    msgHash: txHash,
  });
}

export async function fetchSwaps(
  accountId: string,
  items: Array<{ id: string; chain?: ApiChain }>,
) {
  const account = await fetchStoredAccount(accountId);
  const walletByChain = account.byChain as Partial<Record<ApiChain, ApiWalletByChain[ApiChain]>>;

  const perIdResults = await Promise.all(items.map(async ({ id, chain: chainHint }) => {
    const backendId = id.replace('swap:', '');
    const lookupEntries = getSwapHistoryLookupEntries(walletByChain, chainHint);

    if (!lookupEntries.length) {
      return { id };
    }

    const attempts = await Promise.allSettled(
      lookupEntries.map(async ({ address }) => swapGetHistoryItem(address, backendId)),
    );

    const fulfilled = attempts.find((r) => r.status === 'fulfilled');
    if (fulfilled) {
      return { id, found: fulfilled.value };
    }

    const isAllNotFound = attempts.every((r) => (
      r.status === 'rejected'
      && r.reason instanceof ApiServerError
      && r.reason.statusCode === 404
    ));

    return { id, isNonExistent: isAllNotFound };
  }));

  const nonExistentIds: string[] = [];
  const swaps: ApiSwapActivity[] = [];

  for (const result of perIdResults) {
    if (result.found) {
      swaps.push(swapItemToActivity(result.found));
    } else if (result.isNonExistent) {
      nonExistentIds.push(result.id);
    }
  }

  return { nonExistentIds, swaps };
}

type SwapHistoryLookupEntry = {
  address: string;
};

function getSwapHistoryLookupEntries(
  walletByChain: Partial<Record<ApiChain, ApiWalletByChain[ApiChain]>>,
  chainHint?: ApiChain,
): SwapHistoryLookupEntry[] {
  const historyAddress = walletByChain.ton?.address;
  const result: SwapHistoryLookupEntry[] = [];

  if (historyAddress) {
    result.push({ address: historyAddress });
  }

  const fallbackEntries = chainHint
    ? [[chainHint, walletByChain[chainHint]] as [ApiChain, ApiWalletByChain[ApiChain] | undefined]]
    : (Object.entries(walletByChain) as [ApiChain, ApiWalletByChain[ApiChain]][]);

  for (const [, wallet] of fallbackEntries) {
    if (wallet?.address && wallet.address !== historyAddress) {
      result.push({ address: wallet.address });
    }
  }

  return result;
}

export async function swapEstimate(
  accountId: string,
  request: ApiSwapEstimateRequest,
): Promise<ApiSwapEstimateResponse | { error: string }> {
  const walletVersion = (await fetchStoredWallet(accountId, 'ton')).version;
  const { swapVersion } = await getBackendConfigCache();

  return callBackendPost('/swap/estimate', {
    ...request,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    walletVersion,
  }, {
    isAllowBadRequest: true,
  });
}

export async function swapBuild(
  authToken: string,
  request: ApiSwapBuildTransactionRequest,
): Promise<ApiSwapBuildTransactionResponse> {
  const { swapVersion } = await getBackendConfigCache();

  return callBackendPost('/swap/buildTransaction', {
    ...request,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    isMsgHashMode: true,
  }, {
    authToken,
  });
}

export function swapExecute(
  authToken: string,
  swapId: string,
  signedTransaction: string,
): Promise<ApiSwapExecuteTransactionResult> {
  return callBackendPost('/swap/execute', {
    swapId,
    signedTransaction,
  }, {
    authToken,
  });
}

export function swapGetAssets(): Promise<ApiSwapAsset[]> {
  return callBackendGet('/swap/assets');
}

export function swapGetPairs(symbolOrTokenAddress: string): Promise<ApiSwapPairAsset[]> {
  return callBackendGet('/swap/pairs', { asset: symbolOrTokenAddress });
}

export function swapCexValidateAddress(params: { slug: string; address: string; cexLabel?: ApiSwapCexLabel }): Promise<{
  result: boolean;
  message?: string;
}> {
  return callBackendGet('/swap/cex/validate-address', params);
}

export async function swapCexCreateTransaction(
  accountId: string,
  password: string,
  request: ApiSwapBuildTransactionRequest,
): Promise<{
    swap: ApiSwapHistoryItem;
    activity: ApiSwapActivity;
  }> {
  const authToken = await getBackendAuthToken(accountId, password);

  const buildResponse = await swapBuild(authToken, request);

  if (buildResponse.route !== 'cex') {
    throw new Error('Unexpected non-CEX response for swapCexCreateTransaction');
  }

  const swap = convertSwapItemToTrusted(buildResponse.swap);

  const activity = swapItemToActivity(swap);

  onUpdate({
    type: 'newActivities',
    accountId,
    activities: [activity],
  });

  void callHook('onSwapCreated', accountId, swap.timestamp - 1);

  return { swap, activity };
}

export async function swapCexSubmit(chain: ApiChain, transferOptions: ApiSubmitGasfullTransferOptions, swapId: string) {
  const result = await chains[chain].submitGasfullTransfer(transferOptions);

  if ('error' in result) {
    return result;
  }

  if (result.mfaRequest) {
    const { accountId } = transferOptions;
    const { mfaRequestHash } = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);

    return { swapId, mfaRequestHash };
  }

  const txHash = result.msgHashForCexSwap ?? result.txId;
  if (txHash) {
    const { accountId, password } = transferOptions;
    // CEX swap history rows are owned by the TON history address even when the
    // actual deposit transfer is submitted from another source chain.
    const { address: historyAddress } = await fetchStoredWallet(accountId, 'ton');
    const authToken = await getBackendAuthToken(accountId, password ?? '');
    await patchSwapItem({ address: historyAddress, authToken, msgHash: txHash, swapId });
  }

  return result;
}
