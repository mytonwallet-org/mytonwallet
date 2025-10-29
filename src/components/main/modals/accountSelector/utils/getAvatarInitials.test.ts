import { getAvatarInitials } from './getAvatarInitials';

describe('getAvatarInitials', () => {
  test('returns empty string for empty/undefined', () => {
    expect(getAvatarInitials()).toBe('');
    expect(getAvatarInitials('')).toBe('');
    expect(getAvatarInitials('   ')).toBe('');
    expect(getAvatarInitials('   -   ')).toBe('');
  });

  test('single word: takes first 2 graphemes (uppercased)', () => {
    expect(getAvatarInitials('alice')).toBe('AL');
    expect(getAvatarInitials(' Alice ')).toBe('AL');

    // Handles emoji as single grapheme when Intl.Segmenter available
    // Fallback still keeps correct display using Array.from code points
    expect(getAvatarInitials('🤝hand')).toBe('🤝H');
  });

  test('two words: takes first grapheme of first two words', () => {
    expect(getAvatarInitials('Alice Bob')).toBe('AB');
    expect(getAvatarInitials('alice-bob')).toBe('AB');
    expect(getAvatarInitials(' alice  bob ')).toBe('AB');
  });

  test('removes # characters before processing', () => {
    expect(getAvatarInitials('#Alice #Bob')).toBe('AB');
    expect(getAvatarInitials('###alice')).toBe('AL');
  });

  test('supports complex emoji and ZWJ sequences', () => {
    // Family emoji is a single grapheme with ZWJ if Segmenter is available
    // Regardless, we expect first emoji + first grapheme of next word
    expect(getAvatarInitials('👨‍👩‍👧‍👦 Family')).toBe('👨‍👩‍👧‍👦F');
  });

  test('fallback path works when Intl.Segmenter.segment throws', () => {
    const hasSegmenter = typeof (global as any).Intl !== 'undefined'
      && typeof (global as any).Intl.Segmenter === 'function';

    if (!hasSegmenter) {
      // Environment without Segmenter already uses fallback; just assert behavior
      expect(getAvatarInitials('hello world')).toBe('HW');
      expect(getAvatarInitials('👨‍👩‍👧‍👦family')).toBe('👨‍');
      return;
    }

    const spy = jest
      .spyOn((Intl as any).Segmenter.prototype, 'segment')
      .mockImplementation(() => { throw new Error('boom'); });

    try {
      // With segment() throwing, code should use fallback via Array.from
      expect(getAvatarInitials('hello world')).toBe('HW');
      // Fallback does not know grapheme clusters; it slices first two code points: '👨' + ZWJ
      expect(getAvatarInitials('👨‍👩‍👧‍👦family')).toBe('👨‍');
    } finally {
      spy.mockRestore();
    }
  });
});
