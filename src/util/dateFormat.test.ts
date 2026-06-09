import type { LangFn } from './langProvider';

import { formatRelativeDays } from './dateFormat';

describe('formatRelativeDays', () => {
  function createLangSpy() {
    const calls: Array<{ key: string; value?: number; format?: string }> = [];
    const lang = ((key: string, value?: number, format?: string) => {
      calls.push({ key, value, format });
      return key;
    }) as unknown as LangFn;

    return { lang, calls };
  }

  it('uses the dedicated "today" key for 0 days (never the plural)', () => {
    const { lang, calls } = createLangSpy();

    expect(formatRelativeDays(lang, 0)).toBe('$relative_today');
    expect(calls).toEqual([{ key: '$relative_today', value: undefined, format: undefined }]);
  });

  it('uses the dedicated "tomorrow" key for exactly 1 day (never the plural)', () => {
    const { lang, calls } = createLangSpy();

    expect(formatRelativeDays(lang, 1)).toBe('$relative_tomorrow');
    expect(calls).toEqual([{ key: '$relative_tomorrow', value: undefined, format: undefined }]);
  });

  // Regression: the Slavic `one` plural category covers 21, 31, 61… which must read
  // "in N days", not "tomorrow". Those values must go through the `$in_days` plural.
  it.each([2, 5, 21, 61])('uses the $in_days plural for %i days', (days) => {
    const { lang, calls } = createLangSpy();

    formatRelativeDays(lang, days);
    expect(calls).toEqual([{ key: '$in_days', value: days, format: undefined }]);
  });

  it('forwards the number format flag to the plural', () => {
    const { lang, calls } = createLangSpy();

    formatRelativeDays(lang, 61, 'i');
    expect(calls).toEqual([{ key: '$in_days', value: 61, format: 'i' }]);
  });
});
