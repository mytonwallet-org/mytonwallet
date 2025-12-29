import { Cell } from '@ton/core';

import type { TonTransferParams } from '../chains/ton/types';
import type {
  ApiChain,
  ApiSubmitGasfullTransferOptions,
  ApiSwapActivity,
  ApiSwapAsset,
  ApiSwapBuildRequest,
  ApiSwapBuildResponse,
  ApiSwapCexCreateTransactionRequest,
  ApiSwapCexCreateTransactionResponse,
  ApiSwapCexEstimateRequest,
  ApiSwapCexEstimateResponse,
  ApiSwapEstimateRequest,
  ApiSwapEstimateResponse,
  ApiSwapHistoryItem,
  ApiSwapPairAsset,
  ApiSwapTransfer,
  OnApiUpdate,
} from '../types';

import { SWAP_API_VERSION, TONCOIN } from '../../config';
import { parseAccountId } from '../../util/account';
import { buildLocalTxId } from '../../util/activities';
import { omitUndefined } from '../../util/iteratees';
import chains from '../chains';
import * as ton from '../chains/ton';
import { fetchStoredChainAccount, fetchStoredWallet } from '../common/accounts';
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
import { getBackendAuthToken } from './other';

let onUpdate: OnApiUpdate;

export function initSwap(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function swapBuildTransfer(
  accountId: string,
  password: string,
  request: ApiSwapBuildRequest,
) {
  const { network } = parseAccountId(accountId);
  const authToken = await getBackendAuthToken(accountId, password);

  const { address, version } = await fetchStoredWallet(accountId, 'ton');
  request.walletVersion = version;

  const { id, transfers } = await swapBuild(authToken, request);

  const transferList = parseSwapTransfers(transfers);

  try {
    const account = await fetchStoredChainAccount(accountId, 'ton');
    await ton.validateDexSwapTransfers(network, address, request, transferList, account);

    const result = await ton.checkMultiTransactionDraft(accountId, transferList, request.shouldTryDiesel);

    if ('error' in result) {
      await patchSwapItem({
        address, swapId: id, authToken, error: result.error,
      });
      return result;
    }

    return { ...result, id, transfers };
  } catch (err: any) {
    await patchSwapItem({
      address, swapId: id, authToken, error: errorToString(err),
    });
    throw err;
  }
}

export async function swapSubmit(
  accountId: string,
  password: string,
  transfers: ApiSwapTransfer[],
  historyItem: ApiSwapHistoryItem,
  isGasless?: boolean,
) {
  const swapId = historyItem.id;
  const tonWallet = await fetchStoredWallet(accountId, 'ton');

  const { address } = tonWallet;
  const authToken = await getBackendAuthToken(accountId, password);

  const from = getSwapItemSlug(historyItem, historyItem.from);
  const to = getSwapItemSlug(historyItem, historyItem.to);

  const localActivityId = buildLocalTxId(swapId);
  const localSwap: ApiSwapActivity = {
    ...historyItem,
    id: localActivityId,
    from,
    to,
    kind: 'swap',
  };

  onUpdate({
    type: 'newLocalActivities',
    accountId,
    activities: [localSwap],
  });

  try {
    const transferList = parseSwapTransfers(transfers);

    if (historyItem.from !== TONCOIN.symbol) {
      transferList[0] = await ton.insertMintlessPayload('mainnet', address, historyItem.from, transferList[0]);
    }

    const result = await ton.submitMultiTransfer({
      accountId,
      password,
      messages: transferList,
      isGasless,
    });

    if ('error' in result) {
      // Update local activity to show error state
      onUpdate({
        type: 'newLocalActivities',
        accountId,
        activities: [{ ...localSwap, status: 'failed' }],
      });

      await patchSwapItem({
        address, swapId, authToken, error: result.error,
      });
      return result;
    }

    delete result.messages[0].stateInit;

    const updatedSwap: ApiSwapActivity = {
      ...localSwap,
      externalMsgHashNorm: result.msgHashNormalized,
      extra: omitUndefined({
        withW5Gasless: result.withW5Gasless,
      }),
    };

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [updatedSwap],
    });

    await patchSwapItem({
      address, swapId, authToken, msgHash: result.msgHash,
    });

    void callHook('onSwapCreated', accountId, updatedSwap.timestamp - 1);

    return { activityId: updatedSwap.id };
  } catch (err: any) {
    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [{ ...localSwap, status: 'failed' }],
    });

    await patchSwapItem({
      address, swapId, authToken, error: errorToString(err),
    });
    throw err;
  }
}

