import type {
  ApiActivity,
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
import { logDebugError } from '../../util/logs';
import chains from '../chains';
import { fetchStoredAccount, fetchStoredWallet } from '../common/accounts';
import {
  expireActiveCexSwaps,
  rememberActiveCexSwap,
  rememberActiveCexSwaps,
  rememberActiveCexSwapSubmittedHashes,
} from '../common/activities/reconciler/activeCexSwapState';
import {
  buildCexSwapRefreshPatch,
  normalizeCexSwapRefreshActivity,
} from '../common/activities/reconciler/cexSwapReconciler';
import {
  buildSwapOperationId,
  getWalletOperationIntents,
  rememberCexSwapOperationIntent,
  rememberDexSwapOperationIntent,
  rememberWalletOperationSubmittedHashes,
} from '../common/activities/reconciler/operationIntentStore';
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
  enclaveToken: string,
  request: ApiSwapBuildTransactionRequest,
) {
  const authToken = await getBackendAuthToken(accountId, enclaveToken);

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
  enclaveToken: string,
  transfers: ApiSwapTransfer[] | undefined,
  historyItem: ApiSwapHistoryItem,
  isGasless?: boolean,
  transaction?: string,
): Promise<{ activityId?: string; mfaRequestHash?: string; swapId: string } | { error: string }> {
  const swapId = historyItem.id;

  const authToken = await getBackendAuthToken(accountId, enclaveToken);

  const from = getSwapItemSlug(historyItem.from, chain);
  const to = getSwapItemSlug(historyItem.to, chain);

  const localActivityId = buildLocalTxId(swapId);
  const operationId = buildSwapOperationId(swapId);
  const localSwap: ApiSwapActivity = {
    ...historyItem,
    id: localActivityId,
    from,
    to,
    kind: 'swap',
    extra: {
      reconciliation: {
        operationId,
        sourceActionIds: [localActivityId],
        hiddenSourceActionIds: [],
        reason: 'local-intent',
      },
    },
  };
  await rememberDexSwapOperationIntent(accountId, localSwap, { gasless: isGasless });

  const result = await chains[chain].submitOnchainSwapTransfer({
    accountId,
    enclaveToken,
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
    await rememberDexSwapOperationIntent(accountId, { ...localSwap, status: 'failed' }, { gasless: isGasless });
    return result;
  }

  if ('mfaRequest' in result) {
    const { mfaRequestHash } = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);

    return { swapId, mfaRequestHash };
  }

  await rememberWalletOperationSubmittedHashes(accountId, operationId, result.submittedHashes);

  return { activityId: result.activityId, swapId };
}

