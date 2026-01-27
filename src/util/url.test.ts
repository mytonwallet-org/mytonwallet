import { convertExplorerUrl, isValidUrl, normalizeUrl } from './url';

// Test constants
const TEST_TON_ADDRESS = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
const TEST_TRON_ADDRESS = 'TRjE1H8dxypKM1NZRdysbs9wo7huR4bdNz';
const TEST_TON_HASH = 'cd3547d822b1f33e5825572709b9ac95e64d46680cde5fc6e5ae489ecec83b27';
const TEST_NFT_ADDRESS = 'EQCchzdeVwH5js22ReWU7smONvgpB9bZG9k_VEmYmGhIhuTL';
const TEST_NFT_COLLECTION_ADDRESS = 'EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM';

describe('isValidUrl', () => {
  it('should return true for valid urls', () => {
    expect(isValidUrl('https://www.google.com')).toBe(true);
    expect(isValidUrl('http://localhost')).toBe(true);
    expect(isValidUrl('http://localhost:3000')).toBe(true);
    expect(isValidUrl('https://what-about-non-ascii.рф')).toBe(true);
    expect(isValidUrl('http://127.0.0.1:3000')).toBe(true);
  });

  it('should return false for invalid urls', () => {
    expect(isValidUrl('https://fragment')).toBe(false);
    expect(isValidUrl('https://@push')).toBe(false);
    expect(isValidUrl('https://what is push?')).toBe(false);
    expect(isValidUrl('https://what is push.')).toBe(false);
    expect(isValidUrl('javascript:alert("Hello, world!")')).toBe(false);
    // eslint-disable-next-line @stylistic/max-len
    expect(isValidUrl('data:image/svg+xml,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20onload%3D%27alert(1)%27%3E%3C%2Fsvg%3E')).toBe(false);
    expect(isValidUrl('file://localhost/path/to/file')).toBe(false);
  });
});

describe('normalizeUrl', () => {
  it('should add https:// prefix when protocol is missing', () => {
    expect(normalizeUrl('example.com')).toBe('https://example.com');
    expect(normalizeUrl('my.tt/view/?ton=123')).toBe('https://my.tt/view/?ton=123');
    expect(normalizeUrl('subdomain.example.com/path')).toBe('https://subdomain.example.com/path');
  });

  it('should convert http:// to https://', () => {
    expect(normalizeUrl('http://example.com')).toBe('https://example.com');
    expect(normalizeUrl('http://my.tt/view/?ton=123')).toBe('https://my.tt/view/?ton=123');
  });

  it('should not modify URLs that already have https:// protocol', () => {
    expect(normalizeUrl('https://example.com')).toBe('https://example.com');
    expect(normalizeUrl('https://my.tt/view/?ton=123&tron=456')).toBe('https://my.tt/view/?ton=123&tron=456');
  });

  it('should handle URLs with query parameters and fragments', () => {
    expect(normalizeUrl('example.com/path?query=value#fragment'))
      .toBe('https://example.com/path?query=value#fragment');
    const deeplinkUrl = `my.tt/view/?ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`;
    const expectedUrl = `https://my.tt/view/?ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`;
    expect(normalizeUrl(deeplinkUrl)).toBe(expectedUrl);
  });

  it('should handle empty string', () => {
    expect(normalizeUrl('')).toBe('https://');
  });
});

describe('convertExplorerUrl', () => {
  describe('TON explorer conversions (mainnet)', () => {
    it('should convert address URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert address URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      const expected = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert transaction URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/tx/${TEST_TON_HASH}`;
      const expected = `https://tonviewer.com/transaction/${TEST_TON_HASH}`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert transaction URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/transaction/${TEST_TON_HASH}`;
      const expected = `https://tonscan.org/tx/${TEST_TON_HASH}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert NFT URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/nft/${TEST_NFT_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_NFT_ADDRESS}?nft`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert NFT URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_NFT_ADDRESS}?nft`;
      const expected = `https://tonscan.org/nft/${TEST_NFT_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert NFT collection URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/collection/${TEST_NFT_COLLECTION_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_NFT_COLLECTION_ADDRESS}?collection`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert NFT collection URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_NFT_COLLECTION_ADDRESS}?collection`;
      const expected = `https://tonscan.org/collection/${TEST_NFT_COLLECTION_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert token/jetton URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/jetton/${TEST_TON_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?jetton`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert token/jetton URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_TON_ADDRESS}?jetton`;
      const expected = `https://tonscan.org/jetton/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });
  });

  describe('TON explorer conversions (testnet)', () => {
    it('should convert testnet address URL from Tonscan to Tonviewer', () => {
      const input = `https://testnet.tonscan.org/address/${TEST_TON_ADDRESS}`;
      const expected = `https://testnet.tonviewer.com/${TEST_TON_ADDRESS}?address`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert testnet address URL from Tonviewer to Tonscan', () => {
      const input = `https://testnet.tonviewer.com/${TEST_TON_ADDRESS}?address`;
      const expected = `https://testnet.tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert testnet transaction URL', () => {
      const input = `https://testnet.tonscan.org/tx/${TEST_TON_HASH}`;
      const expected = `https://testnet.tonviewer.com/transaction/${TEST_TON_HASH}`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });
  });

  describe('URLs with query strings and fragments', () => {
    it('should preserve query string when converting address URL', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}?tab=tokens`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      // Query string is not preserved in the converted URL (identifier extraction stops at ?)
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should handle URLs with hash fragments', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}#section`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      // Hash fragment is not preserved (identifier extraction stops at #)
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });
  });

  describe('Edge cases', () => {
    it('should return the same URL if already on target explorer', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(input);
    });

    it('should return undefined for non-explorer URLs', () => {
      expect(convertExplorerUrl('https://google.com', 'tonscan')).toBeUndefined();
      expect(convertExplorerUrl('https://example.com/path', 'tonviewer')).toBeUndefined();
    });

    it('should return undefined for invalid explorer ID', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'nonexistent')).toBeUndefined();
    });

    it('should return undefined for cross-chain conversion attempts', () => {
      const tronUrl = `https://tronscan.org/#/address/${TEST_TRON_ADDRESS}`;
      expect(convertExplorerUrl(tronUrl, 'tonscan')).toBeUndefined();
    });

    it('should use fallback for URLs that do not match any pattern', () => {
      // Create a URL that starts with explorer base but doesn't match any pattern
      const input = 'https://tonscan.org/unknown/path';
      const expected = 'https://tonviewer.com/unknown/path';
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });
  });

  describe('TRON explorer (single explorer, no conversion)', () => {
    it('should return the same URL for TRON explorer (only one explorer available)', () => {
      const input = `https://tronscan.org/#/address/${TEST_TRON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tronscan')).toBe(input);
    });

    it('should return undefined when trying to convert TRON to non-existent explorer', () => {
      const input = `https://tronscan.org/#/address/${TEST_TRON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBeUndefined();
    });
  });
});
