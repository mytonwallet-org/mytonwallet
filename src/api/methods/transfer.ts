import { Cell } from '@ton/core';

import type { ApiSubmitTransferTonResult, ApiSubmitTransferWithDieselResult } from '../chains/ton/types';
import type { ApiSubmitTransferTronResult } from '../chains/tron/types';
import type { ApiActivity, ApiChain, ApiLocalTransactionParams, ApiTransactionActivity, OnApiUpdate } from '../types';
import type { ApiSubmitTransferOptions, ApiSubmitTransferResult, CheckTransactionDraftOptions } from './types';

import { parseAccountId } from '../../util/account';
import { buildLocalTxId } from '../../util/activities';
import { getChainConfig } from '../../util/chain';
import chains from '../chains';
import { fetchStoredAddress } from '../common/accounts';
import { buildLocalTransaction } from '../common/helpers';
import { FAKE_TX_ID } from '../constants';
import { buildTokenSlug } from './tokens';

let onUpdate: OnApiUpdate;

const { ton } = chains;

export function initTransfer(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export function checkTransactionDraft(chain: ApiChain, options: CheckTransactionDraftOptions) {
  return chains[chain].checkTransactionDraft(options);
}

export async function submitTransfer(
  chain: ApiChain,
  options: ApiSubmitTransferOptions,
  shouldCreateLocalActivity = true,
): Promise<ApiSubmitTransferResult> {
  const {
    accountId,
    password,
    toAddress,
    amount,
    tokenAddress,
    comment,
    fee,
    realFee,
    shouldEncrypt,
    isBase64Data,
    withDiesel,
    dieselAmount,
    isGaslessWithStars,
    noFeeCheck,
  } = options;
  const stateInit = typeof options.stateInit === 'string' ? Cell.fromBase64(options.stateInit) : options.stateInit;

  const fromAddress = await fetchStoredAddress(accountId, chain);

  let result: ApiSubmitTransferTonResult | ApiSubmitTransferTronResult | ApiSubmitTransferWithDieselResult;

  if (withDiesel && chain === 'ton') {
    result = await ton.submitTransferWithDiesel({
      accountId,
      password,
      toAddress,
      amount,
      tokenAddress: tokenAddress!,
      data: comment,
      shouldEncrypt,
      dieselAmount: dieselAmount!,
      isGaslessWithStars,
    });
  } else {
    result = await chains[chain].submitTransfer({
      accountId,
      password,
      toAddress,
      amount,
      tokenAddress,
      data: comment,
      shouldEncrypt,
      isBase64Data,
      stateInit,
      fee,
      noFeeCheck,
    });
  }

  if ('error' in result) {
    return result;
  }

  if (!shouldCreateLocalActivity) {
    return result;
  }

  const slug = tokenAddress
    ? buildTokenSlug(chain, tokenAddress)
    : getChainConfig(chain).nativeToken.slug;

  let localActivity: ApiTransactionActivity;

  if ('msgHash' in result) {
    const { encryptedComment, msgHashNormalized } = result;
    [localActivity] = createLocalTransactions(accountId, chain, [{
      id: msgHashNormalized,
      amount,
      fromAddress,
      toAddress,
      comment: shouldEncrypt ? undefined : comment,
      encryptedComment,
      fee: realFee ?? 0n,
      slug,
      externalMsgHashNorm: msgHashNormalized,
      extra: {
        ...('withW5Gasless' in result && { withW5Gasless: result.withW5Gasless }),
      },
    }]);
    if ('paymentLink' in result && result.paymentLink) {
      onUpdate({ type: 'openUrl', url: result.paymentLink, isExternal: true });
    }
  } else {
    const { txId } = result;
    [localActivity] = createLocalTransactions(accountId, chain, [{
      id: txId,
      amount,
      fromAddress,
      toAddress,
      comment,
      fee: realFee ?? 0n,
      slug,
    }]);
  }

  return {
    ...result,
    activityId: localActivity.id,
  };
}

export function createLocalTransactions(
  accountId: string,
  chain: ApiChain,
  params: ApiLocalTransactionParams[],
) {
  const { network } = parseAccountId(accountId);

  const localTransactions = params.map((subParams, index) => {
    const { toAddress } = subParams;

    let normalizedAddress: string;
    if (subParams.normalizedAddress) {
      normalizedAddress = subParams.normalizedAddress;
    } else if (chain === 'ton') {
      normalizedAddress = ton.normalizeAddress(toAddress, network);
    } else {
      normalizedAddress = toAddress;
    }

    return buildLocalTransaction(subParams, normalizedAddress, index);
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

export function fetchEstimateDiesel(accountId: string, tokenAddress: string) {
  const chain = chains.ton;

  return chain.fetchEstimateDiesel(accountId, tokenAddress);
}

/**
 * Creates local activities from emulation results instead of basic transaction parameters.
 * This provides richer, parsed transaction details like "liquidity withdrawal" instead of "send TON".
 */
export function createLocalActivitiesFromEmulation(
  accountId: string,
  chain: ApiChain,
  msgHashNormalized: string,
  emulationActivities: ApiActivity[],
): ApiActivity[] {
  const localActivities: ApiActivity[] = [];
  let localActivityIndex = 0;

  emulationActivities.forEach((activity) => {
    if (activity.shouldHide || activity.id === FAKE_TX_ID) {
      return;
    }

    const localActivity = convertEmulationActivityToLocal(
      activity,
      msgHashNormalized,
      localActivityIndex,
      chain,
      accountId,
    );

    localActivities.push(localActivity);

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

/**
 * Converts an emulation activity to a local activity with proper ID and timestamp
 */
function convertEmulationActivityToLocal(
  activity: ApiActivity,
  msgHashNormalized: string,
  index: number,
  chain: ApiChain,
  accountId?: string,
): ApiActivity {
  const localTxId = buildLocalTxId(msgHashNormalized, index);
  const commonFields = {
    id: localTxId,
    timestamp: Date.now(),
    externalMsgHashNorm: msgHashNormalized,
    // Emulation activities are not trusted
    status: 'pending',
  } satisfies Partial<ApiActivity>;

  if (activity.kind === 'transaction') {
    let normalizedAddress = activity.normalizedAddress;
    if (!normalizedAddress && chain === 'ton' && accountId) {
      const { network } = parseAccountId(accountId);
      normalizedAddress = chains.ton.normalizeAddress(activity.toAddress, network);
    }

    return {
      ...activity,
      ...commonFields,
      normalizedAddress: normalizedAddress || activity.normalizedAddress,
    };
  } else {
    return {
      ...activity,
      ...commonFields,
    };
  }
}
