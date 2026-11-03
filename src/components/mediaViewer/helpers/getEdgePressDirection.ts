// Telegram's zone for paging with a tap near an edge: an eighth of the width, at most 135 px
const EDGE_ZONE_MAX_WIDTH = 135;
const EDGE_ZONE_WIDTH_SHARE = 1 / 8;

/** How far from either edge a press pages to the neighbouring picture on a touch screen */
export function getEdgeZoneWidth(width: number) {
  return Math.min(EDGE_ZONE_MAX_WIDTH, width * EDGE_ZONE_WIDTH_SHARE);
}

/**
 * The picture a press at `x` pages to: -1 for the previous one near the left edge and 1 for the next one near the right
 * edge, as a tap there does, when there is one
 */
export function getEdgePressDirection(x: number, width: number, hasPrevious: boolean, hasNext: boolean) {
  const zoneWidth = getEdgeZoneWidth(width);
  if (x < zoneWidth) return hasPrevious ? -1 : undefined;
  if (x > width - zoneWidth) return hasNext ? 1 : undefined;

  return undefined;
}
