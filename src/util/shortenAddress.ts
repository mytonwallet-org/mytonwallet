import withCache from './withCache';

export const MEANINGFUL_CHAR_LENGTH = 6;
const ELLIPSIS = '···';
const ELLIPSIS_LENGTH = ELLIPSIS.length;

export const shortenAddress = withCache((address: string, shift = MEANINGFUL_CHAR_LENGTH, fromRight = shift) => {
  if (!address) return undefined;

  if (address.length <= shift + fromRight + ELLIPSIS_LENGTH) return address;

  return `${address.slice(0, shift)}${ELLIPSIS}${address.slice(-fromRight)}`;
});
