import {
  captureBrowserAttribution, getAttributionCandidate, getExternalReferrerDomain, normalizeReferrerDomain,
  selectBrowserAttribution, splitAttributionDeeplink,
} from './installAttribution';

describe('browser install attribution', () => {
  it('keeps only external http hostname', () => {
    expect(getExternalReferrerDomain('https://News.Example/a?q=secret', 'web.mywallet.io')).toBe('news.example');
    for (const url of ['https://get.mywallet.io/a', 'https://foo.mytonwallet.app/', 'android-app://com.app', 'bad']) {
      expect(getExternalReferrerDomain(url, 'web.mywallet.io')).toBeUndefined();
    }
  });
  it('prefers explicit UTM over transported or document fallback', () => {
    expect(getAttributionCandidate(
      '?utm_source=wc&attribution_referrer=news.example', 'https://other.example', 'web.mywallet.io',
    ))
      .toEqual({ channel: 'wc', attributionKind: 'utm' });
    expect(getAttributionCandidate('?attribution_referrer=news.example', '', 'web.mywallet.io'))
      .toEqual({ channel: '', attributionKind: 'referrer', referrerDomain: 'news.example' });
  });
  it('upgrades referrer once without extending the cookie window', () => {
    const fallback = {
      channel: '', attributionKind: 'referrer' as const, referrerDomain: 'news.example', expiresAt: 1000,
    };
    const paid = { channel: 'wc', attributionKind: 'utm' as const };
    expect(selectBrowserAttribution(fallback, paid, 100)).toEqual({ ...paid, expiresAt: 1000 });
    expect(selectBrowserAttribution({ ...paid, expiresAt: 1000 }, { ...paid, channel: 'youtube' }, 200))
      .toEqual({ ...paid, expiresAt: 1000 });
    expect(selectBrowserAttribution(fallback, undefined, 1001)).toBeUndefined();
  });
});

describe('source cookie', () => {
  it('shares the agreed cookie wire format and keeps the original expiry', () => {
    const saved = {
      channel: '', attributionKind: 'referrer' as const, referrerDomain: 'news.example', expiresAt: 5000,
    };
    expect(selectBrowserAttribution(saved, undefined, 100)).toEqual(saved);
    expect(selectBrowserAttribution(saved, { channel: 'partner', attributionKind: 'utm' }, 100))
      .toEqual({ channel: 'partner', attributionKind: 'utm', expiresAt: 5000 });
  });
});

describe('browser capture integration', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });
  it('reads shared fallback cookie, upgrades from URL, and writes the original expiry', () => {
    const expiresAt = Date.now() + 60_000;
    const saved = { channel: '', attributionKind: 'referrer', referrerDomain: 'news.example', expiresAt };
    const getCookie = jest.spyOn(document, 'cookie', 'get');
    const setCookie = jest.spyOn(document, 'cookie', 'set').mockImplementation(() => {});
    getCookie.mockReturnValue(`mtw_attribution_v1=${encodeURIComponent(JSON.stringify(saved))}`);
    window.history.replaceState({}, '', '/?utm_source=wc');
    expect(captureBrowserAttribution()).toEqual({ channel: 'wc', attributionKind: 'utm' });
    const written = JSON.parse(decodeURIComponent(setCookie.mock.calls[0][0].split(';')[0].split('=')[1]));
    expect(written).toEqual({ channel: 'wc', attributionKind: 'utm', expiresAt });
    window.history.replaceState({}, '', '/');
  });
});

