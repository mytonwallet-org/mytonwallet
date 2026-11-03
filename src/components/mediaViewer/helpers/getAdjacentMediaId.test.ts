import { getAdjacentMediaId } from './getAdjacentMediaId';

const IDS = ['first', 'second', 'third'];

describe('getAdjacentMediaId', () => {
  it('moves to the media after or before the one shown', () => {
    expect(getAdjacentMediaId(IDS, 'second', 1)).toBe('third');
    expect(getAdjacentMediaId(IDS, 'second', -1)).toBe('first');
  });

  it('stops at either end', () => {
    expect(getAdjacentMediaId(IDS, 'third', 1)).toBeUndefined();
    expect(getAdjacentMediaId(IDS, 'first', -1)).toBeUndefined();
    expect(getAdjacentMediaId(['only'], 'only', 1)).toBeUndefined();
  });

  it('moves nowhere from media it does not have, or without a direction', () => {
    expect(getAdjacentMediaId(IDS, 'missing', 1)).toBeUndefined();
    expect(getAdjacentMediaId(IDS, 'second', 0)).toBeUndefined();
  });
});