export async function confirmSwapMfaRequest(accountId: string, swapId: string, txHash: string) {
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const authToken = await getStoredBackendAuthToken(accountId);

  if (!authToken) {
    throw new Error('Missing backend auth token for swap MFA confirmation');
  }

  await rememberWalletOperationSubmittedHashes(accountId, buildSwapOperationId(swapId), [txHash]);
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
  existingActivities: ApiActivity[] = [],
  options: { forceProviderRefresh?: boolean } = {},
) {
  const account = await fetchStoredAccount(accountId);
  const walletByChain = account.byChain as Partial<Record<ApiChain, ApiWalletByChain[ApiChain]>>;
  const authToken = options.forceProviderRefresh ? await getStoredBackendAuthToken(accountId) : undefined;
  const historyOptions = options.forceProviderRefresh
    ? { ...options, forceProviderRefresh: Boolean(authToken), authToken }
    : options;

  const perIdResults = await Promise.all(items.map(async ({ id, chain: chainHint }) => {
    const backendId = id.replace('swap:', '');

    // Fast path: caller knows the originating chain. Solana swap history is stored under the TON owner address.
    if (chainHint) {
      const historyChain = chainHint === 'solana' ? 'ton' : chainHint;
      const address = walletByChain[historyChain]?.address;
      if (!address) {
        return { id };
      }

      try {
        const swap = await swapGetHistoryItem(address, backendId, historyOptions);
        return { id, found: { chain: chainHint, swap } };
      } catch (err) {
        const is404 = err instanceof ApiServerError && err.statusCode === 404;
        return { id, isNonExistent: is404 };
      }
    }

    // Slow path: probe every chain — only mark non-existent if every chain confirms 404
    const chainEntries = Object.entries(walletByChain)
      .filter(([, wallet]) => !!wallet?.address) as [ApiChain, ApiWalletByChain[ApiChain]][];
    if (!chainEntries.length) {
      return { id };
    }

    const attempts = await Promise.allSettled(
      chainEntries.map(async ([chain, wallet]) => ({
        chain,
        swap: await swapGetHistoryItem(wallet.address, backendId, historyOptions),
      })),
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
      swaps.push(swapItemToActivity(result.found.swap, result.found.chain));
    } else if (result.isNonExistent) {
      nonExistentIds.push(result.id);
    }
  }

  const normalizedSwaps = swaps.map((swap) => {
    return swap.cex ? normalizeCexSwapRefreshActivity(swap) : swap;
  });
  const cexSwaps = normalizedSwaps.filter((swap) => swap.cex);
  await Promise.all(cexSwaps.map((swap) => rememberCexSwapOperationIntent(accountId, swap)));
  await Promise.all([
    rememberActiveCexSwaps(accountId, cexSwaps),
    expireActiveCexSwaps(accountId, nonExistentIds),
  ]);

  const intents = await getWalletOperationIntents(accountId);
  const patch = buildCexSwapRefreshPatch(accountId, normalizedSwaps, nonExistentIds, existingActivities, intents);

  return {
    nonExistentIds,
    swaps: patch.upsert.filter((activity): activity is ApiSwapActivity => activity.kind === 'swap'),
    patch,
  };
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
  enclaveToken: string,
  request: ApiSwapBuildTransactionRequest,
): Promise<{
    swap: ApiSwapHistoryItem;
    activity: ApiSwapActivity;
  }> {
  const authToken = await getBackendAuthToken(accountId, enclaveToken);

  const buildResponse = await swapBuild(authToken, request);

  if (buildResponse.route !== 'cex') {
    throw new Error('Unexpected non-CEX response for swapCexCreateTransaction');
  }

  const swap = convertSwapItemToTrusted(buildResponse.swap);

  // TODO: use actual chain!!!
  const activity = swapItemToActivity(swap, 'ton');
  await rememberCexSwapOperationIntent(accountId, activity);
  await rememberActiveCexSwap(accountId, activity);

  onUpdate({
    type: 'newActivities',
    accountId,
    activities: [activity],
  });

  void callHook('onSwapCreated', accountId, swap.timestamp - 1);

  return { swap, activity };
}

export async function swapCexSubmit(chain: ApiChain, transferOptions: ApiSubmitGasfullTransferOptions, swapId: string) {
  const submitGasfullTransfer = chains[chain].submitGasfullTransfer;
  let result: Awaited<ReturnType<typeof submitGasfullTransfer>>;
  try {
    result = await submitGasfullTransfer(transferOptions);
  } catch (err) {
    await patchSwapSubmitError(transferOptions, swapId, errorToString(err));
    throw err;
  }

  if ('error' in result) {
    await patchSwapSubmitError(transferOptions, swapId, result.error);
    return result;
  }

  if (result.mfaRequest) {
    const { accountId } = transferOptions;
    const { mfaRequestHash } = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);

    return { swapId, mfaRequestHash };
  }

  const backendMsgHash = result.msgHashForCexSwap ?? result.txId;
  if (backendMsgHash) {
    const { accountId, enclaveToken } = transferOptions;
    // TON keeps the backend BOC hash and the activity external-message hash in different namespaces.
    // Persist both explicit values for SDK matching, but keep the backend-facing hash unchanged below.
    const submittedHashes = Array.from(new Set(
      [result.msgHashForCexSwap, result.txId].filter((hash): hash is string => Boolean(hash)),
    ));
    await rememberWalletOperationSubmittedHashes(accountId, buildSwapOperationId(swapId), submittedHashes);
    await rememberActiveCexSwapSubmittedHashes(accountId, swapId, submittedHashes);
    // The transfer already went through - if we can't tell the backend, just log it and move on
    try {
      // CEX swap history rows are owned by the TON history address even when the
      // actual deposit transfer is submitted from another source chain.
      const { address: historyAddress } = await fetchStoredWallet(accountId, 'ton');
      const authToken = await getBackendAuthToken(accountId, enclaveToken ?? '');
      await patchSwapItem({ address: historyAddress, authToken, msgHash: backendMsgHash, swapId });
    } catch (err) {
      logDebugError('swapCexSubmit: failed to patch swap item', err);
    }
  }

  return result;
}

async function patchSwapSubmitError(
  transferOptions: ApiSubmitGasfullTransferOptions,
  swapId: string,
  error: string | undefined,
) {
  const { accountId, enclaveToken } = transferOptions;
  // We already know why the transfer failed - if the backend call also fails, keep the real reason
  try {
    // CEX swap history rows are owned by the TON history address even when the
    // actual deposit transfer is submitted from another source chain.
    const { address: historyAddress } = await fetchStoredWallet(accountId, 'ton');
    const authToken = await getBackendAuthToken(accountId, enclaveToken ?? '');
    await patchSwapItem({ address: historyAddress, authToken, error: error || 'Unknown', swapId });
  } catch (err) {
    logDebugError('patchSwapSubmitError: failed to patch swap item', err);
  }
}

function errorToString(err: unknown) {
  if (typeof err === 'string') return err;
  if (err instanceof Error) return err.stack ?? err.message;
  return String(err);
}
