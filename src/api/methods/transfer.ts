import type {
  ApiActivity,
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
import { buildLocalTxId } from '../../util/activities';
import { SECOND } from '../../util/dateFormat';
import { getNativeToken } from '../../util/tokens';
import chains from '../chains';
import { fetchStoredAddress } from '../common/accounts';
import { buildLocalTransaction } from '../common/helpers';
import { bytesToBase64 } from '../common/utils';
import { FAKE_TX_ID } from '../constants';
import { buildTokenSlug } from './tokens';

let onUpdate: OnApiUpdate;

const DRAFT_CACHE_TTL = 5 * SECOND;

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

export async function checkTransactionDraft(chain: ApiChain, options: ApiCheckTransactionDraftOptions) {
  const cacheKey = buildDraftCacheKey(chain, options);
  const now = Date.now();
  const cached = draftCache.get(cacheKey);

  if (cached) {
    if (cached.value && cached.expiresAt > now) {
      return cached.value;
    }
    if (cached.inFlight) {
      return cached.inFlight;
    }
    draftCache.delete(cacheKey);
  }

  const inFlight = chains[chain].checkTransactionDraft(options)
    .then((result) => {
      const entry = draftCache.get(cacheKey);
      if (entry) {
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
      draftCache.delete(cacheKey);
      throw err;
    });

  draftCache.set(cacheKey, {
    inFlight,
    expiresAt: now + DRAFT_CACHE_TTL,
  });

  return inFlight;
}

export async function submitTransfer(
  chain: ApiChain,
  options: ApiSubmitTransferOptions,
): Promise<{ activityId: string } | { error: string }> {
  const {
    realFee,
    isGasless,
    dieselAmount = 0n,
    isGaslessWithStars,
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

  const [localActivity] = createLocalTransactions(accountId, chain, [{
    ...result.localActivityParams,
    id: result.txId,
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
      normalizedAddress ?? chains[chain].normalizeAddress(network, toAddress),
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

/**
 * Creates local activities from emulation results instead of basic transaction parameters.
 * This provides richer, parsed transaction details like "liquidity withdrawal" instead of "send TON".
 */
export function createLocalActivitiesFromEmulation(
  accountId: string,
  msgHashNormalized: string,
  emulationActivities: ApiActivity[],
): ApiActivity[] {
  const localActivities: ApiActivity[] = [];
  let localActivityIndex = 0;

  emulationActivities.forEach((activity) => {
    if (activity.shouldHide || activity.id === FAKE_TX_ID) {
      return;
    }

    localActivities.push({
      ...activity,
      id: buildLocalTxId(msgHashNormalized, localActivityIndex),
      timestamp: Date.now(),
      externalMsgHashNorm: msgHashNormalized,
      // Emulation activities are not trusted
      status: 'pending',
    });

    localActivityIndex++; // Increment only for visible activities
  });

  if (localActivities.length) {
    onUpdate({
      type: 'newLocalActivities',
      activities: localActivities,
      accountId,
    });
  }

  return localActivities;
}
