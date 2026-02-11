import { Address } from '@ton/core';

import type {
  ApiBackendStakingState,
  ApiBalanceBySlug,
  ApiCheckTransactionDraftResult,
  ApiEthenaStakingState,
  ApiJettonStakingState,
  ApiLoyaltyType,
  ApiNetwork,
  ApiStakingCommonData,
  ApiStakingJettonPool,
  ApiStakingState,
  ApiSubmitGasfullTransferResult,
} from '../../types';
import type { StakingPoolConfigUnpacked } from './contracts/JettonStaking/StakingPool';
import type { TonTransferParams } from './types';
import { ApiLiquidUnstakeMode, ApiTransactionDraftError } from '../../types';

import {
  DEBUG,
  ETHENA_STAKING_VAULT,
  LIQUID_JETTON,
  LIQUID_POOL,
  TON_TSUSDE,
  TON_USDE,
  TONCOIN,
  UNSTAKE_TON_GRACE_PERIOD,
  VALIDATION_PERIOD_MS,
} from '../../../config';
import { parseAccountId } from '../../../util/account';
import { bigintDivideToNumber, bigintMultiplyToNumber } from '../../../util/bigint';
import { fromDecimal } from '../../../util/decimals';
import { getDevSettings } from '../../../util/devSettings';
import { getIsActiveStakingState } from '../../../util/staking';
import calcJettonStakingApr from '../../../util/ton/calcJettonStakingApr';
import {
  buildJettonClaimPayload,
  buildJettonUnstakePayload,
  buildLiquidStakingDepositBody,
  buildLiquidStakingWithdrawBody,
  getJettonPoolStakeWallet,
  getTonClient,
  resolveTokenWalletAddress,
  toBase64Address,
  unpackDicts,
} from './util/tonCore';
import { TsUSDeWallet } from './contracts/Ethena/TsUSDeWallet';
import { StakeWallet } from './contracts/JettonStaking/StakeWallet';
import { StakingPool } from './contracts/JettonStaking/StakingPool';
import { NominatorPool } from './contracts/NominatorPool';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { callBackendGet } from '../../common/backend';
import { getAccountCache, getStakingCommonCache, updateAccountCache } from '../../common/cache';
import { buildTokenSlug, getTokenByAddress, getTokenBySlug } from '../../common/tokens';
import { isKnownStakingPool } from '../../common/utils';
import { STAKE_COMMENT, TON_GAS, UNSTAKE_COMMENT } from './constants';
import { checkTransactionDraft, submitGasfullTransfer } from './transfer';

export async function checkStakeDraft(accountId: string, amount: bigint, state: ApiStakingState) {
  let result: ApiCheckTransactionDraftResult;

  switch (state.type) {
    case 'nominators': {
      if (amount < TON_GAS.stakeNominators) {
        return { error: ApiTransactionDraftError.InvalidAmount };
      }

      result = await checkTransactionDraft({
        accountId,
        toAddress: state.pool,
        amount: amount + TON_GAS.stakeNominators,
        payload: { type: 'comment', text: STAKE_COMMENT },
      });
      if ('fee' in result && result.fee) {
        result.fee = TON_GAS.stakeNominators + result.fee;
      }
      break;
    }
    case 'liquid': {
      result = await checkTransactionDraft({
        accountId,
        toAddress: LIQUID_POOL,
        amount: amount + TON_GAS.stakeLiquid,
        payload: buildLiquidStakingDepositBody(),
      });
      if ('fee' in result && result.fee) {
        result.fee = TON_GAS.stakeLiquid + result.fee;
      }
      break;
    }
    case 'jetton': {
      const { tokenSlug, pool, period } = state;
      const { tokenAddress } = getTokenBySlug(tokenSlug)!;

      result = await checkTransactionDraft({
        accountId,
        toAddress: pool,
        tokenAddress,
        amount,
        payload: StakingPool.stakePayload(period),
        forwardAmount: TON_GAS.stakeJettonsForward,
      });
      break;
    }
    case 'ethena': {
      result = await checkTransactionDraft({
        accountId,
        toAddress: ETHENA_STAKING_VAULT,
        tokenAddress: TON_USDE.tokenAddress,
        amount,
        forwardAmount: TON_GAS.stakeEthenaForward,
      });
      break;
    }
  }

  return result;
}

