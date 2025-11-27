import { isValidUrl, normalizeUrl } from './url';

// Test constants
const TEST_TON_ADDRESS = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
const TEST_TRON_ADDRESS = 'TRjE1H8dxypKM1NZRdysbs9wo7huR4bdNz';

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
    expect(normalizeUrl('my.tt/view?ton=123')).toBe('https://my.tt/view?ton=123');
    expect(normalizeUrl('subdomain.example.com/path')).toBe('https://subdomain.example.com/path');
  });

  it('should convert http:// to https://', () => {
    expect(normalizeUrl('http://example.com')).toBe('https://example.com');
    expect(normalizeUrl('http://my.tt/view?ton=123')).toBe('https://my.tt/view?ton=123');
  });

  it('should not modify URLs that already have https:// protocol', () => {
    expect(normalizeUrl('https://example.com')).toBe('https://example.com');
    expect(normalizeUrl('https://my.tt/view?ton=123&tron=456')).toBe('https://my.tt/view?ton=123&tron=456');
  });

  it('should handle URLs with query parameters and fragments', () => {
    expect(normalizeUrl('example.com/path?query=value#fragment'))
      .toBe('https://example.com/path?query=value#fragment');
    const deeplinkUrl = `my.tt/view?ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`;
    const expectedUrl = `https://my.tt/view?ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`;
    expect(normalizeUrl(deeplinkUrl)).toBe(expectedUrl);
  });

  it('should handle empty string', () => {
    expect(normalizeUrl('')).toBe('https://');
  });
});
