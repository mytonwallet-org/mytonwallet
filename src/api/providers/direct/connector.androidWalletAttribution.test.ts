import type { Storage } from '../../storages/types';

let mockStorage: Storage;
let createDirectApiConnector: typeof import('./connector')['createDirectApiConnector'];
const mockInit = jest.fn();
const mockNative = jest.fn();
const mockPost = jest.fn();
const mockFetch = jest.fn();
jest.mock('../../common/helpers', () => ({ isUpdaterAlive: () => true }));
jest.mock('../../storages', () => ({
  createStorage: () => mockStorage,
  withStorage: (_: unknown, operation: () => unknown) => operation(),
}));
jest.mock('../../methods/init', () => ({ __esModule: true, default: (...args: unknown[]) => mockInit(...args) }));
jest.mock('../../methods/registry', () => ({ methods: {} }));
jest.mock('../../dappProtocols', () => ({ getProtocolManager: jest.fn() }));
jest.mock('../../environment', () => ({ getEnvironment: () => ({ isAndroidApp: true }) }));
jest.mock('../../common/backend', () => ({
  callBackendPost: (...args: unknown[]) => mockPost(...args),
  getBackendHeaders: () => ({ 'X-App-ClientID': 'wallet-client' }),
}));
jest.mock('../../../util/windowProvider/connector', () => ({
  callWindow: (...args: unknown[]) => mockNative(...args),
}));

const source = { channel: 'first_partner', attributionKind: 'utm', utmCampaign: 'launch' };
const originalFetch = global.fetch;
const nativeNull = JSON.parse('null');
const claimOptions = expect.objectContaining({ signal: expect.any(AbortSignal) });

beforeAll(async () => {
  ({ createDirectApiConnector } = await import('./connector'));
});

function storage(seed: Record<string, unknown> = {}) {
  const values = new Map(Object.entries(seed));
  return {
    values,
    getItem: (key: string) => Promise.resolve(values.get(key)),
    setItem: (key: string, value: unknown) => {
      values.set(key, value);
      return Promise.resolve();
    },
    removeItem: (key: string) => {
      values.delete(key);
      return Promise.resolve();
    },
    clear: () => {
      values.clear();
      return Promise.resolve();
    },
  } as Storage & { values: Map<string, unknown> };
}

async function settle() {
  for (let i = 0; i < 100; i++) await Promise.resolve();
}

beforeEach(() => {
  jest.useFakeTimers();
  mockStorage = storage();
  mockInit.mockReset().mockResolvedValue(undefined);
  mockPost.mockReset().mockResolvedValue({ ok: true });
  mockNative.mockReset().mockImplementation((method: string) => {
    if (method === 'airInstallationGetPending') return Promise.resolve([]);
    if (method === 'airInstallationSyncWalletAttribution') {
      return Promise.resolve({ source, technicalKind: nativeNull });
    }
    throw new Error(`Unexpected native call: ${method}`);
  });
  mockFetch.mockReset().mockRejectedValue(new Error('Unexpected network request'));
  global.fetch = mockFetch;
});

afterEach(() => {
  jest.clearAllTimers();
  jest.useRealTimers();
  global.fetch = originalFetch;
});

it('claims the native source after wallet initialization while V2 delivery is already active', async () => {
  let ready!: () => void;
  mockInit.mockReturnValueOnce(new Promise<void>((resolve) => {
    ready = resolve;
  }));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockNative).toHaveBeenCalledWith('airInstallationGetPending');
  expect(mockPost).not.toHaveBeenCalled();
  ready();
  await settle();
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', { ...source, platform: 'android' }, claimOptions);
  expect(await mockStorage.getItem('installAttribution')).toEqual({ ...source, claimed: true });
  expect(mockFetch).not.toHaveBeenCalled();
});

it('replays wallet claims after wallet clearing without reporting another installation', async () => {
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  connector.handleInstallationStateChange();
  await settle();
  expect(mockPost).toHaveBeenCalledTimes(1);
  await mockStorage.clear();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(mockPost.mock.calls.map(([path]) => path)).toEqual(['/attribution/claim', '/attribution/claim']);
  expect(mockFetch).not.toHaveBeenCalled();
});