export async function checkUnstakeDraft(
  accountId: string,
  amount: bigint, // The amount that the user sees
  state: ApiStakingState,
) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const commonData = await getStakingCommonCache();

  let result: ApiCheckTransactionDraftResult;
  let tokenAmount: bigint | undefined;

  switch (state.type) {
    case 'nominators': {
      result = await checkTransactionDraft({
        accountId,
        toAddress: state.pool,
        amount: TON_GAS.unstakeNominators,
        payload: { type: 'comment', text: UNSTAKE_COMMENT },
      });
      break;
    }
    case 'liquid': {
      if (amount > state.balance) {
        return { error: ApiTransactionDraftError.InsufficientBalance };
      } else if (amount === state.balance) {
        tokenAmount = state.tokenBalance;
      } else {
        tokenAmount = bigintDivideToNumber(amount, commonData.liquid.currentRate);
      }

      const params = await buildLiquidStakingWithdraw(network, address, tokenAmount);

      result = await checkTransactionDraft({
        accountId,
        toAddress: params.toAddress,
        amount: params.amount,
        payload: params.payload,
      });
      break;
    }
    case 'jetton': {
      tokenAmount = amount;

      result = await checkTransactionDraft({
        accountId,
        toAddress: state.stakeWalletAddress,
        amount: TON_GAS.unstakeJettons,
        payload: buildJettonUnstakePayload(amount, true),
      });
      break;
    }
    case 'ethena': {
      if (amount > state.balance) {
        return { error: ApiTransactionDraftError.InsufficientBalance };
      } else if (amount === state.balance) {
        tokenAmount = state.tokenBalance;
      } else {
        const rate = network === 'testnet' ? 1 : commonData.ethena.rate;
        tokenAmount = bigintDivideToNumber(amount, rate);
      }

      result = await checkTransactionDraft({
        accountId,
        toAddress: TON_TSUSDE.tokenAddress,
        amount: tokenAmount,
        tokenAddress: TON_TSUSDE.tokenAddress,
        forwardAmount: TON_GAS.unstakeEthenaForward,
      });
      break;
    }
  }

  return {
    ...result,
    type: state.type,
    tokenAmount,
  };
}

export async function submitStake(
  accountId: string,
  password: string | undefined,
  amount: bigint,
  state: ApiStakingState,
) {
  let result: ApiSubmitGasfullTransferResult | { error: string };
  let toAddress: string;

  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');

  switch (state.type) {
    case 'nominators': {
      toAddress = toBase64Address(state.pool, true, network);
      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        amount: amount + TON_GAS.stakeNominators,
        payload: { type: 'comment', text: STAKE_COMMENT },
      });
      break;
    }
    case 'liquid': {
      toAddress = LIQUID_POOL;
      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        amount: amount + TON_GAS.stakeLiquid,
        payload: buildLiquidStakingDepositBody(),
      });
      break;
    }
    case 'jetton': {
      const { tokenSlug, pool, period } = state;
      const { tokenAddress } = getTokenBySlug(tokenSlug)!;
      toAddress = pool;

      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        tokenAddress,
        amount,
        payload: StakingPool.stakePayload(period),
        forwardAmount: TON_GAS.stakeJettonsForward,
      });
      break;
    }
    case 'ethena': {
      toAddress = ETHENA_STAKING_VAULT;
      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        tokenAddress: TON_USDE.tokenAddress,
        amount,
        forwardAmount: TON_GAS.stakeEthenaForward,
      });
      break;
    }
  }

  if ('error' in result) {
    return result;
  }

  updateAccountCache(accountId, address, { stakedAt: Date.now() });

  return {
    ...result,
    localActivityParams: {
      ...result.localActivityParams,
      toAddress,
    },
  };
}

