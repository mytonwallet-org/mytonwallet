jest.mock('../../common/helpers', () => ({ isUpdaterAlive: () => true }));
const mockStorage = {};
const mockInit = jest.fn().mockResolvedValue(undefined);
const mockReport = jest.fn().mockResolvedValue(true);
const mockWalletClaim = jest.fn().mockResolvedValue(true);
jest.mock('../../storages', () => ({
  createStorage: () => mockStorage, withStorage: (_: unknown, action: () => unknown) => action(),
}));
jest.mock('../../methods/init', () => ({ __esModule: true, default: (...args: unknown[]) => mockInit(...args) }));
jest.mock('../../methods/attribution', () => ({
  syncAndroidWalletAttribution: (...args: unknown[]) => mockWalletClaim(...args),
}));
jest.mock('../../methods/nativeInstallation', () => ({
  reportNativeInstallation: (...args: unknown[]) => mockReport(...args),
}));
jest.mock('../../methods/registry', () => ({ methods: {} }));
jest.mock('../../dappProtocols', () => ({ getProtocolManager: jest.fn() }));

it.each(['pending', 'rejected'])('reports on Android while wallet init is %s', async (state) => {
  const { createDirectApiConnector } = await import('./connector');
  mockReport.mockClear();
  mockInit.mockImplementationOnce(() => state === 'pending'
    ? new Promise(() => {}) : Promise.reject(new Error('wallet init')));
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isAndroidApp: true });
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockReport).toHaveBeenCalledTimes(1);
});

it('retries an unsettled installation without a native notification and stops after its persisted ACK', async () => {
  jest.useFakeTimers();
  try {
    const { createDirectApiConnector } = await import('./connector');
    mockReport.mockClear().mockResolvedValueOnce(false).mockResolvedValue(true);
    const connector = createDirectApiConnector();
    connector.initApi(jest.fn(), { isAndroidApp: true });
    await jest.advanceTimersByTimeAsync(29999);
    expect(mockReport).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockReport).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(60000);
    expect(mockReport).toHaveBeenCalledTimes(2);
    expect(jest.getTimerCount()).toBe(0);
  } finally {
    jest.useRealTimers();
  }
});

it('cancels an old installation retry when SDK initialization is replaced', async () => {
  jest.useFakeTimers();
  try {
    const { createDirectApiConnector } = await import('./connector');
    mockReport.mockClear().mockResolvedValueOnce(false).mockResolvedValue(true);
    const connector = createDirectApiConnector();
    connector.initApi(jest.fn(), { isAndroidApp: true });
    await jest.advanceTimersByTimeAsync(1000);
    expect(jest.getTimerCount()).toBe(1);
    connector.initApi(jest.fn(), { isAndroidApp: true });
    await jest.advanceTimersByTimeAsync(0);
    expect(jest.getTimerCount()).toBe(0);
    await jest.advanceTimersByTimeAsync(60000);
    expect(mockReport).toHaveBeenCalledTimes(2);
  } finally {
    jest.useRealTimers();
  }
});

it('reports an iOS Air installation and leaves wallet claims to Android', async () => {
  const { createDirectApiConnector } = await import('./connector');
  mockReport.mockClear();
  mockWalletClaim.mockClear();
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), { isIosApp: true });
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockReport).toHaveBeenCalledTimes(1);
  connector.handleInstallationStateChange();
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockReport).toHaveBeenCalledTimes(2);
  expect(mockWalletClaim).not.toHaveBeenCalled();
});

it('reports nothing outside the native apps', async () => {
  const { createDirectApiConnector } = await import('./connector');
  mockReport.mockClear();
  mockWalletClaim.mockClear();
  const connector = createDirectApiConnector();
  connector.initApi(jest.fn(), {});
  connector.handleInstallationStateChange();
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(mockReport).not.toHaveBeenCalled();
  expect(mockWalletClaim).not.toHaveBeenCalled();
});
