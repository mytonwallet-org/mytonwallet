/** The media before (`direction` -1) or after (1) the given one, if there is one; the viewer stops at either end */
export function getAdjacentMediaId(mediaIds: string[], fromId: string, direction: number) {
  if (direction !== -1 && direction !== 1) return undefined;

  const index = mediaIds.indexOf(fromId);
  if (index === -1) return undefined;

  return mediaIds[index + direction];
}
