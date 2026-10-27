import { IS_GRAM_WALLET, IS_PRODUCTION, IS_STAGING, PRODUCTION_URL } from '../config';

export interface WebFunnelContext {
  visitId: string | null;
  hasExistingState: boolean;
}

export const WEB_FUNNEL_QUERY = 'mw_visit_id';
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export function getWebFunnelVisitId(search: string): string | null {
  const values = new URLSearchParams(search).getAll(WEB_FUNNEL_QUERY);
  // eslint-disable-next-line no-null/no-null
  return values.length === 1 && UUID_V4.test(values[0]) ? values[0] : null;
}

// Build constants pick the origin so production bundles carry no staging host, which the Gram release rejects
const WEB_FUNNEL_ORIGIN = IS_PRODUCTION ? PRODUCTION_URL
  : IS_STAGING && !IS_GRAM_WALLET ? 'https://web-beta.mywallet.io' : undefined;

export function isWebFunnelOrigin(origin: string) {
  return origin === WEB_FUNNEL_ORIGIN;
}
