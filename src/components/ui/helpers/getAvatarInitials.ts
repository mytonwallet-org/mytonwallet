import segmentGraphemes from '../../../util/segmentGraphemes';

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

  return segmentGraphemes(str).slice(0, length).join('');
}
