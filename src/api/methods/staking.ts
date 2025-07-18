import { Address } from '@ton/core';

import type { ApiSubmitTransferTonResult } from '../chains/ton/types';
import type {
  ApiEthenaStakingState,
  ApiJettonStakingState,
  ApiStakingCommonData,
  ApiStakingCommonResponse,
  ApiStakingHistory,
  ApiStakingState,
  ApiTransactionActivity,
} from '../types';

import { TONCOIN } from '../../config';
import { fromDecimal } from '../../util/decimals';
import { logDebugError } from '../../util/logs';
import chains from '../chains';
import { getTonClient } from '../chains/ton/util/tonCore';
import { fetchStoredAccount, fetchStoredTonWallet } from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { setStakingCommonCache } from '../common/cache';
import { createLocalTransaction } from './transactions';

import { StakingPool } from '../chains/ton/contracts/JettonStaking/StakingPool';

const { ton } = chains;

export function initStaking() {
}

export function checkStakeDraft(accountId: string, amount: bigint, state: ApiStakingState) {
  return ton.checkStakeDraft(accountId, amount, state);
}

export function checkUnstakeDraft(accountId: string, amount: bigint, state: ApiStakingState) {
  return ton.checkUnstakeDraft(accountId, amount, state);
}

export async function submitStake(
  accountId: string,
  password: string,
  amount: bigint,
  state: ApiStakingState,
  realFee?: bigint,
) {
  const { address: fromAddress } = await fetchStoredTonWallet(accountId);

  const result = await ton.submitStake(
    accountId, password, amount, state,
  );

  if ('error' in result) {
    return result;
  }

  let localActivity: ApiTransactionActivity;

  if (state.tokenSlug === TONCOIN.slug) {
    localActivity = createLocalTransaction(accountId, 'ton', {
      txId: result.msgHashNormalized,
      amount,
      fromAddress,
      toAddress: result.toAddress,
      fee: realFee ?? 0n,
      type: 'stake',
      slug: state.tokenSlug,
      externalMsgHash: result.msgHash,
    });
  } else {
    localActivity = createLocalTransaction(accountId, 'ton', {
      txId: result.msgHashNormalized,
      amount,
      fromAddress,
      toAddress: result.toAddress,
      fee: realFee ?? 0n,
      type: 'stake',
      slug: state.tokenSlug,
      externalMsgHash: result.msgHash,
    });
  }

  return {
    ...result,
    txId: localActivity.txId,
  };
}

export async function submitUnstake(
  accountId: string,
  password: string,
  amount: bigint,
  state: ApiStakingState,
  realFee?: bigint,
) {
  const { address: fromAddress } = await fetchStoredTonWallet(accountId);

  const result = await ton.submitUnstake(accountId, password, amount, state);
  if ('error' in result) {
    return result;
  }

  const localActivity = createLocalTransaction(accountId, 'ton', {
    txId: result.msgHashNormalized,
    amount: result.toncoinAmount,
    fromAddress,
    toAddress: result.toAddress,
    fee: realFee ?? 0n,
    type: 'unstakeRequest',
    slug: TONCOIN.slug,
    externalMsgHash: result.msgHash,
    ...result.localActivityParams,
  });

  return {
    ...result,
    txId: localActivity.txId,
  };
}

export async function getStakingHistory(
  accountId: string,
  limit?: number,
  offset?: number,
): Promise<ApiStakingHistory> {
  const { ton: tonWallet } = await fetchStoredAccount(accountId);
  if (!tonWallet) return [];
  return callBackendGet(`/staking/profits/${tonWallet.address}`, { limit, offset });
}

export async function tryUpdateStakingCommonData() {
  try {
    const tonClient = getTonClient('mainnet');
    const response = await callBackendGet<ApiStakingCommonResponse>('/staking/common');

    const data: ApiStakingCommonData = {
      ...response,
      liquid: {
        ...response.liquid,
        available: fromDecimal(response.liquid.available),
      },
      jettonPools: await Promise.all(response.jettonPools.map(async (pool) => {
        const poolContract = tonClient.open(StakingPool.createFromAddress(Address.parse(pool.pool)));
        const poolConfig = await poolContract.getStorageData();
        return {
          ...pool,
          poolConfig,
        };
      })),
    };
    data.round.start *= 1000;
    data.round.end *= 1000;
    data.round.unlock *= 1000;
    data.prevRound.start *= 1000;
    data.prevRound.end *= 1000;
    data.prevRound.unlock *= 1000;

    setStakingCommonCache(data);
  } catch (err) {
    logDebugError('tryUpdateLiquidStakingState', err);
  }
}

export async function submitStakingClaimOrUnlock(
  accountId: string,
  password: string,
  state: ApiJettonStakingState | ApiEthenaStakingState,
  realFee?: bigint,
) {
  const { address: walletAddress } = await fetchStoredTonWallet(accountId);

  let result: ApiSubmitTransferTonResult;

  switch (state.type) {
    case 'jetton': {
      result = await ton.submitTokenStakingClaim(accountId, password, state);
      break;
    }
    case 'ethena': {
      result = await ton.submitUnstakeEthenaLocked(accountId, password, state);
      break;
    }
  }

  if ('error' in result) {
    return result;
  }

  const localActivity = createLocalTransaction(accountId, 'ton', {
    txId: result.msgHashNormalized,
    amount: result.amount,
    fromAddress: walletAddress,
    toAddress: result.toAddress,
    fee: realFee ?? 0n,
    slug: TONCOIN.slug,
    externalMsgHash: result.msgHash,
    ...result.localActivityParams,
  });

  return {
    ...result,
    txId: localActivity.txId,
  };
}
