import type {
  ApiChain,
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiLocalTransactionParams,
  ApiSubmitGasfullTransferResult,
  ApiSubmitGaslessTransferResult,
  ApiSubmitTransferOptions,
  ApiTransferPayload,
  OnApiUpdate,
} from '../types';

import { parseAccountId } from '../../util/account';
import { SECOND } from '../../util/dateFormat';
import { getNativeToken } from '../../util/tokens';
import chains from '../chains';
import { fetchStoredAddress } from '../common/accounts';
import { buildLocalTransaction } from '../common/helpers';
import { bytesToBase64 } from '../common/utils';
import { requireMfaMethods } from './optional';
import { buildTokenSlug } from './tokens';

let onUpdate: OnApiUpdate;

const DRAFT_CACHE_TTL = 5 * SECOND;
const DRAFT_CACHE_MAX_ENTRIES = 64;

type DraftCacheEntry = {
  value?: ApiCheckTransactionDraftResult;
  expiresAt: number;
  inFlight?: Promise<ApiCheckTransactionDraftResult>;
};

const draftCache = new Map<string, DraftCacheEntry>();

function buildDraftCacheKey(chain: ApiChain, options: ApiCheckTransactionDraftOptions) {
  const {
    accountId,
    toAddress,
    tokenAddress,
    amount,
    payload,
    stateInit,
    allowGasless,
  } = options;

  return JSON.stringify({
    chain,
    accountId,
    toAddress,
    tokenAddress,
    amount: amount?.toString(),
    payload: normalizePayloadForKey(payload),
    stateInit,
    allowGasless,
  });
}

function pruneDraftCache(now: number) {
  for (const [key, entry] of draftCache) {
    if (entry.expiresAt <= now) {
      draftCache.delete(key);
    }
  }

  while (draftCache.size > DRAFT_CACHE_MAX_ENTRIES) {
    const oldestKey = draftCache.keys().next().value;
    if (oldestKey === undefined) break;
    draftCache.delete(oldestKey);
  }
}

function normalizePayloadForKey(payload?: ApiTransferPayload) {
  if (!payload) return undefined;

  if (payload.type === 'comment') {
    return {
      type: payload.type,
      text: payload.text,
      shouldEncrypt: payload.shouldEncrypt ?? false,
    };
  }

  if (payload.type === 'base64') {
    return {
      type: payload.type,
      data: payload.data,
    };
  }

  return {
    type: payload.type,
    data: bytesToBase64(payload.data),
  };
}

export function initTransfer(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function checkTransactionDraft(
  chain: ApiChain,
  options: ApiCheckTransactionDraftOptions,
  signal?: AbortSignal,
) {
  if (signal) return chains[chain].checkTransactionDraft(options, signal);

  const cacheKey = buildDraftCacheKey(chain, options);
  const now = Date.now();
  pruneDraftCache(now);
  const cached = draftCache.get(cacheKey);

  if (cached) {
    if (cached.value && cached.expiresAt > now) {
      draftCache.delete(cacheKey);
      draftCache.set(cacheKey, cached);
      return cached.value;
    }
    if (cached.inFlight) {
      draftCache.delete(cacheKey);
      draftCache.set(cacheKey, cached);
      return cached.inFlight;
    }
    draftCache.delete(cacheKey);
  }

  const entry: DraftCacheEntry = { expiresAt: now + DRAFT_CACHE_TTL };
  const inFlight = chains[chain].checkTransactionDraft(options)
    .then((result) => {
      if (draftCache.get(cacheKey) === entry) {
        entry.inFlight = undefined;
        if (!('error' in result)) {
          entry.value = result;
          entry.expiresAt = Date.now() + DRAFT_CACHE_TTL;
        } else {
          draftCache.delete(cacheKey);
        }
      }
      return result;
    })
    .catch((err) => {
      if (draftCache.get(cacheKey) === entry) draftCache.delete(cacheKey);
      throw err;
    });

  entry.inFlight = inFlight;
  draftCache.set(cacheKey, entry);
  pruneDraftCache(now);

  return inFlight;
}

export async function submitTransfer(
  chain: ApiChain,
  options: ApiSubmitTransferOptions,
): Promise<{ activityId?: string; mfaRequestHash?: string } | { error: string }> {
  const {
    realFee,
    isGasless,
    dieselAmount = 0n,
    isGaslessWithStars,
    gaslessTransaction,
    ...commonOptions
  } = options;
  const {
    accountId,
    toAddress,
    amount,
    tokenAddress,
    payload,
  } = options;

  const fromAddress = await fetchStoredAddress(accountId, chain);

  let result: ApiSubmitGasfullTransferResult | ApiSubmitGaslessTransferResult | { error: string };

  if (isGasless) {
    if (tokenAddress === undefined) {
      throw new Error('tokenAddress is required for gasless transfer');
    }

    result = await chains[chain].submitGaslessTransfer({
      ...commonOptions,
      tokenAddress,
      dieselAmount,
      isGaslessWithStars,
      gaslessTransaction,
    });
  } else {
    result = await chains[chain].submitGasfullTransfer(commonOptions);
  }

  if ('error' in result) {
    return result;
  }

  const slug = tokenAddress
    ? buildTokenSlug(chain, tokenAddress)
    : getNativeToken(chain).slug;
  const comment = payload?.type === 'comment' && !payload.shouldEncrypt ? payload.text : undefined;

  if (result.mfaRequest) {
    const { publishSignedMfaRequest, registerMfaConfirmationHandler } = requireMfaMethods();
    const mfaResult = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);
    registerMfaConfirmationHandler(mfaResult.mfaRequestHash, (txHash) => {
      createLocalTransactions(accountId, chain, [{
        id: txHash,
        amount,
        fromAddress,
        toAddress,
        comment,
        fee: realFee ?? 0n,
        slug,
        externalMsgHashNorm: txHash,
      }]);
    });
    return mfaResult;
  }

  const [localActivity] = createLocalTransactions(accountId, chain, [{
    ...result.localActivityParams,
    id: result.txId!,
    amount,
    fromAddress,
    toAddress,
    comment,
    fee: realFee ?? 0n,
    slug,
  }]);

  if ('paymentLink' in result && result.paymentLink) {
    onUpdate({ type: 'openUrl', url: result.paymentLink, isExternal: true });
  }

  return {
    activityId: localActivity.id,
  };
}

export function createLocalTransactions(
  accountId: string,
  chain: ApiChain,
  transactions: ApiLocalTransactionParams[],
) {
  const { network } = parseAccountId(accountId);

  const localTransactions = transactions.map((transaction, index) => {
    const { toAddress, normalizedAddress } = transaction;

    return buildLocalTransaction(
      transaction,
      normalizedAddress ?? chains[chain].normalizeAddress(toAddress, network),
      index,
    );
  });

  if (localTransactions.length) {
    onUpdate({
      type: 'newLocalActivities',
      activities: localTransactions,
      accountId,
    });
  }

  return localTransactions;
}

export function fetchEstimateDiesel(accountId: string, chain: ApiChain, tokenAddress: string) {
  return chains[chain].fetchEstimateDiesel(accountId, tokenAddress);
}
