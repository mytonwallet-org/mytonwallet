import withCache from './withCache';

export const DEFAULT_MAX_LENGTH = 16;
const ELLIPSIS = '···';
const ELLIPSIS_LENGTH = ELLIPSIS.length;
const MIN_NAME_LENGTH = 1;

export const shortenDomain = withCache((domain: string, maxLength: number = DEFAULT_MAX_LENGTH) => {
  if (!domain) return undefined;
  if (domain.length <= maxLength) return domain;

  const dotIndex = domain.indexOf('.');

  // No dot found (e.g. "localhost")
  if (dotIndex === -1) {
    const availableLength = maxLength - ELLIPSIS_LENGTH;
    return `${domain.slice(0, Math.max(0, availableLength))}${ELLIPSIS}`;
  }

  // Split into name and zone parts (before and after the dot)
  const namePart = domain.slice(0, dotIndex);
  const zonePart = domain.slice(dotIndex);

  if (namePart.length <= MIN_NAME_LENGTH) return domain;

  // If zone part alone exceeds or equals maxLength, return minimal representation
  // if it's shorter than the original, otherwise return the original
  if (zonePart.length >= maxLength) {
    const shortened = `${namePart.slice(0, MIN_NAME_LENGTH)}${ELLIPSIS}${zonePart}`;
    return shortened.length < domain.length ? shortened : domain;
  }

  const availableNameLength = maxLength - zonePart.length;

  if (availableNameLength < MIN_NAME_LENGTH + ELLIPSIS_LENGTH) {
    // Example: shortenDomain('somedomain.t.me', 8)
    const shortened = `${namePart.slice(0, MIN_NAME_LENGTH)}${ELLIPSIS}${zonePart}`;
    return shortened.length < domain.length ? shortened : domain;
  }

  // Show the maximum possible number of characters from the name part
  const visibleNameLength = Math.min(
    namePart.length,
    availableNameLength - ELLIPSIS_LENGTH,
  );

  const shortened = `${namePart.slice(0, visibleNameLength)}${ELLIPSIS}${zonePart}`;

  // Return original if shortened version is not actually shorter
  return shortened.length < domain.length ? shortened : domain;
});
