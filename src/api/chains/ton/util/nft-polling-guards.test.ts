import { shouldEmitNftFullLoadFinal } from './nft-polling-guards';

describe('shouldEmitNftFullLoadFinal', () => {
  it('emits after a completed stream, even an empty one - the wallet genuinely owns no NFTs', () => {
    expect(shouldEmitNftFullLoadFinal(false, 0)).toBe(true);
    expect(shouldEmitNftFullLoadFinal(false, 12)).toBe(true);
  });

  it('emits after a failed stream that yielded some NFTs - partial data still needs its final flags', () => {
    expect(shouldEmitNftFullLoadFinal(true, 3)).toBe(true);
  });

  it('does not emit after a failed stream that yielded nothing - it would render a false "no collectibles"', () => {
    expect(shouldEmitNftFullLoadFinal(true, 0)).toBe(false);
  });
});