it('imports an already claimed source before receiving native projection without importing its ACK', async () => {
  mockStorage = storage({ installAttribution: { ...source, claimed: true } });
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockNative).toHaveBeenCalledWith('airInstallationSyncWalletAttribution', JSON.stringify(source));
  expect(mockPost).not.toHaveBeenCalled();
});

it('preserves a grandfathered legacy channel and replays its original claim shape after reset', async () => {
  const channel = 'a'.repeat(64);
  const legacy = { channel, attributionKind: 'utm', legacy: true };
  mockStorage = storage({ attributionChannel: channel, attributionClaimed: '1' });
  mockNative.mockImplementation((method: string) => Promise.resolve(method === 'airInstallationGetPending'
    ? [] : { source: legacy, technicalKind: nativeNull }));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockNative).toHaveBeenCalledWith('airInstallationSyncWalletAttribution', JSON.stringify(legacy));
  expect(mockPost).not.toHaveBeenCalled();
  await mockStorage.clear();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockPost).toHaveBeenCalledTimes(1);
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', { channel, platform: 'android' }, claimOptions);
});

it('retains a deferred claim and retries it without another native source notification', async () => {
  mockPost.mockResolvedValueOnce({ ok: false });
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await jest.advanceTimersByTimeAsync(29999);
  expect(mockPost).toHaveBeenCalledTimes(1);
  expect(await mockStorage.getItem('installAttribution')).toEqual(source);
  await jest.advanceTimersByTimeAsync(1);
  expect(mockPost).toHaveBeenCalledTimes(2);
  await jest.advanceTimersByTimeAsync(60000);
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(jest.getTimerCount()).toBe(0);
});

it('drops an old owner native response before it can mutate or claim wallet attribution', async () => {
  let release!: (value: unknown) => void;
  mockNative.mockResolvedValueOnce([]);
  mockNative.mockImplementationOnce(() => new Promise((resolve) => {
    release = resolve;
  }));
  const previous = mockStorage;
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  mockStorage = storage();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  release({ source: { channel: 'stale_partner', attributionKind: 'utm' }, technicalKind: nativeNull });
  await settle();
  expect(await previous.getItem('installAttribution')).toBeUndefined();
  expect(mockPost).toHaveBeenCalledTimes(1);
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', { ...source, platform: 'android' }, claimOptions);
});

it('does not persist an old owner claim response after SDK replacement', async () => {
  let release!: (value: unknown) => void;
  mockPost.mockReturnValueOnce(new Promise((resolve) => {
    release = resolve;
  }));
  const previous = mockStorage;
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  mockStorage = storage();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  release({ ok: true });
  await settle();
  expect(await previous.getItem('installAttribution')).toEqual(source);
  expect(await mockStorage.getItem('installAttribution')).toEqual({ ...source, claimed: true });
});

it('lets a new owner claim through the same storage while its predecessor request is stuck', async () => {
  mockPost.mockReturnValueOnce(new Promise(() => {}));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(await mockStorage.getItem('installAttribution')).toEqual({ ...source, claimed: true });
});

it('bounds a stalled claim response and retries its unacknowledged source', async () => {
  mockPost.mockReturnValueOnce(new Promise(() => {}));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await jest.advanceTimersByTimeAsync(59999);
  expect(mockPost).toHaveBeenCalledTimes(1);
  await jest.advanceTimersByTimeAsync(1);
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(mockPost.mock.calls[0][2].signal.aborted).toBe(true);
  expect(await mockStorage.getItem('installAttribution')).toEqual({ ...source, claimed: true });
});

it('keeps technical claims separate and allows a later explicit source to be claimed', async () => {
  let explicit = false;
  mockNative.mockImplementation((method: string) => Promise.resolve(method === 'airInstallationGetPending'
    ? [] : { source: explicit ? source : nativeNull, technicalKind: 'direct' }));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'direct',
  }, claimOptions);
  explicit = true;
  connector.handleInstallationStateChange();
  await settle();
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(mockPost).toHaveBeenLastCalledWith('/attribution/claim', { ...source, platform: 'android' }, claimOptions);
});