export async function submitUnstake(
  accountId: string,
  password: string | undefined,
  amount: bigint, // Token amount (not the amount that the user sees)
  state: ApiStakingState,
) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');

  let result: ApiSubmitGasfullTransferResult | { error: string };
  let toAddress: string;
  let tokenSlug: string = TONCOIN.slug;

  switch (state.type) {
    case 'nominators': {
      toAddress = toBase64Address(state.pool, true, network);
      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        amount: TON_GAS.unstakeNominators,
        payload: { type: 'comment', text: UNSTAKE_COMMENT },
      });
      break;
    }
    case 'liquid': {
      const mode = !state.instantAvailable
        ? ApiLiquidUnstakeMode.BestRate
        : ApiLiquidUnstakeMode.Default;

      const params = await buildLiquidStakingWithdraw(network, address, amount, mode);

      toAddress = params.toAddress;
      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        amount: params.amount,
        payload: params.payload,
      });
      break;
    }
    case 'jetton': {
      toAddress = state.stakeWalletAddress;
      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        amount: TON_GAS.unstakeJettons,
        payload: buildJettonUnstakePayload(amount, true),
      });
      break;
    }
    case 'ethena': {
      toAddress = TON_TSUSDE.tokenAddress;
      tokenSlug = TON_TSUSDE.slug;
      result = await submitGasfullTransfer({
        accountId,
        password,
        toAddress,
        amount,
        tokenAddress: TON_TSUSDE.tokenAddress,
        forwardAmount: TON_GAS.unstakeEthenaForward,
      });
    }
  }

  if ('error' in result) {
    return result;
  }

  return {
    ...result,
    localActivityParams: {
      ...result.localActivityParams,
      toAddress,
      slug: tokenSlug,
    },
  };
}

export async function buildLiquidStakingWithdraw(
  network: ApiNetwork,
  address: string,
  amount: bigint,
  mode: ApiLiquidUnstakeMode = ApiLiquidUnstakeMode.Default,
): Promise<TonTransferParams> {
  const tokenWalletAddress = await resolveTokenWalletAddress(network, address, LIQUID_JETTON);

  const payload = buildLiquidStakingWithdrawBody({
    amount,
    responseAddress: address,
    fillOrKill: mode === ApiLiquidUnstakeMode.Instant,
    waitTillRoundEnd: mode === ApiLiquidUnstakeMode.BestRate,
  });

  return {
    amount: TON_GAS.unstakeLiquid,
    toAddress: tokenWalletAddress,
    payload,
  };
}

type StakingStateOptions = {
  accountId: string;
  backendState: ApiBackendStakingState;
  commonData: ApiStakingCommonData;
  address: string;
  loyaltyType?: ApiLoyaltyType;
  network: ApiNetwork;
  balances: ApiBalanceBySlug;
};

export async function getStakingStates(
  accountId: string,
  commonData: ApiStakingCommonData,
  backendState: ApiBackendStakingState,
  balances: ApiBalanceBySlug,
): Promise<ApiStakingState[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');

  const {
    loyaltyType,
    shouldUseNominators,
    type: backendType,
  } = backendState;

  const options: StakingStateOptions = {
    accountId,
    backendState,
    commonData,
    address,
    loyaltyType,
    network,
    balances,
  };

  const promises: Promise<ApiStakingState>[] = [];

  for (const poolConfig of commonData.jettonPools) {
    const slug = buildTokenSlug('ton', poolConfig.token);
    if (slug in balances) {
      promises.push(buildJettonState(options, poolConfig));
    }
  }

  if (shouldUseNominators || backendType === 'nominators') {
    promises.push(buildNominatorsState(options));
  }

  const hasEthenaBalance = TON_USDE.slug in balances || TON_TSUSDE.slug in balances;

  if (hasEthenaBalance && (!commonData.ethena.isDisabled || DEBUG)) {
    promises.push(buildEthenaState(options));
  }

  return [buildLiquidState(options), ...await Promise.all(promises)];
}

function buildLiquidState({
  accountId,
  address,
  backendState,
  commonData,
  loyaltyType,
  balances,
}: StakingStateOptions): ApiStakingState {
  const { currentRate } = commonData.liquid;
  const tokenSlug = buildTokenSlug('ton', LIQUID_JETTON);
  const tokenBalance = balances[tokenSlug] ?? 0n;
  const unstakeRequestAmount = fromDecimal(backendState.liquid?.unstakeRequestAmount ?? 0);

  const accountCache = getAccountCache(accountId, address);
  const stakedAt = Math.max(accountCache.stakedAt ?? 0, backendState.stakedAt ?? 0);

  const isInstantUnstake = Date.now() - stakedAt > VALIDATION_PERIOD_MS && !getDevSettings().simulateLongUnstaking;
  const liquidAvailable = isInstantUnstake ? commonData.liquid.available : 0n;
  const { start, end } = getLiquidStakingTimeRange(commonData);

  let liquidApy = commonData.liquid.apy;
  if (loyaltyType && loyaltyType in commonData.liquid.loyaltyApy) {
    liquidApy = commonData.liquid.loyaltyApy[loyaltyType];
  }

  const balance = bigintMultiplyToNumber(tokenBalance, currentRate) + unstakeRequestAmount;

  return {
    type: 'liquid',
    id: 'liquid',
    tokenSlug: TONCOIN.slug,
    pool: LIQUID_POOL,
    balance,
    annualYield: liquidApy,
    yieldType: 'APY',
    tokenBalance,
    unstakeRequestAmount,
    instantAvailable: liquidAvailable,
    start,
    end,
  };
}