describe('producer validation contract', () => {
  afterEach(() => {
    jest.restoreAllMocks();
    window.history.replaceState({}, '', '/');
  });
  it('rejects IP addresses and numeric final labels while keeping punycode', () => {
    expect(normalizeReferrerDomain('1.2.3.4')).toBeUndefined();
    expect(normalizeReferrerDomain('news.123abc')).toBeUndefined();
    expect(normalizeReferrerDomain('news.xn--p1ai')).toBe('news.xn--p1ai');
  });
  it('normalizes explicit UTM', () => {
    expect(getAttributionCandidate('?utm_source=%20WC%20', '', 'web.mywallet.io'))
      .toEqual({ channel: 'wc', attributionKind: 'utm' });
  });
  it.each([
    { attributionKind: 'utm' },
    { channel: 'partner', attributionKind: 'utm', expiresAt: Date.now() + 30 * 86400_000 },
  ])('ignores malformed cookie %j', (value) => {
    const saved = { expiresAt: Date.now() + 60_000, ...value };
    jest.spyOn(document, 'cookie', 'get')
      .mockReturnValue(`mtw_attribution_v1=${encodeURIComponent(JSON.stringify(saved))}`);
    jest.spyOn(document, 'cookie', 'set').mockImplementation(() => {});
    window.history.replaceState({}, '', '/?utm_source=wc');
    expect(captureBrowserAttribution()).toEqual({ channel: 'wc', attributionKind: 'utm' });
  });
  it('strips stray domain metadata from explicit cookie', () => {
    const saved = {
      channel: 'partner', attributionKind: 'utm', referrerDomain: 'news.example', expiresAt: Date.now() + 60_000,
    };
    jest.spyOn(document, 'cookie', 'get')
      .mockReturnValue(`mtw_attribution_v1=${encodeURIComponent(JSON.stringify(saved))}`);
    jest.spyOn(document, 'cookie', 'set').mockImplementation(() => {});
    expect(captureBrowserAttribution()).toEqual({ channel: 'partner', attributionKind: 'utm' });
  });
});

describe('full explicit snapshot', () => {
  it('captures the complete bundle and never enriches a subsequent visit', () => {
    const snapshot = getAttributionCandidate(
      '?utm_source=partner&utm_campaign=launch&utm_medium=post&utm_content=a', '', 'web.mywallet.io',
    );
    expect(snapshot).toEqual({
      channel: 'partner', attributionKind: 'utm', utmCampaign: 'launch', utmMedium: 'post', utmContent: 'a',
    });
    expect(selectBrowserAttribution({ ...snapshot!, expiresAt: 1000 }, { ...snapshot!, utmCampaign: 'later' }, 1))
      .toEqual({ ...snapshot, expiresAt: 1000 });
  });
});

describe('self deeplink attribution', () => {
  it('preserves business values and strips only the outer marketing keys', () => {
    const result = splitAttributionDeeplink(
      'https://my.tt/send/ton:address?amount=1&r=business&uri=wc%3Ax%3Futm_source%3Dinner'
      + '&utm_source=partner&utm_campaign=launch',
    );
    const url = new URL(result.url);
    expect(url.searchParams.get('amount')).toBe('1');
    expect(url.searchParams.get('r')).toBe('business');
    expect(url.searchParams.get('uri')).toBe('wc:x?utm_source=inner');
    expect(url.searchParams.has('utm_source')).toBe(false);
    expect(result.candidate).toEqual({ channel: 'partner', attributionKind: 'utm', utmCampaign: 'launch' });
    expect(splitAttributionDeeplink('https://evil.example/send?utm_source=partner').candidate).toBeUndefined();
    expect(splitAttributionDeeplink('https://my.tt/get/android?utm_source=partner').isGet).toBe(true);
  });
});

it('rejects overlong sources without truncation and omits malformed optional fields by UTF-8 length', () => {
  expect(getAttributionCandidate(`?utm_source=${'a'.repeat(31)}`, '', '')).toBeUndefined();
  const accepted = getAttributionCandidate(`?utm_source=custom&utm_campaign=${'я'.repeat(64)}`, '', '');
  expect(accepted?.utmCampaign).toBe('я'.repeat(64));
  const rejected = getAttributionCandidate(
    `?utm_source=custom&utm_campaign=${'я'.repeat(65)}&utm_content=a%00b`, '', '',
  );
  expect(rejected).toEqual({ channel: 'custom', attributionKind: 'utm' });
});

it('rejects raw optional-field controls before trimming', () => {
  expect(getAttributionCandidate('?utm_source=partner&utm_campaign=%0Alaunch', '', ''))
    .toEqual({ channel: 'partner', attributionKind: 'utm' });
});

it('rejects a transported hostname ending in a newline', () => {
  for (const suffix of ['\n', '\r', '\u2028', '\u2029']) {
    expect(normalizeReferrerDomain(`news.example${suffix}`)).toBeUndefined();
  }
  expect(getAttributionCandidate('?attribution_referrer=news.example%0A', '', '')).toBeUndefined();
});
