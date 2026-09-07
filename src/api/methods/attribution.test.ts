const mockCallBackendPost = jest.fn();
const mockCurrentStorage = jest.fn();
jest.mock('../storages', () => ({ getCurrentStorage: () => mockCurrentStorage() }));
const mockGetEnvironment = jest.fn(() => ({ isIosApp: false, isAndroidApp: false, isElectron: false }));

jest.mock('../common/backend', () => ({
  callBackendPost: (...args: unknown[]) => mockCallBackendPost(...args),
}));

jest.mock('../environment', () => ({
  getEnvironment: () => mockGetEnvironment(),
}));

import type { createStorage } from '../storages';
import type { ApiInitArgs } from '../types';

import {
  acceptInstallAttribution, captureInstallAttribution, claimAttribution, claimInstallAttribution,
  isAllowedChannel, setInstallChannel,
} from './attribution';

function makeStorage(seed: Record<string, string> = {}) {
  const map = new Map<string, string>(Object.entries(seed));
  return {
    getItem: jest.fn((k: string) => Promise.resolve(map.get(k))),
    setItem: jest.fn((k: string, v: string) => {
      map.set(k, v);
      return Promise.resolve();
    }),
    _map: map,
  } as unknown as ReturnType<typeof createStorage> & { _map: Map<string, string> };
}

const argsWith = (channel?: string) => ({ channel } as unknown as ApiInitArgs);

describe('claimAttribution', () => {
  afterEach(() => {
    mockCallBackendPost.mockReset();
  });

  it('posts channel + platform and returns true when the backend accepts', async () => {
    mockCallBackendPost.mockResolvedValue({ ok: true });
    const ok = await claimAttribution('wc', 'web');
    expect(mockCallBackendPost).toHaveBeenCalledWith(
      '/attribution/claim', { channel: 'wc', platform: 'web', attributionKind: 'utm' },
    );
    expect(ok).toBe(true);
  });

  it('returns false when the backend defers (ok:false)', async () => {
    mockCallBackendPost.mockResolvedValue({ ok: false });
    expect(await claimAttribution('wc', 'web')).toBe(false);
  });
});

describe('isAllowedChannel', () => {
  it('accepts any well-formed channel slug (format guard, not a fixed allowlist)', () => {
    expect(isAllowedChannel('wc')).toBe(true);
    expect(isAllowedChannel('probe_web')).toBe(true);
    expect(isAllowedChannel('probe_tg')).toBe(true);
    expect(isAllowedChannel('probe_x')).toBe(true);
    expect(isAllowedChannel('probe_yt')).toBe(true);
    expect(isAllowedChannel('organic')).toBe(true); // Android referrer fallback bucket
    expect(isAllowedChannel('app_share')).toBe(true); // in-app install link tag
    expect(isAllowedChannel('youtube')).toBe(true); // a live campaign bucket
  });

  it('rejects malformed input so a raw untrusted string never reaches the POST', () => {
    expect(isAllowedChannel('WC')).toBe(false);
    expect(isAllowedChannel('')).toBe(false);
    expect(isAllowedChannel('BAD!')).toBe(false);
    expect(isAllowedChannel('a'.repeat(65))).toBe(false); // over the 64-char bound
  });
});

