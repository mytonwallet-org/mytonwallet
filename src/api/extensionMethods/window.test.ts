export {};

const mockWindows = {
  create: jest.fn(),
  get: jest.fn(),
  getAll: jest.fn(),
  getCurrent: jest.fn(),
  onRemoved: { addListener: jest.fn() },
  update: jest.fn(),
};

const mockStorage = {
  getItem: jest.fn(),
  removeItem: jest.fn(),
  setItem: jest.fn(),
};

const mockGetContexts = jest.fn();
const mockMatchAll = jest.fn();

class MockMessageChannel {
  port1 = { onmessage: undefined as ((event: { data: unknown }) => void) | undefined, close: jest.fn() };

  port2 = {
    postMessage: (data: unknown) => this.port1.onmessage?.({ data }),
    close: jest.fn(),
  };
}

let mockResolvePopupReady: VoidFunction;
const mockCreateDappPromise = jest.fn(() => ({
  promise: new Promise<void>((resolve) => {
    mockResolvePopupReady = resolve;
  }),
}));

jest.mock('webextension-polyfill', () => ({
  __esModule: true,
  default: {
    action: { onClicked: { addListener: jest.fn() } },
    runtime: { getURL: jest.fn((path: string) => `chrome-extension://wallet/${path}`) },
    webRequest: { handlerBehaviorChanged: jest.fn() },
    windows: mockWindows,
  },
}));

jest.mock('../common/dappPromises', () => ({
  createDappPromise: mockCreateDappPromise,
  rejectAllDappPromises: jest.fn(),
}));

jest.mock('../storages/extension', () => ({
  __esModule: true,
  default: mockStorage,
}));