function answerTechnical(projection: Record<string, unknown>) {
  mockNative.mockImplementation((method: string) => Promise.resolve(method === 'airInstallationGetPending'
    ? [] : { source: nativeNull, ...projection }));
}

const playInstalledAt = 1760000000000;

it('sends the Play outcome and install time with the first technical claim and only once', async () => {
  answerTechnical({ technicalKind: 'referral', sourceOutcome: 'referral', playInstalledAt });
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  connector.handleInstallationStateChange();
  await settle();
  expect(mockPost).toHaveBeenCalledTimes(1);
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'referral', sourceOutcome: 'referral', playInstalledAt,
  }, claimOptions);
  expect(await mockStorage.getItem('attributionTechnicalClaimed')).toBe('1');
  expect(await mockStorage.getItem('attributionOutcomeClaimed')).toBe('1');
});

it('refines an outcome-less technical claim once and retries a refused refinement', async () => {
  mockStorage = storage({ attributionTechnicalClaimed: '1' });
  mockPost.mockResolvedValueOnce({ ok: false });
  answerTechnical({ technicalKind: 'direct', sourceOutcome: 'organic', playInstalledAt });
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await jest.advanceTimersByTimeAsync(29999);
  expect(mockPost).toHaveBeenCalledTimes(1);
  await jest.advanceTimersByTimeAsync(1);
  expect(mockPost).toHaveBeenCalledTimes(2);
  connector.handleInstallationStateChange();
  await jest.advanceTimersByTimeAsync(60000);
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(mockPost).toHaveBeenLastCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'direct', sourceOutcome: 'organic', playInstalledAt,
  }, claimOptions);
  expect(await mockStorage.getItem('attributionOutcomeClaimed')).toBe('1');
  expect(jest.getTimerCount()).toBe(0);
});

it.each(['stale_referrer', 'play_unavailable'])('never refines an earlier claim with %s', async (sourceOutcome) => {
  mockStorage = storage({ attributionTechnicalClaimed: '1' });
  answerTechnical({ technicalKind: 'direct', sourceOutcome, playInstalledAt: nativeNull });
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await jest.advanceTimersByTimeAsync(60000);
  expect(mockPost).not.toHaveBeenCalled();
  expect(jest.getTimerCount()).toBe(0);
  await mockStorage.clear();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'direct', sourceOutcome,
  }, claimOptions);
});

it('omits an outcome that its claim kind cannot carry instead of losing the claim', async () => {
  answerTechnical({ technicalKind: 'direct', sourceOutcome: 'referral', playInstalledAt });
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await jest.advanceTimersByTimeAsync(60000);
  expect(mockPost).toHaveBeenCalledTimes(1);
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'direct',
  }, claimOptions);
  expect(await mockStorage.getItem('attributionOutcomeClaimed')).toBeUndefined();
});

it('refines a first claim made while Play failed once Play answers', async () => {
  let hasAnswered = false;
  mockNative.mockImplementation((method: string) => Promise.resolve(method === 'airInstallationGetPending'
    ? [] : {
      source: nativeNull,
      technicalKind: 'direct',
      sourceOutcome: hasAnswered ? 'organic' : 'play_unavailable',
      playInstalledAt: hasAnswered ? playInstalledAt : nativeNull,
    }));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockPost).toHaveBeenLastCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'direct', sourceOutcome: 'play_unavailable',
  }, claimOptions);
  hasAnswered = true;
  connector.handleInstallationStateChange();
  await jest.advanceTimersByTimeAsync(60000);
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(mockPost).toHaveBeenLastCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'direct', sourceOutcome: 'organic', playInstalledAt,
  }, claimOptions);
});

it('carries the installation id on source and technical claims', async () => {
  const installationId = '00000000-0000-4000-8000-000000000001';
  answerTechnical({ source, technicalKind: 'direct', sourceOutcome: 'organic', playInstalledAt, installationId });
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  await settle();
  expect(mockPost).toHaveBeenCalledTimes(2);
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', {
    ...source, platform: 'android', installationId,
  }, claimOptions);
  expect(mockPost).toHaveBeenCalledWith('/attribution/claim', {
    channel: '', platform: 'android', attributionKind: 'direct', sourceOutcome: 'organic',
    playInstalledAt, installationId,
  }, claimOptions);
});
