import { getEdgePressDirection, getEdgeZoneWidth } from './getEdgePressDirection';

describe('getEdgePressDirection', () => {
  it('takes an eighth of the width from each edge, at most 135 px, as Telegram does', () => {
    expect(getEdgeZoneWidth(375)).toBe(46.875);
    expect(getEdgeZoneWidth(1440)).toBe(135);
  });

  it('pages back near the left edge and forward near the right one, when there is a picture there', () => {
    expect(getEdgePressDirection(20, 375, true, true)).toBe(-1);
    expect(getEdgePressDirection(360, 375, true, true)).toBe(1);
    expect(getEdgePressDirection(187, 375, true, true)).toBeUndefined();
    expect(getEdgePressDirection(20, 375, false, true)).toBeUndefined();
    expect(getEdgePressDirection(360, 375, true, false)).toBeUndefined();
  });
});
