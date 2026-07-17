import getChainNetworkName from './getChainNetworkName';

describe('getChainNetworkName', () => {
  it.each([
    ['ton', 'TON'],
    ['base', 'Base'],
    ['avalanche', 'Avalanche'],
    ['hyperliquid', 'Hyperliquid'],
  ])('uses the canonical title for the supported %s chain', (chain, expectedTitle) => {
    expect(getChainNetworkName(chain)).toBe(expectedTitle);
  });

  it('retains legacy and unknown raw chain identifiers when they are not app-supported', () => {
    expect(getChainNetworkName('bitcoin_cash')).toBe('Bitcoin Cash');
    expect(getChainNetworkName('future_chain')).toBe('future_chain');
  });
});