async function buildNominatorsState({
  network,
  address,
  backendState,
}: StakingStateOptions): Promise<ApiStakingState> {
  const { address: pool, apy, start, end } = backendState.nominatorsPool;

  const nominatorPool = getTonClient(network).open(new NominatorPool(Address.parse(pool)));
  const nominators = await nominatorPool.getListNominators();
  const addressObject = Address.parse(address);
  const nominator = nominators.find((n) => n.address.equals(addressObject));

  let balance = 0n;
  if (backendState.type === 'nominators') {
    // The backend state includes the loyalty bonus, so it takes priority.
    balance = backendState.balance;
  } else if (nominator) {
    // A rare state when a user has two types of staking or switches between them.
    balance = nominator.amount + nominator.pendingDepositAmount;
  }

  return {
    type: 'nominators',
    id: 'nominators',
    tokenSlug: TONCOIN.slug,
    balance,
    annualYield: apy,
    yieldType: 'APY',
    pool,
    start,
    end: end + UNSTAKE_TON_GRACE_PERIOD,
    unstakeRequestAmount: nominator?.withdrawRequested ? balance : 0n,
  };
}

async function buildJettonState(
  options: StakingStateOptions,
  pool: ApiStakingJettonPool,
): Promise<ApiJettonStakingState> {
  const { network } = options;

  // common
  const {
    pool: poolAddress,
    token: tokenAddress,
    poolConfig,
  } = pool;

  const { decimals, slug: tokenSlug } = getTokenByAddress(tokenAddress)!;

  // pool
  const { tvl, rewardJettons } = unpackDicts(poolConfig) as StakingPoolConfigUnpacked;
  const { rewardsDeposits } = Object.values(rewardJettons!)[0];
  const now = Math.floor(Date.now() / 1000);

  let dailyReward: bigint = 0n;
  for (const { startTime, endTime, distributionSpeed } of Object.values(rewardsDeposits)) {
    if (startTime < now && endTime > now) {
      dailyReward += distributionSpeed;
    }
  }

  const apr = calcJettonStakingApr({ tvl, dailyReward, decimals });

  // wallet
  const { address, balances } = options;
  const periodConfig = pool.periods[0];
  const stakedTokenSlug = buildTokenSlug('ton', periodConfig.token);

  const stakeWallet = await getJettonPoolStakeWallet(network, poolAddress, periodConfig.period, address);

  let unclaimedRewards = 0n;
  let balance = 0n;
  let poolWallets: string[] | undefined;

  if (stakedTokenSlug in balances) { // Avoiding the request when it's unnecessary
    const walletData = await stakeWallet.getStorageData().catch(() => undefined);

    if (walletData) {
      const poolWalletAddress = await resolveTokenWalletAddress(network, poolAddress, tokenAddress);
      const rewards = StakeWallet.getAvailableRewards(walletData, poolConfig);
      unclaimedRewards = (rewards && rewards[poolWalletAddress]) ?? 0n;
      balance = walletData.jettonBalance;
      poolWallets = Object.keys(rewards);
    }
  }

  const state: ApiJettonStakingState = {
    type: 'jetton',
    id: poolAddress,
    pool: poolAddress,
    tokenAddress,
    tokenSlug,
    annualYield: apr,
    yieldType: 'APR',
    balance,
    unclaimedRewards,
    poolWallets,
    stakeWalletAddress: toBase64Address(stakeWallet.address, true),
    tokenAmount: 0n,
    tvl,
    dailyReward,
    period: periodConfig.period,
  };

  return state;
}

