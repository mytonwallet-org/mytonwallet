import { matchesSelector } from './walletQueryAssets';

const tonUsdt = { chain: 'ton' as const, slug: 'ton-eqcxe6mutq', symbol: 'USD₮', tokenAddress: 'EQCxE6mUtQ' };

describe('matchesSelector', () => {
  it('matches a symbol the user writes without the Tether sign or in another case', () => {
    expect(matchesSelector(tonUsdt, { symbol: 'USDT' })).toBe(true);
    expect(matchesSelector(tonUsdt, { symbol: 'USD₮' })).toBe(true);
    expect(matchesSelector({ ...tonUsdt, symbol: 'jUSDT' }, { symbol: 'JUSDT' })).toBe(true);
  });

  it('keeps other symbols and the other selector fields apart', () => {
    expect(matchesSelector(tonUsdt, { symbol: 'USDC' })).toBe(false);
    expect(matchesSelector(tonUsdt, { symbol: 'USD' })).toBe(false);
    expect(matchesSelector(tonUsdt, { symbol: 'USDT', chain: 'tron' })).toBe(false);
  });
});
