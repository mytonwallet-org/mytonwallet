import { logDebugError } from '../../../util/logs';

const segmenter = typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function'
  ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  : undefined;

export function getAvatarInitials(title?: string) {
  if (!title) return '';

  const cleanedTitle = title.replace(/#/g, '');
  const words = cleanedTitle.toUpperCase()
    .trim()
    .split(/[-\s]+/)
    .filter(Boolean);

  if (words.length === 0) return '';
  if (words.length === 1) {
    return getFirstSymbols(words[0], 2);
  }

  return getFirstSymbols(words[0]) + getFirstSymbols(words[1]);
}

function getFirstSymbols(str: string, length = 1) {
  if (!str || length <= 0) return '';

  // Correctly selects characters based on utf16 encoding (emoji 🤝or 👨‍👩‍👧‍👦 for example)
  if (segmenter) {
    try {
      const segments = segmenter.segment(str);
      let result = '';
      let i = 0;

      for (const { segment } of segments) {
        result += segment;
        if (++i >= length) break;
      }

      return result;
    } catch (err: any) {
      logDebugError('getFirstSymbols', err);
    }
  }

  const chars = Array.from(str);

  return chars.slice(0, length).join('');
}
