import { Address } from '@ton/core';

import type { ApiJettonStakingState, ApiStakingCommonResponse } from '../../types';
import { ApiTransactionDraftError } from '../../types';

import { MYCOIN_MAINNET, MYCOIN_STAKING_POOL, TON_USDE } from '../../../config';
import { getTonClient } from './util/tonCore';
import { StakingPool } from './contracts/JettonStaking/StakingPool';
import { fetchStoredWallet } from '../../common/accounts';
import { callBackendGet } from '../../common/backend';
import { getTokenBySlug } from '../../common/tokens';
import {
  checkStakeDraft,
  checkUnstakeDraft,
  getStakingCommonData,
  isKnownJettonStakingPool,
  submitStake,
  submitTokenStakingClaim,
  submitUnstake,
} from './staking';
import { checkTransactionDraft, submitGasfullTransfer } from './transfer';

const UNKNOWN_POOL = 'EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o';
const ACCOUNT_ID = '0';
const ENCLAVE_TOKEN = 'enclave-token';
const AMOUNT = 1_000_000n;
const mockStakePayload = { type: 'mock-stake-payload' };
const mockTokenAddress = MYCOIN_MAINNET.minterAddress;
const STAKED_MYCOIN_ADDRESS = 'EQCbZVsfwQY_1eW8W6Uv60eWwoFYGOXXkkphdBFIk5Uizy7l';
const POOL_CONFIG = { tvl: 1n, rewardJettons: {} };
const WALLET_ADDRESS = 'EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c';
const STATE_STAKE_WALLET = 'EQCqC6EhRJ_tpWngKxL6dV0k6DSnRUrs9GSVkLbfdCqsj6TE';
const POOL_STAKE_WALLET = 'EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o';
const openMock = jest.fn();
const mockGetJettonPoolStakeWallet = jest.fn();

jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn(),
}));

jest.mock('../../common/cache', () => ({
  getAccountCache: jest.fn(() => ({})),
  getStakingCommonCache: jest.fn(),
  updateAccountCache: jest.fn(),
}));

jest.mock('../../common/tokens', () => ({
  buildTokenSlug: jest.fn((chain, address) => `${chain}-${address.toLowerCase().slice(0, 10)}`),
  getTokenByAddress: jest.fn(),
  getTokenBySlug: jest.fn(() => ({
    tokenAddress: mockTokenAddress,
  })),
}));

jest.mock('./contracts/JettonStaking/StakingPool', () => ({
  StakingPool: {
    createFromAddress: jest.fn(() => ({ type: 'staking-pool' })),
    stakePayload: jest.fn(() => mockStakePayload),
  },
}));

jest.mock('./transfer', () => ({
  checkTransactionDraft: jest.fn(),
  submitGasfullTransfer: jest.fn(),
}));

jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'),
  getJettonPoolStakeWallet: (...args: unknown[]) => mockGetJettonPoolStakeWallet(...args),
  getTonClient: jest.fn(),
}));

describe('isKnownJettonStakingPool', () => {
  it('accepts the MY staking pool with the MY jetton', () => {
    expect(isKnownJettonStakingPool(MYCOIN_STAKING_POOL, MYCOIN_MAINNET.minterAddress)).toBe(true);
  });

  it('accepts the MY staking pool and the MY jetton in other address formats', () => {
    const pool = Address.parse(MYCOIN_STAKING_POOL);
    const token = Address.parse(MYCOIN_MAINNET.minterAddress);

    expect(isKnownJettonStakingPool(pool.toString({ bounceable: false }), token.toRawString())).toBe(true);
    expect(isKnownJettonStakingPool(pool.toRawString(), token.toString({ bounceable: false }))).toBe(true);
  });

  it('rejects a different pool', () => {
    expect(isKnownJettonStakingPool(UNKNOWN_POOL, MYCOIN_MAINNET.minterAddress)).toBe(false);
  });

  it('rejects the MY staking pool with a different jetton', () => {
    expect(isKnownJettonStakingPool(MYCOIN_STAKING_POOL, TON_USDE.tokenAddress)).toBe(false);
  });

  it('rejects malformed addresses', () => {
    expect(isKnownJettonStakingPool('not-an-address', MYCOIN_MAINNET.minterAddress)).toBe(false);
    expect(isKnownJettonStakingPool(MYCOIN_STAKING_POOL, '')).toBe(false);
  });
});

