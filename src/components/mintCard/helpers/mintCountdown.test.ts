import type { ApiCardInfo } from '../../../api/types';

import { formatMintCountdown, getMintStartsAt } from './mintCountdown';

const SOLD_OUT: ApiCardInfo = { all: 100, notMinted: 0, price: 10 };

describe('getMintStartsAt', () => {
  it('parses UTC, fractional seconds and timezone offsets', () => {
    expect(getMintStartsAt({ ...SOLD_OUT, startsAt: '2027-01-15T08:00:00Z' })).toBe(Date.UTC(2027, 0, 15, 8));
    expect(getMintStartsAt({ ...SOLD_OUT, startsAt: '2027-01-15T08:00:00.250Z' }))
      .toBe(Date.UTC(2027, 0, 15, 8, 0, 0, 250));
    expect(getMintStartsAt({ ...SOLD_OUT, startsAt: '2027-01-15T11:00:00+03:00' })).toBe(Date.UTC(2027, 0, 15, 8));
  });

  it('shows no countdown while supply is left or the start time is unusable', () => {
    expect(getMintStartsAt({ ...SOLD_OUT, notMinted: 5, startsAt: '2027-01-15T08:00:00Z' })).toBeUndefined();
    expect(getMintStartsAt(SOLD_OUT)).toBeUndefined();
    expect(getMintStartsAt({ ...SOLD_OUT, startsAt: 'soon' })).toBeUndefined();
  });
});

describe('formatMintCountdown', () => {
  it('always shows hours, minutes and seconds', () => {
    expect(formatMintCountdown(0)).toBe('00:00:00');
    expect(formatMintCountdown(59)).toBe('00:00:59');
    expect(formatMintCountdown(3661)).toBe('01:01:01');
    expect(formatMintCountdown(100 * 3600)).toBe('100:00:00');
  });
});