describe('extension popup window recovery', () => {
  const popupUrl = 'chrome-extension://wallet/index.html';

  beforeAll(() => {
    Object.defineProperty(self, 'chrome', {
      configurable: true,
      value: {},
    });
  });

  beforeEach(() => {
    jest.resetModules();
    jest.clearAllMocks();
    mockWindows.create.mockReset();
    mockWindows.get.mockReset();
    mockWindows.getAll.mockReset();
    mockWindows.update.mockReset();
    mockStorage.getItem.mockReset();
    mockStorage.removeItem.mockReset();
    mockStorage.setItem.mockReset();
    mockWindows.getAll.mockResolvedValue([]);
    mockGetContexts.mockReset().mockResolvedValue([]);
    Object.assign(self.chrome, {
      runtime: {
        getContexts: mockGetContexts,
        getURL: (path: string) => `chrome-extension://wallet/${path}`,
      },
    });
    mockMatchAll.mockReset().mockResolvedValue([]);
    Object.assign(self, { clients: { matchAll: mockMatchAll }, MessageChannel: MockMessageChannel });
    Reflect.deleteProperty(self.chrome, 'system');
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('restores the live popup id before resizing after a service-worker restart', async () => {
    mockStorage.getItem.mockResolvedValue(41);
    mockWindows.get.mockResolvedValue({
      id: 41,
      type: 'popup',
      tabs: [{ url: popupUrl }],
    });

    const { updateWindowSize } = await import('./window');
    const size = { width: 980, height: 788 };

    await updateWindowSize(size);

    expect(mockWindows.update).toHaveBeenCalledWith(41, size);
  });

  it('recovers the owned popup when Chrome hides its tab URL', async () => {
    mockStorage.getItem.mockResolvedValue(41);
    mockGetContexts.mockResolvedValue([{
      documentUrl: popupUrl,
      windowId: 41,
      tabId: 7,
      frameId: 0,
    }]);
    mockWindows.get.mockResolvedValue({
      id: 41,
      type: 'popup',
      tabs: [{ id: 7 }],
    });
    mockWindows.getAll.mockResolvedValue([{ id: 41, type: 'popup', tabs: [{ id: 7 }] }]);
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });

    const { updateWindowSize } = await import('./window');
    const size = { width: 980, height: 788 };

    await updateWindowSize(size);

    expect(mockWindows.update).toHaveBeenCalledWith(41, size);
    expect(mockWindows.create).not.toHaveBeenCalled();
  });

  it('distinguishes an owned popup from an owned normal tab before Chrome 116', async () => {
    Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    mockMatchAll.mockResolvedValue([41, 42].map((id) => ({
      url: popupUrl,
      frameType: 'top-level',
      postMessage: (_data: unknown, [port]: MessagePort[]) => port.postMessage(id),
    })));
    mockWindows.getAll.mockResolvedValue([
      { id: 41, type: 'normal', tabs: [{ id: 7 }] },
      { id: 42, type: 'popup', tabs: [{ id: 8 }] },
    ]);
    mockWindows.create.mockResolvedValue({ id: 43, type: 'popup' });

    const { updateWindowSize } = await import('./window');
    await updateWindowSize({ width: 980, height: 788 });

    expect(mockWindows.update).toHaveBeenCalledWith(42, { width: 980, height: 788 });
    expect(mockWindows.create).not.toHaveBeenCalled();
  });

  it.each(['silent', 'closed'])('reuses a responsive popup when another own client is %s', async (state) => {
    Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    mockMatchAll.mockResolvedValue([
      {
        url: popupUrl, frameType: 'top-level',
        postMessage: (_data: unknown, [port]: MessagePort[]) => port.postMessage(42),
      },
      {
        url: popupUrl, frameType: 'top-level',
        postMessage: () => { if (state === 'closed') throw new Error('Client closed'); },
      },
    ]);
    mockWindows.getAll.mockResolvedValue([{ id: 42, type: 'popup', tabs: [{ id: 8 }] }]);
    const { updateWindowSize } = await import('./window');
    const resizing = updateWindowSize({ width: 980, height: 788 }).catch((error: unknown) => error);
    await jest.advanceTimersByTimeAsync(2000);

    expect(await resizing).toBeUndefined();
    expect(mockWindows.update).toHaveBeenCalledWith(42, { width: 980, height: 788 });
    expect(mockWindows.create).not.toHaveBeenCalled();
  });

  it.each(['legacy', 'modern'])('reuses a URL-identified popup when %s discovery fails', async (runtime) => {
    if (runtime === 'legacy') Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    mockMatchAll.mockRejectedValue(new Error('Cannot discover clients'));
    mockGetContexts.mockRejectedValue(new Error('Cannot discover contexts'));
    mockStorage.getItem.mockResolvedValue(41);
    mockWindows.get.mockResolvedValue({ id: 41, type: 'popup', tabs: [{ url: popupUrl }] });
    const { updateWindowSize } = await import('./window');

    await expect(updateWindowSize({ width: 980, height: 788 })).resolves.toBeUndefined();

    expect(mockWindows.update).toHaveBeenCalledWith(41, { width: 980, height: 788 });
    expect(mockWindows.create).not.toHaveBeenCalled();
  });

  it('does not create a popup when partial discovery only identifies a normal window', async () => {
    Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    mockMatchAll.mockResolvedValue([
      {
        url: popupUrl, frameType: 'top-level',
        postMessage: (_data: unknown, [port]: MessagePort[]) => port.postMessage(41),
      },
      { url: popupUrl, frameType: 'top-level', postMessage: jest.fn() },
    ]);
    mockWindows.getAll.mockResolvedValue([{ id: 41, type: 'normal', tabs: [{ url: popupUrl }] }]);
    const { updateWindowSize } = await import('./window');
    const resizing = expect(updateWindowSize({ width: 980, height: 788 })).rejects.toThrow();
    await jest.advanceTimersByTimeAsync(2000);
    await resizing;

    expect(mockWindows.create).not.toHaveBeenCalled();
    expect(mockWindows.update).not.toHaveBeenCalled();
  });

  it('creates a popup when complete legacy discovery only identifies a normal window', async () => {
    Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    mockMatchAll.mockResolvedValue([{
      url: popupUrl, frameType: 'top-level',
      postMessage: (_data: unknown, [port]: MessagePort[]) => port.postMessage(41),
    }]);
    mockWindows.getAll.mockResolvedValue([{ id: 41, type: 'normal', tabs: [{ url: popupUrl }] }]);
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });
    const { updateWindowSize } = await import('./window');

    await updateWindowSize({ width: 980, height: 788 });

    expect(mockWindows.create).toHaveBeenCalledTimes(1);
    expect(mockWindows.update).toHaveBeenCalledWith(42, { width: 980, height: 788 });
  });

  it('retries the owned page while its message listener is starting', async () => {
    Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    const postMessage = jest.fn()
      .mockImplementationOnce(() => undefined)
      .mockImplementation((_data: unknown, [port]: MessagePort[]) => port.postMessage(41));
    mockMatchAll.mockResolvedValue([{ url: popupUrl, frameType: 'top-level', postMessage }]);
    mockWindows.getAll.mockResolvedValue([{ id: 41, type: 'popup', tabs: [{ id: 7 }] }]);
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });

    const { updateWindowSize } = await import('./window');
    const resizing = updateWindowSize({ width: 980, height: 788 });
    await jest.advanceTimersByTimeAsync(1000);
    await resizing;

    expect(mockWindows.update).toHaveBeenCalledWith(41, { width: 980, height: 788 });
    expect(mockWindows.create).not.toHaveBeenCalled();
  });

  it('does not create a duplicate when an owned page never answers', async () => {
    Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    mockMatchAll.mockResolvedValue([{
      url: popupUrl,
      frameType: 'top-level',
      postMessage: jest.fn(),
    }]);
    mockWindows.getAll.mockResolvedValue([{ id: 41, type: 'popup', tabs: [{ id: 7 }] }]);
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });

    const { updateWindowSize } = await import('./window');
    const resizing = expect(updateWindowSize({ width: 980, height: 788 })).rejects.toThrow();
    await jest.advanceTimersByTimeAsync(2000);
    await resizing;

    expect(mockWindows.create).not.toHaveBeenCalled();
    expect(mockWindows.update).not.toHaveBeenCalled();
  });

  it('ignores foreign clients when creating a popup on older Chrome', async () => {
    Reflect.deleteProperty(self.chrome.runtime, 'getContexts');
    const postMessage = jest.fn();
    mockMatchAll.mockResolvedValue([
      { url: 'https://example.com/index.html', frameType: 'top-level', postMessage },
      { url: 'chrome-extension://other/index.html', frameType: 'top-level', postMessage },
      { url: popupUrl, frameType: 'nested', postMessage },
    ]);
    mockWindows.getAll.mockResolvedValue([{ id: 41, type: 'popup', tabs: [{ id: 7 }] }]);
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });

    const { updateWindowSize } = await import('./window');
    await updateWindowSize({ width: 980, height: 788 });

    expect(postMessage).not.toHaveBeenCalled();
    expect(mockWindows.update).toHaveBeenCalledWith(42, { width: 980, height: 788 });
    expect(mockWindows.update).not.toHaveBeenCalledWith(41, expect.anything());
  });

  it('creates only one popup for concurrent cold-start requests', async () => {
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });
    const { updateWindowSize } = await import('./window');

    await Promise.all([
      updateWindowSize({ width: 980, height: 788 }),
      updateWindowSize({ width: 400, height: 700 }),
    ]);

    expect(mockWindows.create).toHaveBeenCalledTimes(1);
    expect(mockWindows.update).toHaveBeenCalledWith(42, { width: 980, height: 788 });
    expect(mockWindows.update).toHaveBeenCalledWith(42, { width: 400, height: 700 });
  });

  it('does not create a popup when context discovery fails', async () => {
    mockGetContexts.mockRejectedValue(new Error('Cannot discover extension contexts'));
    const { updateWindowSize } = await import('./window');

    await expect(updateWindowSize({ width: 980, height: 788 })).rejects.toThrow();

    expect(mockWindows.create).not.toHaveBeenCalled();
    expect(mockWindows.update).not.toHaveBeenCalled();
  });

  it.each([
    {
      name: 'right edge of the primary display',
      window: { left: 1124, top: 120, width: 368, height: 770 },
      displays: [{ isPrimary: true, workArea: { left: 0, top: 25, width: 1512, height: 900 } }],
      expected: { left: 532, top: 120, width: 980, height: 788 },
    },
    {
      name: 'a secondary display with negative coordinates',
      window: { left: -390, top: 120, width: 368, height: 770 },
      displays: [
        { isPrimary: true, workArea: { left: 0, top: 25, width: 1512, height: 900 } },
        { isPrimary: false, workArea: { left: -1440, top: 0, width: 1440, height: 900 } },
      ],
      expected: { left: -980, top: 112, width: 980, height: 788 },
    },
    {
      name: 'a work area smaller than the requested layout',
      window: { left: 400, top: 120, width: 368, height: 600 },
      displays: [{ isPrimary: true, workArea: { left: 0, top: 25, width: 800, height: 700 } }],
      expected: { left: 0, top: 25, width: 800, height: 700 },
    },
  ])('keeps the resized popup inside $name', async ({ window, displays, expected }) => {
    Object.assign(self.chrome, {
      system: {
        display: {
          getInfo: jest.fn((callback?: (value: typeof displays) => void) => {
            callback?.(displays.map((display) => ({ ...display, bounds: display.workArea })));
          }),
        },
      },
    });
    mockStorage.getItem.mockResolvedValue(41);
    mockWindows.get.mockResolvedValue({ id: 41, type: 'popup', tabs: [{ url: popupUrl }], ...window });

    const { updateWindowSize } = await import('./window');
    await updateWindowSize({ width: 980, height: 788 });

    expect(mockWindows.update).toHaveBeenCalledWith(41, expected);
  });

  it('fits saved bounds onto the primary display after a monitor is disconnected', async () => {
    const workArea = { left: 0, top: 25, width: 1512, height: 900 };
    const displays = [{ isPrimary: true, bounds: workArea, workArea }];
    Object.assign(self.chrome, {
      system: {
        display: {
          getInfo: jest.fn((callback?: (value: typeof displays) => void) => {
            callback?.(displays);
          }),
        },
      },
    });
    mockStorage.getItem.mockImplementation((key: string) => (
      Promise.resolve(key === 'windowState' ? { left: -2000, top: 120, width: 980, height: 788 } : undefined)
    ));
    mockWindows.create.mockImplementation(() => {
      mockResolvePopupReady();
      return Promise.resolve({ id: 42, type: 'popup' });
    });

    const { openPopupWindow } = await import('./window');
    await openPopupWindow();

    expect(mockWindows.create).toHaveBeenCalledWith(expect.objectContaining({
      left: 0, top: 120, width: 980, height: 788,
    }));
  });

  it.each(['create', 'resize'])('continues to %s after a display query failure', async (operation) => {
    const workArea = { left: 0, top: 25, width: 1512, height: 900 };
    const displays = [{ isPrimary: true, bounds: workArea, workArea }];
    const getInfo = jest.fn((
      callback?: (value: typeof displays | undefined) => void,
    ): Promise<typeof displays> | void => {
      callback?.(displays);
    });
    Object.assign(self.chrome, { system: { display: { getInfo } } });
    const bounds = { left: 100, top: 120, width: 980, height: 788 };
    mockStorage.getItem.mockImplementation((key: string) => Promise.resolve(
      key === 'windowState' ? bounds : operation === 'resize' ? 41 : undefined,
    ));
    mockWindows.get.mockResolvedValue({ id: 41, type: 'popup', tabs: [{ url: popupUrl }], ...bounds });
    mockWindows.create.mockImplementation(() => {
      mockResolvePopupReady();
      return Promise.resolve({ id: 42, type: 'popup' });
    });

    const { openPopupWindow, updateWindowSize } = await import('./window');
    getInfo.mockImplementation((callback) => {
      if (!callback) return Promise.reject(new Error('Display API unavailable'));
      Object.assign(self.chrome.runtime, { lastError: { message: 'Display API unavailable' } });
      try {
        callback(undefined);
      } finally {
        Reflect.deleteProperty(self.chrome.runtime, 'lastError');
      }
      return undefined;
    });

    if (operation === 'resize') {
      await expect(updateWindowSize({ width: 980, height: 788 })).resolves.toBeUndefined();
      expect(mockWindows.update).toHaveBeenCalledWith(41, bounds);
      expect(mockWindows.create).not.toHaveBeenCalled();
    } else {
      await expect(openPopupWindow()).resolves.toBeUndefined();
      expect(mockWindows.create).toHaveBeenCalledWith(expect.objectContaining(bounds));
      expect(mockWindows.update).toHaveBeenCalledWith(42, { focused: true });
    }
    expect(mockStorage.removeItem).not.toHaveBeenCalled();
  });

  it.each(['throws', 'has no response', 'is absent'])('opens the popup when the display API %s', async (failure) => {
    const getInfo = failure === 'is absent' ? undefined : jest.fn((callback?: (value: undefined) => void) => {
      if (failure === 'throws') throw new Error('Display API unavailable');
      callback?.(undefined);
    });
    Object.assign(self.chrome, { system: { display: { getInfo } } });
    mockWindows.create.mockImplementation(() => {
      mockResolvePopupReady();
      return Promise.resolve({ id: 42, type: 'popup' });
    });

    const { openPopupWindow } = await import('./window');
    await expect(openPopupWindow()).resolves.toBeUndefined();

    expect(mockWindows.create).toHaveBeenCalledWith(expect.objectContaining({
      left: 20, top: 120, width: 368, height: 770,
    }));
    expect(mockWindows.update).toHaveBeenCalledWith(42, { focused: true });
  });

  it('waits for the existing popup to reconnect after a service-worker restart', async () => {
    mockStorage.getItem.mockResolvedValue(41);
    mockWindows.get.mockResolvedValue({
      id: 41,
      type: 'popup',
      tabs: [{ url: popupUrl }],
    });

    let completeFocus!: VoidFunction;
    const focusCompleted = new Promise<void>((resolve) => {
      completeFocus = resolve;
    });
    mockWindows.update.mockImplementation(() => {
      completeFocus();
      return Promise.resolve();
    });

    const { openPopupWindow } = await import('./window');
    let isReady = false;
    const opening = openPopupWindow().then(() => {
      isReady = true;
    });
    await focusCompleted;
    await jest.advanceTimersByTimeAsync(0);

    expect(mockWindows.update).toHaveBeenCalledWith(41, { focused: true });

    expect(isReady).toBe(false);

    mockResolvePopupReady();
    await opening;

    expect(isReady).toBe(true);
  });

  it('observes popup readiness that arrives before the first open request', async () => {
    mockStorage.getItem.mockResolvedValue(41);
    mockWindows.get.mockResolvedValue({
      id: 41,
      type: 'popup',
      tabs: [{ url: popupUrl }],
    });

    const { openPopupWindow } = await import('./window');
    mockResolvePopupReady();

    await expect(openPopupWindow()).resolves.toBeUndefined();
  });

  it('creates the readiness waiter before a new popup can initialize', async () => {
    mockStorage.getItem.mockResolvedValue(undefined);
    mockWindows.create.mockImplementation(() => {
      mockResolvePopupReady();
      return Promise.resolve({ id: 42, type: 'popup' });
    });

    const { openPopupWindow } = await import('./window');

    await expect(openPopupWindow()).resolves.toBeUndefined();
  });

  it('replaces a stale stored popup before resizing after an extension reload', async () => {
    mockStorage.getItem
      .mockResolvedValueOnce(41)
      .mockResolvedValueOnce(undefined);
    mockWindows.get.mockRejectedValue(new Error('No window with id: 41'));
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });

    const { updateWindowSize } = await import('./window');
    const size = { width: 980, height: 788 };

    await updateWindowSize(size);

    expect(mockStorage.removeItem).toHaveBeenCalledWith('windowId');
    expect(mockWindows.create).toHaveBeenCalledWith(expect.objectContaining({ type: 'popup' }));
    expect(mockWindows.update).toHaveBeenCalledWith(42, size);
  });

  it('rediscovers the owned popup instead of mutating a colliding normal window id', async () => {
    mockStorage.getItem
      .mockResolvedValueOnce(41)
      .mockResolvedValue(undefined);
    mockWindows.get.mockResolvedValue({ id: 41, type: 'normal' });
    mockWindows.getAll.mockResolvedValue([{
      id: 42,
      type: 'popup',
      tabs: [{ url: popupUrl }],
    }]);

    const { updateWindowSize } = await import('./window');
    const size = { width: 980, height: 788 };

    await updateWindowSize(size);

    expect(mockWindows.update).not.toHaveBeenCalledWith(41, expect.anything());
    expect(mockWindows.update).toHaveBeenCalledWith(42, size);
    expect(mockWindows.create).not.toHaveBeenCalled();
  });

  it('never mutates a foreign popup that reuses the stored window id', async () => {
    mockStorage.getItem
      .mockResolvedValueOnce(41)
      .mockResolvedValue(undefined);
    mockWindows.get.mockResolvedValue({
      id: 41,
      type: 'popup',
      tabs: [{ url: 'https://example.com/' }],
    });
    mockWindows.create.mockResolvedValue({ id: 42, type: 'popup' });

    const { updateWindowSize } = await import('./window');
    const size = { width: 980, height: 788 };

    await updateWindowSize(size);

    expect(mockWindows.update).not.toHaveBeenCalledWith(41, expect.anything());
    expect(mockWindows.update).toHaveBeenCalledWith(42, size);
  });

  it('recovers when the popup closes while ownership is being resolved', async () => {
    let resolveStoredWindow!: (window: { id: number; type: string; tabs: { url: string }[] }) => void;
    mockStorage.getItem.mockResolvedValue(41);
    mockWindows.get
      .mockImplementationOnce(() => new Promise((resolve) => {
        resolveStoredWindow = resolve;
      }))
      .mockRejectedValue(new Error('No window with id: 41'));
    mockWindows.create.mockImplementation(() => {
      mockResolvePopupReady();
      return Promise.resolve({ id: 42, type: 'popup' });
    });
    mockWindows.update
      .mockRejectedValueOnce(new Error('No window with id: 41'))
      .mockResolvedValue(undefined);

    const { openPopupWindow } = await import('./window');
    const opening = openPopupWindow();
    await jest.advanceTimersByTimeAsync(0);

    const onRemoved = mockWindows.onRemoved.addListener.mock.calls[0][0];
    onRemoved(41);
    resolveStoredWindow({ id: 41, type: 'popup', tabs: [{ url: popupUrl }] });

    await expect(opening).resolves.toBeUndefined();
    expect(mockWindows.update).toHaveBeenLastCalledWith(42, { focused: true });
  });
});
