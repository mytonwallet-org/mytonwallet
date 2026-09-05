import getIsAppUpdateNeeded from './getIsAppUpdateNeeded';

describe('getIsAppUpdateNeeded', () => {
  describe('strict', () => {
    it('reports a strictly newer served version', () => {
      expect(getIsAppUpdateNeeded('26.8.10', '26.8.9', true)).toBe(true);
      expect(getIsAppUpdateNeeded('26.10.0', '26.9.9', true)).toBe(true);
      expect(getIsAppUpdateNeeded('27.0.0', '26.9.9', true)).toBe(true);
    });

    it('stays quiet on an equal or older served version', () => {
      expect(getIsAppUpdateNeeded('26.8.9', '26.8.9', true)).toBe(false);
      expect(getIsAppUpdateNeeded('26.8.8', '26.8.9', true)).toBe(false);
      expect(getIsAppUpdateNeeded('26.9.0', '26.10.0', true)).toBe(false);
    });

    it('ignores a served version that is not a bare version string', () => {
      expect(getIsAppUpdateNeeded('', '26.8.9', true)).toBe(false);
      expect(getIsAppUpdateNeeded('26.9.0-beta', '26.8.9', true)).toBe(false);
      expect(getIsAppUpdateNeeded('<!doctype html>', '26.8.9', true)).toBe(false);
    });

    it('tolerates whitespace around the served version', () => {
      expect(getIsAppUpdateNeeded(' 26.8.10\n', '26.8.9', true)).toBe(true);
    });
  });

  describe('non-strict', () => {
    it('reports any difference in either direction', () => {
      expect(getIsAppUpdateNeeded('26.8.10', '26.8.9')).toBe(true);
      expect(getIsAppUpdateNeeded('26.8.8', '26.8.9')).toBe(true);
      expect(getIsAppUpdateNeeded('26.8.9', '26.8.9')).toBe(false);
    });
  });
});