function errorToString(err: Error | string) {
  return typeof err === 'string' ? err : err.stack;
}

export async function fetchSwaps(accountId: string, ids: string[]) {
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const results = await Promise.allSettled(
    ids.map((id) => swapGetHistoryItem(address, id.replace('swap:', ''))),
  );

  const nonExistentIds: string[] = [];

  const swaps = results
    .map((result, i) => {
      if (result.status === 'rejected') {
        if (result.reason instanceof ApiServerError && result.reason.statusCode === 404) {
          nonExistentIds.push(ids[i]);
        }
        return undefined;
      }

      return swapItemToActivity(result.value);
    })
    .filter(Boolean);

  return { nonExistentIds, swaps };
}

export async function swapEstimate(
  accountId: string,
  request: ApiSwapEstimateRequest,
): Promise<ApiSwapEstimateResponse | { error: string }> {
  const walletVersion = (await fetchStoredWallet(accountId, 'ton')).version;
  const { swapVersion } = await getBackendConfigCache();

  return callBackendPost('/swap/ton/estimate', {
    ...request,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    walletVersion,
  }, {
    isAllowBadRequest: true,
  });
}

export async function swapBuild(authToken: string, request: ApiSwapBuildRequest): Promise<ApiSwapBuildResponse> {
  const { swapVersion } = await getBackendConfigCache();

  return callBackendPost('/swap/ton/build', {
    ...request,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    isMsgHashMode: true,
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

export function swapCexEstimate(
  request: ApiSwapCexEstimateRequest,
): Promise<ApiSwapCexEstimateResponse | { error: string }> {
  return callBackendPost<ApiSwapCexEstimateResponse | { error: string }>(
    '/swap/cex/estimate',
    request,
    { isAllowBadRequest: true },
  );
}

export function swapCexValidateAddress(params: { slug: string; address: string }): Promise<{
  result: boolean;
  message?: string;
}> {
  return callBackendGet('/swap/cex/validate-address', params);
}

export async function swapCexCreateTransaction(
  accountId: string,
  password: string,
  request: ApiSwapCexCreateTransactionRequest,
): Promise<{
    swap: ApiSwapHistoryItem;
    activity: ApiSwapActivity;
  }> {
  const authToken = await getBackendAuthToken(accountId, password);
  const { swapVersion } = await getBackendConfigCache();

  const { swap: rawSwap } = await callBackendPost<ApiSwapCexCreateTransactionResponse>('/swap/cex/createTransaction', {
    ...request,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
  }, {
    authToken,
  });

  const swap = convertSwapItemToTrusted(rawSwap);
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

  if (!('error' in result) && result.msgHashForCexSwap) {
    const { accountId, password } = transferOptions;
    const { address } = await fetchStoredWallet(accountId, chain);
    const authToken = await getBackendAuthToken(accountId, password ?? '');
    await patchSwapItem({ address, authToken, msgHash: result.msgHashForCexSwap, swapId });
  }

  return result;
}

function parseSwapTransfers(transfers: ApiSwapTransfer[]): TonTransferParams[] {
  return transfers.map((transfer) => ({
    ...transfer,
    amount: BigInt(transfer.amount),
    payload: Cell.fromBase64(transfer.payload),
  }));
}
