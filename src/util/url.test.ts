import { isValidUrl } from './url';

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
