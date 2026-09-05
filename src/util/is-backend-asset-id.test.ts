import { getIsBackendAssetId } from './is-backend-asset-id';

describe('getIsBackendAssetId', () => {
  it('recognizes the backend spelling of a coin and of a token', () => {
    expect(getIsBackendAssetId('bitcoin:native')).toBe(true);
    expect(getIsBackendAssetId('ethereum:0xdAC17F958D2ee523a2206206994597C13D831ec7')).toBe(true);
  });

  it('leaves the slugs of this app alone', () => {
    expect(getIsBackendAssetId('toncoin')).toBe(false);
    expect(getIsBackendAssetId('ton-eqcxe6mutq')).toBe(false);
    expect(getIsBackendAssetId('solana-dz9mq9nzkb')).toBe(false);
  });
});
