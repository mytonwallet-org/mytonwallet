import type { ApiChain, ApiStakingState } from '../api/types';
import type { ChainDisplayConfiguration, UserToken } from '../global/types';

import {
  DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
  getAddressLineChains,
  getChainsWithBalance,
  getDefaultVisibleChains,
  getHasOnlyTonTokens,
  getNormalizedManualOrder,
  getOrderedChainsForDisplay,
  getVisibleChains,
  setChainDisplayMode,
  setChainVisibility,
  setManualChainOrder,
} from './chainDisplay';

function buildToken(slug: string, chain: ApiChain, amount: bigint, isDisabled?: boolean) {
  return { slug, chain, amount, isDisabled } as UserToken;
}

function buildStakingState(tokenSlug: string, balance: bigint) {
  return { type: 'liquid', tokenSlug, balance } as ApiStakingState;
}

describe('getChainsWithBalance', () => {
  it('collects the chains of non-empty tokens', () => {
    const tokens = [
      buildToken('ton', 'ton', 10n),
      buildToken('tron', 'tron', 0n),
      buildToken('solana', 'solana', 5n),
    ];

    expect([...getChainsWithBalance(tokens)]).toEqual(['ton', 'solana']);
  });

  it('counts staked balances of otherwise empty tokens', () => {
    const tokens = [buildToken('ton', 'ton', 0n), buildToken('tron', 'tron', 0n)];
    const stakingStates = [buildStakingState('ton', 100n)];

    expect([...getChainsWithBalance(tokens, stakingStates)]).toEqual(['ton']);
  });
});

describe('getDefaultVisibleChains', () => {
  it('shows every chain of an empty wallet', () => {
    const chains: ApiChain[] = ['ton', 'tron', 'solana'];

    expect([...getDefaultVisibleChains(chains, new Set())]).toEqual(chains);
  });

  it('shows only the funded chains of a non-empty wallet', () => {
    const chains: ApiChain[] = ['ton', 'tron', 'solana'];

    expect([...getDefaultVisibleChains(chains, new Set(['tron', 'ethereum']))]).toEqual(['tron']);
  });

  it('shows only the first chain when the funds are outside the account chains', () => {
    expect([...getDefaultVisibleChains(['ton', 'tron'], new Set(['ethereum']))]).toEqual(['ton']);
  });
});

describe('getAddressLineChains', () => {
  const chains: ApiChain[] = ['ton', 'tron', 'ethereum'];

  it('collapses a Gram Wallet line to TON while the shown tokens are TON-only', () => {
    expect(getAddressLineChains(chains, true, true)).toEqual(['ton']);
  });

  it('keeps every chain once a foreign-chain token is shown', () => {
    expect(getAddressLineChains(chains, false, true)).toBe(chains);
  });

  it('keeps every chain while the token list is not known yet', () => {
    expect(getAddressLineChains(chains, undefined, true)).toBe(chains);
  });

  it('keeps an account without a TON wallet intact', () => {
    const noTonChains: ApiChain[] = ['tron', 'ethereum'];

    expect(getAddressLineChains(noTonChains, true, true)).toBe(noTonChains);
  });

  it('never collapses outside the Gram Wallet build', () => {
    expect(getAddressLineChains(chains, true, false)).toBe(chains);
  });
});

describe('getHasOnlyTonTokens', () => {
  it('is true while every shown token is on TON', () => {
    expect(getHasOnlyTonTokens([buildToken('ton', 'ton', 10n)])).toBe(true);
  });

  it('is true for an empty token list', () => {
    expect(getHasOnlyTonTokens([])).toBe(true);
  });

  it('ignores disabled foreign tokens', () => {
    expect(getHasOnlyTonTokens([buildToken('ton', 'ton', 10n), buildToken('tron', 'tron', 0n, true)])).toBe(true);
  });

  it('is false once a foreign-chain token is shown', () => {
    expect(getHasOnlyTonTokens([buildToken('tron', 'tron', 5n)])).toBe(false);
  });

  it('is undefined while the token list is not known yet', () => {
    expect(getHasOnlyTonTokens(undefined)).toBeUndefined();
  });
});

