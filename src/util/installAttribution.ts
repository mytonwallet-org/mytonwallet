export interface InstallAttributionCandidate {
  channel: string;
  attributionKind: 'utm' | 'referrer';
  referrerDomain?: string;
  utmMedium?: string;
  utmCampaign?: string;
  utmContent?: string;
}

interface BrowserAttribution extends InstallAttributionCandidate {
  expiresAt: number;
}

export const ATTRIBUTION_SOURCE_MAX_BYTES = 30;
export const ATTRIBUTION_CHANNEL_FORMAT = new RegExp(`^[a-z0-9_]{1,${ATTRIBUTION_SOURCE_MAX_BYTES}}$`);
const OWNED_ROOTS = ['mywallet.io', 'mytonwallet.io', 'mytonwallet.org', 'mytonwallet.app', 'my.tt'];
const COOKIE_NAME = 'mtw_attribution_v1';
const DOMAIN_FORMAT = /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
const WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

export function normalizeReferrerDomain(value: string, currentHost = ''): string | undefined {
  const host = value.toLowerCase().replace(/\.$/, '');
  if (host.length > 253 || DOMAIN_FORMAT.exec(host)?.[0] !== host) {
    return undefined;
  }
  if (host === currentHost.toLowerCase() || OWNED_ROOTS.some((root) => host === root || host.endsWith(`.${root}`))) {
    return undefined;
  }
  return host;
}

export function getExternalReferrerDomain(value: string, currentHost: string): string | undefined {
  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol) ? normalizeReferrerDomain(url.hostname, currentHost) : undefined;
  } catch {
    return undefined;
  }
}

export function getAttributionCandidate(search: string, referrer: string, currentHost: string) {
  const params = new URLSearchParams(search);
  const channel = params.get('utm_source')?.trim().toLowerCase();
  if (channel && ATTRIBUTION_CHANNEL_FORMAT.test(channel)) {
    return normalizeAttributionCandidate({
      channel, attributionKind: 'utm', utmMedium: params.get('utm_medium'),
      utmCampaign: params.get('utm_campaign'), utmContent: params.get('utm_content'),
    });
  }
  const domain = normalizeReferrerDomain(params.get('attribution_referrer') ?? '', currentHost)
    ?? getExternalReferrerDomain(referrer, currentHost);
  return domain ? {
    channel: '', attributionKind: 'referrer', referrerDomain: domain,
  } satisfies InstallAttributionCandidate : undefined;
}

export function selectBrowserAttribution(
  saved: BrowserAttribution | undefined, candidate: InstallAttributionCandidate | undefined, now: number,
): BrowserAttribution | undefined {
  if (saved && saved.expiresAt > now) {
    return saved.attributionKind === 'referrer' && candidate?.attributionKind === 'utm'
      ? { ...candidate, expiresAt: saved.expiresAt } : saved;
  }
  return candidate ? { ...candidate, expiresAt: now + WINDOW_MS } : undefined;
}

export function captureBrowserAttribution(): InstallAttributionCandidate | undefined {
  const candidate = getAttributionCandidate(location.search, document.referrer, location.hostname);
  const now = Date.now();
  let saved: BrowserAttribution | undefined;
  try {
    const value = document.cookie.split(';').map((part) => part.trim())
      .find((part) => part.startsWith(`${COOKIE_NAME}=`))
      ?.slice(COOKIE_NAME.length + 1);
    const parsed = value ? JSON.parse(decodeURIComponent(value)) : undefined;
    const normalized = parsed && ['utm', 'referrer'].includes(parsed.attributionKind)
      && normalizeAttributionCandidate(parsed);
    if (normalized && Number.isFinite(parsed.expiresAt) && parsed.expiresAt <= now + WINDOW_MS) {
      saved = { ...normalized, expiresAt: parsed.expiresAt };
    }
  } catch { /* A blocked or malformed cookie must not prevent this visit's capture. */ }
  const selected = selectBrowserAttribution(saved, candidate, now);
  if (!selected) return undefined;
  try {
    const domain = location.hostname === 'mywallet.io' || location.hostname.endsWith('.mywallet.io')
      ? '; Domain=mywallet.io' : '';
    const secure = location.protocol === 'https:' ? '; Secure' : '';
    document.cookie = `${COOKIE_NAME}=${encodeURIComponent(JSON.stringify(selected))}; Path=/; SameSite=Lax`
      + `; Max-Age=${Math.max(0, Math.floor((selected.expiresAt - now) / 1000))}${domain}${secure}`;
  } catch { /* The SDK storage still retains a claim when browser cookies are unavailable. */ }
  const { expiresAt, ...result } = selected;
  return result;
}

const UTM_FIELDS = ['utmMedium', 'utmCampaign', 'utmContent'] as const;
export function normalizeAttributionCandidate(value: unknown): InstallAttributionCandidate | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const input = value as Record<string, unknown>;
  if (input.attributionKind === 'referrer') {
    const domain = typeof input.referrerDomain === 'string' ? normalizeReferrerDomain(input.referrerDomain) : undefined;
    return domain && (input.channel === '' || input.channel === 'web_referral')
      ? { channel: '', attributionKind: 'referrer', referrerDomain: domain } : undefined;
  }
  if (input.attributionKind !== undefined && input.attributionKind !== 'utm') return undefined;
  const channel = typeof input.channel === 'string' ? input.channel.trim().toLowerCase() : undefined;
  if (!channel || !ATTRIBUTION_CHANNEL_FORMAT.test(channel)) return undefined;
  const candidate: InstallAttributionCandidate = { channel, attributionKind: 'utm' };
  for (const field of UTM_FIELDS) {
    const raw = input[field];
    if (typeof raw !== 'string') continue;
    const text = raw.trim();
    if (text && !Array.from(raw).some((char) => char.charCodeAt(0) < 32
      || (char.charCodeAt(0) >= 127 && char.charCodeAt(0) <= 159)) && new TextEncoder().encode(text).length <= 128) {
      candidate[field] = text;
    }
  }
  return candidate;
}

// Only the outer marketing query is removed; business r and nested protocol URLs remain intact.
export function splitAttributionDeeplink(value: string) {
  try {
    const url = new URL(value);
    const isSelf = ['mtw:', 'gramwallet:'].includes(url.protocol)
      || (['https:', 'http:'].includes(url.protocol)
        && ['my.tt', 'go.mytonwallet.org', 'go.gramwallet.io'].includes(url.hostname));
    if (!isSelf) return { url: value };
    const candidate = getAttributionCandidate(url.search, '', '');
    for (const key of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'attribution_referrer']) {
      url.searchParams.delete(key);
    }
    const path = ['mtw:', 'gramwallet:'].includes(url.protocol) ? `/${url.host}${url.pathname}` : url.pathname;
    return { url: url.toString(), candidate, isGet: path === '/get' || path.startsWith('/get/') };
  } catch {
    return { url: value };
  }
}
