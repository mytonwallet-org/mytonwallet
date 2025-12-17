import { MEANINGFUL_CHAR_LENGTH, shortenAddress } from './shortenAddress';

describe('shortenAddress', () => {
  it('should return undefined for empty string', () => {
    expect(shortenAddress('')).toBeUndefined();
  });

  it('should return undefined for null/undefined', () => {
    // eslint-disable-next-line no-null/no-null
    expect(shortenAddress(null as any)).toBeUndefined();
    expect(shortenAddress(undefined as any)).toBeUndefined();
  });

  it('should return address as is if length is within limit', () => {
    const shortAddress = 'ABC123';
    expect(shortenAddress(shortAddress)).toBe(shortAddress);

    const addressWithinLimit = 'A'.repeat(MEANINGFUL_CHAR_LENGTH * 2 + 3); // 6 + 6 + 3 (filler) = 15
    expect(shortenAddress(addressWithinLimit)).toBe(addressWithinLimit);
  });

  it('should shorten address with default parameters', () => {
    const longAddress = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
    const result = shortenAddress(longAddress);
    expect(result).toBe('EQAIsi···1B282S');
    expect(result!.length).toBe(MEANINGFUL_CHAR_LENGTH + 3 + MEANINGFUL_CHAR_LENGTH); // 6 + 3 + 6 = 15
  });

  it('should shorten address with custom shift', () => {
    const address = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
    expect(shortenAddress(address, 4)).toBe('EQAI···282S');
    // When shift=8, fromRight defaults to 8 (same as shift)
    expect(shortenAddress(address, 8)).toBe('EQAIsixs···UG1B282S');
  });

  it('should shorten address with custom fromRight', () => {
    const address = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
    expect(shortenAddress(address, 6, 4)).toBe('EQAIsi···282S');
    expect(shortenAddress(address, 6, 8)).toBe('EQAIsi···UG1B282S');
  });

  it('should handle very short addresses', () => {
    expect(shortenAddress('ABC')).toBe('ABC');
    expect(shortenAddress('ABCDEF')).toBe('ABCDEF');
    expect(shortenAddress('ABCDEFG')).toBe('ABCDEFG');
  });

  it('should use cache for same inputs', () => {
    const address = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
    const result1 = shortenAddress(address);
    const result2 = shortenAddress(address);
    expect(result1).toBe(result2);
  });

  it('should handle addresses at boundary length', () => {
    // Address length = shift + fromRight + FILLER_LENGTH (6 + 6 + 3 = 15)
    const boundaryAddress = 'A'.repeat(15);
    expect(shortenAddress(boundaryAddress)).toBe(boundaryAddress);

    // Address length = shift + fromRight + FILLER_LENGTH + 1 (16)
    const overBoundaryAddress = 'A'.repeat(16);
    const result = shortenAddress(overBoundaryAddress);
    expect(result).toBe('AAAAAA···AAAAAA');
  });

  it('should handle different address formats', () => {
    const tonAddress = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
    expect(shortenAddress(tonAddress)).toBe('EQAIsi···1B282S');

    const hexAddress = '0x1234567890abcdef1234567890abcdef12345678';
    expect(shortenAddress(hexAddress)).toBe('0x1234···345678');
  });

  it('should handle custom parameters correctly', () => {
    const address = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    expect(shortenAddress(address, 3, 3)).toBe('ABC···XYZ');
    expect(shortenAddress(address, 5, 5)).toBe('ABCDE···VWXYZ');
    expect(shortenAddress(address, 2, 4)).toBe('AB···WXYZ');
  });
});
