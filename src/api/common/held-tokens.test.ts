import {
  forgetAllHeldTokens,
  forgetHeldTokens,
  forgetOtherNetworksHeldTokens,
  getHeldSlugs,
  recordHeldTokens,
} from './held-tokens';

const MAINNET_ACCOUNT = '1-mainnet';
const OTHER_MAINNET_ACCOUNT = '2-mainnet';
const TESTNET_ACCOUNT = '3-testnet';

describe('held tokens', () => {
  beforeEach(forgetAllHeldTokens);

  it('ignores the token accounts left with no balance', () => {
    recordHeldTokens(MAINNET_ACCOUNT, { 'ton-held': 5n, 'ton-spent': 0n });

    expect(getHeldSlugs()).toEqual(new Set(['ton-held']));
  });

  it('keeps the tokens a partial update says nothing about', () => {
    recordHeldTokens(MAINNET_ACCOUNT, { 'ton-a': 1n, 'ton-b': 2n });
    recordHeldTokens(MAINNET_ACCOUNT, { 'ton-a': 3n });

    expect(getHeldSlugs()).toEqual(new Set(['ton-a', 'ton-b']));
  });

  it('reports new slugs once, across accounts', () => {
    expect(recordHeldTokens(MAINNET_ACCOUNT, { 'ton-a': 1n })).toBe(true);
    expect(recordHeldTokens(MAINNET_ACCOUNT, { 'ton-a': 2n })).toBe(false);
    expect(recordHeldTokens(OTHER_MAINNET_ACCOUNT, { 'ton-a': 1n })).toBe(false);
    expect(recordHeldTokens(OTHER_MAINNET_ACCOUNT, { 'ton-b': 1n })).toBe(true);
  });

  it('reports nothing new for a balance that never was held', () => {
    expect(recordHeldTokens(MAINNET_ACCOUNT, { 'ton-spent': 0n })).toBe(false);
    expect(getHeldSlugs().size).toBe(0);
  });

  it('drops an account on removal and leaves the others alone', () => {
    recordHeldTokens(MAINNET_ACCOUNT, { 'ton-a': 1n });
    recordHeldTokens(OTHER_MAINNET_ACCOUNT, { 'ton-b': 1n });
    forgetHeldTokens(MAINNET_ACCOUNT);

    expect(getHeldSlugs()).toEqual(new Set(['ton-b']));
  });

  it('keeps a token another account still holds', () => {
    recordHeldTokens(MAINNET_ACCOUNT, { 'ton-shared': 1n });
    recordHeldTokens(OTHER_MAINNET_ACCOUNT, { 'ton-shared': 2n });
    forgetHeldTokens(MAINNET_ACCOUNT);

    expect(getHeldSlugs()).toEqual(new Set(['ton-shared']));
  });

  it('keeps a token an account of the polled network still holds', () => {
    recordHeldTokens(TESTNET_ACCOUNT, { 'ton-shared': 1n });
    recordHeldTokens(MAINNET_ACCOUNT, { 'ton-shared': 2n });
    forgetOtherNetworksHeldTokens('mainnet');

    expect(getHeldSlugs()).toEqual(new Set(['ton-shared']));
  });

  it('drops the networks that are no longer polled', () => {
    recordHeldTokens(MAINNET_ACCOUNT, { 'ton-a': 1n });
    recordHeldTokens(TESTNET_ACCOUNT, { 'ton-b': 1n });
    forgetOtherNetworksHeldTokens('testnet');

    expect(getHeldSlugs()).toEqual(new Set(['ton-b']));
  });
});