async function buildEthenaState(options: StakingStateOptions): Promise<ApiEthenaStakingState> {
  const {
    network, balances, address: walletAddress,
    commonData, commonData: { ethena: { apy, apyVerified } },
    backendState: { ethena: { isVerified, isBoostAvailable } },
  } = options;

  const rate = network === 'testnet' ? 1 : commonData.ethena.rate;

  const tonClient = getTonClient(network);
  const tsUsdeWalletAddress = await resolveTokenWalletAddress(network, walletAddress, TON_TSUSDE.tokenAddress);
  const tsUsdeWallet = tonClient.open(TsUSDeWallet.createFromAddress(Address.parse(tsUsdeWalletAddress)));
  const { lockedUsdeBalance, unlockTime } = await tsUsdeWallet.getTimeLockData();

  const tokenBalance = balances[TON_TSUSDE.slug] ?? 0n;
  const balance = bigintMultiplyToNumber(tokenBalance, rate);

  const state: ApiEthenaStakingState = {
    id: 'ethena',
    type: 'ethena',
    tokenSlug: TON_USDE.slug,
    yieldType: 'APY',
    annualYield: isVerified ? apyVerified : apy,
    annualYieldStandard: apy,
    annualYieldVerified: apyVerified,
    balance,
    pool: ETHENA_STAKING_VAULT,
    tokenBalance,
    unstakeRequestAmount: lockedUsdeBalance,
    unlockTime: unlockTime && lockedUsdeBalance ? unlockTime * 1000 : undefined,
    isBoostAvailable,
    tsUsdeWalletAddress,
  };

  // If the user never passed verification and has no active USDe staking, we should optimistically show the high APY.
  if (isVerified === undefined && !getIsActiveStakingState(state)) {
    state.annualYield = apyVerified;
  }

  return state;
}

function getLiquidStakingTimeRange(commonData: ApiStakingCommonData) {
  const { prevRound, round: currentRound } = commonData;
  const now = Date.now();
  const gracePeriod = UNSTAKE_TON_GRACE_PERIOD;

  const round = (
    // Show date of next unlock plus few minutes
    // (except when grace period is active and payout has already occurred — i.e. collection has disappeared).
    (now > prevRound.unlock && now < prevRound.unlock + gracePeriod && !commonData.liquid.collection)
    || now >= prevRound.unlock + gracePeriod
  ) ? currentRound : prevRound;

  return {
    start: round.start,
    end: round.unlock + gracePeriod,
  };
}

export async function getBackendStakingState(accountId: string): Promise<ApiBackendStakingState> {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  return fetchBackendStakingState(account.byChain.ton.address, account.type === 'view');
}

export async function fetchBackendStakingState(address: string, isViewOnly: boolean): Promise<ApiBackendStakingState> {
  const stakingState = await callBackendGet(`/staking/state/${address}`, {
    isViewMode: isViewOnly ? 1 : undefined,
  });

  stakingState.balance = fromDecimal(stakingState.balance);
  stakingState.totalProfit = fromDecimal(stakingState.totalProfit);

  if (!isKnownStakingPool(stakingState.nominatorsPool.address)) {
    throw Error('Unexpected pool address, likely a malicious activity');
  }

  return stakingState as ApiBackendStakingState;
}

export async function submitTokenStakingClaim(
  accountId: string,
  password: string | undefined,
  state: ApiJettonStakingState,
) {
  const toAddress = state.stakeWalletAddress;
  const amount = TON_GAS.claimJettons;
  const result = await submitGasfullTransfer({
    accountId,
    password,
    toAddress,
    amount,
    payload: buildJettonClaimPayload(state.poolWallets!),
  });

  if ('error' in result) {
    return result;
  }

  return {
    ...result,
    localActivityParams: {
      ...result.localActivityParams,
      toAddress,
      amount,
      slug: TONCOIN.slug,
    },
  };
}

export async function submitUnstakeEthenaLocked(
  accountId: string,
  password: string | undefined,
  state: ApiEthenaStakingState,
) {
  const { address } = await fetchStoredWallet(accountId, 'ton');

  const result = await submitGasfullTransfer({
    accountId,
    password,
    toAddress: state.tsUsdeWalletAddress,
    amount: TON_GAS.unstakeEthenaLocked,
    payload: TsUSDeWallet.transferTimelockedMessage({
      jettonAmount: state.unstakeRequestAmount,
      to: Address.parse(TON_TSUSDE.tokenAddress),
      responseAddress: Address.parse(address),
      forwardTonAmount: TON_GAS.unstakeEthenaLockedForward,
    }),
  });

  if ('error' in result) {
    return result;
  }

  return {
    ...result,
    localActivityParams: {
      ...result.localActivityParams,
      type: 'unstake' as const,
      amount: state.unstakeRequestAmount,
      isIncoming: true,
      slug: TON_USDE.slug,
      fromAddress: ETHENA_STAKING_VAULT,
      toAddress: address,
    },
  };
}