describe('claimInstallAttribution', () => {
  afterEach(() => {
    mockCallBackendPost.mockReset();
  });

  it('first sight persists the channel, then claims', async () => {
    const storage = makeStorage();
    mockCallBackendPost.mockResolvedValue({ ok: true });

    await claimInstallAttribution(argsWith('wc'), storage);

    expect(storage._map.get('installAttribution')).toMatchObject({ channel: 'wc' });
    expect(mockCallBackendPost).toHaveBeenCalledWith(
      '/attribution/claim', { channel: 'wc', platform: 'web', attributionKind: 'utm' },
    );
    expect(storage._map.get('installAttribution')).toMatchObject({ claimed: true });
  });

  it('malformed channel is neither persisted nor POSTed', async () => {
    const storage = makeStorage();

    await claimInstallAttribution(argsWith('BAD!'), storage);

    expect(storage._map.get('attributionChannel')).toBeUndefined();
    expect(mockCallBackendPost).not.toHaveBeenCalled();
  });

  it('replays from storage claims without a URL channel', async () => {
    const storage = makeStorage({ attributionChannel: 'wc' });
    mockCallBackendPost.mockResolvedValue({ ok: true });

    await claimInstallAttribution(argsWith(undefined), storage);

    expect(mockCallBackendPost).toHaveBeenCalledWith(
      '/attribution/claim', { channel: 'wc', platform: 'web' },
    );
    expect(storage._map.get('attributionClaimed')).toBe('1');
  });

  it('ok:false leaves the flag unset and the channel intact', async () => {
    const storage = makeStorage({ attributionChannel: 'wc' });
    mockCallBackendPost.mockResolvedValue({ ok: false });

    await claimInstallAttribution(argsWith(undefined), storage);

    expect(storage._map.get('attributionClaimed')).toBeUndefined();
    expect(storage._map.get('attributionChannel')).toBe('wc');
  });

  it('already-claimed short-circuits', async () => {
    const storage = makeStorage({ attributionChannel: 'wc', attributionClaimed: '1' });

    await claimInstallAttribution(argsWith(undefined), storage);

    expect(mockCallBackendPost).not.toHaveBeenCalled();
  });

  it('no channel (undefined) does nothing', async () => {
    const storage = makeStorage();

    await claimInstallAttribution(argsWith(undefined), storage);

    expect(mockCallBackendPost).not.toHaveBeenCalled();
  });

  it('re-validates a stale or tampered persisted channel and never POSTs it', async () => {
    const storage = makeStorage({ attributionChannel: 'BAD!' }); // tampered/corrupted leftover

    await claimInstallAttribution(argsWith(undefined), storage);

    expect(mockCallBackendPost).not.toHaveBeenCalled();
    expect(storage._map.get('attributionClaimed')).toBeUndefined();
  });

  it('resolves quietly when storage throws, without rejecting into init', async () => {
    const storage = {
      getItem: jest.fn(() => Promise.reject(new Error('storage unavailable'))),
      setItem: jest.fn(() => Promise.resolve()),
    } as unknown as ReturnType<typeof createStorage>;

    await expect(claimInstallAttribution(argsWith('wc'), storage)).resolves.toBeUndefined();
    expect(mockCallBackendPost).not.toHaveBeenCalled();
  });

  it('in-flight latch: two overlapping calls POST once', async () => {
    // Regression test for the TOCTOU race: the latch must reserve synchronously, before
    // any await, so two near-simultaneous init() calls cannot both pass the guard.
    const storage = makeStorage({ attributionChannel: 'wc' });

    let resolvePost!: (v: unknown) => void;
    const postPromise = new Promise((resolve) => {
      resolvePost = resolve;
    });
    mockCallBackendPost.mockReturnValue(postPromise);

    const p1 = claimInstallAttribution(argsWith(undefined), storage);
    const p2 = claimInstallAttribution(argsWith(undefined), storage);

    // let both run up to their awaits
    for (let i = 0; i < 40; i++) await Promise.resolve();

    expect(mockCallBackendPost).toHaveBeenCalledTimes(1);

    resolvePost({ ok: true });
    await Promise.all([p1, p2]);
  });
});

describe('setInstallChannel (android)', () => {
  beforeEach(() => {
    mockGetEnvironment.mockReturnValue({ isIosApp: false, isAndroidApp: true, isElectron: false });
  });

  afterEach(() => {
    mockCallBackendPost.mockReset();
    mockGetEnvironment.mockReturnValue({ isIosApp: false, isAndroidApp: false, isElectron: false });
  });

  it('setInstallChannel claims a well-formed channel on android', async () => {
    mockCallBackendPost.mockResolvedValue({ ok: true });
    const storage = makeStorage();
    await setInstallChannel('wc', storage);
    expect(mockCallBackendPost).toHaveBeenCalledWith('/attribution/claim', {
      channel: 'wc', platform: 'android', attributionKind: 'utm',
    });
    expect(storage._map.get('installAttribution')).toMatchObject({ claimed: true });
  });

  it('setInstallChannel claims the organic referrer fallback', async () => {
    mockCallBackendPost.mockResolvedValue({ ok: true });
    const storage = makeStorage();
    await setInstallChannel('organic', storage);
    expect(mockCallBackendPost).toHaveBeenCalledWith(
      '/attribution/claim', { channel: '', platform: 'android', attributionKind: 'direct' },
    );
    expect(storage._map.get('attributionTechnicalClaimed')).toBe('1');
  });

  it('setInstallChannel claims the app_share tag', async () => {
    mockCallBackendPost.mockResolvedValue({ ok: true });
    const storage = makeStorage();
    await setInstallChannel('app_share', storage);
    expect(mockCallBackendPost).toHaveBeenCalledWith(
      '/attribution/claim', { channel: 'app_share', platform: 'android', attributionKind: 'utm' },
    );
    expect(storage._map.get('installAttribution')).toMatchObject({ claimed: true });
  });

  it('setInstallChannel drops a malformed channel', async () => {
    const storage = makeStorage();
    await setInstallChannel('BAD!', storage);
    expect(mockCallBackendPost).not.toHaveBeenCalled();
  });
});

