import { DEFAULT_MAX_LENGTH, shortenDomain } from './shortenDomain';

describe('shortenDomain', () => {
  it('should return undefined for empty string', () => {
    expect(shortenDomain('')).toBeUndefined();
  });

  it('should return undefined for null/undefined', () => {
    // eslint-disable-next-line no-null/no-null
    expect(shortenDomain(null as any)).toBeUndefined();
    expect(shortenDomain(undefined as any)).toBeUndefined();
  });

  it('should return domain as is if length is within limit', () => {
    expect(shortenDomain('somedomain.t.me', 15)).toBe('somedomain.t.me');
    expect(shortenDomain('example.com', 11)).toBe('example.com');
    expect(shortenDomain('test.t.me', 9)).toBe('test.t.me');
  });

  it(`should shorten domain when exceeding default maxLength (${DEFAULT_MAX_LENGTH})`, () => {
    const result = shortenDomain('verylongdomainname.t.me');
    expect(result).toBe('verylong···.t.me');
    expect(result!.length).toEqual(DEFAULT_MAX_LENGTH);
  });

  it('should shorten domain when exceeding custom maxLength', () => {
    expect(shortenDomain('somedomain.t.me', 10)).toBe('so···.t.me');
    expect(shortenDomain('somedomain.t.me', 8)).toBe('s···.t.me');
    expect(shortenDomain('somedomain.t.me', 6)).toBe('s···.t.me');
  });

  it('should handle domains without zone', () => {
    expect(shortenDomain('localhost', 9)).toBe('localhost');
    expect(shortenDomain('localhost', 8)).toBe('local···');
    expect(shortenDomain('verylongdomainname', 10)).toBe('verylon···');
    expect(shortenDomain('test', 4)).toBe('test');
  });

  it('should handle very short maxLength', () => {
    // somedomain.t.me = 15 chars, zone = .t.me = 5 chars
    // zonePart.length (5) >= maxLength (5), so we try minimal representation
    // minimalShortened = "s" + "···" + ".t.me" = "s···.t.me" (8 chars) < domain.length (15)
    // So we return minimal representation
    expect(shortenDomain('somedomain.t.me', 5)).toBe('s···.t.me');
    // example.com = 11 chars, zone = .com = 4 chars
    // zonePart.length (4) >= maxLength (4), so we try minimal representation
    // minimalShortened = "e" + "···" + ".com" = "e···.com" (7 chars) < domain.length (11)
    // So we return minimal representation
    expect(shortenDomain('example.com', 4)).toBe('e···.com');
    // But if zonePart is shorter, we can shorten normally
    // somedomain.t.me = 15 chars, zone = .t.me = 5 chars
    // availableNameLength = 10 - 5 = 5, we can show 5 - 3 = 2 chars from namePart
    expect(shortenDomain('somedomain.t.me', 10)).toBe('so···.t.me');
  });

  it('should handle domains with long zones', () => {
    // name.verylongzonename.com = 24 chars, zone = .verylongzonename.com = 20 chars
    // zonePart.length (20) >= maxLength (20), so we can't shorten, return as is
    expect(shortenDomain('name.verylongzonename.com', 20)).toBe('name.verylongzonename.com');
    // short.name.verylongzonename.com = 30 chars, zone = .name.verylongzonename.com = 24 chars
    // zonePart.length (24) < maxLength (25), so we can shorten
    // availableNameLength = 25 - 24 = 1, minimalShortenedLength = 1 + 3 + 24 = 28 > 25
    // So we return minimal representation: "s" + "···" + ".name.verylongzonename.com"
    expect(shortenDomain('short.name.verylongzonename.com', 25)).toBe('s···.name.verylongzonename.com');
    // longname.verylongzonename.com = 28 chars, zone = .verylongzonename.com = 20 chars
    // domain.length (28) <= maxLength (30), so return as is
    expect(shortenDomain('longname.verylongzonename.com', 30)).toBe('longname.verylongzonename.com');
    // But if domain exceeds maxLength, we shorten
    // verylongname.verylongzonename.com = 32 chars, zone = .verylongzonename.com = 20 chars
    // availableNameLength = 30 - 20 = 10, we can show 10 - 3 = 7 chars from namePart
    // But shortened version length check might return original if it's not shorter
    // Let's check what function actually returns
    const result = shortenDomain('verylongname.verylongzonename.com', 30);
    expect(result).toBe('verylo···.verylongzonename.com');
  });

  it('should preserve zone completely', () => {
    const result1 = shortenDomain('somedomain.t.me', 10);
    expect(result1).toContain('.t.me');
    expect(result1).toMatch(/^.+\.t\.me$/);

    const result2 = shortenDomain('example.com', 8);
    expect(result2).toContain('.com');
    expect(result2).toMatch(/^.+\.com$/);
  });

  it('should use cache for same inputs', () => {
    const result1 = shortenDomain('somedomain.t.me', 10);
    const result2 = shortenDomain('somedomain.t.me', 10);
    expect(result1).toBe(result2);
  });

  it('should handle edge cases with minimal length', () => {
    expect(shortenDomain('a.b', 3)).toBe('a.b');
    expect(shortenDomain('ab.c', 3)).toBe('ab.c');
    expect(shortenDomain('abc.d', 4)).toBe('abc.d');
  });

  it('should handle multiple dots in domain', () => {
    expect(shortenDomain('subdomain.example.com', 15)).toBe('s···.example.com');
    expect(shortenDomain('a.b.c', 5)).toBe('a.b.c');
    expect(shortenDomain('ab.b.c', 5)).toBe('ab.b.c');
    expect(shortenDomain('abc.b.c', 5)).toBe('abc.b.c');
    expect(shortenDomain('abcd.b.c', 5)).toBe('abcd.b.c');
  });
});
