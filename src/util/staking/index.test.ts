import type { ApiStakingState } from '../../api/types';

import { MYCOIN_MAINNET, MYCOIN_TESTNET, TONCOIN } from '../../config';
import { getFullStakingBalance, getIsNewStakeAllowed, pickStakingStateForToken } from '.';

describe('getIsNewStakeAllowed', () => {
  it('forbids new stakes for MY coin (mainnet and testnet)', () => {
    expect(getIsNewStakeAllowed(MYCOIN_MAINNET.slug)).toBe(false);
    expect(getIsNewStakeAllowed(MYCOIN_TESTNET.slug)).toBe(false);
  });

  it('allows new stakes for other tokens', () => {
    expect(getIsNewStakeAllowed(TONCOIN.slug)).toBe(true);
    expect(getIsNewStakeAllowed('ton-some-other-jetton')).toBe(true);
  });

  it('allows when the slug is unknown', () => {
    expect(getIsNewStakeAllowed(undefined)).toBe(true);
  });
});

describe('getFullStakingBalance', () => {
  function buildLiquidState(balance: bigint, loyaltyBalance: bigint) {
    return {
      type: 'liquid',
      id: 'liquid',
      tokenSlug: TONCOIN.slug,
      pool: 'EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o',
      balance,
      loyaltyBalance,
      tokenBalance: 4_549_625_219_272n,
      annualYield: 14.37,
      yieldType: 'APY',
      instantAvailable: 0n,
      start: 0,
      end: 0,
      tvl: 0n,
      totalStakers: 0,
    } as unknown as ApiStakingState;
  }

  it('adds the loyalty bonus to a liquid stake', () => {
    // The bonus lives outside the STAKED jetton, so only the full balance accounts for it.
    expect(getFullStakingBalance(buildLiquidState(5_206_490_590_615n, 1_392_408_248n)))
      .toBe(5_207_882_998_863n);
  });

  it('leaves a liquid stake without a bonus untouched', () => {
    expect(getFullStakingBalance(buildLiquidState(5_206_490_590_615n, 0n)))
      .toBe(5_206_490_590_615n);
  });

  it('survives a state persisted before the bonus field existed', () => {
    const state = { ...buildLiquidState(5_206_490_590_615n, 0n) } as Record<string, unknown>;
    delete state.loyaltyBalance;

    expect(getFullStakingBalance(state as unknown as ApiStakingState)).toBe(5_206_490_590_615n);
  });

  it('still adds unclaimed rewards to a jetton stake', () => {
    const state = {
      type: 'jetton',
      id: 'jetton',
      tokenSlug: MYCOIN_MAINNET.slug,
      pool: 'EQCaSTAKE',
      balance: 1_000n,
      unclaimedRewards: 25n,
      annualYield: 10,
      yieldType: 'APR',
    } as unknown as ApiStakingState;

    expect(getFullStakingBalance(state)).toBe(1_025n);
  });

  it('returns the bare balance for a nominators stake', () => {
    const state = {
      type: 'nominators',
      id: 'nominators',
      tokenSlug: TONCOIN.slug,
      pool: 'EQCaPOOL',
      balance: 700n,
      annualYield: 3,
      yieldType: 'APY',
      start: 0,
      end: 0,
    } as unknown as ApiStakingState;

    expect(getFullStakingBalance(state)).toBe(700n);
  });
});

describe('pickStakingStateForToken', () => {
  const LIQUID_STATE_POOL = 'EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o';
  const NOMINATORS_STATE_POOL = 'Ef84o4VJRnlp1wsqSHov1QttqSTQda2Z1vGK-b7EaPQoeJMx';

  function buildToncoinStates(liquidBalance: bigint, nominatorsBalance: bigint) {
    // The API always puts the liquid state first, so the order here mirrors production.
    return [{
      type: 'liquid',
      id: 'liquid',
      tokenSlug: TONCOIN.slug,
      pool: LIQUID_STATE_POOL,
      balance: liquidBalance,
      annualYield: 14.37,
      yieldType: 'APY',
    }, {
      type: 'nominators',
      id: 'nominators',
      tokenSlug: TONCOIN.slug,
      pool: NOMINATORS_STATE_POOL,
      balance: nominatorsBalance,
      annualYield: 3.1,
      yieldType: 'APY',
    }] as unknown as ApiStakingState[];
  }

  it('keeps a forced account in nominators while its liquid stake is empty', () => {
    const states = buildToncoinStates(0n, 0n);

    expect(pickStakingStateForToken(states, TONCOIN.slug)?.id).toBe('nominators');
  });

  it('keeps an active nominators stake when liquid is empty', () => {
    const states = buildToncoinStates(0n, 10_000_000_000_000n);

    expect(pickStakingStateForToken(states, TONCOIN.slug)?.id).toBe('nominators');
  });

  it('prefers the liquid stake when both are active', () => {
    const states = buildToncoinStates(5_000_000_000n, 10_000_000_000_000n);

    expect(pickStakingStateForToken(states, TONCOIN.slug)?.id).toBe('liquid');
  });

  it('picks liquid for an account that never used nominators', () => {
    const states = buildToncoinStates(5_000_000_000n, 0n);

    expect(pickStakingStateForToken(states, TONCOIN.slug)?.id).toBe('liquid');
  });

  it('leaves other tokens to their own single position', () => {
    const states = [...buildToncoinStates(5_000_000_000n, 0n), {
      type: 'jetton',
      id: 'jetton',
      tokenSlug: MYCOIN_MAINNET.slug,
      pool: 'EQCaSTAKE',
      balance: 1_000n,
      annualYield: 10,
      yieldType: 'APR',
    }] as unknown as ApiStakingState[];

    expect(pickStakingStateForToken(states, MYCOIN_MAINNET.slug)?.id).toBe('jetton');
  });

  it('keeps the sole position of a forced account whose cache dropped the rest', () => {
    // The cache keeps only active positions, so a forced account can boot with the default liquid
    // state alone. Dropping it would leave the token with no position and hide Earn.
    const states = [buildToncoinStates(0n, 0n)[0]];

    expect(pickStakingStateForToken(states, TONCOIN.slug)?.id).toBe('liquid');
  });

  it('answers nominators for a position the API only built because the account is forced', () => {
    // The API builds a nominators position from a wider condition than the flag it ships alongside,
    // so the presence of that position is the answer - reading the flag could contradict it.
    const states = buildToncoinStates(0n, 5_000_000_000_000n);

    expect(pickStakingStateForToken(states, TONCOIN.slug)?.id).toBe('nominators');
  });

  it('returns nothing for a token without a position', () => {
    expect(pickStakingStateForToken(buildToncoinStates(0n, 0n), 'ton-unknown-jetton'))
      .toBeUndefined();
  });
});
