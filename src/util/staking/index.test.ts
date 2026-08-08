import { MYCOIN_MAINNET, MYCOIN_TESTNET, TONCOIN } from '../../config';
import { getIsNewStakeAllowed } from '.';

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