describe('chain display order', () => {
  it('uses the automatic visibility and the value order without a configuration', () => {
    const visibleChains = getVisibleChains(
      DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
      ['ton', 'tron', 'solana'],
      ['solana', 'ton', 'tron'],
      new Set(['ton', 'solana']),
    );

    expect(visibleChains).toEqual(['solana', 'ton']);
  });

  it('keeps the visible zero value chains ahead of the hidden ones', () => {
    const defaultOrder: ApiChain[] = ['ton', 'tron', 'solana', 'base', 'bnb'];
    const valueOrder: ApiChain[] = ['tron', 'ton', 'solana', 'base', 'bnb'];
    const defaultVisibleChains = new Set<ApiChain>(['ton', 'tron', 'base']);

    expect(getOrderedChainsForDisplay(
      DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
      defaultOrder,
      valueOrder,
      defaultVisibleChains,
    )).toEqual(['tron', 'ton', 'base', 'solana', 'bnb']);

    expect(getVisibleChains(
      DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
      defaultOrder,
      valueOrder,
      defaultVisibleChains,
    )).toEqual(['tron', 'ton', 'base']);
  });

  it('ignores the preserved manual choices in the automatic mode', () => {
    const config: ChainDisplayConfiguration = {
      displayMode: 'value',
      hiddenChains: ['ton'],
      shownChains: ['tron'],
      manualOrder: ['tron', 'ton', 'solana'],
    };

    expect(getVisibleChains(
      config,
      ['ton', 'tron', 'solana'],
      ['solana', 'ton', 'tron'],
      new Set(['ton', 'solana']),
    )).toEqual(['solana', 'ton']);
  });

  it('appends the chains missing from a partial manual order in the default order', () => {
    const config: ChainDisplayConfiguration = { displayMode: 'manual', manualOrder: ['solana', 'ton'] };

    expect(getOrderedChainsForDisplay(
      config,
      ['ton', 'tron', 'solana', 'ethereum'],
      ['ethereum', 'tron', 'ton', 'solana'],
      new Set(['ton', 'tron', 'solana', 'ethereum']),
    )).toEqual(['solana', 'ton', 'tron', 'ethereum']);
  });

  it('keeps the manual order for the visible chains and the value order for the hidden ones', () => {
    const config: ChainDisplayConfiguration = {
      displayMode: 'manual',
      hiddenChains: ['solana'],
      shownChains: ['base'],
      manualOrder: ['solana', 'tron', 'bnb', 'ton', 'base'],
    };
    const defaultOrder: ApiChain[] = ['ton', 'tron', 'solana', 'base', 'bnb', 'ethereum'];

    expect(getNormalizedManualOrder(config, defaultOrder, new Set(['ton', 'tron'])))
      .toEqual(['tron', 'ton', 'base']);

    expect(getOrderedChainsForDisplay(config, defaultOrder, ['bnb', 'base'], new Set(['ton', 'tron'])))
      .toEqual(['tron', 'ton', 'base', 'bnb', 'solana', 'ethereum']);
  });

  it('shows a newly funded chain in the manual mode', () => {
    const config: ChainDisplayConfiguration = {
      displayMode: 'manual',
      hiddenChains: ['tron'],
      manualOrder: ['solana', 'ton', 'tron'],
    };

    expect(getVisibleChains(
      config,
      ['ton', 'tron', 'solana', 'ethereum'],
      ['ethereum', 'ton', 'tron', 'solana'],
      new Set(['ton', 'ethereum']),
    )).toEqual(['ton', 'ethereum']);
  });
});

describe('chain display configuration updates', () => {
  it('stores only the differences from the automatic visibility', () => {
    let config = setChainDisplayMode(DEFAULT_CHAIN_DISPLAY_CONFIGURATION, 'manual', ['solana', 'ton', 'tron']);
    config = setChainVisibility(config, 'ton', false, true);
    config = setChainVisibility(config, 'tron', true, false);

    expect(config.hiddenChains).toEqual(['ton']);
    expect(config.shownChains).toEqual(['tron']);
    expect(config.manualOrder).toEqual(['solana', 'tron']);
    expect(getVisibleChains(
      config,
      ['ton', 'tron', 'solana'],
      ['ton', 'solana', 'tron'],
      new Set(['ton', 'solana']),
    )).toEqual(['solana', 'tron']);

    config = setChainVisibility(config, 'ton', true, true);
    config = setChainVisibility(config, 'tron', false, false);

    expect(config.hiddenChains).toBeUndefined();
    expect(config.shownChains).toBeUndefined();
  });

  it('removes a disabled chain from the manual order', () => {
    const config: ChainDisplayConfiguration = {
      displayMode: 'manual',
      manualOrder: ['tron', 'ton', 'solana'],
    };

    expect(setChainVisibility(config, 'ton', false, true).manualOrder).toEqual(['tron', 'solana']);
  });

  it('persists the relative order of the visible chains only', () => {
    const config: ChainDisplayConfiguration = {
      displayMode: 'manual',
      hiddenChains: ['ton'],
      shownChains: ['base'],
    };
    const defaultVisibleChains = new Set<ApiChain>(['solana', 'ton']);

    const newConfig = setManualChainOrder(
      config,
      ['solana', 'ton', 'base', 'tron'],
      defaultVisibleChains,
    );

    expect(newConfig.manualOrder).toEqual(['solana', 'base']);
    expect(getOrderedChainsForDisplay(
      newConfig,
      ['ton', 'tron', 'solana', 'base'],
      ['tron', 'ton', 'base', 'solana'],
      defaultVisibleChains,
    )).toEqual(['solana', 'base', 'tron', 'ton']);
  });

  it('preserves a prior manual order when the mode is switched back and forth', () => {
    const config: ChainDisplayConfiguration = {
      displayMode: 'manual',
      manualOrder: ['solana', 'ton', 'tron'],
    };

    const newConfig = setChainDisplayMode(setChainDisplayMode(config, 'value'), 'manual');

    expect(newConfig.manualOrder).toEqual(['solana', 'ton', 'tron']);
  });
});