describe('jetton staking pool guard', () => {
  beforeEach(() => {
    jest.mocked(fetchStoredWallet).mockResolvedValue({
      address: WALLET_ADDRESS,
    } as Awaited<ReturnType<typeof fetchStoredWallet>>);
    jest.mocked(checkTransactionDraft).mockResolvedValue({});
    jest.mocked(submitGasfullTransfer).mockResolvedValue({
      txId: 'tx-id',
      localActivityParams: {},
    });
    mockGetJettonPoolStakeWallet.mockResolvedValue({ address: Address.parse(POOL_STAKE_WALLET) });
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('rejects unknown jetton pool before checking stake draft', async () => {
    const result = await checkStakeDraft(ACCOUNT_ID, AMOUNT, buildJettonState(UNKNOWN_POOL));

    expect(result).toEqual({ error: ApiTransactionDraftError.InvalidToAddress });
    expect(checkTransactionDraft).not.toHaveBeenCalled();
  });

  it('checks stake draft for a known jetton pool', async () => {
    await checkStakeDraft(ACCOUNT_ID, AMOUNT, buildJettonState(MYCOIN_STAKING_POOL));

    expect(checkTransactionDraft).toHaveBeenCalledWith({
      accountId: ACCOUNT_ID,
      toAddress: MYCOIN_STAKING_POOL,
      tokenAddress: mockTokenAddress,
      amount: AMOUNT,
      payload: mockStakePayload,
      forwardAmount: expect.any(BigInt),
    });
  });

  it('rejects unknown jetton pool before submitting stake', async () => {
    const result = await submitStake(ACCOUNT_ID, ENCLAVE_TOKEN, AMOUNT, buildJettonState(UNKNOWN_POOL));

    expect(result).toEqual({ error: ApiTransactionDraftError.InvalidToAddress });
    expect(fetchStoredWallet).not.toHaveBeenCalled();
    expect(submitGasfullTransfer).not.toHaveBeenCalled();
  });

  it('submits stake for a known jetton pool', async () => {
    await submitStake(ACCOUNT_ID, ENCLAVE_TOKEN, AMOUNT, buildJettonState(MYCOIN_STAKING_POOL));

    expect(submitGasfullTransfer).toHaveBeenCalledWith({
      accountId: ACCOUNT_ID,
      enclaveToken: ENCLAVE_TOKEN,
      toAddress: MYCOIN_STAKING_POOL,
      tokenAddress: mockTokenAddress,
      amount: AMOUNT,
      payload: mockStakePayload,
      forwardAmount: expect.any(BigInt),
    });
  });

  it('rejects a stake that sends a jetton other than the pool one', async () => {
    jest.mocked(getTokenBySlug).mockReturnValueOnce({
      tokenAddress: TON_USDE.tokenAddress,
    } as ReturnType<typeof getTokenBySlug>);

    const result = await submitStake(ACCOUNT_ID, ENCLAVE_TOKEN, AMOUNT, buildJettonState(MYCOIN_STAKING_POOL));

    expect(result).toEqual({ error: ApiTransactionDraftError.InvalidToAddress });
    expect(submitGasfullTransfer).not.toHaveBeenCalled();
  });

  it('rejects unknown jetton pool before checking unstake draft', async () => {
    const result = await checkUnstakeDraft(ACCOUNT_ID, AMOUNT, buildJettonState(UNKNOWN_POOL));

    expect(result).toEqual({ error: ApiTransactionDraftError.InvalidToAddress });
    expect(fetchStoredWallet).not.toHaveBeenCalled();
    expect(checkTransactionDraft).not.toHaveBeenCalled();
  });

  it('rejects unknown jetton pool before submitting unstake', async () => {
    const result = await submitUnstake(ACCOUNT_ID, ENCLAVE_TOKEN, AMOUNT, buildJettonState(UNKNOWN_POOL));

    expect(result).toEqual({ error: ApiTransactionDraftError.InvalidToAddress });
    expect(fetchStoredWallet).not.toHaveBeenCalled();
    expect(submitGasfullTransfer).not.toHaveBeenCalled();
  });

  it('rejects unknown jetton pool before submitting claim', async () => {
    const result = await submitTokenStakingClaim(ACCOUNT_ID, ENCLAVE_TOKEN, buildJettonState(UNKNOWN_POOL));

    expect(result).toEqual({ error: ApiTransactionDraftError.InvalidToAddress });
    expect(submitGasfullTransfer).not.toHaveBeenCalled();
  });

  it('checks unstake draft against the stake wallet resolved by the pool', async () => {
    await checkUnstakeDraft(ACCOUNT_ID, AMOUNT, buildJettonState(MYCOIN_STAKING_POOL));

    expect(checkTransactionDraft).toHaveBeenCalledWith(expect.objectContaining({ toAddress: POOL_STAKE_WALLET }));
  });

  it('submits unstake to the stake wallet resolved by the pool', async () => {
    await submitUnstake(ACCOUNT_ID, ENCLAVE_TOKEN, AMOUNT, buildJettonState(MYCOIN_STAKING_POOL));

    expect(mockGetJettonPoolStakeWallet)
      .toHaveBeenCalledWith('mainnet', MYCOIN_STAKING_POOL, 86_400, WALLET_ADDRESS);
    expect(submitGasfullTransfer).toHaveBeenCalledWith(expect.objectContaining({ toAddress: POOL_STAKE_WALLET }));
  });

  it('submits claim to the stake wallet resolved by the pool', async () => {
    await submitTokenStakingClaim(ACCOUNT_ID, ENCLAVE_TOKEN, {
      ...buildJettonState(MYCOIN_STAKING_POOL),
      poolWallets: [],
    });

    expect(submitGasfullTransfer).toHaveBeenCalledWith(expect.objectContaining({ toAddress: POOL_STAKE_WALLET }));
  });
});

describe('getStakingCommonData', () => {
  beforeEach(() => {
    jest.mocked(callBackendGet).mockResolvedValue(buildStakingCommonResponse());
    jest.mocked(getTonClient).mockReturnValue({
      open: openMock,
    } as unknown as ReturnType<typeof getTonClient>);
    openMock.mockReturnValue({
      getStorageData: jest.fn().mockResolvedValue(POOL_CONFIG),
    });
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('keeps only known jetton staking pools with their own jettons', async () => {
    const data = await getStakingCommonData();

    expect(StakingPool.createFromAddress).toHaveBeenCalledTimes(1);
    expect(openMock).toHaveBeenCalledTimes(1);
    expect(data.jettonPools).toHaveLength(1);
    expect(data.jettonPools[0]).toEqual(expect.objectContaining({
      pool: MYCOIN_STAKING_POOL,
      poolConfig: POOL_CONFIG,
    }));
  });
});

function buildJettonState(pool: string): ApiJettonStakingState {
  return {
    type: 'jetton',
    id: pool,
    tokenSlug: MYCOIN_MAINNET.slug,
    pool,
    tokenAddress: mockTokenAddress,
    balance: 0n,
    annualYield: 0,
    yieldType: 'APR',
    unclaimedRewards: 0n,
    stakeWalletAddress: STATE_STAKE_WALLET,
    tokenAmount: 0n,
    period: 86_400,
    tvl: 0n,
    dailyReward: 0n,
  };
}

function buildStakingCommonResponse(): ApiStakingCommonResponse {
  return {
    liquid: {
      currentRate: 1,
      nextRoundRate: 1,
      apy: 0,
      available: '0',
      tvl: '0',
      totalStakers: 0,
      loyaltyApy: {
        black: 0,
        platinum: 0,
        gold: 0,
        silver: 0,
        standard: 0,
      },
    },
    round: { start: 1, end: 2, unlock: 3 },
    prevRound: { start: 1, end: 2, unlock: 3 },
    jettonPools: [
      [MYCOIN_STAKING_POOL, MYCOIN_MAINNET.minterAddress],
      [UNKNOWN_POOL, MYCOIN_MAINNET.minterAddress],
      [MYCOIN_STAKING_POOL, TON_USDE.tokenAddress],
    ].map(([pool, token]) => ({
      pool,
      token,
      periods: [{
        period: 86_400,
        unstakeCommission: 0,
        token: STAKED_MYCOIN_ADDRESS,
      }],
    })),
    ethena: {
      apy: 0,
      rate: 1,
    },
  };
}