describe('referrer attribution upgrades', () => {
  beforeEach(() => {
    mockCallBackendPost.mockReset();
    mockCallBackendPost.mockResolvedValue({ ok: true });
  });
  const fallback: ApiInitArgs = {
    channel: 'web_referral', attributionKind: 'referrer', referrerDomain: 'news.example',
  };
  it('upgrades an accepted referrer once and leaves subsequent UTM immutable', async () => {
    const storage = makeStorage();
    await claimInstallAttribution(fallback, storage);
    await claimInstallAttribution({ channel: 'wc' }, storage);
    await claimInstallAttribution({ channel: 'youtube' }, storage);
    expect(mockCallBackendPost.mock.calls.map((call) => call[1].channel)).toEqual(['', 'wc']);
  });
  it('drains an upgrade captured during the fallback request', async () => {
    const storage = makeStorage();
    let complete!: (result: { ok: boolean }) => void;
    mockCallBackendPost.mockImplementationOnce(() => new Promise((resolve) => {
      complete = resolve;
    }));
    const first = claimInstallAttribution(fallback, storage);
    while (!complete) await Promise.resolve();
    await claimInstallAttribution({ channel: 'wc' }, storage);
    complete({ ok: true });
    await first;
    expect(mockCallBackendPost.mock.calls.map((call) => call[1].channel)).toEqual(['', 'wc']);
  });
  it('retries failed upgrade on next init', async () => {
    const storage = makeStorage();
    await claimInstallAttribution(fallback, storage);
    mockCallBackendPost.mockRejectedValueOnce(new Error('offline'));
    await claimInstallAttribution({ channel: 'wc' }, storage);
    await claimInstallAttribution({}, storage);
    expect(mockCallBackendPost.mock.calls.map((call) => call[1].channel)).toEqual(['', 'wc', 'wc']);
  });
  it('preserves already claimed legacy explicit channels', async () => {
    const storage = makeStorage({ attributionChannel: 'wc', attributionClaimed: '1' });
    await claimInstallAttribution(fallback, storage);
    expect(mockCallBackendPost).not.toHaveBeenCalled();
  });
});

describe('Android referrer provenance', () => {
  beforeEach(() => {
    mockGetEnvironment.mockReturnValue({ isIosApp: false, isAndroidApp: true, isElectron: false });
  });

  afterEach(() => {
    mockGetEnvironment.mockReturnValue({ isIosApp: false, isAndroidApp: false, isElectron: false });
  });
  it('sends the host separately from the bounded channel', async () => {
    mockCallBackendPost.mockReset();
    mockCallBackendPost.mockResolvedValue({ ok: true });
    await setInstallChannel('web_referral', makeStorage(), 'news.example');
    expect(mockCallBackendPost).toHaveBeenCalledWith('/attribution/claim', {
      channel: '', platform: 'android', attributionKind: 'referrer', referrerDomain: 'news.example',
    });
  });
});

describe('pending attribution selection', () => {
  it('replaces an unacknowledged referrer with UTM and retries only the UTM', async () => {
    mockCallBackendPost.mockReset();
    mockCallBackendPost.mockResolvedValue({ ok: false });
    const storage = makeStorage();
    await claimInstallAttribution({
      channel: 'web_referral', attributionKind: 'referrer', referrerDomain: 'news.example',
    }, storage);
    await claimInstallAttribution({ channel: 'wc' }, storage);
    mockCallBackendPost.mockResolvedValue({ ok: true });
    await claimInstallAttribution({}, storage);
    expect(mockCallBackendPost.mock.calls.map((call) => call[1].channel)).toEqual(['', 'wc', 'wc']);
  });
});

