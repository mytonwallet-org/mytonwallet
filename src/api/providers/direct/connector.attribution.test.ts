const mockStorage = {};
const mockClaim = jest.fn().mockResolvedValue(undefined);
const mockTechnicalClaim = jest.fn().mockResolvedValue(undefined);
const mockInit = jest.fn().mockResolvedValue(undefined);
jest.mock('../../storages', () => ({
  createStorage: () => mockStorage, withStorage: (_: unknown, action: () => unknown) => action(),
}));
jest.mock('../../methods/init', () => ({ __esModule: true, default: (...args: unknown[]) => mockInit(...args) }));
jest.mock('../../methods/attribution', () => ({
  acceptInstallAttribution: (...args: unknown[]) => mockClaim(...args),
  setInstallChannel: (...args: unknown[]) => mockTechnicalClaim(...args),
}));
jest.mock('../../methods/registry', () => ({ methods: {} }));
jest.mock('../../dappProtocols', () => ({ getProtocolManager: jest.fn() }));

it('retains a full candidate received before bridge init and delivers after init resolves', async () => {
  const { createDirectApiConnector } = await import('./connector');
  let ready!: () => void;
  mockInit.mockImplementationOnce(() => new Promise<void>((resolve) => {
    ready = resolve;
  }));
  const connector = createDirectApiConnector();
  const snapshot = { channel: 'partner', attributionKind: 'utm' as const, utmCampaign: 'launch' };
  connector.captureInstallAttribution(snapshot);
  expect(mockClaim).not.toHaveBeenCalled();
  connector.initApi(jest.fn(), {});
  expect(mockClaim).not.toHaveBeenCalled();
  ready();
  for (let i = 0; i < 10; i++) await Promise.resolve();
  expect(mockClaim).toHaveBeenCalledWith(snapshot, mockStorage);
});

it('retains a technical Play claim received before SDK initialization', async () => {
  const { createDirectApiConnector } = await import('./connector');
  const connector = createDirectApiConnector();
  connector.setInstallChannel('referral', undefined, 'referral');
  expect(mockTechnicalClaim).not.toHaveBeenCalled();
  connector.initApi(jest.fn(), {});
  for (let i = 0; i < 10; i++) await Promise.resolve();
  expect(mockTechnicalClaim).toHaveBeenCalledWith('referral', mockStorage, undefined, 'referral');
});

it('uses one queue drain while technical acceptance is in flight', async () => {
  const { createDirectApiConnector } = await import('./connector');
  mockTechnicalClaim.mockClear();
  mockClaim.mockClear();
  let release!: () => void;
  mockTechnicalClaim.mockImplementationOnce(() => new Promise<void>((resolve) => {
    release = resolve;
  }));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), {});
  connector.setInstallChannel('unknown');
  for (let i = 0; i < 10; i++) await Promise.resolve();
  connector.setInstallChannel('referral', undefined, 'referral');
  connector.captureInstallAttribution({ channel: 'partner', attributionKind: 'utm' });
  for (let i = 0; i < 10; i++) await Promise.resolve();
  expect(mockTechnicalClaim).toHaveBeenCalledTimes(1);
  expect(mockClaim).not.toHaveBeenCalled();
  release();
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockTechnicalClaim).toHaveBeenCalledTimes(2);
  expect(mockClaim).toHaveBeenCalledWith({ channel: 'partner', attributionKind: 'utm' }, mockStorage);
});

it('lets a replacement init drain pending attribution without waiting for the old init', async () => {
  const { createDirectApiConnector } = await import('./connector');
  mockClaim.mockClear();
  let oldReady!: () => void;
  mockInit.mockImplementationOnce(() => new Promise<void>((resolve) => {
    oldReady = resolve;
  }));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), {});
  const snapshot = { channel: 'partner', attributionKind: 'utm' as const };
  connector.captureInstallAttribution(snapshot);
  connector.initApi(jest.fn(), {});
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockClaim).toHaveBeenCalledTimes(1);
  oldReady();
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockClaim).toHaveBeenCalledTimes(1);
});

it('retains a failed durable acceptance for the next init without a hot retry loop', async () => {
  const { createDirectApiConnector } = await import('./connector');
  mockClaim.mockClear().mockRejectedValueOnce(new Error('storage unavailable'));
  const connector = createDirectApiConnector();
  connector.captureInstallAttribution({ channel: 'partner', attributionKind: 'utm' });
  connector.initApi(jest.fn(), {});
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockClaim).toHaveBeenCalledTimes(1);
  connector.initApi(jest.fn(), {});
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockClaim).toHaveBeenCalledTimes(2);
});

it('rejects invalid queue inputs and snapshots valid input before caller mutation', async () => {
  const { createDirectApiConnector } = await import('./connector');
  mockClaim.mockClear();
  const connector = createDirectApiConnector();
  connector.captureInstallAttribution({ channel: 'invalid-source', attributionKind: 'utm' });
  const snapshot = { channel: 'partner', attributionKind: 'utm' as const, utmCampaign: 'launch' };
  connector.captureInstallAttribution(snapshot);
  snapshot.channel = 'invalid-source';
  snapshot.utmCampaign = 'changed';
  connector.initApi(jest.fn(), {});
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockClaim).toHaveBeenCalledTimes(1);
  expect(mockClaim).toHaveBeenCalledWith({
    channel: 'partner', attributionKind: 'utm', utmCampaign: 'launch',
  }, mockStorage);
});
