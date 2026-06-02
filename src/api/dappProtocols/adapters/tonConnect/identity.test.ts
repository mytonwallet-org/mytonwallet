import { resolveTonConnectDappUrl } from './identity';

describe('resolveTonConnectDappUrl', () => {
  it('prefers requestUrl when provided', () => {
    expect(resolveTonConnectDappUrl({
      requestUrl: 'https://example.com/some/path',
      manifestUrl: 'https://manifest.example.com/tonconnect-manifest.json',
      declaredUrl: 'https://declared.example.com',
    })).toBe('https://example.com');
  });

  it('uses declaredUrl origin when it matches manifestUrl origin', () => {
    expect(resolveTonConnectDappUrl({
      manifestUrl: 'https://example.com/tonconnect-manifest.json',
      declaredUrl: 'https://example.com/',
    })).toBe('https://example.com');
  });

  it('falls back to manifestUrl origin when declaredUrl origin mismatches', () => {
    expect(resolveTonConnectDappUrl({
      manifestUrl: 'https://attacker.com/tonconnect-manifest.json',
      declaredUrl: 'https://victim.com',
    })).toBe('https://attacker.com');
  });
});