describe('complete attribution source snapshot', () => {
  beforeEach(() => {
    mockCallBackendPost.mockReset();
    mockCallBackendPost.mockResolvedValue({ ok: true });
  });
  it('upgrades inferred source with a complete UTM snapshot and never mixes later detail fields', async () => {
    const storage = makeStorage();
    await claimInstallAttribution({
      channel: '', attributionKind: 'referrer', referrerDomain: 'news.example',
    }, storage);
    await claimInstallAttribution({ channel: 'partner', utmCampaign: 'first', utmMedium: 'post' }, storage);
    await claimInstallAttribution({ channel: 'partner', utmCampaign: 'second', utmContent: 'new' }, storage);
    expect(mockCallBackendPost).toHaveBeenLastCalledWith('/attribution/claim', {
      channel: 'partner', platform: 'web', attributionKind: 'utm', utmCampaign: 'first', utmMedium: 'post',
    });
    expect(mockCallBackendPost).toHaveBeenCalledTimes(2);
  });
  it('replays legacy source longer than 30 via the legacy envelope and does not replace it', async () => {
    const source = 'a'.repeat(40);
    const storage = makeStorage({ attributionChannel: source });
    await claimInstallAttribution({ channel: 'new' }, storage);
    expect(mockCallBackendPost).toHaveBeenCalledWith('/attribution/claim', { channel: source, platform: 'web' });
  });
  it('records Play technical status as direct and permits later explicit acquisition', async () => {
    const storage = makeStorage();
    await setInstallChannel('organic', storage);
    await claimInstallAttribution({ channel: 'partner' }, storage);
    expect(mockCallBackendPost).toHaveBeenNthCalledWith(1, '/attribution/claim', {
      channel: '', platform: 'android', attributionKind: 'direct',
    });
    expect(mockCallBackendPost).toHaveBeenNthCalledWith(2, '/attribution/claim', {
      channel: 'partner', platform: 'web', attributionKind: 'utm',
    });
  });
});

describe('native durable acceptance', () => {
  it('does not acknowledge a failed SDK storage write', async () => {
    const storage = makeStorage();
    jest.mocked(storage.setItem).mockRejectedValueOnce(new Error('storage unavailable'));
    await expect(acceptInstallAttribution({ channel: 'partner', attributionKind: 'utm' }, storage))
      .rejects.toThrow('storage unavailable');
  });
  it('acknowledges persisted source without waiting for the network', async () => {
    const storage = makeStorage();
    mockCallBackendPost.mockImplementationOnce(() => new Promise(() => {}));
    const snapshot = { channel: 'partner', attributionKind: 'utm' as const, utmCampaign: 'launch' };
    await expect(acceptInstallAttribution(snapshot, storage)).resolves.toBe(true);
    expect(storage._map.get('installAttribution')).toEqual(snapshot);
  });
});

it('distinguishes Play technical referral from an explicit referral source', async () => {
  mockCallBackendPost.mockReset().mockResolvedValue({ ok: true });
  const technical = makeStorage();
  await setInstallChannel('referral', technical, undefined, 'referral');
  expect(mockCallBackendPost).toHaveBeenLastCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'referral',
  });
  await setInstallChannel('referral', technical);
  expect(mockCallBackendPost).toHaveBeenLastCalledWith('/attribution/claim', {
    channel: 'referral', platform: 'web', attributionKind: 'utm',
  });
});

it('resolves SDK capture to each concrete runtime storage before asynchronous delivery', async () => {
  const first = makeStorage();
  const second = makeStorage();
  mockCurrentStorage.mockReturnValueOnce(first).mockReturnValueOnce(second);
  mockCallBackendPost.mockReset().mockResolvedValue({ ok: true });
  await Promise.all([
    captureInstallAttribution({ channel: 'first', attributionKind: 'utm' }),
    captureInstallAttribution({ channel: 'second', attributionKind: 'utm' }),
  ]);
  expect(first._map.get('installAttribution')).toEqual(expect.objectContaining({ channel: 'first' }));
  expect(second._map.get('installAttribution')).toEqual(expect.objectContaining({ channel: 'second' }));
});
