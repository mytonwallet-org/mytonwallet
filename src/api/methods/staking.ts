import { Address } from '@ton/core';

import type {
  ApiEthenaStakingState,
  ApiJettonStakingState,
  ApiStakingCommonData,
  ApiStakingCommonResponse,
  ApiStakingHistory,
  ApiStakingState,
} from '../types';

import { fromDecimal } from '../../util/decimals';
import { logDebugError } from '../../util/logs';
import * as ton from '../chains/ton';
import { getTonClient } from '../chains/ton/util/tonCore';
import { fetchStoredAccount, fetchStoredWallet } from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { setStakingCommonCache } from '../common/cache';
import { createLocalTransactions } from './transfer';

import { StakingPool } from '../chains/ton/contracts/JettonStaking/StakingPool';

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
  password: string | undefined,
  amount: bigint,
  state: ApiStakingState,
  realFee?: bigint,
) {
  const { address: fromAddress } = await fetchStoredWallet(accountId, 'ton');

  const result = await ton.submitStake(
    accountId, password, amount, state,
  );

  if ('error' in result) {
    return result;
  }

  const [localActivity] = createLocalTransactions(accountId, 'ton', [{
    id: result.txId,
    amount,
    fromAddress,
    fee: realFee ?? 0n,
    type: 'stake',
    slug: state.tokenSlug,
    ...result.localActivityParams,
  }]);

  return {
    activityId: localActivity.id,
  };
}

export async function submitUnstake(
  accountId: string,
  password: string | undefined,
  tokenAmount: bigint,
  state: ApiStakingState,
  realFee?: bigint,
) {
  const { address: fromAddress } = await fetchStoredWallet(accountId, 'ton');

  const result = await ton.submitUnstake(accountId, password, tokenAmount, state);
  if ('error' in result) {
    return result;
  }

  const [localActivity] = createLocalTransactions(accountId, 'ton', [{
    id: result.txId,
    amount: 0n, // Always 0, because all the gas send for the unstaking is in the fee
    fromAddress,
    fee: realFee ?? 0n,
    type: 'unstakeRequest',
    ...result.localActivityParams,
  }]);

  return {
    activityId: localActivity.id,
  };
}

export async function getStakingHistory(accountId: string): Promise<ApiStakingHistory> {
  const { byChain: { ton: tonWallet } } = await fetchStoredAccount(accountId);
  if (!tonWallet) return [];
  return callBackendGet(`/staking/profits/${tonWallet.address}`);
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
  password: string | undefined,
  state: ApiJettonStakingState | ApiEthenaStakingState,
  realFee?: bigint,
) {
  const { address: walletAddress } = await fetchStoredWallet(accountId, 'ton');

  const result = state.type === 'ethena'
    ? await ton.submitUnstakeEthenaLocked(accountId, password, state)
    : await ton.submitTokenStakingClaim(accountId, password, state);

  if ('error' in result) {
    return result;
  }

  const [localActivity] = createLocalTransactions(accountId, 'ton', [{
    id: result.txId,
    fromAddress: walletAddress,
    fee: realFee ?? 0n,
    ...result.localActivityParams,
  }]);

  return {
    activityId: localActivity.id,
  };
}
